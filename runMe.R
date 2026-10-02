################### PACKAGE INSTALLATION

# BIRDMONITOR_SKIP_INSTALL=1 skips this block -- for cluster jobs, where
# compute nodes have throttled internet (EVE) and packages must already be
# installed from a login node beforehand.
if (Sys.getenv("BIRDMONITOR_SKIP_INSTALL") != "1") {
  # Non-interactive R (Rscript on a cluster) has no default CRAN mirror, so
  # install.packages() would fail with "trying to use CRAN without setting a mirror".
  cranRepo <- getOption("repos")["CRAN"]
  if (is.null(cranRepo) || is.na(cranRepo) || cranRepo == "@CRAN@")
    options(repos = c(CRAN = "https://cloud.r-project.org"))
  # Cluster R installs (e.g. EVE) have a read-only system library and no personal
  # library yet, so install.packages() fails. Create one and put it first.
  if (!any(file.access(.libPaths(), 2) == 0)) {
    userLib <- Sys.getenv("R_LIBS_USER")
    if (!nzchar(userLib)) userLib <- file.path("~", "R", "library")
    dir.create(userLib, recursive = TRUE, showWarnings = FALSE)
    .libPaths(c(userLib, .libPaths()))
    message("No writable R library found; using ", userLib)
  }
  if (!require("pak")) install.packages("pak")
  pe <- "predictiveecology.r-universe.dev"
  if (!any(grepl(pe, getOption("repos"))))
    options(repos = c(pe, getOption("repos")))
  pak::pak(c("PredictiveEcology/Require@fix/pak-no-copy-ensure-in-projlint",
            "PredictiveEcology/SpaDES.core@development"),
           ask = FALSE)
}

################### SETUP

# Windows-only: the username check alone would also fire on EVE (same
# username there) and setwd() to a nonexistent Windows path. On a cluster the
# working directory is simply wherever the job was submitted from (the repo
# root).
if (.Platform$OS.type == "windows" && SpaDES.project::user("michelet"))
  setwd("C:/Users/michelet/Documents/GitHub/birdMonitor")

################### SHARED CONFIGURATION
# See sharedConfig.R -- single source of truth, also sourced by
# tools/runClusterTask.R so a cluster task and the full pipeline can never
# silently disagree on these values.
source("tools/sharedConfig.R")

################### PIPELINE STAGE (cluster runs)
# See tools/sharedStageConfig.R -- BIRDMONITOR_STAGE (all/prep/index) and
# BIRDMONITOR_RUNNAME let each non-model-fitting piece of the workflow run as
# its own SLURM job on EVE. Unset (default, local runs): everything runs in
# this one session, exactly as before.
source("tools/sharedStageConfig.R")
stageModules <- pipelineStageModules()

################### FITTING-YEARS / PREDICTION-YEARS DEPENDENCIES
# See sharedYearsConfig.R -- computes what dataPrep_Monitor's landuseYears
# actually needs to cover (every scale's fitting years, the shared
# predictionYears, and whatever hedges-backfill reference years that
# union implies) so restricting predictionYears alone never breaks
# backfill or shrinks any scale's training data. See DECISIONS.md's
# 2026-09-28 "Decouple fitting years from prediction years" entry.
source("tools/sharedYearsConfig.R")
# warnIfOutsideRealDataRange() calls against sharedHabitatYears/
# sharedLandscapeYears removed 2026-10-01: those hardcoded a single
# "real-data range" (2022:2025) that was only ever true for Buteo buteo/
# Sturnus vulgaris's MhB-routed data, not for species on DDA territories
# (genuinely real across the full 2005:2025 shared default). Per-species
# real-data constraints are now the whole POINT of years_override
# (speciesConfig_general.csv) + resolveYearsPerSpecies() below, not
# something to warn about after the fact.
landuseYearsNeeded <- sort(unique(c(sharedHabitatYears, sharedLandscapeYears, predictionYears)))
landuseYearsNeeded <- sort(unique(c(landuseYearsNeeded, computeHedgesBackfillYears(landuseYearsNeeded))))

################### PER-SPECIES/SCALE CONFIGURATION (optional)
# See sharedSpeciesConfig.R -- data/speciesConfig_general.csv/
# data/speciesConfig_predictors.csv are optional; when absent, every value
# below stays NULL and every module falls back to its shared defaults
# exactly as before these files existed. hedges is included by default now
# (see covariatePredictorColumns()); per-species exclusion goes through
# simply leaving "hedges" out of that species' row in the predictors file
# (speciesConfig_predictors.csv is the ONLY source of a species'
# predictors -- see DECISIONS.md's 2026-09-28 entry).
source("tools/sharedSpeciesConfig.R")
speciesGeneralConfigFile <- "data/speciesConfig_general.csv"
speciesPredictorsConfigFile <- "data/speciesConfig_predictors.csv"
perSpeciesGeneralConfig <- if (file.exists(speciesGeneralConfigFile)) {
  loadSpeciesGeneralConfig(speciesGeneralConfigFile)
} else NULL
speciesPredictorTable <- if (file.exists(speciesPredictorsConfigFile)) {
  loadSpeciesPredictorConfig(speciesPredictorsConfigFile)
} else NULL

