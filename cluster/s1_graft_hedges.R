# SERIES 1 (HCTM series), 2026-11-19: give the land-use files of inputs_s1 the SAME fixed hedge layer as SERIES 2 (the mean of the hedge layers of the FINAL CTM v302 maps 2017-2025).
# Why: the hedge layer of inputs_s1 was copied from run v3 (mean of CTM v202 2017-2021, v302 2024 and the PRELIMINARY August 2025 map). Hedges exist only in CTM, so both series should use one and the same final layer.
# What it does: for every land-use file of every scale of inputs_s1 (all years) the band `hedges` is replaced by the fixed layer of inputs_s2 (resampled, bilinear, onto the grid of the file, exactly as completeHedges()
#   does), the sidecar `.studyarea` is removed (the study-area crop and the rim repair run again in the preparation) and `.hedgesfixed` gets the tag of the source. All other bands stay as they are
#   (heterogeneity and unmapped_other do not use the hedges). The land-use files of inputs_s1 are COPIES (make_inputs_s1.sh), the originals in inputs/ are not touched.
# Needs: the preparation of SERIES 2 has finished (its files carry the fixed mean) and NO job of the HCTM series is running.
#   Rscript cluster/s1_graft_hedges.R --dry     # reports what it would do
#   Rscript cluster/s1_graft_hedges.R           # does it
suppressPackageStartupMessages(library(terra))
args <- commandArgs(trailingOnly = TRUE); dry <- "--dry" %in% args
getArg <- function(f, d) { i <- which(args == f); if (length(i)) args[i + 1] else d }
s1 <- getArg("--s1", "inputs_s1/predictors/processed"); s2 <- getArg("--s2", "inputs_s2/predictors/processed")
wantTag <- "fixed mean of the hedge layers of 2017,2018,2019,2020,2021,2022,2023,2024,2025"
pat <- "^landuse_[0-9]{4}_(habitat|landscape)_scale_[0-9]+[.]tif$"
done <- 0L; skipped <- 0L
for (d in sort(list.dirs(s1, recursive = FALSE, full.names = TRUE))) {
  b <- basename(d); fs <- list.files(d, pattern = pat, full.names = TRUE); if (!length(fs)) next
  src <- list.files(file.path(s2, b), pattern = pat, full.names = TRUE)
  src <- src[vapply(src, function(f) { sf <- paste0(f, ".hedgesfixed"); file.exists(sf) && identical(readLines(sf, warn = FALSE)[1], wantTag) }, logical(1))]
  if (!length(src)) stop(b, ": no land-use file of inputs_s2 carries the tag '", wantTag, "' (is the preparation of SERIES 2 finished?)")
  srcH <- rast(src[1])[["hedges"]]
  stopifnot(isTRUE(global(srcH, function(x) any(!is.na(x)))[1, 1] > 0))
  cat(sprintf("%s: %d files; source %s (hedge mean %.4f)\n", b, length(fs), basename(src[1]), global(srcH, "mean", na.rm = TRUE)[1, 1]))
  for (f in fs) {
    sf <- paste0(f, ".hedgesfixed")
    if (file.exists(sf) && identical(readLines(sf, warn = FALSE)[1], wantTag)) { skipped <- skipped + 1L; next }
    if (dry) { done <- done + 1L; next }
    r <- rast(f); old <- r[["hedges"]]
    mh <- resample(srcH, r[[1]], method = "bilinear"); names(mh) <- "hedges"
    out <- rast(lapply(names(r), function(n) if (n == "hedges") mh else r[[n]])); names(out) <- names(r)
    part <- paste0(f, ".part")
    writeRaster(out, part, filetype = "GTiff", overwrite = TRUE, datatype = datatype(r)[1], gdal = "COMPRESS=DEFLATE")
    nOld <- global(old, "mean", na.rm = TRUE)[1, 1]; nNew <- global(mh, "mean", na.rm = TRUE)[1, 1]
    rm(r, out, mh, old); invisible(gc())
    file.remove(f); file.rename(part, f)
    st <- paste0(f, ".studyarea"); if (file.exists(st)) file.remove(st)
    writeLines(wantTag, sf)
    cat(sprintf("  %s: hedge mean %.4f -> %.4f\n", basename(f), nOld, nNew)); done <- done + 1L
  }
}
cat(sprintf("%s: %d files %s, %d already carried the tag\n", if (dry) "DRY RUN" else "done", done, if (dry) "would be changed" else "changed", skipped))
