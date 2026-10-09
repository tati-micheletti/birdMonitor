# READ-ONLY diagnostic (2026-10-10): the BRT-only replicates show LESS decline than the baseline. Combined index 2025: baseline 95.6, replicates 97.5 (90% interval 96.1-99.0);
# Perdix perdix baseline 91.1 vs replicates 99.0-100; Vanellus vanellus 90.8 vs 91.3-96.3. Replicate 0 (= the main model) equals the baseline (parity OK), so the question is why the
# 50 bootstrap replicates sit systematically higher. Suspect: the ridge meta-model of a replicate chooses its penalty with SPATIAL BLOCK folds (the baseline: ten random folds) and may shrink a
# scale that carries the trend (climate) towards zero. Per species this prints
#   1. the index of the last year for replicate 0 and for the replicates (median, 5%, 95%) and the percentile rank of replicate 0 among them
#   2. the ridge weights: baseline (= replicate 0) and the replicates (median, 5%, 95%, and the share of replicates whose weight is exactly 0)
#   3. the penalty (lambda): replicate 0 vs the median of the replicates
#
#   Rscript tools/diagnoseReplicateBias.R [run test4] [tag honest2] [label reps_000-050] [year 2025]
args <- commandArgs(trailingOnly = TRUE)
a <- function(i, d) if (length(args) >= i && nzchar(args[i])) args[i] else d
runName <- a(1, "test4"); tag <- a(2, "honest2"); lab <- a(3, "reps_000-050"); yr <- as.integer(a(4, "2025"))
uncDir <- file.path("outputs", runName, paste0("uncertainty_", tag))
sps <- list.dirs(uncDir, recursive = FALSE, full.names = FALSE); sps <- sps[file.exists(file.path(uncDir, sps, "ridge", paste0("ridge_", lab, ".rds")))]
rows <- list()
for (sp in sps) {
  r <- tryCatch({
    am <- read.csv(file.path(uncDir, sp, "area_mean_replicates_germany.csv"))
    idx <- function(y) { a0 <- am[am$year == 2005, c("replicate", "areaMean")]; ay <- am[am$year == y, c("replicate", "areaMean")]; m <- merge(a0, ay, by = "replicate"); setNames(100 * m[[3]] / m[[2]], m$replicate) }
    ix <- idx(yr); i0 <- ix["0"]; ir <- ix[names(ix) != "0"]
    rk <- mean(ir < i0)
    rg <- readRDS(file.path(uncDir, sp, "ridge", paste0("ridge_", lab, ".rds"))); cf <- rg$coef; ids <- rg$ids; r0 <- which(ids == 0); co <- cf[-r0, , drop = FALSE]
    zero <- function(j) mean(co[, j] == 0, na.rm = TRUE)
    data.frame(species = sp, idxRep0 = round(i0, 1), idxMedian = round(median(ir), 1), idx05 = round(quantile(ir, .05), 1), idx95 = round(quantile(ir, .95), 1), rankRep0 = round(rk, 2),
               climBase = round(cf[r0, 2], 2), climMed = round(median(co[, 2], na.rm = TRUE), 2), climZero = round(zero(2), 2),
               landBase = round(cf[r0, 3], 2), landMed = round(median(co[, 3], na.rm = TRUE), 2), habBase = round(cf[r0, 4], 2), habMed = round(median(co[, 4], na.rm = TRUE), 2),
               lamBase = signif(rg$info$lambda[r0], 3), lamMed = signif(median(rg$info$lambda[-r0], na.rm = TRUE), 3), row.names = NULL)
  }, error = function(e) data.frame(species = sp, idxRep0 = conditionMessage(e)))
  rows[[sp]] <- r
}
res <- do.call(rbind, lapply(rows, function(d) { d })); rownames(res) <- NULL
options(width = 250); print(res, row.names = FALSE)
cat("\nReading: rankRep0 = share of replicates BELOW replicate 0 in the index of the last year (0 = replicate 0 is lower than every replicate); clim/land/hab Base = the baseline (replicate 0) weight,",
    "\nMed = median over the replicates, climZero = share of replicates whose climate weight is exactly 0; lamBase / lamMed = ridge penalty of replicate 0 / median of the replicates.\n")
