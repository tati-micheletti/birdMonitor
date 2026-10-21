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

# Canonical species roster + Latin<->German name lookup -- see
# data/speciesCanonical.csv and sharedSpeciesCanonical.R for the full
# rationale. ONE source of truth for both "which species does the pipeline
# run" (sharedSpecies, below) and "what's this species' German name"
# (sharedGermanNames, below -- needed because the raw DDA territories data
# has no Latin-name column at all, only German). Previously these were two
# separate, manually-synced things (a hardcoded vector here, plus a
# completely separate speciesLookup() data.frame in dataPrep_Monitor) with
# no validation tying them together -- exactly why adding Anthus pratensis
# here on 2026-09-24 didn't also update the other file, silently producing
# 0 presences at habitat/landscape scale until caught live in a test run.
# Milvus milvus is flagged excluded (include column blank) as of
# 2026-09-26, finally implementing the 2026-09-24 Confluence decision to
# drop it from scope (see project_birdmonitor_confluence_decisions memory).
source("tools/sharedSpeciesCanonical.R")
speciesCanonical <- loadSpeciesCanonical("data/speciesCanonical.csv")
sharedSpecies <- canonicalIncludedSpecies(speciesCanonical)
# DEBUG ONLY: BIRDMONITOR_SPECIES="Emberiza citrinella;Emberiza calandra" restricts the run to those species
# (semicolon-separated Latin names) for a fast test of the real pipeline. Unset = the full roster.
local({
  dbg <- Sys.getenv("BIRDMONITOR_SPECIES", "")
  if (nzchar(dbg)) {
    keep <- trimws(strsplit(dbg, ";")[[1]])
    unknown <- setdiff(keep, sharedSpecies)
    if (length(unknown)) stop("BIRDMONITOR_SPECIES contains species not in the roster: ", paste(unknown, collapse = ", "), call. = FALSE)
    sharedSpecies <<- sharedSpecies[sharedSpecies %in% keep]
    message("BIRDMONITOR_SPECIES set -- running ONLY: ", paste(sharedSpecies, collapse = ", "))
  }
})
sharedGermanNames <- canonicalGermanNames(speciesCanonical, sharedSpecies)

sharedTargetCRS <- "EPSG:3035"
sharedEuropeBbox <- c(72, -25, 34, 45)  # N, W, S, E (WGS84) -- also used as the DEM download extent
sharedClimateResolutionM <- 50000
sharedHabitatResolutionM <- 200
sharedLandscapeResolutionM <- 1000

# Years to generate PREDICTION rasters for -- climate/habitat/landscape
# scales and the meta-model all predict onto this same range. Independent
# of each scale's own FITTING years below (see sharedYearsConfig.R/
# DECISIONS.md's 2026-09-28 "Decouple fitting years from prediction years"
# entry) -- restricting this alone (e.g. to a handful of test years) never
# shrinks any scale's training data, and dataPrep_Monitor automatically
# generates whatever extra years fitting/backfill structurally need on top
# of it (see runMe.R's landuseYearsNeeded). Deliberately no `shared` prefix
# -- unlike the other sharedX values, it's used as-is everywhere, never
# transformed before being passed into a module's params.
# Widened back to the full range 2026-10-01 -- the 2022:2025 narrowing was
# specific to the Buteo buteo/Sturnus vulgaris DDA-fix comparison test and
# is no longer in effect now that Lanius collurio/Lullula arborea (full
# 2005:2025 DDA-territories data) are back in scope for a real, full
# cluster-timing run.
predictionYears <- 2005:2025

sharedClimateWindowLength <- 6
sharedEbba2TrainingYear <- 2017          # -> bioclim_2012-2017.tif is the EBBA2 training climatology

