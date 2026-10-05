#' Entry point for one task of the uncertainty workflow (option B: spatial-block bootstrap of the BRTs)
#'
#' Usage (from the repo root; on EVE through the cluster/eve_unc_*.sbatch scripts):
#'   Rscript tools/runUncertaintyTask.R --step <step> [--index N]
#'
#' Steps, in the order the pipeline runs them (cluster/submit_eve_uncertainty.sh chains them):
#'   preflight       once, on a login node: check that every input exists, and print the problems
#'   covcache        once: write the habitat covariate stacks of all needed years
#'   fit             per species (index = species number): refit the replicate BRTs of the three scales
#'   coarse          per species: predict the replicate climate and landscape BRTs for all years
#'   ridge           per species: fit the replicate ridge meta-models
#'   bandpredict     per species x band (index = (species - 1) * nBands + band): predict all years
#'   summarize       per species x band: percentile summaries, change maps, per-pixel trend (pieces)
#'   assemble        per species: stitch pieces into maps, area means, index uncertainty
#'   community       per band (index = band): expected richness / mean change, all species
#'   assembleAll     once: combined multi-species indices per replicate, community maps stitched
#'
#' Settings come from environment variables, see uncCfg() in uncertainty/R/uncCommon.R
#' (BIRDMONITOR_RUNNAME, BIRDMONITOR_UNC_REPS, BIRDMONITOR_UNC_YEARS, BIRDMONITOR_UNC_BANDS, ...).

Sys.setenv(OMP_NUM_THREADS = "1", GDAL_NUM_THREADS = "1")
args <- commandArgs(trailingOnly = TRUE)
getArg <- function(flag, default = NULL) { i <- which(args == flag); if (length(i) == 0) default else args[i + 1] }
step <- getArg("--step")
index <- as.integer(getArg("--index", Sys.getenv("SLURM_ARRAY_TASK_ID", unset = NA)))
repoRoot <- getArg("--repo-root", getwd())

# the personal R library the pipeline installed its packages in (EVE; no-op elsewhere)
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
suppressMessages({ library(terra); library(gbm); library(glmnet) })
if (!requireNamespace("matrixStats", quietly = TRUE))
  warning("matrixStats is not installed: summaries fall back to a very slow method. ",
          "Install it once on a login node (see uncertainty/README.md).", call. = FALSE)

for (f in sort(list.files(file.path(repoRoot, "uncertainty", "R"), pattern = "[.]R$", full.names = TRUE))) source(f)
cfg <- uncCfg(repoRoot)

needIndex <- function(n) if (is.na(index) || index < 1 || index > n) stop("--index must be 1..", n, " for step ", step, " (got ", index, ")")
speciesOf <- function() { needIndex(length(cfg$species)); cfg$species[index] }
bandsFor <- function(sp) uncBands(cfg, sp)$bands

message("=== uncertainty task: step = ", step, " | run = ", cfg$runName, " | replicates ", cfg$repLabel,
        " | cores = ", cfg$cores, " | ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " ===")
t0 <- Sys.time()

switch(step,
  preflight = uncPreflight(cfg),
  covcache = uncCovcache(cfg),
  fit = { sp <- speciesOf(); message("species: ", sp); uncFitSpecies(cfg, sp) },
  coarse = { sp <- speciesOf(); message("species: ", sp); uncCoarseSpecies(cfg, sp) },
  ridge = { sp <- speciesOf(); message("species: ", sp); uncRidgeSpecies(cfg, sp) },
  bandpredict = {
    needIndex(length(cfg$species) * cfg$nBands)
    sp <- cfg$species[(index - 1L) %/% cfg$nBands + 1L]; k <- (index - 1L) %% cfg$nBands + 1L
    message("species: ", sp, " | band ", k, " of ", cfg$nBands)
    band <- bandsFor(sp)[[k]]
    ctx <- uncContext(cfg, sp)
    ridge <- readRDS(file.path(uncSpDir(cfg, sp, "ridge"), paste0("ridge_", cfg$repLabel, ".rds")))
    for (yr in cfg$outYears) {
      t1 <- Sys.time()
      status <- uncPredictBandYear(cfg, sp, ctx, ridge, yr, band)
      message(sp, " band ", k, " year ", yr, ": ", status, " (", round(as.numeric(difftime(Sys.time(), t1, units = "mins")), 1), " min)")
    }
  },
  summarize = {
    needIndex(length(cfg$species) * cfg$nBands)
    sp <- cfg$species[(index - 1L) %/% cfg$nBands + 1L]; k <- (index - 1L) %% cfg$nBands + 1L
    message("species: ", sp, " | band ", k)
    uncSummarizeSpeciesBand(cfg, sp, bandsFor(sp)[[k]])
  },
  assemble = { sp <- speciesOf(); message("species: ", sp); uncAssembleSpecies(cfg, sp) },
  community = { needIndex(cfg$nBands); uncCommunityBand(cfg, bandsFor(cfg$species[1])[[index]]) },
  assembleAll = uncAssembleAll(cfg),
  stop("--step must be one of: preflight, covcache, fit, coarse, ridge, bandpredict, summarize, assemble, community, assembleAll (got: ", step, ")")
)
message("=== done: ", step, " in ", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), " min ===")
