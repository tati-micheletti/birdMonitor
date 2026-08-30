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
# Single source of truth for values referenced by more than one module's
# params below. Several modules stop() with a clear error if their
# copies of these disagree (e.g. inputs_Monitor/models_Monitor's
# ebba2TrainingYear/climateWindowLength must match dataPrep_Monitor's,
# or the bioclim training file they look for won't exist) -- defining
# each value once here and reusing it in every params = list(...) block
# below avoids that drift the same way tools/check_duplicated_functions.R
# guards against it for the duplicated R functions.

sharedSpecies <- c("Vanellus vanellus", "Milvus milvus", "Lanius collurio",
                   "Lullula arborea", "Alauda arvensis", "Saxicola rubetra",
                   "Emberiza calandra", "Emberiza citrinella", "Buteo buteo",
                   "Sturnus vulgaris", "Perdix perdix")

sharedTargetCRS <- "EPSG:3035"
sharedEuropeBbox <- c(72, -25, 34, 45)  # N, W, S, E (WGS84) -- also used as the DEM download extent
sharedClimateResolutionM <- 50000
sharedHabitatResolutionM <- 200
sharedLandscapeResolutionM <- 1000

sharedClimateTargetYears <- 2005:2025
sharedClimateWindowLength <- 6
sharedEbba2TrainingYear <- 2017          # -> bioclim_2012-2017.tif is the EBBA2 training climatology

sharedLandscapeYears <- 2005:2025        # also used as the habitat/landscape/meta PREDICTION range
sharedHabitatYears <- 2022:2025          # the only years real MhB point-count occurrence data exists

sharedLocaleCtype <- "de_DE.UTF-8"

# Your personal CLMS API token for CORINE Land Cover downloads (see the
# setup steps at the top of dataPrep_Monitor/python/download_landcover.py).
# Deliberately kept OUTSIDE any git-tracked folder -- never move this
# into modules/ or any other repo path.
sharedClmsTokenJSONPath <- "C:/Users/michelet/.clms/clms_token.json"

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
                   reproducible.destinationPathShared = file.path(getwd(), "data/"),
                   reproducible.destinationPath = file.path(getwd(), "outputs/"),
                   reproducible.useMemoise = TRUE
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
        climateWindowLength = sharedClimateWindowLength
        # runSpatialBlocking / runCollinearityCheck / predictorsToUse /
        # kFolds / block-size / collinearity params: left at module
        # defaults (see inputs_Monitor.R) -- override here to A/B
        # spatial-blocking or collinearity-filtering strategies.
      ),
      models_Monitor = list(
        climateTargetYears = sharedClimateTargetYears,
        climateWindowLength = sharedClimateWindowLength,
        landscapeYears = sharedLandscapeYears,
        habitatYears = sharedHabitatYears
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

