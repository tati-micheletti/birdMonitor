# READ-ONLY: how many regional cells are affected by the baseline floor, and what would a floor / a cap change? (DECISIONS.md, decision 1 of the Steering Consortium document)
#
# The regional index of a species in a cell is 100 x (cell mean probability in year t) / (cell mean in the baseline year). Where the baseline mean is tiny, the ratio explodes.
# Today a species is left out of a cell only below `minBaseline` = 1e-6. This tool shows, on the GERMANY-ONLY maps, for several candidate floors:
#   1. per species: the number of cells whose baseline mean falls in each band (below 1e-6, 1e-6..1e-4, 1e-4..1e-3, 1e-3..1e-2, 1e-2..5e-2, above)
#   2. per floor: how many species-cell ratios are above 10 (the DDA truncates year ratios above 10) and above 100, how many cells lose at least one species,
#      and the spread of the combined regional index of the last year (median, 5%-95%, maximum, cells above 200 or below 50)
#
#   Rscript tools/floorCounts.R [run, default test4] [baseline year 2005] [last year 2025] [meta folder suffix, default _germany]
# On EVE: sbatch cluster/eve_floor_counts.sbatch    (reads outputs/<run>/metamodel_<res>_germany/)
args <- commandArgs(trailingOnly = TRUE)
runName <- if (length(args) >= 1) args[1] else "test4"
y0 <- if (length(args) >= 2) as.integer(args[2]) else 2005L; y1 <- if (length(args) >= 3) as.integer(args[3]) else 2025L
suffix <- if (length(args) >= 4) args[4] else "_germany"
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
suppressMessages(library(terra))
for (f in c("aggregateSpeciesToGrid", "computeGriddedCombinedIndex", "computeRegionalIndexUncertainty"))
  source(file.path("modules", "runIndex_Monitor", "R", paste0(f, ".R")))
dirs <- list.dirs(file.path("outputs", runName), recursive = FALSE, full.names = TRUE)
metaDir <- dirs[grepl(paste0("^metamodel_[0-9_]+", suffix, "$"), basename(dirs))]
if (length(metaDir) != 1) stop("Expected one metamodel_<resolutions>", suffix, " folder under outputs/", runName)
files <- list.files(metaDir, pattern = paste0("_meta_suitability_", y0, "[.]tif$"))
species <- gsub("_", " ", sub("_meta_suitability_.*", "", files))
cat("Maps:", metaDir, "| species:", length(species), "| baseline year", y0, "| last year", y1, "\n")
bands <- c(-Inf, 1e-6, 1e-4, 1e-3, 1e-2, 5e-2, Inf); bandNames <- c("<1e-6", "1e-6..1e-4", "1e-4..1e-3", "1e-3..1e-2", "1e-2..5e-2", ">5e-2")
floors <- c(1e-6, 1e-4, 1e-3, 1e-2)

for (cs in c(10000, 20000, 50000)) {
  cat("\n================ grid", cs / 1000, "km ================\n")
  A <- lapply(species, function(sp) {
    g <- aggregateSpeciesToGrid(sp, c(y0, y1), metaDir, cs)                 # maps are already masked to Germany: no boundary needed
    v <- terra::values(g)[, c(as.character(y0), as.character(y1)), drop = FALSE]; v })
  names(A) <- species
  tab <- t(sapply(A, function(v) table(cut(v[!is.na(v[, 1]), 1], bands, labels = bandNames))))
  cat("\n1. Cells per species by baseline-year cell mean (cells with data: ", sum(!is.na(A[[1]][, 1])), "):\n", sep = ""); print(tab)

  out <- do.call(rbind, lapply(floors, function(fl) {
    ratios <- unlist(lapply(A, function(v) { ok <- !is.na(v[, 1]) & v[, 1] >= fl & !is.na(v[, 2]); v[ok, 2] / v[ok, 1] }))
    left <- Reduce(`+`, lapply(A, function(v) as.integer(!is.na(v[, 1]) & v[, 1] < fl)))       # species left out per cell
    arr <- lapply(A, function(v) array(v, c(nrow(v), 2, 1)))
    idx <- regionalCombineSpecies(arr, baseIdx = 1, minBaseline = fl)[, 2, 1]
    data.frame(floor = format(fl, scientific = TRUE), ratiosAbove10 = sum(ratios > 10), ratiosAbove100 = sum(ratios > 100), speciesCells = length(ratios),
               cellsLosingASpecies = sum(left > 0, na.rm = TRUE), indexMedian = round(stats::median(idx, na.rm = TRUE), 1),
               index5pct = round(stats::quantile(idx, 0.05, na.rm = TRUE), 1), index95pct = round(stats::quantile(idx, 0.95, na.rm = TRUE), 1),
               indexMax = round(max(idx, na.rm = TRUE), 1), cellsAbove200 = sum(idx > 200, na.rm = TRUE), cellsBelow50 = sum(idx < 50, na.rm = TRUE))
  }))
  cat("\n2. What each candidate floor does (", y1, " vs ", y0, "):\n", sep = ""); print(out, row.names = FALSE)
}
cat("\nReading: 'ratiosAbove10' = species-cell values where the index (as a ratio) is more than 10 times the baseline; the DDA truncates such ratios.\n",
    "A floor that removes few species-cells but removes most of the huge ratios is the one to prefer; the decision is Tati's, with the DDA.\n", sep = "")
