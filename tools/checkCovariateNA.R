#!/usr/bin/env Rscript
# READ-ONLY: which covariate layers have NA pixels, inside and outside Germany? Predictors must be complete inside Germany BY CONSTRUCTION (fill NA in the layer, not drop records later),
# so this lists, for every layer of every covariate file of one scale: the NA cells inside the German outline, and the share of cells outside the outline that are NA.
#   Rscript tools/checkCovariateNA.R [--scale scale_02] [--root inputs/predictors/processed] [--out outputs/covariate_na_<scale>.csv]
# Output: a table (file, layer, cellsInGermany, naInGermany, naOutsideShare) printed and written as csv. Runs on any machine that has the processed predictors (PC or EVE).
Sys.setenv(OMP_NUM_THREADS = "1")
args <- commandArgs(trailingOnly = TRUE)
getArg <- function(flag, default = NULL) { i <- which(args == flag); if (length(i) == 0) default else args[i + 1] }
repoRoot <- normalizePath(getArg("--repo-root", getwd()), winslash = "/"); setwd(repoRoot)
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
suppressMessages(library(terra))
source("modules/models_Monitor/R/uncRegional.R")                           # uncOutlineLAEA()
scale <- getArg("--scale", "scale_02"); root <- getArg("--root", file.path("inputs", "predictors", "processed")); dir <- file.path(root, scale)
out <- getArg("--out", file.path("outputs", paste0("covariate_na_", scale, ".csv")))
fs <- list.files(dir, pattern = "[.]tif$"); fs <- fs[!grepl("^(elevation|slope|solar)", fs) | TRUE]
outline <- NULL; rows <- list()
for (f in fs) {
  r <- rast(file.path(dir, f)); if (is.null(outline)) outline <- uncOutlineLAEA(file.path("inputs", "predictors", "raw", "gadm"), crs(r))
  inG <- !is.na(rasterize(outline, r[[1]], field = 1, background = NA)); nIn <- global(inG, "sum")[1, 1]; nOut <- ncell(r) - nIn
  for (i in seq_len(nlyr(r))) {
    na <- is.na(r[[i]])
    rows[[length(rows) + 1]] <- data.frame(file = f, layer = names(r)[i], cellsInGermany = nIn, naInGermany = global(na & inG, "sum")[1, 1],
                                           naOutsideShare = if (nOut > 0) round(global(na & !inG, "sum")[1, 1] / nOut, 4) else NA)
  }
  message(f, " | ", format(Sys.time(), "%H:%M:%S"))
}
tab <- do.call(rbind, rows); dir.create(dirname(out), showWarnings = FALSE, recursive = TRUE); write.csv(tab, out, row.names = FALSE)
cat("\nLayers with NA INSIDE Germany:\n"); print(tab[tab$naInGermany > 0, c("file", "layer", "naInGermany")], row.names = FALSE)
cat("\nFiles with every layer complete inside Germany:", sum(tapply(tab$naInGermany, tab$file, sum) == 0), "of", length(unique(tab$file)), "\n")
cat("\nShare of cells OUTSIDE Germany that are NA, by layer (median over files):\n"); print(round(sort(tapply(tab$naOutsideShare, tab$layer, median), decreasing = TRUE), 3))
