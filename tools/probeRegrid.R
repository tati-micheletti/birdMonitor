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
  tmpl <- rast(ext(r), resolution = targetRes, crs = crs)
  try1("A project(r, crs, res)  [current code]", project(r, "EPSG:3035", res = targetRes, method = "bilinear"))
  try1("B project(r, crs, res, use_gdal = FALSE)", project(r, "EPSG:3035", res = targetRes, method = "bilinear", use_gdal = FALSE))
  try1("C project(r, template)", project(r, tmpl, method = "bilinear"))
  try1("D project(r, template, use_gdal = FALSE)", project(r, tmpl, method = "bilinear", use_gdal = FALSE))
  try1("E resample(r, template)", resample(r, tmpl, method = "bilinear"))
  try1("F resample(r, template, 'average')", resample(r, tmpl, method = "average"))
  cat("
")
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

# 2) made-up rasters with the plain "EPSG:3035" code
probe("DEM extent, EPSG code",  c(1172421, 7552041, 1218230, 5846210), 690,  700)
probe("Germany box, EPSG code", c(4031000, 4672000, 2682000, 3552000), 690,  700)
cat("DONE
")
