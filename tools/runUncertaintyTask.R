#' Entry point for one task of the uncertainty workflow (option B: spatial-block bootstrap of the BRTs)
#'
#' Every step is a SpaDES EVENT of models_Monitor (or, for the index intervals, of runIndex_Monitor): this script runs a
#' small simInitAndSpades() for just that event, like tools/runClusterTask.R does for the model arrays. The code is in
#' modules/models_Monitor/R/unc*.R and modules/runIndex_Monitor/R/computeIndexUncertainty.R; method and outputs:
#' modules/models_Monitor/UNCERTAINTY.md.
#'
#' Usage (from the repo root; on EVE through the cluster/eve_unc_*.sbatch scripts):
#'   Rscript tools/runUncertaintyTask.R --step <step> [--index N]
#'
#' Steps, in the order the pipeline runs them (cluster/submit_eve_uncertainty.sh chains them):
#'   preflight       once, on a login node: check that every input exists and print the problems (no SpaDES)
#'   covcache        once: write the habitat covariate stacks of all needed years     [uncertaintyCovcache]
#'   fit             per species (index = species number): refit the replicate BRTs    [uncertaintyFit]
#'   coarse          per species: predict the replicate climate and landscape BRTs    [uncertaintyCoarse]
#'   ridge           per species: fit the replicate ridge meta-models                 [uncertaintyRidge]
#'   bandpredict     per species x band (index = (species - 1) * nBands + band)       [uncertaintyBand]
#'   summarize       per species x band: percentile maps, change maps, per-pixel trend [uncertaintySummarize]
#'   assemble        per species: stitch pieces into maps, area means, parity check    [uncertaintyAssemble]
#'   community      per band (index = band): expected richness / mean change           [uncertaintyCommunity]
#'   assembleAll     once: index intervals, combined indices per replicate, community maps  [runIndex_Monitor]
#'
#' Settings come from environment variables:
#'   BIRDMONITOR_RUNNAME (baseline run folder, default test4), BIRDMONITOR_UNC_REPS (replicate ids of this run, default 0:50;
#'   0 = the main models, a built-in check; later 51:100 to add replicates), BIRDMONITOR_UNC_YEARS (e.g. 2005,2020:2025),
#'   BIRDMONITOR_UNC_BANDS (16), BIRDMONITOR_UNC_REPBATCH (10), BIRDMONITOR_UNC_CORES (SLURM_CPUS_PER_TASK),
#'   BIRDMONITOR_UNC_BLOCKMULT (1), BIRDMONITOR_UNC_PROBS (0.05,0.95), BIRDMONITOR_UNC_TAG (separate folder for
#'   test runs), BIRDMONITOR_UNC_BASELINE (2005).

Sys.setenv(OMP_NUM_THREADS = "1", GDAL_NUM_THREADS = "1")
suppressMessages(library(SpaDES.core))
args <- commandArgs(trailingOnly = TRUE)
getArg <- function(flag, default = NULL) { i <- which(args == flag); if (length(i) == 0) default else args[i + 1] }
step <- getArg("--step")
index <- as.integer(getArg("--index", Sys.getenv("SLURM_ARRAY_TASK_ID", unset = NA)))
repoRoot <- normalizePath(getArg("--repo-root", getwd()), winslash = "/")
setwd(repoRoot)

# the personal R library the pipeline installed its packages in (EVE; no-op elsewhere)
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))

env <- function(name, default = "") { v <- Sys.getenv(name, ""); if (nzchar(v)) v else default }
parseRange <- function(x) { p <- as.integer(strsplit(x, ":", fixed = TRUE)[[1]]); if (length(p) == 1) p else p[1]:p[2] }
parseYears <- function(x) sort(unique(unlist(lapply(trimws(strsplit(x, ",", fixed = TRUE)[[1]]), parseRange))))

## ---- shared configuration (species, years, resolutions): same sources as the full pipeline ----
source("tools/sharedConfig.R")
source("tools/sharedSpeciesConfig.R")
gen <- if (file.exists("data/speciesConfig_general.csv")) loadSpeciesGeneralConfig("data/speciesConfig_general.csv") else NULL
resolutionConfig <- extractResolutionConfig(gen)
habitatYearsConfig <- extractYearsConfig(gen)

runName <- env("BIRDMONITOR_RUNNAME", "test4")
reps <- parseRange(env("BIRDMONITOR_UNC_REPS", "0:50"))
outYears <- if (nzchar(env("BIRDMONITOR_UNC_YEARS"))) parseYears(env("BIRDMONITOR_UNC_YEARS")) else predictionYears
nBands <- as.integer(env("BIRDMONITOR_UNC_BANDS", "16"))
cores <- as.integer(env("BIRDMONITOR_UNC_CORES", Sys.getenv("SLURM_CPUS_PER_TASK", "1")))
probs <- as.numeric(strsplit(env("BIRDMONITOR_UNC_PROBS", "0.05,0.95"), ",")[[1]])
baselineYear <- as.integer(env("BIRDMONITOR_UNC_BASELINE", "2005"))
currentYear <- max(sharedHabitatYears)
tag <- env("BIRDMONITOR_UNC_TAG", "")
habitatYearsAll <- resolveYearsPerSpecies(sharedSpecies, "habitat", habitatYearsConfig, sharedHabitatYears)
inputRoot <- file.path(repoRoot, "inputs")
outputRoot <- file.path(repoRoot, "outputs", runName)

