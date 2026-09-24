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

# Canonical species roster -- the single source of truth for which species
# the whole pipeline runs (nothing downstream should hardcode a species
# count; always derive it from length(sharedSpecies)/nrow() on data keyed
# by this list). Updated per the Steering Consortium's revised list:
# Anthus pratensis (Wiesenpieper) newly added; no species dropped from the
# prior 11 -- Anthus pratensis has no model outputs yet, so it will show as
# pending in any report until dataPrep/inputs/models are run for it.
sharedSpecies <- c("Vanellus vanellus", "Milvus milvus", "Lanius collurio",
                   "Lullula arborea", "Alauda arvensis", "Saxicola rubetra",
                   "Emberiza calandra", "Emberiza citrinella", "Buteo buteo",
                   "Sturnus vulgaris", "Perdix perdix", "Anthus pratensis")

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

# Canonical regional-index grid resolutions (computeRegionalIndex()) -- the
# single source of truth for which coarse grid sizes get computed. Nothing
# downstream (scripts, computeRegionalIndex()'s own signature) should
# hardcode 10km/20km/50km or any other cell size; they should all read
# this. Currently 10/20/50km: 10km added as a middle ground between the
# original 20/50km (whose smoothing looked "mild" at that coarseness);
# held off on 5km since it starts to approach identifying individual
# localities, which cuts against the reason these grids exist in the
# first place (a regional picture without pointing at specific areas).
sharedRegionalCellSizesM <- c(10000, 20000, 50000)

# Your personal CLMS API token for CORINE Land Cover downloads (see the
# setup steps at the top of dataPrep_Monitor/python/download_landcover.py).
# Deliberately kept OUTSIDE any git-tracked folder -- never move this
# into modules/ or any other repo path.
sharedClmsTokenJSONPath <- "C:/Users/michelet/.clms/clms_token.json"
