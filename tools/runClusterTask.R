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
    repoRoot = getArg("--repo-root", getwd())
  )
}

opt <- parseArgs(commandArgs(trailingOnly = TRUE))

if (is.null(opt$scale) || !opt$scale %in% c("europe", "habitat", "landscape", "meta")) {
  stop("--scale must be one of: europe, habitat, landscape, meta (got: ", opt$scale, ")")
}

## Single source of truth for species/year/resolution values -- see
## sharedConfig.R's own header for why this replaces a hand-typed copy.
source(file.path(opt$repoRoot, "sharedConfig.R"))

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

SpaDES.core::simInitAndSpades(
  times = list(start = 2005, end = 2005),
  modules = "models_Monitor",
  objects = list(inputsData = inputsData),
  paths = list(modulePath = file.path(opt$repoRoot, "modules"),
               inputPath  = file.path(opt$repoRoot, "inputs"),
               outputPath = file.path(opt$repoRoot, "outputs", opt$runName)),
  params = list(models_Monitor = list(
    runScale = opt$scale,
    runSpecies = species,
    climateTargetYears = sharedClimateTargetYears,
    climateWindowLength = sharedClimateWindowLength,
    landscapeYears = sharedLandscapeYears,
    habitatYears = sharedHabitatYears,
    climateResolutionM = sharedClimateResolutionM,
    habitatResolutionM = sharedHabitatResolutionM,
    landscapeResolutionM = sharedLandscapeResolutionM
  ))
)

message("=== Done: ", opt$scale, " / ", species, " ===")
