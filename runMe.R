################### PACKAGE INSTALLATION

if (!require("pak")) install.packages("pak")
pe <- "predictiveecology.r-universe.dev"
if (!any(grepl(pe, getOption("repos"))))
  options(repos = c(pe, getOption("repos")))
pak::pak(c("PredictiveEcology/Require@fix/pak-no-copy-ensure-in-projlint",
           "PredictiveEcology/SpaDES.project@development",
          "PredictiveEcology/SpaDES.core@development"),
         ask = FALSE)

################### SETUP

# if (SpaDES.project::user("michelet")) setwd("c:/Users/michelet/Documents/GitHub/birdMonitor")

##################################################
#                                                #
#          Running the bird monitor              #
#                                                #
##################################################

  runName <- "test1"
  
  out <- SpaDES.project::setupProject(
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
    times = list(start = 2005,
                 end = 2005),
    params = list(),
    packages = c("terra", "yaml",
                 "PredictiveEcology/SpaDES.core@development",
                 "PredictiveEcology/reproducible@development",
                 "PredictiveEcology/Require@development (>= 1.0.1)"),
    useGit = "both",
    restart = FALSE,
    loadOrder = c(
      "dataPrep_Monitor", "inputs_Monitor", "models_Monitor"
    )
  )
    
  birdMonitorOutputs <- do.call(SpaDES.core::simInitAndSpades, out)
  