# Minimal, self-contained reprex (no project data): does terra opening a raster BEFORE sf's first
# transformation change the axis order sf returns for EPSG:3035?
# Run:  Rscript tools/reprexTerraSfAxis.R
# Each case runs in its own fresh R process (the effect is per process, set by who initialises GDAL/PROJ first).
# Expected for the point (11.5E, 48.1N) in EPSG:3035 (easting, northing): x = 4432769, y = 2777406.
# EVE only: use the personal R library the pipeline installed its packages in (no-op elsewhere)
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
args <- commandArgs(trailingOnly = TRUE)
mode <- if (length(args)) args[1] else "all"
tif <- if (length(args) > 1) args[2] else NA_character_

if (mode == "make") {                         # write a tiny GeoTIFF (any raster file would do)
  suppressMessages(library(terra))
  r <- rast(nrows = 10, ncols = 10, xmin = 4000000, xmax = 4100000, ymin = 2800000, ymax = 2900000, crs = "EPSG:3035")
  values(r) <- 1; writeRaster(r, tif, overwrite = TRUE); quit(save = "no")
}
if (mode %in% c("terraFirst", "sfFirst")) {
  sfTransform <- function() {
    p <- sf::st_as_sf(data.frame(lon = 11.5, lat = 48.1), coords = c("lon", "lat"), crs = 4326)
    xy <- sf::st_coordinates(sf::st_transform(p, 3035))
    cat(sprintf("  sf::st_transform(point, 3035): x=%.0f y=%.0f -> %s\n", xy[1, 1], xy[1, 2],
                if (xy[1, 1] > xy[1, 2]) "ok (easting, northing)" else "SWAPPED (northing, easting)"))
  }
  if (mode == "terraFirst") { r <- terra::rast(tif); sfTransform() }       # terra opens a raster file first
  else { sfTransform(); r <- terra::rast(tif); sfTransform() }              # sf first, then terra, then sf again
  quit(save = "no")
}

# ---- parent: only base R, so it does not initialise GDAL/PROJ itself ----
rs <- file.path(R.home("bin"), "Rscript"); self <- sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1])
tif <- tempfile(fileext = ".tif")
run <- function(...) system2(rs, c(shQuote(self), ...))
run("make", shQuote(tif))
cat("== versions ==\n")
cat(R.version.string, "\n")
cat("sf", as.character(packageVersion("sf")), "| terra", as.character(packageVersion("terra")), "\n")
print(sf::sf_extSoftVersion()[c("GEOS", "GDAL", "proj.4")]); cat("terra GDAL/PROJ/GEOS:", paste(terra::gdal(lib = TRUE), collapse = " / "), "\n")
cat("\n== case 1: terra opens a raster first, then sf transforms ==\n"); run("terraFirst", shQuote(tif))
cat("\n== case 2: sf transforms first, then terra, then sf again ==\n"); run("sfFirst", shQuote(tif))
