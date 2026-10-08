# READ-ONLY check: how much of the prediction window lies inside Germany, and does it matter for the area mean?
# The national indices (and the intervals around them) average ALL non-NA pixels of the meta-model maps; the regional indices mask to the German
# outline first. If the maps are non-NA outside Germany too (the window is the bounding box of Germany), the two differ in what they average.
#   Rscript tools/checkGermanyShare.R [run name, default test4] [year, default 2025]    (run on EVE after: module load <R module>)
args <- commandArgs(trailingOnly = TRUE)
runName <- if (length(args) >= 1) args[1] else "test4"; yr <- if (length(args) >= 2) as.integer(args[2]) else 2025L
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
suppressMessages(library(terra))
source("modules/models_Monitor/R/uncRegional.R")          # uncOutlineLAEA(): the outline without a GDAL/PROJ transformation
fs <- Sys.glob(file.path("outputs", runName, "metamodel_*", sprintf("*_meta_suitability_%d.tif", yr)))
fs <- fs[!grepl("_ens_", fs)]
if (!length(fs)) stop("No meta_suitability files for year ", yr, " under outputs/", runName)
cat("Checking", length(fs), "species maps of", yr, "

")
b <- NULL; out <- list()
for (f in fs) {
  r <- terra::rast(f)[["meta_prob"]]
  cat(sprintf("%s | folder %s | extent %s | crs %s | cells %d
", basename(f), basename(dirname(f)), paste(round(as.vector(terra::ext(r))), collapse = " "),
              terra::crs(r, describe = TRUE)$code, terra::ncell(r)))
  if (is.null(b)) {
    b <- uncOutlineLAEA(file.path("inputs", "predictors", "raw", "gadm"), terra::crs(r))   # pure-R transform: terra/sf can flip x/y on EVE
    cat("German outline, same crs, extent:", paste(round(as.vector(terra::ext(b))), collapse = " "), "
")
  }
  res1 <- tryCatch({
    n <- terra::global(!is.na(r), "sum")[1, 1]
    rg <- terra::mask(terra::crop(r, b), b)
    nG <- terra::global(!is.na(rg), "sum")[1, 1]
    data.frame(species = sub("_meta_suitability.*", "", basename(f)), pixelsWithValue = n, insideGermany = nG, shareOutside = round(1 - nG / n, 3),
               areaMeanWindow = round(terra::global(r, "mean", na.rm = TRUE)[1, 1], 4), areaMeanGermany = round(terra::global(rg, "mean", na.rm = TRUE)[1, 1], 4))
  }, error = function(e) { cat("  ERROR for this map:", conditionMessage(e), "
"); NULL })
  if (!is.null(res1)) out[[basename(f)]] <- res1
}
if (!length(out)) stop("No map could be checked (see the ERROR lines above).")
res <- do.call(rbind, out); rownames(res) <- NULL
print(res)
cat(sprintf("
Share of the pixels with a value that lies OUTSIDE Germany: %.1f%% (this is the mean over the species; it differs by species).
", 100 * mean(res$shareOutside)))
cat("If this is well above 0, the national area means include foreign pixels; the two area-mean columns show how much that changes each species' level.
")
