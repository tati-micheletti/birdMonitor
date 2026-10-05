# Diagnostic (EVE): resample a Europe-wide covariate onto the Germany habitat grid, exactly like
# occurrencePrepGerHabitat() does, and report the NA fraction + any GDAL warnings. Tries variants.
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
suppressMessages(library(terra))
cat("terra", as.character(packageVersion("terra")), "| GDAL/PROJ/GEOS:", paste(unlist(gdal(lib = TRUE)[1, 1:3]), collapse = " / "), "\n\n")
dir <- "inputs/predictors/processed/scale_02"
elev <- rast(file.path(dir, "elevation_habitat_scale_02.tif"))
lu   <- rast(file.path(dir, "landuse_2022_habitat_scale_02.tif"))[[1]]
cat("elevation:", ncell(elev), "cells | grid:", ncell(lu), "cells\n\n")

run <- function(label, f) {
  w <- character()
  t0 <- Sys.time()
  res <- withCallingHandlers(tryCatch(f(), error = function(e) { message("   ERROR: ", conditionMessage(e)); NULL }),
                             warning = function(x) { w <<- c(w, conditionMessage(x)); invokeRestart("muffleWarning") })
  if (is.null(res)) { cat(sprintf("%-52s FAILED\n", label)); return(invisible()) }
  v <- values(res, mat = FALSE)
  cat(sprintf("%-52s NA%%=%5.1f  mean=%8.2f  (%.0fs)%s\n", label, 100 * mean(is.na(v)), mean(v, na.rm = TRUE),
              as.numeric(difftime(Sys.time(), t0, units = "secs")),
              if (length(w)) paste0("  WARN: ", unique(w)[1]) else ""))
}
run("A resample(elev, grid)  [current code]", function() resample(elev, lu, method = "bilinear"))
e2 <- elev; crs(e2) <- "EPSG:3035"; l2 <- lu; crs(l2) <- "EPSG:3035"
run("B relabel both CRS to EPSG:3035, resample", function() resample(e2, l2, method = "bilinear"))
run("C crop elev to the grid extent, then resample", function() resample(crop(elev, ext(lu)), lu, method = "bilinear"))
run("D crop (relabelled), then resample", function() resample(crop(e2, ext(l2)), l2, method = "bilinear"))
run("E crop, then project(elev, grid)", function() project(crop(elev, ext(lu)), lu, method = "bilinear"))
run("F crop, then resample(use_gdal = FALSE) via project", function() project(crop(elev, ext(lu)), lu, method = "bilinear", use_gdal = FALSE))
cat("DONE\n")
