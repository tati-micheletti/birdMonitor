# Reprex: does the ORDER in which sf and terra first touch GDAL/PROJ change EPSG:3035 axis order?
# Usage:  Rscript tools/reprexOrder.R terraFirst   |   Rscript tools/reprexOrder.R sfFirst
args <- commandArgs(trailingOnly = TRUE); mode <- if (length(args)) args[1] else "terraFirst"
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
source("tools/sharedAxisCheck.R")
shp <- "inputs/response/raw/MhB/MhB_Probeflaechen_DE_S2637_epsg25832.shp"
elev <- "inputs/predictors/processed/scale_02/elevation_habitat_scale_02.tif"
terraStep <- function(step) {                  # ONE terra operation (plus all the ones before it), to see which one triggers the flip
  suppressMessages(library(terra))
  if (step == "library") return(invisible(NULL))                     # only attaching terra
  r <- terra::rast(elev); if (step == "rast") return(invisible(r))   # open a raster
  v <- terra::vect(shp); if (step == "vect") return(invisible(v))    # read a vector
  vp <- terra::project(v, "EPSG:3035"); if (step == "vectProject") return(invisible(vp))   # project a vector
  invisible(terra::extract(r, terra::centroids(vp)[1:20]))           # extract
}
terraWork <- function() terraStep("extract")
shpTest <- function(label) {
  pf <- sf::st_read(shp, quiet = TRUE); b <- sf::st_coordinates(suppressWarnings(sf::st_centroid(sf::st_transform(pf, 3035))))
  cat(sprintf("[%s] shapefile centroids via sf::st_transform(., 3035): x=%s y=%s -> %s\n", label,
              paste(round(range(b[, 1])), collapse = ".."), paste(round(range(b[, 2])), collapse = ".."),
              if (mean(b[, 1] < b[, 2]) > 0.5) "<<< FLIPPED" else "ok"))
}
cat("MODE:", mode, "\n")
if (mode %in% c("terraFirst", "library", "rast", "vect", "vectProject", "extract")) {
  terraStep(if (mode == "terraFirst") "extract" else mode)
  suppressMessages(library(sf)); axisCheck(paste("after terra step", mode, "- first sf use")); shpTest(mode)
} else if (mode == "sfFirst") {
  suppressMessages(library(sf)); axisCheck("first sf use, before any terra work"); shpTest("sfFirst (before terra)")
  terraWork(); axisCheck("after terra work"); shpTest("sfFirst (after terra)")
} else stop("unknown mode: ", mode)
cat("DONE\n")
