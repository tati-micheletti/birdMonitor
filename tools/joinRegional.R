# Regional (10 km cell) version of the series join (2026-11-23), AFTER prediction, same rule as tools/joinSeries.R (CTM v302 = reference):
#   cell mean of the joined series = HCTM cell mean / k(species, replicate) BEFORE the first CTM year (2005-2016), CTM v302 cell mean for all its years (2017-2025).
#   k = the national scale factor of tools/joinSeries.R (scale_factors.csv of the national join): ONE factor per species and replicate, the same in every cell (decision of the project lead 2026-11-22).
# Then, per replicate and cell, EXACTLY as runIndex_Monitor/R/computeRegionalIndexUncertainty.R does it (its own functions are sourced, nothing re-implemented): species index = 100 x cell mean / baseline cell mean,
# combined index = geometric mean over the species of the group, then summaries over the replicates (replicate 0 = main model is not part of any interval), changes and the trend per decade.
#   Rscript tools/joinRegional.R --hctm outputs/s1v3 --ctm outputs/s2v2 --join outputs/joined_ctmref --out outputs/joined_ctmref/regional [--km 10] [--group farmland] [--baseline 2005] [--current 2025]
# CHECKS (printed, written to regional_join_checks.txt):
#   1. control: the same plumbing with k = 1 and the HCTM years only reproduces the pipeline function computeRegionalIndexUncertainty() on the s1v3 files (max |difference| must be ~0);
#   2. consistency: the weighted mean of the joined cell means over the cells (weights = number of German 200 m pixels) equals the national joined area mean of tools/joinSeries.R, per species, year and replicate;
#   3. the joined index of the MAIN model, averaged over the cells with the same weights, is reported next to the national Bird Index Farmland (descriptive: they differ by construction).
# Writes into --out (same names as the pipeline files): regional_index_<km>km_unc_<year>.tif (5 layers), ..._unc_change_<vsBaseline|vs5YearsAgo|vsLastYear>.tif (7), ..._unc_trend_per_decade.tif (7),
# ..._coverage.tif, ..._replicates.rds (cells x years x replicates), and joined_cell_means_<km>km.rds (species -> cells x years x replicates, the joined cell means, for the case-study areas).
suppressMessages(library(terra))
args <- commandArgs(trailingOnly = TRUE)
getArg <- function(f, d = NULL) { i <- which(args == f); if (length(i)) args[i + 1] else d }
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*")); if (length(libs)) .libPaths(c(libs, .libPaths()))
hctmRun <- getArg("--hctm"); ctmRun <- getArg("--ctm"); joinDir <- getArg("--join"); out <- getArg("--out")
if (is.null(hctmRun) || is.null(ctmRun) || is.null(joinDir) || is.null(out)) stop("usage: Rscript tools/joinRegional.R --hctm outputs/s1v3 --ctm outputs/s2v2 --join outputs/joined_ctmref --out outputs/joined_ctmref/regional")
km <- as.integer(getArg("--km", 10)); group <- getArg("--group", "farmland"); base <- as.integer(getArg("--baseline", 2005)); current <- as.integer(getArg("--current", 2025))
tag <- getArg("--tag", "ens_brt-glm-gam-rf-nn"); probs <- c(0.05, 0.95); minBaseline <- 1e-6
kmode <- getArg("--kmode", "national")        # national (default, first version) | cell (2026-11-23): k per species x replicate x 10 km CELL (same definition as the national k, over the overlap years of the cell), the national k where the cell k is not finite or <= 0
if (!kmode %in% c("national", "cell")) stop("--kmode must be national or cell")
scaleYears <- getArg("--scale-years", NULL)   # 2026-11-23 sensitivity (cell mode only): the overlap years the cell k is calibrated on, e.g. 2017:2019 (default = the whole overlap 2017-2023)
if (file.exists(out) && length(list.files(out))) stop("STOP: ", out, " exists and is not empty; choose a new --out (nothing is overwritten)")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
source("modules/runIndex_Monitor/R/computeRegionalIndexUncertainty.R")
g <- read.csv("data/speciesGroups.csv", stringsAsFactors = FALSE); spp <- g$latin_name[g$group == group]; if (!length(spp)) stop("group not found: ", group)
sf <- read.csv(file.path(joinDir, "scale_factors.csv"), stringsAsFactors = FALSE); jam <- read.csv(file.path(joinDir, "joined_area_means.csv"), stringsAsFactors = FALSE)
f <- function(run, sp) file.path(run, paste0("uncertainty_", tag), gsub(" ", "_", sp), "regional", sprintf("regional_means_%dkm.rds", km))
H <- lapply(spp, function(s) readRDS(f(hctmRun, s))); C <- lapply(spp, function(s) readRDS(f(ctmRun, s))); names(H) <- names(C) <- spp
cells <- H[[1]]$cells; grid <- H[[1]]$grid
stopifnot(all(vapply(c(H, C), function(p) identical(p$cells, cells), logical(1))), all(vapply(c(H, C), function(p) identical(p$grid, grid), logical(1))))
ids <- Reduce(intersect, c(lapply(H, `[[`, "ids"), lapply(C, `[[`, "ids"))); hy <- Reduce(intersect, lapply(H, `[[`, "years")); cy <- Reduce(intersect, lapply(C, `[[`, "years"))
hPart <- hy[hy < min(cy)]; yrs <- sort(c(hPart, cy)); message("species ", length(spp), " | cells ", length(cells), " | replicates ", length(ids), " | HCTM years used ", min(hPart), "-", max(hPart), " (divided by k) | CTM years ", min(cy), "-", max(cy), " | joined ", min(yrs), "-", max(yrs))
nG <- H[[1]]$nGerman
## joined cell means per species ---------------------------------------------------------------------------------------------------------------------------------------------------------------
joined <- lapply(spp, function(s) {
  k <- sf$k[match(paste(gsub(" ", "_", s), ids), paste(sf$species, sf$replicate))]; if (anyNA(k)) stop("no scale factor for ", s)
  A <- array(NA_real_, c(length(cells), length(yrs), length(ids)), dimnames = list(NULL, yrs, ids))
  ov <- intersect(hy, cy); nFallback <- 0L
  if (!is.null(scaleYears)) { p <- as.integer(strsplit(scaleYears, ":")[[1]]); ov <- intersect(ov, if (length(p) == 1) p else p[1]:p[2]); if (!length(ov)) stop("--scale-years has no overlap year") }
  kc <- if (kmode == "cell") vapply(seq_along(ids), function(j) {                      # cells x replicates
    hm <- rowMeans(H[[s]]$mean[, match(ov, H[[s]]$years), match(ids[j], H[[s]]$ids), drop = TRUE]); cm <- rowMeans(C[[s]]$mean[, match(ov, C[[s]]$years), match(ids[j], C[[s]]$ids), drop = TRUE])
    kk <- hm / cm; bad <- !is.finite(kk) | kk <= 0; nFallback <<- nFallback + sum(bad); kk[bad] <- k[j]; kk }, numeric(length(cells))) else NULL
  for (j in seq_along(ids)) {
    A[, as.character(hPart), j] <- H[[s]]$mean[, match(hPart, H[[s]]$years), match(ids[j], H[[s]]$ids)] / (if (is.null(kc)) k[j] else kc[, j])
    A[, as.character(cy), j] <- C[[s]]$mean[, match(cy, C[[s]]$years), match(ids[j], C[[s]]$ids)]
  }
  attr(A, "kcell") <- kc; attr(A, "knational") <- k; attr(A, "nFallback") <- nFallback
  A
}); names(joined) <- spp
saveRDS(list(cells = cells, grid = grid, years = yrs, ids = ids, nGerman = nG, means = joined), file.path(out, sprintf("joined_cell_means_%dkm.rds", km)))
lines <- sprintf("k mode: %s", if (kmode == "cell") "CELL (k per species x replicate x 10 km cell over the overlap years; national k where not finite or <= 0)" else "NATIONAL (one k per species and replicate, tools/joinSeries.R)")
if (kmode == "cell") {                                  # per-cell k summary and the junction-step map: how far is the cell k from the national k (geometric mean over the species of cell k / national k, median over replicates)
  kmed <- lapply(spp, function(s) { kc <- attr(joined[[s]], "kcell"); kn <- attr(joined[[s]], "knational"); iM <- which(ids == 0); apply(kc[, -iM, drop = FALSE], 1, median) / median(kn[-iM]) }); names(kmed) <- spp
  step <- exp(rowMeans(vapply(kmed, log, numeric(length(cells))), na.rm = TRUE))
  stepR <- regionalRaster(grid, cells, cbind(stepVsNational = step)); writeRaster(stepR, file.path(out, sprintf("regional_index_%dkm_cell_k_vs_national_geomean.tif", km)), overwrite = TRUE)
  ks <- do.call(rbind, lapply(spp, function(s) { z <- kmed[[s]]; data.frame(species = s, p05 = quantile(z, .05, na.rm = TRUE), p25 = quantile(z, .25, na.rm = TRUE), median = median(z, na.rm = TRUE), p75 = quantile(z, .75, na.rm = TRUE), p95 = quantile(z, .95, na.rm = TRUE), nFallbackCellsReplicates = attr(joined[[s]], "nFallback")) }))
  write.csv(ks, file.path(out, sprintf("cell_k_over_national_k_by_species_%dkm.csv", km)), row.names = FALSE)
  lines <- c(lines, sprintf("cell k / national k (geometric mean over species, median over replicates) over the %d cells: 5%% %.3f | 25%% %.3f | median %.3f | 75%% %.3f | 95%% %.3f", length(cells), quantile(step, .05, na.rm = TRUE), quantile(step, .25, na.rm = TRUE), median(step, na.rm = TRUE), quantile(step, .75, na.rm = TRUE), quantile(step, .95, na.rm = TRUE)),
             sprintf("fallback to the national k in %d cell x replicate x species values (cell k not finite or <= 0)", sum(ks$nFallbackCellsReplicates)))
}
## check 2: weighted mean over the cells = national joined area mean ------------------------------------------------------------------------------------------------------------------------------
w <- nG / sum(nG, na.rm = TRUE); worst <- 0; worstRel <- 0
for (s in spp) {
  nat <- jam[jam$species == gsub(" ", "_", s), ]; A <- joined[[s]]
  for (j in seq_along(ids)) for (yy in yrs) {
    cm <- A[, as.character(yy), j]; ok <- !is.na(cm); reg <- sum(cm[ok] * nG[ok]) / sum(nG[ok])
    nv <- nat$areaMean[nat$replicate == ids[j] & nat$year == yy]; if (length(nv) == 1) { d <- abs(reg - nv); worst <- max(worst, d); worstRel <- max(worstRel, d / nv) }
  }
}
lines <- c(lines, sprintf("CHECK 2 (cells -> national): max |weighted mean of the joined cell means - national joined area mean| = %.3g (relative %.3g %%) over %d species x %d replicates x %d years", worst, 100 * worstRel, length(spp), length(ids), length(yrs)))
## combined index (joined) and the files ----------------------------------------------------------------------------------------------------------------------------------------------------------
comb <- regionalCombineSpecies(unname(joined), baseIdx = match(base, yrs), minBaseline = minBaseline); dimnames(comb) <- list(NULL, yrs, ids)
isMain <- ids == 0; reps3 <- comb[, , !isMain, drop = FALSE]
wr <- function(r, name) writeRaster(r, file.path(out, sprintf("regional_index_%dkm_%s.tif", km, name)), datatype = "FLT4S", overwrite = TRUE, gdal = c("COMPRESS=DEFLATE", "PREDICTOR=3"))
rasterOf <- function(mat) regionalRaster(grid, cells, mat)
for (yr in yrs) wr(rasterOf(regionalSummary(reps3[, as.character(yr), ], probs)), sprintf("unc_%d", yr))
comps <- list(vsBaseline = base, vs5YearsAgo = current - 5L, vsLastYear = current - 1L)
for (nm in names(comps)) if (current %in% yrs && comps[[nm]] %in% yrs) wr(rasterOf(regionalChange(reps3[, as.character(current), ] - reps3[, as.character(comps[[nm]]), ], probs, "delta")), sprintf("unc_change_%s", nm))
slopeOf <- function(arr, yy) { wt <- (yy - mean(yy)) / sum((yy - mean(yy))^2) * 10; s <- matrix(0, dim(arr)[1], dim(arr)[3]); for (i in seq_along(yy)) s <- s + wt[i] * arr[, i, ]; s }
wr(rasterOf(regionalChange(slopeOf(reps3, yrs), probs, "slope")), "unc_trend_per_decade")
wr(rasterOf(cbind(coverage = H[[1]]$nGerman / H[[1]]$fact^2)), "coverage")
saveRDS(list(cellSizeM = km * 1000, cells = cells, years = yrs, ids = ids, index = comb, grid = grid, species = spp), file.path(out, sprintf("regional_index_%dkm_replicates.rds", km)))
## main model: weighted mean over the cells of the combined index, per year (descriptive) --------------------------------------------------------------------------------------------------------
mm <- comb[, , isMain, drop = TRUE]; okc <- rowSums(is.na(mm)) == 0
reg <- apply(mm[okc, , drop = FALSE], 2, function(v) sum(v * nG[okc]) / sum(nG[okc]))
nat <- read.csv(file.path(joinDir, "combined_index_main_model.csv"))
lines <- c(lines, sprintf("CHECK 3 (descriptive): main model, mean over the %d cells with a value in every year (weights = German pixels) of the cell index vs the national Bird Index Farmland:", sum(okc)),
           paste(sprintf("  %d: cells %.2f | national %.2f", yrs[yrs %in% c(2005, 2010, 2016, 2017, 2020, 2023, 2025)], reg[as.character(yrs[yrs %in% c(2005, 2010, 2016, 2017, 2020, 2023, 2025)])], nat$SBI[match(yrs[yrs %in% c(2005, 2010, 2016, 2017, 2020, 2023, 2025)], nat$year)]), collapse = "\n"))
