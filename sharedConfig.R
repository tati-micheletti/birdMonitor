################### SHARED CONFIGURATION
# Single source of truth for values referenced by more than one module's
# params, AND by any standalone cluster task (tools/runClusterTask.R) that
# runs a module outside the full runMe.R pipeline. Several modules stop()
# with a clear error if their copies of these disagree (e.g. inputs_Monitor/
# models_Monitor's ebba2TrainingYear/climateWindowLength must match
# dataPrep_Monitor's, or the bioclim training file they look for won't
# exist) -- defining each value once here and sourcing it from every entry
# point avoids that drift the same way tools/check_duplicated_functions.R
# guards against it for the duplicated R functions. Previously these lived
# inline in runMe.R; tools/runClusterTask.R used to keep its own
# hand-typed copy, which is exactly the kind of silent-drift risk this
# file is meant to prevent -- it now sources this file too.

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
