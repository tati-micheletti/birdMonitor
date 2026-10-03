# Diagnostic (run on EVE via cluster/eve_probe.sbatch): which way of re-gridding an already
# 3035-projected raster to an exact resolution works with EVE's terra/GDAL/PROJ?
# Uses synthetic rasters with the REAL extents of the DEM and of the landuse maps.
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
suppressMessages(library(terra))
cat("terra", as.character(packageVersion("terra")), "| GDAL/PROJ/GEOS:", paste(unlist(gdal(lib = TRUE)[1, 1:3]), collapse = " / "), "\n\n")

try1 <- function(label, expr) {
  res <- tryCatch({ x <- force(expr); paste("OK   ", paste(dim(x)[1:2], collapse = "x")) },
                  error = function(e) paste("ERROR", conditionMessage(e)),
                  warning = function(w) paste("WARN ", conditionMessage(w)))
  cat(sprintf("  %-46s %s\n", label, res))
}

probe <- function(name, e, srcRes, targetRes, crs = "EPSG:3035") {
  cat(name, ": extent", paste(round(e), collapse = " "), "| source", srcRes, "m -> target", targetRes, "m
")
  r <- rast(ext(e[1], e[2], e[3], e[4]), resolution = srcRes, crs = crs); values(r) <- 1
  tmpl <- rast(ext(r), resolution = targetRes, crs = "EPSG:3035")
  try1("A project(r, 'EPSG:3035', res)  [CURRENT CODE]", project(r, "EPSG:3035", res = targetRes, method = "bilinear"))
  r2 <- r; crs(r2) <- "EPSG:3035"
  try1("G relabel crs to EPSG:3035, then project  [PROPOSED]", project(r2, "EPSG:3035", res = targetRes, method = "bilinear"))
  try1("H relabel crs, then resample(r2, template)", resample(r2, tmpl, method = "bilinear"))
  try1("I project(r, template)", project(r, tmpl, method = "bilinear"))
  cat("
"); invisible(gc())
}

# 1) REAL geometry + REAL projection definition, taken from the 30 m DEM file's header only
demFile <- "inputs/predictors/processed/dem/dem_30m_laea.tif"
if (file.exists(demFile)) {
  dem <- rast(demFile)
  cat("real 30m DEM:", nrow(dem), "x", ncol(dem), "cells; crs code:", crs(dem, describe = TRUE)$code, "
")
  cat("crs name:", crs(dem, describe = TRUE)$name, "

")
  for (res in c(700, 5000)) {
    fact <- round(res / 30)                      # what aggregate() does
    e <- as.vector(ext(dem))
    ncA <- ceiling(ncol(dem) / fact); nrA <- ceiling(nrow(dem) / fact)   # aggregate() pads the extent
    eAgg <- c(e[1], e[1] + ncA * fact * 30, e[4] - nrA * fact * 30, e[4])
    probe(paste0("REAL DEM geometry, real CRS, ", res, " m"), eAgg, fact * 30, res, crs = crs(dem))
  }
}

cat("DONE
")
