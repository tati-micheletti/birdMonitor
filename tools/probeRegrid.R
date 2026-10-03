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

probe <- function(name, e, srcRes, targetRes) {
  cat(name, ": extent", paste(round(e), collapse = " "), "| source", srcRes, "m -> target", targetRes, "m\n")
  r <- rast(ext(e[1], e[2], e[3], e[4]), resolution = srcRes, crs = "EPSG:3035"); values(r) <- 1
  tmpl <- rast(ext(r), resolution = targetRes, crs = "EPSG:3035")
  try1("A project(r, crs, res)  [current code]", project(r, "EPSG:3035", res = targetRes, method = "bilinear"))
  try1("B project(r, crs, res, use_gdal = FALSE)", project(r, "EPSG:3035", res = targetRes, method = "bilinear", use_gdal = FALSE))
  try1("C project(r, template)", project(r, tmpl, method = "bilinear"))
  try1("D project(r, template, use_gdal = FALSE)", project(r, tmpl, method = "bilinear", use_gdal = FALSE))
  try1("E resample(r, template)", resample(r, tmpl, method = "bilinear"))
  try1("F resample(r, template, 'average')", resample(r, tmpl, method = "average"))
  cat("\n")
}

# the real extents (xmin, xmax, ymin, ymax) in EPSG:3035
probe("DEM (Europe)",       c(1172421, 7552041, 1218230, 5846210), 690,  700)
probe("DEM (Europe) 5 km",  c(1172421, 7552041, 1218230, 5846210), 4980, 5000)
probe("Germany box",        c(4031000, 4672000, 2682000, 3552000), 690,  700)
cat("DONE\n")
