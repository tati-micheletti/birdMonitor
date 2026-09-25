################### RUN THE MULTI-SPECIES INDEX/REPORT
# Run this AFTER runMe.R has finished (needs metaModel()'s already-computed
# per-species/year prediction rasters -- no new model fitting happens here).
# Not part of runMe.R's own SpaDES event flow: the index/report functions
# (models_Monitor/R/computeAnnualReport.R, computeRegionalIndex.R, and their
# dependencies) are auto-sourced by SpaDES.core when models_Monitor loads,
# but nothing calls them automatically -- this script is the actual entry
# point. See README.md's "Multi-species index" section for what each output
# file is and how to read it.

if (SpaDES.project::user("michelet")) setwd("C:/Users/michelet/Documents/GitHub/birdMonitor")

source("sharedConfig.R")

# The index/report functions below (computeAnnualReport, computeRegionalIndex,
# metamodelLabel, and everything they call) live in modules/models_Monitor/R/
# and are normally auto-sourced by SpaDES.core when that module loads during
# simInit() -- which only happens inside runMe.R's own session. Running this
# script afterwards, in a fresh R session, needs them sourced explicitly.
invisible(lapply(list.files("modules/models_Monitor/R", pattern = "\\.R$", full.names = TRUE), source))

##################################################
#                                                #
#     EDIT THESE FOR YOUR TEST/RUN              #
#                                                #
##################################################

# Must match the runName the corresponding runMe.R run actually used (see
# its console output, or list outputs/ -- it's timestamped, e.g.
# "test1_20260927_091500"). The metamodel/report outputs are read from/
# written under outputs/<runName>/.
runName <- "test1_CHANGE_ME"

# The species this index/report covers -- must be a subset of whatever
# species runMe.R was actually run with (sharedSpecies, or your own edited
# subset -- see README.md's "Running a species subset" section). Indices
# and change maps are meaningless for a species with no metaModel() output.
indexSpecies <- sharedSpecies

# baselineYear: fixed at 2005 (first year with genuinely real landscape-
# scale training data -- see computeSpeciesIndex.R's docstring). Change
# only if you deliberately want a different baseline for a test.
baselineYear <- 2005
currentYear <- max(sharedHabitatYears)      # the report is "for" this year
allYears <- sharedLandscapeYears            # full index time series range
restrictedYears <- sharedHabitatYears       # non-hindcast years, for the
                                             # Chain-index robustness check

##################################################

resolutionsM <- c(europe = sharedClimateResolutionM,
                   landscape = sharedLandscapeResolutionM,
                   habitat = sharedHabitatResolutionM)
metaDir <- file.path("outputs", runName, metamodelLabel(resolutionsM))
if (!dir.exists(metaDir)) {
  stop("No metaModel() output found at: ", metaDir, "\n",
       "Check that runName above matches a completed runMe.R run.")
}

reportDir <- file.path("outputs", runName, "annual_report")
regionalDir <- file.path("outputs", runName, "regional_index")

## ---- Germany boundary (for computeRegionalIndex()'s countryBoundary) -------
# Same GADM level-0 fetch/cache pattern as tools/maskToGermany.R -- avoids
# cells straddling the border silently averaging in non-German source data.
germanyBoundary <- NULL
if (requireNamespace("geodata", quietly = TRUE)) {
  gadmCacheDir <- file.path("inputs", "predictors", "raw", "gadm")
  dir.create(gadmCacheDir, recursive = TRUE, showWarnings = FALSE)
  germanyBoundary <- geodata::gadm(country = "DEU", level = 0, path = gadmCacheDir)
} else {
  warning("'geodata' package not installed -- computeRegionalIndex() will run ",
          "without a country boundary (cells near the border may average in ",
          "non-German source data). install.packages('geodata') to fix.")
}

## ---- 1. Annual report: per-species + 4 combined-index methods, SR map, -----
## ----    change maps ---------------------------------------------------------
message("=== Annual report (", currentYear, ") ===")
report <- computeAnnualReport(
  species = indexSpecies,
  baselineYear = baselineYear,
  currentYear = currentYear,
  allYears = allYears,
  metaDir = metaDir,
  outputDir = reportDir,
  restrictedYears = restrictedYears)

## ---- 2. Regional gridded + smoothed index maps (10/20/50km) ----------------
message("\n=== Regional index maps ===")
regional <- computeRegionalIndex(
  species = indexSpecies,
  years = allYears,
  baselineYear = baselineYear,
  metaDir = metaDir,
  outputDir = regionalDir,
  cellSizesM = sharedRegionalCellSizesM,
  countryBoundary = germanyBoundary)

message("\nDone. Report -> ", reportDir, " | Regional maps -> ", regionalDir)
