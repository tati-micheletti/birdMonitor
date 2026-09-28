################### PACKAGE INSTALLATION

if (!require("pak")) install.packages("pak")
pe <- "predictiveecology.r-universe.dev"
if (!any(grepl(pe, getOption("repos"))))
  options(repos = c(pe, getOption("repos")))
pak::pak(c("PredictiveEcology/Require@fix/pak-no-copy-ensure-in-projlint",
          "PredictiveEcology/SpaDES.core@development"),
         ask = FALSE)

################### SETUP

if (SpaDES.project::user("michelet")) setwd("C:/Users/michelet/Documents/GitHub/birdMonitor")

################### SHARED CONFIGURATION
# See sharedConfig.R -- single source of truth, also sourced by
# tools/runClusterTask.R so a cluster task and the full pipeline can never
# silently disagree on these values.
source("sharedConfig.R")

################### PER-SPECIES/SCALE CONFIGURATION (optional)
# See sharedSpeciesConfig.R -- data/speciesConfig_general.csv/
# data/speciesConfig_predictors.csv are optional; when absent, every value
# below stays NULL and every module falls back to its shared defaults
# exactly as before these files existed. hedges is included by default now
# (see covariatePredictorColumns()); per-species exclusion goes through
# simply leaving "hedges" out of that species' row in the predictors file
# (speciesConfig_predictors.csv is the ONLY source of a species'
# predictors -- see DECISIONS.md's 2026-09-28 entry).
source("sharedSpeciesConfig.R")
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
  runNameBase <- "test2"
  runName <- paste0(runNameBase, "_", format(Sys.time(), "%Y%m%d_%H%M%S"))

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
    modules =c(
      "tati-micheletti/dataPrep_Monitor@main", # Downloads and prepare all data
      "tati-micheletti/inputs_Monitor@main", # Creates the "final" analysis table with options for spatial blocking and for collinearity handling
      "tati-micheletti/models_Monitor@main" # Fits and predicts from the models provided
    ),
    options = list(spades.allowInitDuringSimInit = TRUE,
                   reproducible.cacheSaveFormat = "rds",
                   repos = "https://cloud.r-project.org",
                   reproducible.gdalwarp = TRUE,
                   reproducible.destinationPath = file.path(getwd(), "outputs/"),
                   reproducible.useMemoise = TRUE
                   # reproducible.destinationPathShared removed -- the old
                   # "data/" shared-path workaround is superseded by
                   # inputPath(sim) (set in `paths` above), which is what
                   # every module now uses for raw/processed inputs.
    ),
    # None of the 3 modules use SpaDES "simulation time" to drive which
    # years get processed -- they're one-shot pipelines whose events all
    # schedule at time(sim) and never self-reschedule. Which years
    # actually get computed is controlled entirely by the
    # climateTargetYears/landscapeYears/habitatYears params below.
    # start = end = 2005 just satisfies simInit's requirement for a time
    # range; it has no other effect on the pipeline.
    times = list(start = 2005,
                 end = 2005),
    params = list(
      dataPrep_Monitor = list(
        targetCRS = sharedTargetCRS,
        europeBbox = sharedEuropeBbox,
        climateResolutionM = sharedClimateResolutionM,
        habitatResolutionM = sharedHabitatResolutionM,
        landscapeResolutionM = sharedLandscapeResolutionM,
        climateTargetYears = sharedClimateTargetYears,
        climateWindowLength = sharedClimateWindowLength,
        ebba2TrainingYear = sharedEbba2TrainingYear,
        landuseYears = sharedLandscapeYears,
        habitatYears = sharedHabitatYears,
        landscapeYears = sharedLandscapeYears,
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
        climateTargetYears = sharedClimateTargetYears,
        climateWindowLength = sharedClimateWindowLength,
        landscapeYears = sharedLandscapeYears,
        habitatYears = sharedHabitatYears,
        climateResolutionM = sharedClimateResolutionM,
        habitatResolutionM = sharedHabitatResolutionM,
        landscapeResolutionM = sharedLandscapeResolutionM,
        resolutionConfig = resolutionConfig
        # No species param here -- models_Monitor takes its species list
        # from sim$inputsData's names(), supplied by inputs_Monitor.
        # europeInitialLR / habitatInitialLR / landscapeInitialLR /
        # rerun* flags: left at module defaults (see models_Monitor.R).
      )
    ),
    packages = c("terra", "yaml",
                 "PredictiveEcology/SpaDES.core@development",
                 "PredictiveEcology/reproducible@development",
                 "PredictiveEcology/Require@development (>= 1.0.1)"),
    # IMPORTANT: setupProject's git handling runs `git checkout <branch>`
    # then `git pull` on every module folder listed above. All three
    # modules currently have uncommitted local work and their GitHub
    # @main branches are still at the old (pre-this-session) state --
    # pulling here could conflict with or overwrite that work. Left as
    # FALSE (skip git management entirely; use the module folders
    # exactly as they already exist on disk) until everything is
    # committed and pushed. Switch back to "both" afterwards for
    # reproducible fresh-clone behaviour (e.g. on Lisa's machine, or CI).
    useGit = FALSE,
    loadOrder = c(
      "dataPrep_Monitor", "inputs_Monitor", "models_Monitor"
    )
  )

  birdMonitorOutputs <- do.call(SpaDES.core::simInitAndSpades, out)