# Landscape-scale FITTING years only (DDA territory data's real
# availability) -- no longer also the prediction range, see
# `predictionYears` above.
# Widened back to the full range 2026-10-01 (see predictionYears above for
# why) -- DDA territories genuinely span 2005:2025, and real MhB
# point-count occurrence data for the habitat-scale species in scope now
# also goes back to 2005 (confirmed via actual historical
# Lanius_collurio_habitat_2005.rds-era files). The 2022:2025 narrowing
# was specific to Buteo buteo/Sturnus vulgaris's MhB-routed landscape
# data; both habitat's fitting-year constraint AND metaModel's training
# window share this same value (see DECISIONS.md's 2026-09-28 entry).
sharedLandscapeYears <- 2005:2025
sharedHabitatYears <- 2005:2025

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
# THE STUDY AREA of the whole pipeline (DECISIONS.md 2026-10-21): one definition, everything else follows. Predictor layers are cropped and masked to it when they are made,
# response records are filtered by it, models are fitted and predicted on it. Change it and the pipeline runs for another area (a state, several countries, Europe, a shapefile).
#   list(label, countries = ISO3 codes (GADM level 0), regions = names of GADM level-1 regions or NULL (= the whole country), shapefile = path or NULL)
# Environment (one run for another area, nothing else to change):  BIRDMONITOR_STUDY_AREA="DEU:Sachsen"   "DEU,AUT"   "DEU"   "/path/area.shp"   (label: BIRDMONITOR_STUDY_AREA_LABEL)
# Buffers (m) around the area: records and the habitat/landscape layers; the PREDICTION windows of the climate scale (one 50 km cell, for the resampling at the border).
# The climate model itself is fitted on all of Europe (EBBA2): its training window is not cropped.
sharedStudyArea <- list(label = "Germany", countries = "DEU", regions = NULL, shapefile = NULL)
local({
  sa <- Sys.getenv("BIRDMONITOR_STUDY_AREA", "")
  if (nzchar(sa)) {
    spec <- if (grepl("[.](shp|gpkg|geojson)$", sa, ignore.case = TRUE)) list(label = tools::file_path_sans_ext(basename(sa)), countries = NULL, regions = NULL, shapefile = sa) else {
      parts <- strsplit(sa, ":", fixed = TRUE)[[1]]
      cc <- trimws(strsplit(parts[1], ",", fixed = TRUE)[[1]]); rg <- if (length(parts) > 1) trimws(strsplit(parts[2], ";", fixed = TRUE)[[1]]) else NULL
      list(label = paste(c(cc, rg), collapse = "-"), countries = cc, regions = rg, shapefile = NULL)
    }
    lab <- Sys.getenv("BIRDMONITOR_STUDY_AREA_LABEL", ""); if (nzchar(lab)) spec$label <- lab
    sharedStudyArea <<- spec
  }
})
sharedRecordsBufferM <- 1000
sharedClimatePredictBufferM <- 50000

# BIRDMONITOR_REGIONAL_KM="10" restricts a run to the grid sizes (km, comma-separated) given: the Bird Monitor shows only the 10 km map, so an update of what the
# Monitor shows can skip the 20 and 50 km grids (the regional steps then take about a third of the time). Unset = all three, as before.
sharedRegionalCellSizesM <- c(10000, 20000, 50000)
local({
  km <- Sys.getenv("BIRDMONITOR_REGIONAL_KM", "")
  if (nzchar(km)) {
    want <- as.numeric(strsplit(km, ",")[[1]]) * 1000
    if (anyNA(want) || !all(want %in% sharedRegionalCellSizesM)) stop("BIRDMONITOR_REGIONAL_KM must be a comma-separated subset of 10,20,50 (got: ", km, ")", call. = FALSE)
    sharedRegionalCellSizesM <<- sharedRegionalCellSizesM[sharedRegionalCellSizesM %in% want]
  }
})

# Your personal CLMS API token for CORINE Land Cover downloads (see the
# setup steps at the top of dataPrep_Monitor/python/download_landcover.py).
# Deliberately kept OUTSIDE any git-tracked folder -- never move this
# into modules/ or any other repo path.
sharedClmsTokenJSONPath <- "C:/Users/michelet/.clms/clms_token.json"
