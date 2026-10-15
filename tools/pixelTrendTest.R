#!/usr/bin/env Rscript
# READ-ONLY on the model results; writes one small GeoTIFF per species and run. A classical significance test of the trend at every pixel:
# the Mann-Kendall test and the Sen slope, applied to the yearly probability maps of the MAIN model (<species>_meta_suitability_<year>.tif, band meta_prob,
# Germany-only copies, all years 2005-2025).
#
#   Rscript tools/pixelTrendTest.R --index <species number 1..11> [--variants brt,big5] [--run test4] [--species "Genus species"]
#   (cluster: sbatch cluster/eve_pixel_trend_test.sbatch, an array over the 11 species)
#
# Output: outputs/<run>/pixel_trend_test_<variant>/<Species>_pixel_trend_test.tif with 4 layers
#   senSlope  median of all pairwise slopes between years, in probability per DECADE (robust to single odd years)
#   tau       Kendall's tau, -1 (every year lower than the one before) ... +1 (every year higher)
#   pValue    two-sided Mann-Kendall p-value (normal approximation with continuity correction; ties are not corrected for)
#   nYears    number of years used
#
# HOW TO READ IT (and why it is only a second opinion): the yearly values of a pixel are predictions of one fitted model, not independent observations. The test
# therefore only asks "is the sequence of predicted values monotonic compared with its own year-to-year wiggle?". It does NOT include the uncertainty of the model itself
# (that is what the bootstrap replicates and their 90% interval do), it ignores the strong correlation between neighbouring years (climate windows overlap, land cover changes in
# steps) and it is repeated for about 15 million pixels, so a share of 5% of pixels is "significant" at p < 0.05 by chance alone. Expect it to flag many more pixels than the replicate interval.
Sys.setenv(OMP_NUM_THREADS = "1")
args <- commandArgs(trailingOnly = TRUE)
getArg <- function(flag, default = NULL) { i <- which(args == flag); if (length(i) == 0) default else args[i + 1] }
repoRoot <- normalizePath(getArg("--repo-root", getwd()), winslash = "/"); setwd(repoRoot)
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
suppressMessages(library(terra))
speciesCanonical <- read.csv("data/speciesCanonical.csv", stringsAsFactors = FALSE)
allSpecies <- speciesCanonical$latin_name[nzchar(trimws(speciesCanonical$include))]
run <- getArg("--run", Sys.getenv("BIRDMONITOR_RUNNAME", "test4")); ensTag <- getArg("--ens-tag", "ens_brt-glm-gam-rf-nn")
variants <- strsplit(getArg("--variants", "brt,big5"), ",")[[1]]
sp <- getArg("--species")
if (is.null(sp)) { i <- as.integer(getArg("--index", Sys.getenv("SLURM_ARRAY_TASK_ID", NA))); if (is.na(i) || i < 1 || i > length(allSpecies)) stop("--index must be 1..", length(allSpecies)); sp <- allSpecies[i] }
spClean <- gsub(" ", "_", sp); root <- file.path("outputs", run)
minYears <- as.integer(getArg("--min-years", 8))
chunk <- as.integer(getArg("--chunk", 60000))                           # cells per chunk (pairwise slopes need 210 columns per cell for 21 years)
hasMS <- requireNamespace("matrixStats", quietly = TRUE)
rowMed <- function(m) if (hasMS) matrixStats::rowMedians(m) else apply(m, 1, stats::median)

mkTest <- function(m, yrs) {                                            # m: cells x years (no NA); returns cells x 4
  n <- length(yrs); pairs <- t(combn(n, 2)); np <- nrow(pairs)
  dy <- yrs[pairs[, 2]] - yrs[pairs[, 1]]
  d <- m[, pairs[, 2], drop = FALSE] - m[, pairs[, 1], drop = FALSE]    # cells x pairs
  S <- rowSums(sign(d))
  sen <- rowMed(sweep(d, 2, dy, "/")) * 10
  v0 <- n * (n - 1) * (2 * n + 5) / 18
  z <- ifelse(S > 0, (S - 1) / sqrt(v0), ifelse(S < 0, (S + 1) / sqrt(v0), 0))
  cbind(senSlope = sen, tau = S / np, pValue = 2 * stats::pnorm(-abs(z)), nYears = n)
}

for (vn in variants) {
  tag <- if (vn == "big5") ensTag else ""
  d <- list.dirs(root, recursive = FALSE, full.names = TRUE)
  metaDir <- d[grepl(paste0("^metamodel_[0-9_]+", if (nzchar(tag)) paste0("_", tag) else "", "_germany$"), basename(d))]
  if (length(metaDir) != 1) { message("SKIP ", vn, ": expected one metamodel_*_germany folder, found ", length(metaDir)); next }
  fs <- sort(list.files(metaDir, pattern = paste0("^", spClean, "_meta_suitability_[0-9]{4}[.]tif$"), full.names = TRUE))
  yrs <- as.integer(sub(".*_([0-9]{4})[.]tif$", "\\1", fs))
  if (length(fs) < minYears) { message("SKIP ", vn, " ", sp, ": only ", length(fs), " yearly maps (need at least ", minYears, ")"); next }
  outDir <- file.path(root, paste0("pixel_trend_test_", vn)); dir.create(outDir, showWarnings = FALSE)
  outF <- file.path(outDir, paste0(spClean, "_pixel_trend_test.tif"))
  if (file.exists(outF)) { message("exists: ", outF); next }
  message("=== ", sp, " | ", vn, " | ", length(fs), " years ", min(yrs), "-", max(yrs), " | ", format(Sys.time(), "%H:%M:%S"), " ===")
  st <- rast(lapply(fs, function(f) rast(f)[["meta_prob"]])); names(st) <- yrs
  res <- rast(st[[1]], nlyrs = 4); names(res) <- c("senSlope", "tau", "pValue", "nYears")
  part <- sub("[.]tif$", ".part.tif", outF)
  readStart(st)
  b <- writeStart(res, part, overwrite = TRUE, datatype = "FLT4S", gdal = c("COMPRESS=DEFLATE", "PREDICTOR=3"))
  for (i in seq_len(b$n)) {
    m <- readValues(st, b$row[i], b$nrows[i], mat = TRUE)
    outm <- matrix(NA_real_, nrow(m), 4); ok <- which(rowSums(is.na(m)) == 0)
    if (length(ok)) for (s in split(ok, ceiling(seq_along(ok) / chunk))) outm[s, ] <- mkTest(m[s, , drop = FALSE], yrs)
    writeValues(res, outm, b$row[i], b$nrows[i])
    if (i %% 25 == 0) message("  block ", i, " of ", b$n, " | ", format(Sys.time(), "%H:%M:%S"))
  }
  writeStop(res); readStop(st); file.rename(part, outF)
  message("written ", outF)
}
message("=== done: ", sp, " ===")
marker <- Sys.getenv("UNC_DONE_MARKER", ""); if (nzchar(marker)) writeLines("ok", marker)
