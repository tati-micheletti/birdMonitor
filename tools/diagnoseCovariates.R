# Diagnostic: for the bird points of ONE species/year (taken from the existing table on disk),
# extract every covariate layer FILE separately and report how many points get NA.
# Usage (repo root):  Rscript tools/diagnoseCovariates.R habitat Emberiza_citrinella 2022 scale_02
#                     Rscript tools/diagnoseCovariates.R landscape Emberiza_citrinella 2020 scale_1
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
suppressMessages(library(terra))
a <- commandArgs(trailingOnly = TRUE)
scaleName <- a[1]; sp <- a[2]; yr <- a[3]; leaf <- a[4]
tabFile <- if (scaleName == "habitat") sprintf("inputs/response/processed/MhB/%s_habitat_%s.rds", sp, yr) else
  sprintf("inputs/response/processed/territories/%s_landscape_%s.rds", sp, yr)
x <- readRDS(tabFile)
cat("points from", tabFile, ":", nrow(x), "rows; columns:", paste(names(x), collapse = ", "), "\n\n")
pts <- as.matrix(x[, c("x", "y")])
dir <- file.path("inputs/predictors/processed", leaf)
files <- list.files(dir, pattern = paste0("(", yr, "|elevation|slope|solar|2018|2012|2006).*[.]tif$"), full.names = TRUE)
files <- files[grepl(scaleName, basename(files))]
cat(sprintf("%-60s %5s %7s %9s  %s\n", "file", "nlyr", "cells", "pts_NA%", "extent (xmin xmax ymin ymax)"))
for (f in files) {
  r <- tryCatch(rast(f), error = function(e) NULL)
  if (is.null(r)) { cat(sprintf("%-60s UNREADABLE\n", basename(f))); next }
  v <- terra::extract(r, pts)
  if ("ID" %in% names(v)) v <- v[, names(v) != "ID", drop = FALSE]
  naPct <- round(100 * mean(is.na(v[[1]])), 1)
  allNa <- names(v)[vapply(v, function(col) all(is.na(col)), logical(1))]
  cat(sprintf("%-60s %5d %7s %8s%%  %s%s\n", basename(f), nlyr(r), format(ncell(r), big.mark = ","), naPct,
              paste(round(as.vector(ext(r))), collapse = " "),
              if (length(allNa)) paste0("   ALL-NA layers: ", paste(allNa, collapse = ",")) else ""))
}
cat("\npoints extent:", paste(round(range(pts[, 1])), collapse = " "), "|", paste(round(range(pts[, 2])), collapse = " "), "\n")
