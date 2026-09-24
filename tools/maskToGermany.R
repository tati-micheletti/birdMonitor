#' Post-hoc crop + mask already-computed output rasters to Germany
#'
#' Stopgap for the current run: crops and masks every raster already sitting
#' under `outputs/<runName>/` (species/scale predictions, meta-model
#' outputs, SR maps, change maps) to Germany's real national boundary,
#' writing masked copies to `outputs/<runName>_masked/` (mirroring the same
#' relative paths) -- originals are left untouched. Confirmed via direct
#' raster inspection that only ~1.9% of the current stored extent (a
#' leftover full-Europe download bounding box) is actually non-NA data, so
#' this also shrinks file sizes drastically, not just tidies up map edges.
#'
#' This does NOT touch `inputs/` (raw/processed predictors) -- masking
#' those doesn't change anything a co-author or the Steering Consortium
#' would see, and re-cropping them properly belongs in `dataPrep_Monitor`
#' itself (a separate, bigger piece of work -- see the project discussion
#' on cropping the working extent at the source, using a rasterToMatch/
#' studyArea pattern, before any calculation starts).
#'
#' Requires a Germany national-boundary vector. Options, in order tried:
#' 1. `--boundary <path>` -- any vector file `terra::vect()` can read
#'    (shapefile, GeoPackage, GeoJSON...).
#' 2. If omitted and the `geodata` package is installed: auto-downloads the
#'    GADM level-0 Germany boundary (cached under
#'    `inputs/predictors/raw/gadm/`).
#' 3. Otherwise: stops with instructions (download from gadm.org, country
#'    = Germany, level 0, or Germany's own BKG, then pass its path).
#'
#' Usage, from the birdMonitor repo root:
#'   Rscript tools/maskToGermany.R --run-name test1
#'   Rscript tools/maskToGermany.R --run-name test1 --boundary path/to/germany.gpkg

library(terra)

parseArgs <- function(args) {
  getArg <- function(flag, default = NULL) {
    i <- which(args == flag)
    if (length(i) == 0) return(default)
    args[i + 1]
  }
  list(
    boundary = getArg("--boundary"),
    runName  = getArg("--run-name", "test1"),
    repoRoot = getArg("--repo-root", getwd())
  )
}

opt <- parseArgs(commandArgs(trailingOnly = TRUE))

## ---- Get Germany's boundary ------------------------------------------------
if (!is.null(opt$boundary)) {
  germany <- vect(opt$boundary)
} else if (requireNamespace("geodata", quietly = TRUE)) {
  library(geodata)
  cacheDir <- file.path(opt$repoRoot, "inputs", "predictors", "raw", "gadm")
  dir.create(cacheDir, recursive = TRUE, showWarnings = FALSE)
  message("No --boundary given -- downloading GADM level-0 Germany boundary...")
  germany <- vect(gadm(country = "DEU", level = 0, path = cacheDir))
} else {
  stop("No --boundary supplied and the 'geodata' package isn't installed.\n",
       "Either install.packages('geodata') to auto-download, or download\n",
       "Germany's national boundary yourself (e.g. gadm.org, country =\n",
       "Germany, level 0) and pass its path via --boundary.")
}

## ---- Find every output raster ----------------------------------------------
outputRoot <- file.path(opt$repoRoot, "outputs", opt$runName)
maskedRoot <- file.path(opt$repoRoot, "outputs", paste0(opt$runName, "_masked"))

if (!dir.exists(outputRoot)) {
  stop("No such run output directory: ", outputRoot)
}

tifFiles <- list.files(outputRoot, pattern = "\\.tif$", full.names = TRUE, recursive = TRUE)
message("Found ", length(tifFiles), " raster(s) under ", outputRoot)

if (length(tifFiles) == 0) {
  message("Nothing to do.")
  quit(status = 0)
}

## Reproject the boundary once (every raster here shares the same CRS,
## EPSG:3035 -- sharedTargetCRS in runMe.R), rather than per file.
firstRast <- tryCatch(rast(tifFiles[1]), error = function(e) NULL)
if (is.null(firstRast)) stop("Could not read the first raster to determine CRS: ", tifFiles[1])
germanyProj <- project(germany, crs(firstRast))

## ---- Crop + mask each one ---------------------------------------------------
nOK <- 0L
nFailed <- 0L

for (f in tifFiles) {
  relPath <- substring(f, nchar(outputRoot) + 2)  # strip "<outputRoot>/"
  outPath <- file.path(maskedRoot, relPath)
  dir.create(dirname(outPath), recursive = TRUE, showWarnings = FALSE)

  result <- tryCatch({
    r <- rast(f)
    rCropped <- crop(r, germanyProj)
    rMasked <- mask(rCropped, germanyProj)
    writeRaster(rMasked, outPath, overwrite = TRUE)
    message("Masked -> ", relPath, "  (", ncell(r), " -> ", ncell(rMasked), " cells)")
    TRUE
  }, error = function(e) {
    warning("Failed on ", relPath, ": ", conditionMessage(e))
    FALSE
  })

  if (isTRUE(result)) nOK <- nOK + 1L else nFailed <- nFailed + 1L
}

message("\nDone: ", nOK, " masked, ", nFailed, " failed. Masked copies under: ", maskedRoot)
