# Reprex / bisection: does a coordinate transformation flip x/y (axis order) INSIDE a SpaDES simulation,
# and if so after which step? Run on EVE:  Rscript tools/reprexAxis.R   (see cluster/eve_reprex_axis.sbatch)
# Expected for Germany in EPSG:3035: x ~ 4.0-4.7e6, y ~ 2.7-3.5e6 (a flip gives x ~ 2.7-3.5e6, y ~ 4.0-4.7e6).
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
suppressMessages({library(sf); library(terra)})
shp <- "inputs/response/raw/MhB/MhB_Probeflaechen_DE_S2637_epsg25832.shp"
rg <- function(v) paste(round(range(v)), collapse = "..")
testAxis <- function(label) {
  p <- sf::st_as_sf(data.frame(lon = c(9.2, 11.5, 13.4), lat = c(48.8, 48.1, 52.5)), coords = c("lon", "lat"), crs = 4326)
  a <- sf::st_coordinates(sf::st_transform(p, 3035))
  pf <- sf::st_read(shp, quiet = TRUE)
  b <- sf::st_coordinates(suppressWarnings(sf::st_centroid(sf::st_transform(pf, 3035))))
  flipped <- mean(a[, 1] < a[, 2]) > 0.5
  cat(sprintf("%-46s pts: x=%-17s y=%-17s | shp centroids: x=%-17s y=%-17s | %s\n", label, rg(a[, 1]), rg(a[, 2]),
              rg(b[, 1]), rg(b[, 2]), if (flipped) "<<< FLIPPED" else "ok"))
  invisible(!flipped)
}
cat("sf", as.character(packageVersion("sf")), "| terra", as.character(packageVersion("terra")),
    "| GDAL", sf::sf_extSoftVersion()[["GDAL"]], "| PROJ", sf::sf_extSoftVersion()[["PROJ"]], "\n\n")
source("tools/sharedAxisCheck.R"); cat("LIBS:", loadedGeoLibs(), "
")
testAxis("0. plain session")

cat("\n-- 1. options that setupProject() sets in the real run, one at a time\n")
suppressMessages({library(reproducible); library(SpaDES.core)})
opts <- list(spades.allowInitDuringSimInit = TRUE, reproducible.cacheSaveFormat = "rds", reproducible.gdalwarp = TRUE,
             reproducible.useMemoise = FALSE, reproducible.destinationPath = tempdir(), repos = "https://cloud.r-project.org")
for (nm in names(opts)) { do.call(options, setNames(list(opts[[nm]]), nm)); testAxis(paste("option", nm)) }

cat("\n-- 2. a reproducible::Cache() call, then a postProcess-style operation\n")
cp <- file.path(tempdir(), "cache"); dir.create(cp)
addOne <- function(x) x + 1
invisible(reproducible::Cache(addOne, 1, cachePath = cp)); testAxis("after a Cache() call")

cat("\n-- 3. inside a minimal SpaDES module (init event)\n")
modDir <- file.path(tempdir(), "modules"); dir.create(file.path(modDir, "reprexAxis"), recursive = TRUE)
writeLines(c(
  'defineModule(sim, list(',
  '  name = "reprexAxis", description = "reprex", keywords = "reprex",',
  '  authors = person("A", "B", email = "a@b.c", role = c("aut", "cre")),',
  '  childModules = character(0), version = list(reprexAxis = "0.0.1"),',
  '  timeframe = as.POSIXlt(c(NA, NA)), timeunit = "year", citation = list(), documentation = list(),',
  '  reqdPkgs = list("sf", "terra"),',
  '  parameters = bindrows(defineParameter(".plots", "character", "screen", NA, NA, "plots")),',
  '  inputObjects = bindrows(), outputObjects = bindrows()))',
  'doEvent.reprexAxis <- function(sim, eventTime, eventType) {',
  '  switch(eventType, init = { get("testAxis", envir = .GlobalEnv)("inside SpaDES init event") },',
  '         warning(noEventWarning(sim)))',
  '  invisible(sim)',
  '}'), file.path(modDir, "reprexAxis", "reprexAxis.R"))
sim <- tryCatch(SpaDES.core::simInitAndSpades(modules = "reprexAxis",
                  paths = list(modulePath = modDir, inputPath = tempdir(), outputPath = tempdir(), cachePath = cp),
                  times = list(start = 0, end = 0)),
                error = function(e) { cat("simInit failed:", conditionMessage(e), "\n"); NULL })
testAxis("after the simulation")
cat("\nDONE\n")