# Per-species+scale resolution override (default: NA everywhere until you
# actually need a species at a non-default resolution, e.g. Milvus milvus
# at 15km landscape) -- see DECISIONS.md's 2026-09-28 entry. Distinct
# resolutions actually needed per scale are computed below and used by
# dataPrep_Monitor to generate each one exactly once (not once per species).
resolutionConfig <- extractResolutionConfig(perSpeciesGeneralConfig)
distinctResolutions <- function(scale, sharedDefault) {
  if (is.null(resolutionConfig)) return(sharedDefault)
  vals <- sapply(sharedSpecies, function(sp) {
    v <- resolutionConfig[[sp]][[scale]]
    if (is.null(v) || is.na(v)) sharedDefault else v
  })
  sort(unique(vals))
}
distinctClimateResolutions <- distinctResolutions("climate", sharedClimateResolutionM)
distinctHabitatResolutions <- distinctResolutions("habitat", sharedHabitatResolutionM)
distinctLandscapeResolutions <- distinctResolutions("landscape", sharedLandscapeResolutionM)

# Per-species fitting-year overrides (2026-10-01) -- e.g. Buteo buteo/
# Sturnus vulgaris's real MhB point-count data is negligible before ~2020,
# while DDA-territories-sourced species genuinely span the full
# sharedHabitatYears/sharedLandscapeYears default range. Resolved ONCE
# here into a complete named list (every included species gets an entry,
# either its own years_override or the shared default) and passed as-is
# into every module below -- see resolveYearsPerSpecies()
# (sharedSpeciesConfig.R) for the mechanism, and DECISIONS.md's 2026-10-01
# entry for why a single shared value could never serve both groups of
# species correctly in the same run.
yearsConfig <- extractYearsConfig(perSpeciesGeneralConfig)
habitatYearsResolved <- resolveYearsPerSpecies(sharedSpecies, "habitat", yearsConfig, sharedHabitatYears)
landscapeYearsResolved <- resolveYearsPerSpecies(sharedSpecies, "landscape", yearsConfig, sharedLandscapeYears)

# Per-species thinning distance (dataPrep_Monitor) and ATLAS_CODE/
# "Brutzeitcode" filter (habitat scale for any species; landscape scale for
# MhB-routed species only, e.g. Buteo buteo -- see DECISIONS.md) -- both
# reshaped from speciesConfig_general.csv's thinning_dist_m/
# brutzeitcode_filter columns, per species+scale.
perSpeciesThinDist <- if (!is.null(perSpeciesGeneralConfig)) {
  lapply(perSpeciesGeneralConfig, function(sp) {
    scales <- lapply(sp, function(scaleRow) scaleRow$thinning_dist_m)
    scales[!sapply(scales, is.na)]
  })
} else NULL
brutzeitcodeFilter <- if (!is.null(perSpeciesGeneralConfig)) {
  filt <- lapply(perSpeciesGeneralConfig, function(sp) {
    scales <- lapply(sp, function(scaleRow) scaleRow$brutzeitcode_filter)
    scales[!sapply(scales, is.na)]
  })
  filt <- filt[sapply(filt, length) > 0]
  if (length(filt) == 0) NULL else filt
} else NULL

# Landscape-scale data source per species (DDA territories by default; MhB
# point counts for Buteo buteo/Sturnus vulgaris -- see DECISIONS.md's
# "Buteo/Sturnus landscape data source" entry).
perSpeciesDataSource <- if (!is.null(perSpeciesGeneralConfig)) {
  src <- lapply(perSpeciesGeneralConfig, function(sp) sp$landscape$data_source)
  src <- src[!sapply(src, is.na)]
  if (length(src) == 0) NULL else src
} else NULL

# Per-species+scale opt-in for the x/y spatial trend-surface predictor --
# see DECISIONS.md's 2026-09-26 entries (deliberately opt-in, not
# blanket-applied: currently only Emberiza calandra, following up on its
# "unexplained regional clustering" finding from the 2026-09-25 results
# meeting; other species were NOT observed to need it and it carries real
# risk of overfitting/reduced transportability if applied where unneeded).
spatialTermConfig <- extractSpatialTermSpecies(perSpeciesGeneralConfig)

