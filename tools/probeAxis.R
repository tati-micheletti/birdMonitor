# Diagnostic: which loaded package flips the x/y (axis) order of coordinate transformations?
# Loads packages one at a time and, after each, tests several ways of transforming the same points and
# the real Probeflaechen shapefile. Expected for Germany in EPSG:3035: x ~ 4.0-4.7e6, y ~ 2.7-3.5e6.
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
shp <- "inputs/response/raw/MhB/MhB_Probeflaechen_DE_S2637_epsg25832.shp"
laea <- "+proj=laea +lat_0=52 +lon_0=10 +x_0=4321000 +y_0=3210000 +ellps=GRS80 +towgs84=0,0,0,0,0,0,0 +units=m +no_defs"
cat("ENV:", paste(Sys.getenv(c("OSR_DEFAULT_AXIS_MAPPING_STRATEGY", "PROJ_DATA", "PROJ_LIB", "GDAL_DATA", "PROJ_NETWORK")), collapse = " | "), "\n")
rg <- function(v) paste(round(range(v)), collapse = "..")
testSet <- function(label) {
  p <- sf::st_as_sf(data.frame(lon = c(9.2, 11.5, 13.4), lat = c(48.8, 48.1, 52.5)), coords = c("lon", "lat"), crs = 4326)
  a <- sf::st_coordinates(sf::st_transform(p, 3035)); b <- sf::st_coordinates(sf::st_transform(p, laea))
  tm <- tryCatch(terra::project(cbind(c(9.2, 11.5, 13.4), c(48.8, 48.1, 52.5)), from = "EPSG:4326", to = "EPSG:3035"), error = function(e) NULL)
  pf <- sf::st_read(shp, quiet = TRUE); raw <- sf::st_bbox(pf)
  g <- sf::st_bbox(sf::st_transform(pf, 4326)); l <- sf::st_bbox(sf::st_transform(pf, laea))
  cat(sprintf("[%-18s] pts->3035: x=%s y=%s | pts->LAEA: x=%s y=%s | terra: x=%s | shp raw x=%s y=%s | shp->4326 lon=%s lat=%s | shp->LAEA x=%s y=%s\n",
              label, rg(a[,1]), rg(a[,2]), rg(b[,1]), rg(b[,2]), if (is.null(tm)) "NA" else rg(tm[,1]),
              rg(raw[c(1,3)]), rg(raw[c(2,4)]), rg(g[c(1,3)]), rg(g[c(2,4)]), rg(l[c(1,3)]), rg(l[c(2,4)])))
}
suppressMessages(library(sf)); cat("sf", as.character(packageVersion("sf")), "PROJ", sf::sf_extSoftVersion()[["PROJ"]], "GDAL", sf::sf_extSoftVersion()[["GDAL"]], "\n")
source("tools/sharedAxisCheck.R"); cat("LIBS:", loadedGeoLibs(), "
")
testSet("sf only")
for (pkg in c("terra", "dplyr", "readxl", "raster", "dismo", "blockCV", "geodata", "reproducible", "Require", "SpaDES.core", "SpaDES.project", "reticulate", "spatialEco", "mgcv")) {
  if (!requireNamespace(pkg, quietly = TRUE)) { cat("[", pkg, "] not installed\n"); next }
  suppressMessages(suppressWarnings(library(pkg, character.only = TRUE)))
  testSet(paste("+", pkg))
}
cat("DONE\n")
