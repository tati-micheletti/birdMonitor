#' Standalone entry point for one species x scale/meta cluster task
#'
#' Runs a REAL, small SpaDES simulation -- `simInitAndSpades()` on just the
#' `models_Monitor` module, restricted to one species and one stage via its
#' `runScale`/`runSpecies` parameters (see `models_Monitor.R`). Unlike the
#' earlier version of this script, this does NOT bypass SpaDES: every
#' cluster task gets the same automatic parameter validation, `reqdPkgs`
#' loading, and self-documentation as the full `runMe.R` pipeline -- it's
#' just told to handle one species/stage instead of all eleven. In
#' particular, SpaDES's own module loading now handles attaching `terra`
#' etc. correctly, so the manual package-loading (and the bug it needed
#' working around) this script used to do is no longer needed at all.
#'
#' Sources `sharedConfig.R` (repo root) rather than keeping its own copy of
#' species/year/resolution values, so a cluster task and the full pipeline
#' can never silently disagree on these.
#'
#' `--scale meta` self-triggers automatically from whichever of
#' europe/habitat/landscape actually finishes last for a species (see
#' `models_Monitor.R`'s `checkAllScalesReady()`) -- you don't need to
#' submit it separately in normal operation. Submitting it directly is
#' only for catching stragglers (e.g. re-running a species whose scale
#' task failed and so never self-triggered meta).
#'
#' Lives here, not in `modules/models_Monitor/R/`, because SpaDES.core
#' sources every `.R` file in a module's `R/` directory during `simInit()`
#' -- this file's top-level CLI parsing/dispatch must never run as a side
#' effect of the normal pipeline loading that module (see
#' `tools/check_duplicated_functions.R` for the sibling convention of
#' repo-root, non-module-owned utilities).
#'
#' Requires `inputs_Monitor`'s `collinearityCheck` event to have already
#' run for this `runName` (that's what writes the `_inputs.rds`/
#' `_predictors.rds` files this script reads), and for `--scale meta`
#' submitted directly, additionally requires that species'
#' europe/habitat/landscape tasks to have already completed.
#'
#' Usage (local test, one task), from the birdMonitor repo root:
#'   Rscript tools/runClusterTask.R --scale habitat --index 3 --run-name test1
#' Usage (SLURM array task -- index comes from $SLURM_ARRAY_TASK_ID if
#' --index is omitted):
#'   Rscript tools/runClusterTask.R --scale habitat --run-name test1

Sys.setenv(OMP_NUM_THREADS = "1", GDAL_NUM_THREADS = "1")

## ---- CLI argument parsing (no extra package dependency) ----------------
parseArgs <- function(args) {
  getArg <- function(flag, default = NULL) {
    i <- which(args == flag)
    if (length(i) == 0) return(default)
    args[i + 1]
  }
  slurmIdx <- Sys.getenv("SLURM_ARRAY_TASK_ID", unset = NA)
  list(
    scale    = getArg("--scale"),
    index    = as.integer(getArg("--index", slurmIdx)),
    runName  = getArg("--run-name", "test1"),
    repoRoot = getArg("--repo-root", getwd()),
    # habitat only: run chunk i of n of the prediction years (see modelGerHabitat(yearChunk))
    yearChunk = as.integer(getArg("--year-chunk", NA)),
    nChunks = as.integer(getArg("--n-chunks", NA))
  )
}

opt <- parseArgs(commandArgs(trailingOnly = TRUE))

if (is.null(opt$scale) || !opt$scale %in% c("europe", "habitat", "landscape", "meta")) {
  stop("--scale must be one of: europe, habitat, landscape, meta (got: ", opt$scale, ")")
}

## Single source of truth for species/year/resolution values -- see
## sharedConfig.R's own header for why this replaces a hand-typed copy.
source(file.path(opt$repoRoot, "tools", "sharedConfig.R"))

## Per-species/scale resolution overrides (e.g. Milvus milvus's coarser
## landscape window) -- same speciesConfig_general.csv resolutionConfig
## the full runMe.R pipeline builds, so a cluster task can never silently
## disagree with a full run on a species' resolution (see DECISIONS.md's
## 2026-09-28 entry; this replaces the old, cluster-task-only
## --landscape-resolution flag).
source(file.path(opt$repoRoot, "tools", "sharedSpeciesConfig.R"))
speciesGeneralConfigFile <- file.path(opt$repoRoot, "data", "speciesConfig_general.csv")
perSpeciesGeneralConfig <- if (file.exists(speciesGeneralConfigFile)) {
  loadSpeciesGeneralConfig(speciesGeneralConfigFile)
} else NULL
resolutionConfig <- extractResolutionConfig(perSpeciesGeneralConfig)

