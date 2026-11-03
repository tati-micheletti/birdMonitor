# Continuity check of the land-use layers: the country mean of every class share, year by year, and a flag where a class jumps from one year to the next.  READ-ONLY.
#   Rscript tools/checkLanduseContinuity.R [--dir inputs/predictors/processed/scale_1] [--scale landscape] [--flag 0.10] [--min-share 0.02] [--out outputs/<run>/diagnostics/landuse_continuity.csv]
# Why: the land-use layers used to be a patchwork of two products that map the area differently, and the grassland share jumped by 17% in 2017, 23% in 2022 and -13% in 2024 (the "humps" of the
# combined index). Run this after land use has been (re)computed: with one consistent product no class above --min-share should change by more than --flag from one year to the next
# without a reason; a year that does is listed. Real year-to-year changes of single crops (maize, rapeseed) can be of the order of 5-10%, so a flag is a prompt to look, not an error.
args <- commandArgs(trailingOnly = TRUE)
getArg <- function(flag, default = NULL) { i <- which(args == flag); if (length(i)) args[i + 1] else default }
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
suppressMessages(library(terra))
runName <- if (nzchar(Sys.getenv("BIRDMONITOR_RUNNAME"))) Sys.getenv("BIRDMONITOR_RUNNAME") else "test4"
dir <- getArg("--dir", file.path("inputs", "predictors", "processed", "scale_1")); scale <- getArg("--scale", "landscape")
flagAt <- as.numeric(getArg("--flag", 0.10)); minShare <- as.numeric(getArg("--min-share", 0.02))
outFile <- getArg("--out", file.path("outputs", runName, "diagnostics", "landuse_continuity.csv"))
fs <- list.files(dir, pattern = paste0("^landuse_[0-9]{4}_", scale, "_", basename(dir), "[.]tif$"), full.names = TRUE)
if (!length(fs)) stop("no land-use files in ", dir)
yrs <- as.integer(sub(paste0("^landuse_([0-9]{4})_.*$"), "\\1", basename(fs))); o <- order(yrs); fs <- fs[o]; yrs <- yrs[o]
m <- do.call(rbind, lapply(seq_along(fs), function(i) { r <- terra::rast(fs[i]); g <- terra::global(r, "mean", na.rm = TRUE)
  data.frame(year = yrs[i], class = rownames(g), share = g[, 1]) }))
w <- reshape(m, idvar = "class", timevar = "year", direction = "wide"); names(w) <- sub("^share[.]", "", names(w)); rownames(w) <- NULL
ch <- w; for (j in seq_along(yrs)[-1]) ch[[as.character(yrs[j])]] <- w[[as.character(yrs[j])]] / w[[as.character(yrs[j - 1])]] - 1; ch[[as.character(yrs[1])]] <- NA_real_
big <- w$class[rowMeans(w[, as.character(yrs)], na.rm = TRUE) >= minShare]
cat(sprintf("country mean share of each class (%s scale, %d years); classes below %.2f on average are not flagged\n", scale, length(yrs), minShare)); options(width = 250)
print(cbind(class = w$class, round(w[, as.character(yrs)], 4)), row.names = FALSE)
flags <- do.call(rbind, lapply(big, function(k) { v <- unlist(ch[ch$class == k, as.character(yrs)]); h <- which(abs(v) > flagAt)
  if (length(h)) data.frame(class = k, year = yrs[h], changeVsPreviousYearPct = round(100 * v[h], 1)) }))
cat(sprintf("\nflags: a class above %.2f that changes by more than %.0f%% from the previous year\n", minShare, 100 * flagAt))
if (is.null(flags) || !nrow(flags)) cat("none\n") else print(flags, row.names = FALSE)
dir.create(dirname(outFile), recursive = TRUE, showWarnings = FALSE)
write.csv(cbind(class = w$class, round(w[, as.character(yrs)], 5)), outFile, row.names = FALSE); if (!is.null(flags) && nrow(flags)) write.csv(flags, sub("[.]csv$", "_flags.csv", outFile), row.names = FALSE)
cat("written:", outFile, "\n")
