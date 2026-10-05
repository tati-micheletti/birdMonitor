# Diagnostic: run the REAL habitat and landscape occurrence builders for ONE species/year with the real
# input files, into a temporary folder + temporary cache (nothing in inputs/ or cache/ is touched).
# ALL species are loaded (so absences are built as in the real run) but only `sp` is processed, for one year.
# Usage (repo root):  Rscript tools/probeOccurrence.R "Emberiza citrinella" 2022 2020
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
suppressMessages({library(terra); library(sf); library(dplyr); library(readxl)})
a <- commandArgs(trailingOnly = TRUE)
sp <- if (length(a) >= 1) a[1] else "Emberiza citrinella"
yrH <- as.integer(if (length(a) >= 2) a[2] else 2022)
yrL <- as.integer(if (length(a) >= 3) a[3] else 2020)
for (f in list.files("modules/dataPrep_Monitor/R", full.names = TRUE, pattern = "[.]R$")) try(source(f), silent = TRUE)
source("tools/sharedConfig.R")
tmp <- file.path(tempdir(), "probeocc"); dir.create(tmp, recursive = TRUE)
raw <- "inputs/response/raw"
cat("\n===== HABITAT:", sp, yrH, "=====\n")
t0 <- Sys.time()
r1 <- occurrencePrepGerHabitat(
  mhbObsPath = file.path(raw, "MhB/dbird_observations_CBBM.csv"),
  probeflaechenShpPath = file.path(raw, "MhB/MhB_Probeflaechen_DE_S2637_epsg25832.shp"),
  processedRoot = "inputs/predictors/processed", outputDir = file.path(tmp, "MhB"),
  species = sharedSpecies, habitatYears = setNames(lapply(sharedSpecies, function(s) if (s == sp) yrH else integer(0)), sharedSpecies), sharedResolutionM = 200,
  thinDist = 400, cachePath = file.path(tmp, "cache"))
cat("habitat done in", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), "min; files:", length(r1), "\n")
for (f in r1) { x <- readRDS(f); cat(basename(f), ": rows", nrow(x), "| has heterogeneity:", "landscape_heterogeneity" %in% names(x), "\n") }

cat("\n===== LANDSCAPE:", sp, yrL, "=====\n")
t0 <- Sys.time()
r2 <- occurrencePrepGerLandscape(
  ddaTerritoriesXlsxPath = file.path(raw, "territories/BirdStats_Daten2005-2024D_alle.xlsx"),
  ddaVisitsXlsxPath = file.path(raw, "territories/BirdStats_Visits2005-2024D.xlsx"),
  probeflaechenShpPath = file.path(raw, "MhB/MhB_Probeflaechen_DE_S2637_epsg25832.shp"),
  processedRoot = "inputs/predictors/processed", outputDir = file.path(tmp, "territories"),
  species = sharedSpecies, landscapeYears = setNames(lapply(sharedSpecies, function(s) if (s == sp) yrL else integer(0)), sharedSpecies), sharedResolutionM = 1000,
  thinDist = 2000, mhbObsPath = file.path(raw, "MhB/dbird_observations_CBBM.csv"),
  germanNames = sharedGermanNames, cachePath = file.path(tmp, "cache"))
cat("landscape done in", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), "min; files:", length(r2), "\n")
for (f in r2) { x <- readRDS(f); cat(basename(f), ": rows", nrow(x), "| columns:", paste(names(x), collapse = ","), "\n") }
