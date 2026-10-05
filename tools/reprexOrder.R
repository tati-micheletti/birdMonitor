# Reprex: does the ORDER in which sf and terra first touch GDAL/PROJ change EPSG:3035 axis order?
# Usage:  Rscript tools/reprexOrder.R terraFirst   |   Rscript tools/reprexOrder.R sfFirst
args <- commandArgs(trailingOnly = TRUE); mode <- if (length(args)) args[1] else "terraFirst"
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
source("tools/sharedAxisCheck.R")
shp <- "inputs/response/raw/MhB/MhB_Probeflaechen_DE_S2637_epsg25832.shp"
elev <- "inputs/predictors/processed/scale_02/elevation_habitat_scale_02.tif"
terraWork <- function() {                      # typical early pipeline work: open rasters, project a vector, extract
  suppressMessages(library(terra))
  r <- terra::rast(elev); v <- terra::vect(shp); vp <- terra::project(v, "EPSG:3035")
  invisible(terra::extract(r, terra::centroids(vp)[1:20]))
  cat("terra work done; projected route centroids x range:", paste(round(range(terra::crds(terra::centroids(vp))[, 1])), collapse = ".."), "\n")
}
shpTest <- function(label) {
  pf <- sf::st_read(shp, quiet = TRUE); b <- sf::st_coordinates(suppressWarnings(sf::st_centroid(sf::st_transform(pf, 3035))))
  cat(sprintf("[%s] shapefile centroids via sf::st_transform(., 3035): x=%s y=%s -> %s\n", label,
              paste(round(range(b[, 1])), collapse = ".."), paste(round(range(b[, 2])), collapse = ".."),
              if (mean(b[, 1] < b[, 2]) > 0.5) "<<< FLIPPED" else "ok"))
}
cat("MODE:", mode, "\n")
if (mode == "terraFirst") {
  terraWork(); suppressMessages(library(sf)); axisCheck("after terra work, first sf use"); shpTest("terraFirst")
} else {
  suppressMessages(library(sf)); axisCheck("first sf use, before any terra work"); shpTest("sfFirst (before terra)")
  terraWork(); axisCheck("after terra work"); shpTest("sfFirst (after terra)")
}
cat("DONE\n")