## check 1: control with k = 1 and the HCTM years only vs the pipeline function --------------------------------------------------------------------------------------------------------------------
ctrlDir <- file.path(tempdir(), "ctrl"); suppressMessages(computeRegionalIndexUncertainty(spp, file.path(hctmRun, paste0("uncertainty_", tag)), ctrlDir, base, max(hy), km * 1000, probs, minBaseline))
pip <- readRDS(file.path(ctrlDir, sprintf("regional_index_%dkm_replicates.rds", km)))$index
mine <- regionalCombineSpecies(lapply(spp, function(s) H[[s]]$mean[, match(hy, H[[s]]$years), match(ids, H[[s]]$ids), drop = FALSE]), baseIdx = match(base, hy), minBaseline = minBaseline)
dd <- abs(mine - pip); lines <- c(lines, sprintf("CHECK 1 (control, k = 1, HCTM years %d-%d): max |difference| to the pipeline function = %.3g; NA pattern identical: %s", min(hy), max(hy), max(dd, na.rm = TRUE), all(is.na(unname(mine)) == is.na(unname(pip)))))
## summary numbers -------------------------------------------------------------------------------------------------------------------------------------------------------------------------------
tr <- regionalChange(slopeOf(reps3, yrs), probs, "slope")
lines <- c(lines, sprintf("Trend per decade %d-%d over the %d cells with a value: median of the cell means of the slope = %.2f index points per decade; cells with slope < 0 in >= 95%% of the replicates: %.1f %%; in >= 95%% > 0: %.1f %%",
           min(yrs), max(yrs), sum(!is.na(tr[, 1])), median(tr[, "slopeMean"], na.rm = TRUE), 100 * mean(tr[, "shareDecrease"] >= 0.95, na.rm = TRUE), 100 * mean(tr[, "shareIncrease"] >= 0.95, na.rm = TRUE)))
writeLines(lines, file.path(out, "regional_join_checks.txt")); message(paste(lines, collapse = "\n"))