## Per-species fitting-year overrides (e.g. Buteo buteo/Sturnus vulgaris's
## real MhB point-count data is negligible before ~2020) -- same
## speciesConfig_general.csv years_override the full runMe.R pipeline
## resolves, so a cluster task can never silently disagree with a full run
## on a species' training-year window (see DECISIONS.md's 2026-10-01 entry).
habitatYearsConfig <- extractYearsConfig(perSpeciesGeneralConfig)

if (is.na(opt$index) || opt$index < 1 || opt$index > length(sharedSpecies)) {
  stop("--index (or $SLURM_ARRAY_TASK_ID) must be an integer between 1 and ",
       length(sharedSpecies), " -- got: ", opt$index)
}

species <- sharedSpecies[opt$index]
spClean <- gsub(" ", "_", species)

message("=== Cluster task: scale = ", opt$scale, " | species = ", species,
        " (index ", opt$index, "/", length(sharedSpecies), ") ===")

## ---- Load models_Monitor's scaleLabel() (needed below, before simInit) ----
source(file.path(opt$repoRoot, "modules", "models_Monitor", "R", "scaleLabel.R"))

scaleLabels <- c(europe = scaleLabel(sharedClimateResolutionM),
                  habitat = scaleLabel(sharedHabitatResolutionM),
                  landscape = scaleLabel(sharedLandscapeResolutionM))

## ---- Load just this one species' persisted inputs_Monitor output -------
## `meta` reads habitat-scale model_ready data, exactly as the meta event
## itself does in the full run (metaModel() trains on habitat occurrence).
inputsKey <- switch(opt$scale, europe = "europe", habitat = "gerHabitat",
                     landscape = "gerLandscape", meta = "gerHabitat")
inputsScaleLabel <- if (opt$scale == "meta") scaleLabels[["habitat"]] else scaleLabels[[opt$scale]]

inputsDir <- file.path(opt$repoRoot, "inputs", "model_ready", inputsScaleLabel)
dataFile <- file.path(inputsDir, paste0(spClean, "_inputs.rds"))
predFile <- file.path(inputsDir, paste0(spClean, "_predictors.rds"))
if (!file.exists(dataFile) || !file.exists(predFile)) {
  stop("Missing inputs_Monitor output for ", species, " at ", inputsDir,
       " -- has inputs_Monitor's collinearityCheck event run for runName '",
       opt$runName, "'?")
}

oneSpeciesEntry <- list(data = readRDS(dataFile), predictors = readRDS(predFile))
inputsData <- setNames(list(list(), list(), list()), c("europe", "gerHabitat", "gerLandscape"))
inputsData[[inputsKey]] <- setNames(list(oneSpeciesEntry), species)

## ---- Run a real, small SpaDES simulation -- models_Monitor only, one ----
## ---- species, one stage (+ meta, if this task's stage finishes last) ----
suppressMessages(library(SpaDES.core))

if (!is.null(resolutionConfig[[species]])) {
  message(species, ": resolution overrides in effect -- ",
          paste(names(resolutionConfig[[species]]), resolutionConfig[[species]], sep = "=",
                collapse = ", "),
          " (requires that species' inputs_Monitor model-ready table to already be built ",
          "at that resolution -- this script does not build it).")
}

SpaDES.core::simInitAndSpades(
  times = list(start = 2005, end = 2005),
  modules = "models_Monitor",
  objects = list(inputsData = inputsData),
  paths = list(modulePath = file.path(opt$repoRoot, "modules"),
               inputPath  = file.path(opt$repoRoot, "inputs"),
               outputPath = file.path(opt$repoRoot, "outputs", opt$runName)),
  params = list(models_Monitor = c(list(
    runScale = opt$scale,
    runSpecies = species,
    predictionYears = predictionYears,
    climateWindowLength = sharedClimateWindowLength,
    habitatYears = resolveYearsPerSpecies(species, "habitat", habitatYearsConfig, sharedHabitatYears),
    climateResolutionM = sharedClimateResolutionM,
    habitatResolutionM = sharedHabitatResolutionM,
    landscapeResolutionM = sharedLandscapeResolutionM,
    resolutionConfig = resolutionConfig
  ), if (!is.na(opt$yearChunk) && !is.na(opt$nChunks)) list(habitatYearChunk = c(opt$yearChunk, opt$nChunks))))
)

message("=== Done: ", opt$scale, " / ", species, " ===")
