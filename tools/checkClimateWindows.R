# Are the bioclim windows sane? READ-ONLY; exits with status 1 if any window looks broken (used before the EVE rerun, see
# cluster/rerun_after_climate_fix.sh).   Rscript tools/checkClimateWindows.R
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
suppressMessages(library(terra))
dir <- file.path("inputs", "predictors", "processed", "scale_50")
# every target year of the run needs its window: a MISSING window must stop the rerun just like a broken one (found 2026-10-08: the check
# looked only at the windows that existed, and let a run start before the corrected 2022-2025 windows had been uploaded)
source("tools/sharedConfig.R")
expected <- file.path(dir, sprintf("bioclim_%d-%d_scale_50.tif", predictionYears - (sharedClimateWindowLength - 1), predictionYears))
missingWin <- expected[!file.exists(expected)]
if (length(missingWin)) { cat("MISSING window(s):
", paste0("  ", basename(missingWin), collapse = "
"), "
"); quit(status = 1) }
fs <- sort(list.files(dir, pattern = "^bioclim_[0-9]{4}-[0-9]{4}_scale_50[.]tif$", full.names = TRUE))
de <- ext(4031000, 4672000, 2684000, 3550000)   # rough Germany, EPSG:3035
chk <- do.call(rbind, lapply(fs, function(f) { r <- crop(rast(f), de)
  v <- global(r[[c("bio1", "bio2", "bio4", "bio5", "bio7", "bio10", "bio12")]], "mean", na.rm = TRUE)[, 1]
  data.frame(window = sub("bioclim_|_scale_50[.]tif", "", basename(f)), bio1 = v[1], bio2 = v[2], bio4 = v[3], bio5 = v[4], bio7 = v[5], bio10 = v[6], bio12 = v[7],
             modified = format(file.mtime(f), "%Y-%m-%d %H:%M")) }))
options(width = 170); print(chk, row.names = FALSE, digits = 4)
bad <- chk[chk$bio1 < 6 | chk$bio1 > 12 | chk$bio2 > 9 | chk$bio4 > 800 | chk$bio7 > 30 | chk$bio10 > 22, ]
if (nrow(bad)) { cat("\nBROKEN window(s):", paste(bad$window, collapse = ", "), "\n"); quit(status = 1) }
cat("\nAll", nrow(chk), "windows look sane.\n")
