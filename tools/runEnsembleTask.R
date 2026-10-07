# One task of the ENSEMBLE workflow (feature/ensemble; see modules/models_Monitor/R/algoScale.R and ensembleScale.R).
#
#   Rscript tools/runEnsembleTask.R --step algo --scale habitat --algo gam --index 5   fit + CV + maps of ONE model family for species 5
#                                          (--algo = glm | gam | rf | nn | brt; brt only rebuilds the BRT's out-of-fold files, cheap)
#   Rscript tools/runEnsembleTask.R --step ens --scale habitat --index 5 [--members brt,glm,gam,rf]
#                                          the ensemble of the chosen members for species 5 (default brt,glm,gam,rf = "ens"; any subset works,
#                                          each subset gets its own name and files, see ensTag())
# --index = species number in the roster (1..11). Options: --threads N (default $SLURM_CPUS_PER_TASK; used by the random forest),
#          --years 2005,2010,2020:2025 (default all prediction years + habitat years).
# Run name: BIRDMONITOR_RUNNAME (default test4). The BIRDMONITOR_SPECIES filter works as in the other tools.
args <- commandArgs(trailingOnly = TRUE)
getArg <- function(flag, default = NULL) { i <- which(args == flag); if (length(i) == 0) default else args[i + 1] }
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
Sys.setenv(OMP_NUM_THREADS = "1", GDAL_NUM_THREADS = "1")
suppressMessages({ library(terra); library(gbm); library(glmnet); library(ranger); library(mgcv) })
runName <- if (nzchar(Sys.getenv("BIRDMONITOR_RUNNAME"))) Sys.getenv("BIRDMONITOR_RUNNAME") else "test4"
repoRoot <- normalizePath(getArg("--repo-root", getwd()), winslash = "/"); setwd(repoRoot)
for (f in sort(list.files("modules/models_Monitor/R", pattern = "[.]R$", full.names = TRUE))) source(f)
source("tools/sharedConfig.R"); source("tools/sharedSpeciesConfig.R")
gen <- if (file.exists("data/speciesConfig_general.csv")) loadSpeciesGeneralConfig("data/speciesConfig_general.csv") else NULL
cfg <- uncCfgFromParams(inputRoot = file.path(repoRoot, "inputs"), outputRoot = file.path(repoRoot, "outputs", runName), species = sharedSpecies,
                        predictionYears = predictionYears,
                        habitatYears = resolveYearsPerSpecies(sharedSpecies, "habitat", extractYearsConfig(gen), sharedHabitatYears),
                        resolutionConfig = extractResolutionConfig(gen), climateResolutionM = sharedClimateResolutionM,
                        habitatResolutionM = sharedHabitatResolutionM, landscapeResolutionM = sharedLandscapeResolutionM,
                        climateWindowLength = sharedClimateWindowLength, reps = 1, codeRoot = repoRoot)
step <- getArg("--step"); scale <- getArg("--scale")
if (!step %in% c("algo", "ens") || !scale %in% c("climate", "landscape", "habitat")) stop("--step algo|ens and --scale climate|landscape|habitat are required")
index <- as.integer(getArg("--index", Sys.getenv("SLURM_ARRAY_TASK_ID", NA)))
threads <- as.integer(getArg("--threads", Sys.getenv("SLURM_CPUS_PER_TASK", "1")))
algo <- getArg("--algo", NULL)
members <- strsplit(getArg("--members", "brt,glm,gam,rf"), ",")[[1]]
rng <- function(x) { p <- as.integer(strsplit(x, ":", fixed = TRUE)[[1]]); if (length(p) == 1) p else p[1]:p[2] }
yrArg <- getArg("--years", NULL)
yearsOf <- function(sp) if (is.null(yrArg)) uncAllYears(cfg, sp) else sort(unique(unlist(lapply(strsplit(yrArg, ",")[[1]], rng))))
nSp <- length(sharedSpecies)
t0 <- Sys.time()
if (step == "algo") {
  if (is.na(index) || index < 1 || index > nSp) stop("--index must be 1..", nSp, " for step algo")
  if (is.null(algo) || !algo %in% ALGO_MEMBERS) stop("--algo must be one of: ", paste(ALGO_MEMBERS, collapse = ", "))
  sp <- sharedSpecies[index]
  message("=== ensemble task: algo | ", sp, " | ", scale, " | ", algo, " | run ", runName, " | threads ", threads, " ===")
  algoScaleRun(cfg, sp, scale, algo, threads = threads, years = yearsOf(sp))
} else {
  if (is.na(index) || index < 1 || index > nSp) stop("--index must be 1..", nSp, " for step ens")
  sp <- sharedSpecies[index]
  message("=== ensemble task: ens | ", sp, " | ", scale, " | members ", paste(members, collapse = "+"), " | run ", runName, " ===")
  ensembleScaleRun(cfg, sp, scale, members, years = yearsOf(sp))
}
message("=== done in ", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), " min ===")
marker <- Sys.getenv("UNC_DONE_MARKER", ""); if (nzchar(marker)) writeLines("ok", marker)
