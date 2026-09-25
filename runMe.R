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
# See sharedSpeciesConfig.R -- speciesConfig_general.csv/
# speciesConfig_predictors.csv are optional; when absent, every *Config
# value below stays NULL and every module falls back to its shared
# defaults exactly as before these files existed.
source("sharedSpeciesConfig.R")
speciesGeneralConfigFile <- "speciesConfig_general.csv"
speciesPredictorsConfigFile <- "speciesConfig_predictors.csv"
perSpeciesGeneralConfig <- if (file.exists(speciesGeneralConfigFile)) {
  loadSpeciesGeneralConfig(speciesGeneralConfigFile)
} else NULL
perSpeciesExtraCandidates <- if (file.exists(speciesPredictorsConfigFile)) {
  loadSpeciesPredictorExtras(speciesPredictorsConfigFile)
} else NULL
# inputs_Monitor only needs the hedges_treatment slice of the general
# config (resolution_m/thinning_dist_m/brutzeitcode_filter go to
# dataPrep_Monitor once those are wired -- see sharedSpeciesConfig.R's
# docstring for what's actually consumed where as of 2026-09-25).
perSpeciesHedges <- if (!is.null(perSpeciesGeneralConfig)) {
  lapply(perSpeciesGeneralConfig, function(sp) {
    # Blank/NA hedges_treatment (always true for the climate row -- hedges
    # isn't a climate covariate) is dropped here, not just left as NA, so
    # extractScaleExtras() never hands a scale an invalid non-drop/backfill
    # value regardless of which scale asks for it.
    scales <- lapply(sp, function(scaleRow) scaleRow$hedges_treatment)
    scales[!sapply(scales, is.na)]
  })
} else NULL

##################################################
#                                                #
#          Running the bird monitor              #
#                                                #
##################################################

  runName <- "test1"

  out <- SpaDES.project::setupProject(
        Restart = FALSE,
    runName = runName,
    paths = list(projectPath = "birdMonitor",
                 inputPath = "inputs",
                 outputPath = file.path("outputs", runName)),
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
        clmsTokenJSONPath = sharedClmsTokenJSONPath
        # ebba2CSVSubpath / ebba2ShpSubpath / mhbObsSubpath /
        # probeflaechenShpSubpath / ddaTerritoriesXlsxSubpath /
        # ddaVisitsXlsxSubpath / rerun* : left at module defaults (see
        # dataPrep_Monitor.R) -- raw survey data must already be placed
        # at those default dataPath(sim)/raw/... locations, or override
        # the *Subpath params here to point elsewhere.
      ),
      inputs_Monitor = list(
        species = sharedSpecies,
        ebba2TrainingYear = sharedEbba2TrainingYear,
        climateWindowLength = sharedClimateWindowLength,
        climateResolutionM = sharedClimateResolutionM,
        habitatResolutionM = sharedHabitatResolutionM,
        landscapeResolutionM = sharedLandscapeResolutionM,
        perSpeciesHedges = perSpeciesHedges,
        perSpeciesExtraCandidates = perSpeciesExtraCandidates
        # runSpatialBlocking / runCollinearityCheck / predictorsToUse /
        # kFolds / block-size / collinearity params: left at module
        # defaults (see inputs_Monitor.R) -- override here to A/B
        # spatial-blocking or collinearity-filtering strategies.
      ),
      models_Monitor = list(
        climateTargetYears = sharedClimateTargetYears,
        climateWindowLength = sharedClimateWindowLength,
        landscapeYears = sharedLandscapeYears,
        habitatYears = sharedHabitatYears,
        climateResolutionM = sharedClimateResolutionM,
        habitatResolutionM = sharedHabitatResolutionM,
        landscapeResolutionM = sharedLandscapeResolutionM,
        perSpeciesGeneralConfig = perSpeciesGeneralConfig
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