##################################################
#                                                #
#          Running the bird monitor              #
#                                                #
##################################################

  # Bump the BASE name by hand (test1 -> test2 -> ...) whenever a config
  # change means the previous run's cached outputs shouldn't be reused --
  # a timestamp is then always appended automatically, so every run gets
  # its own outputs/ folder regardless of whether the base name changed.
  runNameBase <- "test4"
  runName <- resolveRunName(runNameBase)

  out <- SpaDES.project::setupProject(
        Restart = FALSE,
    runName = runName,
    paths = list(projectPath = "birdMonitor",
                 inputPath = "inputs",
                 outputPath = file.path("outputs", runName),
                 # Persistent, NOT timestamped like outputPath -- reproducible::Cache()
                 # calls throughout all 3 modules use this so a config change for one
                 # species only triggers recompute for that species, across separate
                 # runMe.R invocations (not just within one run). See DECISIONS.md,
                 # 2026-09-28.
                 cachePath = "cache"),
    # Filtered to the modules of the selected BIRDMONITOR_STAGE (all four by
    # default) -- see tools/sharedStageConfig.R.
    modules = unname(c(
      dataPrep_Monitor = "tati-micheletti/dataPrep_Monitor@main", # Downloads and prepare all data
      inputs_Monitor = "tati-micheletti/inputs_Monitor@main", # Creates the "final" analysis table with options for spatial blocking and for collinearity handling
      models_Monitor = "tati-micheletti/models_Monitor@main", # Fits and predicts from the models provided
      runIndex_Monitor = "tati-micheletti/runIndex_Monitor@main" # Builds the SBI-style trend index from metaModel() output
    )[stageModules]),
    options = list(spades.allowInitDuringSimInit = TRUE,
                   reproducible.cacheSaveFormat = "rds",
                   repos = "https://cloud.r-project.org",
                   reproducible.gdalwarp = TRUE,
                   reproducible.destinationPath = file.path(getwd(), "outputs/"),
                   # Disabled 2026-10-01: every Cache() call (40+ distinct
                   # cached functions across this pipeline) also keeps its
                   # result resident in R's own memory for the rest of the
                   # session when this is TRUE, on top of the on-disk cache.
                   # Across one long session processing 3 species x multiple
                   # scales x years of large rasters, that accumulates until
                   # a large allocation fails outright -- confirmed via a
                   # real crash, `Error: ! std::bad_alloc` inside
                   # combineTwoLayerRaster()'s terra::setValues() call,
                   # always at the same point in the pipeline (Lullula
                   # arborea's 2024 meta suitability prediction) across two
                   # separate run attempts, since both ran the same
                   # cumulative amount of prior work before hitting it.
                   # Disk-cache hits across restarts are unaffected; only a
                   # repeat call within the SAME session now re-reads from
                   # disk instead of RAM, a minor cost next to crashing.
                   reproducible.useMemoise = FALSE
                   # reproducible.destinationPathShared removed -- the old
                   # "data/" shared-path workaround is superseded by
                   # inputPath(sim) (set in `paths` above), which is what
                   # every module now uses for raw/processed inputs.
    ),
    # None of the 3 modules use SpaDES "simulation time" to drive which
    # years get processed -- they're one-shot pipelines whose events all
    # schedule at time(sim) and never self-reschedule. Which years
    # actually get computed is controlled entirely by the
    # predictionYears/landuseYears/landscapeYears/habitatYears params below.
    # start = end = 2005 just satisfies simInit's requirement for a time
    # range; it has no other effect on the pipeline.
    times = list(start = 2005,
                 end = 2005),
    params = paramsForStage(list(
      dataPrep_Monitor = list(
        rastersOnly = identical(Sys.getenv("BIRDMONITOR_STAGE"), "rasters"),
        targetCRS = sharedTargetCRS,
        europeBbox = sharedEuropeBbox,
        climateResolutionM = sharedClimateResolutionM,
        habitatResolutionM = sharedHabitatResolutionM,
        landscapeResolutionM = sharedLandscapeResolutionM,
        climateTargetYears = predictionYears,
        climateWindowLength = sharedClimateWindowLength,
        ebba2TrainingYear = sharedEbba2TrainingYear,
        landuseYears = landuseYearsNeeded,
        habitatYears = habitatYearsResolved,
        landscapeYears = landscapeYearsResolved,
        species = sharedSpecies,
        localeCtype = sharedLocaleCtype,
        clmsTokenJSONPath = sharedClmsTokenJSONPath,
        perSpeciesThinDist = perSpeciesThinDist,
        brutzeitcodeFilter = brutzeitcodeFilter,
        perSpeciesDataSource = perSpeciesDataSource,
        germanNames = sharedGermanNames,
        resolutionConfig = resolutionConfig,
        distinctClimateResolutions = distinctClimateResolutions,
        distinctHabitatResolutions = distinctHabitatResolutions,
        distinctLandscapeResolutions = distinctLandscapeResolutions
        # ebba2CSVSubpath / ebba2ShpSubpath / mhbObsSubpath /
        # probeflaechenShpSubpath / ddaTerritoriesXlsxSubpath /
        # ddaVisitsXlsxSubpath / rerun* / thinDist*M (shared defaults, used
        # for any species without its own entry above): left at module
        # defaults (see dataPrep_Monitor.R) -- raw survey data must already
        # be placed at those default dataPath(sim)/raw/... locations, or
        # override the *Subpath params here to point elsewhere.
      ),
      inputs_Monitor = list(
        species = sharedSpecies,
        ebba2TrainingYear = sharedEbba2TrainingYear,
        climateWindowLength = sharedClimateWindowLength,
        habitatYears = habitatYearsResolved,
        landscapeYears = landscapeYearsResolved,
        climateResolutionM = sharedClimateResolutionM,
        habitatResolutionM = sharedHabitatResolutionM,
        landscapeResolutionM = sharedLandscapeResolutionM,
        speciesPredictorTable = speciesPredictorTable,
        spatialTermConfig = spatialTermConfig,
        resolutionConfig = resolutionConfig
        # dropCollinearPredictors: left at module default (FALSE, see
        # inputs_Monitor.R) -- a technical/algorithmic toggle, not
        # per-species/CSV-driven.
        # runSpatialBlocking / kFolds / block-size / collinearity params:
        # left at module defaults (see inputs_Monitor.R).
      ),
      models_Monitor = list(
        predictionYears = predictionYears,
        climateWindowLength = sharedClimateWindowLength,
        habitatYears = habitatYearsResolved,
        climateResolutionM = sharedClimateResolutionM,
        habitatResolutionM = sharedHabitatResolutionM,
        landscapeResolutionM = sharedLandscapeResolutionM,
        resolutionConfig = resolutionConfig
        # No scalesToRun override -- every included species now runs all 4
        # stages (climate/habitat/landscape/meta), needed for a real index
        # run and for timing a full cluster-bound batch.
        # No species param here -- models_Monitor takes its species list
        # from sim$inputsData's names(), supplied by inputs_Monitor.
        # europeInitialLR / habitatInitialLR / landscapeInitialLR /
        # rerun* flags: left at module defaults (see models_Monitor.R).
      ),
      runIndex_Monitor = list(
        species = sharedSpecies,
        baselineYear = 2005,
        allYears = predictionYears,
        currentYear = max(sharedHabitatYears),
        restrictedYears = sharedHabitatYears,
        cellSizesM = sharedRegionalCellSizesM,
        climateResolutionM = sharedClimateResolutionM,
        habitatResolutionM = sharedHabitatResolutionM,
        landscapeResolutionM = sharedLandscapeResolutionM
        # indexSpecies: left at module default (NULL -> uses `species`) --
        # set to a subset here for a restricted test report/index.
        # changeThresh / nBoot / nSim / useBootstrapSE / pollIntervalSeconds /
        # pollTimeoutHours: left at module defaults (see runIndex_Monitor.R)
        # -- the poll params only matter for a cluster run (see DECISIONS.md's
        # 2026-09-28 "runIndex_Monitor" entry).
      )
    ), stageModules),
    packages = c("terra", "yaml",
                 "PredictiveEcology/SpaDES.core@development",
                 "PredictiveEcology/reproducible@development",
                 "PredictiveEcology/Require@development (>= 1.0.1)"),
    # IMPORTANT: setupProject's git handling runs `git checkout <branch>`
    # then `git pull` on every module folder listed above. dataPrep_Monitor/
    # inputs_Monitor/models_Monitor currently have uncommitted local work
    # and their GitHub @main branches are still at the old (pre-this-
    # session) state -- pulling here could conflict with or overwrite that
    # work. runIndex_Monitor additionally has no real GitHub repo/submodule
    # yet at all (see DECISIONS.md's 2026-09-28 "runIndex_Monitor" entry) --
    # it's read straight from modules/runIndex_Monitor/ on disk regardless
    # of useGit's setting until that's set up. Left as FALSE (skip git
    # management entirely; use the module folders exactly as they already
    # exist on disk) until everything is committed and pushed. Switch back
    # to "both" afterwards for reproducible fresh-clone behaviour (e.g. on
    # Lisa's machine, or CI).
    useGit = FALSE,
    loadOrder = stageModules
  )

  # BIRDMONITOR_INSTALL_ONLY=1: setupProject() above has just installed every
  # package the pipeline needs (its own + each module's reqdPkgs). Stop here
  # without running anything -- this is how packages get installed once, from an
  # EVE login node (see README, section 3).
  if (Sys.getenv("BIRDMONITOR_INSTALL_ONLY") == "1") {
    message("BIRDMONITOR_INSTALL_ONLY=1: all packages installed. Nothing was run.")
    quit(save = "no", status = 0)
  }

  birdMonitorOutputs <- do.call(SpaDES.core::simInitAndSpades, out)