modelParams <- list(
  predictionYears = predictionYears, climateWindowLength = sharedClimateWindowLength, habitatYears = habitatYearsAll,
  climateResolutionM = sharedClimateResolutionM, habitatResolutionM = sharedHabitatResolutionM,
  landscapeResolutionM = sharedLandscapeResolutionM, resolutionConfig = resolutionConfig,
  uncertaintyReps = reps, uncertaintySpecies = sharedSpecies, uncertaintyYears = outYears, uncertaintyBands = nBands,
  uncertaintyRepBatch = as.integer(env("BIRDMONITOR_UNC_REPBATCH", "10")), uncertaintyCores = max(1L, cores),
  uncertaintyBlockMult = as.numeric(env("BIRDMONITOR_UNC_BLOCKMULT", "1")), uncertaintyProbs = probs,
  uncertaintyTag = tag, uncertaintyBaselineYear = baselineYear, uncertaintyCurrentYear = currentYear)

needIndex <- function(n) if (is.na(index) || index < 1 || index > n) stop("--index must be 1..", n, " for step ", step, " (got ", index, ")")
message("=== uncertainty task: step = ", step, " | run = ", runName, " | replicates ", min(reps), "-", max(reps),
        " | cores = ", cores, " | ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " ===")
t0 <- Sys.time()

runModels <- function(runScale, runSpecies = NA_character_, runBand = NA_real_) {
  SpaDES.core::simInitAndSpades(
    times = list(start = 2005, end = 2005), modules = "models_Monitor", objects = list(inputsData = list()),
    paths = list(modulePath = file.path(repoRoot, "modules"), inputPath = inputRoot, outputPath = outputRoot),
    params = list(models_Monitor = c(modelParams, list(runScale = runScale, runSpecies = runSpecies, runBand = runBand))))
}
speciesOf <- function() { needIndex(length(sharedSpecies)); sharedSpecies[index] }
speciesBand <- function() {
  needIndex(length(sharedSpecies) * nBands)
  list(sp = sharedSpecies[(index - 1L) %/% nBands + 1L], k = (index - 1L) %% nBands + 1L)
}

if (step == "preflight") {
  for (f in sort(list.files("modules/models_Monitor/R", pattern = "[.]R$", full.names = TRUE))) source(f)
  cfg <- uncCfgFromParams(inputRoot = inputRoot, outputRoot = outputRoot, species = sharedSpecies, predictionYears = predictionYears,
                          habitatYears = habitatYearsAll, resolutionConfig = resolutionConfig, climateResolutionM = sharedClimateResolutionM,
                          habitatResolutionM = sharedHabitatResolutionM, landscapeResolutionM = sharedLandscapeResolutionM,
                          climateWindowLength = sharedClimateWindowLength, reps = reps, outYears = outYears, nBands = nBands,
                          tag = tag, baselineYear = baselineYear, currentYear = currentYear, codeRoot = repoRoot)
  uncPreflight(cfg)
} else if (step == "covcache") {
  runModels("uncertaintyCovcache")
} else if (step %in% c("fit", "coarse", "ridge", "assemble")) {
  runModels(c(fit = "uncertaintyFit", coarse = "uncertaintyCoarse", ridge = "uncertaintyRidge", assemble = "uncertaintyAssemble")[[step]],
            runSpecies = speciesOf())
} else if (step %in% c("bandpredict", "summarize")) {
  sb <- speciesBand()
  message("species: ", sb$sp, " | band ", sb$k, " of ", nBands)
  runModels(c(bandpredict = "uncertaintyBand", summarize = "uncertaintySummarize")[[step]], runSpecies = sb$sp, runBand = sb$k)
} else if (step == "community") {
  needIndex(nBands)
  runModels("uncertaintyCommunity", runBand = index)
} else if (step == "assembleAll") {
  SpaDES.core::simInitAndSpades(
    times = list(start = 2005, end = 2005), modules = "runIndex_Monitor",
    paths = list(modulePath = file.path(repoRoot, "modules"), inputPath = inputRoot, outputPath = outputRoot),
    params = list(runIndex_Monitor = list(
      species = sharedSpecies, allYears = predictionYears, currentYear = currentYear, baselineYear = baselineYear,
      uncertaintyDir = file.path(outputRoot, paste0("uncertainty", if (nzchar(tag)) paste0("_", tag) else "")),
      uncertaintyOnly = TRUE, uncertaintyProbs = probs, uncertaintyBands = nBands)))
} else {
  stop("--step must be one of: preflight, covcache, fit, coarse, ridge, bandpredict, summarize, assemble, community, assembleAll (got: ", step, ")")
}
message("=== done: ", step, " in ", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), " min ===")
