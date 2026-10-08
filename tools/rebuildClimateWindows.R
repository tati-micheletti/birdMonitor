# Rebuild the bioclim windows whose monthly temperature came from the daily CHELSA files (target years 2022-2025) with the FIXED
# aggregation (mean of the daily minima/maxima; fill values removed; months with < 90% of their days not used).
# See DECISIONS.md, 2026-10-07. Run on the PC that holds the inputs, from the repo root:
#
#   Rscript tools/rebuildClimateWindows.R            # default: target years 2022:2025
#
# What it does, in order:
#   1. MOVES (never deletes) the existing bioclim files of those target years into
#      inputs/predictors/processed/scale_50/_old_before_dmean_fix_2026-10-07/ (both the *_scale_50.tif and the plain *.tif twins).
#   2. Downloads the daily tasmin/tasmax of 2022-01-01 .. 2025-09-30 (about 2,740 files; CHELSA ends on 2025-09-30), averages them to
#      months (files cached as inputs/predictors/raw/chelsa_monthly/europe/<var>_<year>_<month>_dmean.tif) and rebuilds the windows.
#      Precipitation is NOT touched (its cached months are fine). Roughly 1-2 hours, mostly download time; it can be stopped and
#      restarted: finished months are kept.
#   3. Prints a check table: the mean temperature statistics of ALL windows, which must now vary smoothly across 2021/2022.
args <- commandArgs(trailingOnly = TRUE)
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
suppressMessages({ library(terra); library(dismo); library(raster) })
for (f in list.files("modules/dataPrep_Monitor/R", pattern = "[.]R$", full.names = TRUE)) source(f)
source("tools/sharedConfig.R")
targetYears <- 2022:2025
winLen <- sharedClimateWindowLength; res <- sharedClimateResolutionM
outDir <- file.path("inputs", "predictors", "processed", scaleLabel(res))
rawDir <- file.path("inputs", "predictors", "raw", "chelsa_monthly", "europe")
backup <- file.path(outDir, "_old_before_dmean_fix_2026-10-07"); dir.create(backup, showWarnings = FALSE)

# 1. move the old windows aside
old <- unlist(lapply(targetYears, function(y) {
  b <- paste0("bioclim_", y - (winLen - 1), "-", y)
  file.path(outDir, c(paste0(b, ".tif"), paste0(b, "_", scaleLabel(res), ".tif"))) }))
old <- old[file.exists(old)]
for (f in old) { to <- file.path(backup, basename(f)); if (file.exists(to)) stop("Already in the backup folder: ", to); file.rename(f, to); message("moved aside: ", basename(f)) }
if (!length(old)) message("(no old window files found for ", paste(targetYears, collapse = ","), " -- nothing to move)")

# 2. rebuild
prepareClimateData(climateTargetYears = targetYears, climateWindowLength = winLen, europeBboxVec = c(72, -25, 34, 45),
                   targetCRS = "EPSG:3035", climateResolutionM = res, chelsaMonthlyDir = rawDir, climateOutputDir = outDir)

# 3. check
de <- ext(4031000, 4672000, 2684000, 3550000)   # rough Germany, EPSG:3035
fs <- sort(list.files(outDir, pattern = paste0("^bioclim_[0-9]{4}-[0-9]{4}_", scaleLabel(res), "[.]tif$"), full.names = TRUE))
chk <- do.call(rbind, lapply(fs, function(f) { r <- crop(rast(f), de); v <- global(r[[c("bio1", "bio2", "bio4", "bio5", "bio7", "bio10", "bio12")]], "mean", na.rm = TRUE)[, 1]
  data.frame(window = sub("bioclim_|_scale_50[.]tif", "", basename(f)), bio1 = v[1], bio2 = v[2], bio4 = v[3], bio5 = v[4], bio7 = v[5], bio10 = v[6], bio12 = v[7]) }))
options(width = 160); print(chk, row.names = FALSE, digits = 4)
cat("\nOK when bio2 stays near 6.5-7, bio4 near 640-670, bio7 near 24-25, bio10 near 17-19 and nothing jumps at the 2017-2022 .. 2020-2025 windows.\n")
