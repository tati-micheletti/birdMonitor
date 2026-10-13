#!/usr/bin/env Rscript
# READ-ONLY sensitivity analysis (2026-10-13). Changes nothing under outputs/ except one new csv.
#
# Why: in the BRT-only run (honest2) 9 of 50 replicates of Perdix perdix have an index of exactly 100 in every year, i.e. the replicate
# meta-model chose the penalty (lambda.1se) so large that all scale weights are zero and the predicted map is constant. Those replicates
# carry no information about change, yet they enter the interval. This script
#   1. counts, for EVERY species, the replicates whose index is constant over all years (the answer to "is it only Perdix?"),
#   2. recomputes the interval of each affected species without those replicates,
#   3. recomputes the combined index (SBI, geometric mean) interval three ways:
#        all        = every replicate (should reproduce combined_index_uncertainty.csv),
#        cells      = the constant species-replicate cells are dropped, the other species of that replicate stay,
#        replicates = every replicate with at least one constant species is dropped completely.
# The rule of the main run is NOT changed: this is a reported sensitivity analysis next to the main interval.
#
#   Rscript tools/sensitivityConstantReplicates.R [run test4] [tag honest2] [area-mean file area_mean_replicates_germany.csv]
#   big 5:  Rscript tools/sensitivityConstantReplicates.R test4 ens_brt-glm-gam-rf-nn
# Output: screen + outputs/<run>/sensitivity_constant_replicates_<tag>.csv
args <- commandArgs(trailingOnly = TRUE)
run <- if (length(args) >= 1) args[1] else "test4"
tag <- if (length(args) >= 2) args[2] else "honest2"
areaFile <- if (length(args) >= 3) args[3] else "area_mean_replicates_germany.csv"
probs <- c(0.05, 0.95)

uncDir <- file.path("outputs", run, paste0("uncertainty_", tag))
if (!dir.exists(uncDir)) stop("not found: ", uncDir, " (run from the repo root)")
files <- Sys.glob(file.path(uncDir, "*", areaFile))
if (length(files) == 0) stop("no ", areaFile, " files under ", uncDir)
am <- do.call(rbind, lapply(files, function(f) read.csv(f, stringsAsFactors = FALSE)[, c("species", "replicate", "year", "areaMean")]))
am <- am[am$replicate != 0, ]                                   # replicate 0 = the main model, never part of an interval
yrs <- sort(unique(am$year)); baseYear <- min(yrs)
key <- paste(am$species, am$replicate)
b <- am[am$year == baseYear, ]
am$index <- 100 * am$areaMean / b$areaMean[match(key, paste(b$species, b$replicate))]

# 1. constant replicates (index identical in every year)
rng <- aggregate(index ~ species + replicate, am, function(v) max(v) - min(v))
rng$constant <- rng$index < 1e-6
spp <- sort(unique(am$species)); reps <- sort(unique(am$replicate))
constMat <- matrix(FALSE, length(spp), length(reps), dimnames = list(spp, reps))
constMat[cbind(match(rng$species, spp), match(rng$replicate, reps))] <- rng$constant
cat("\n=== replicates with a CONSTANT index (all years equal), of", length(reps), "replicates per species\n")
cnt <- data.frame(species = spp, nConstant = rowSums(constMat), share = round(rowSums(constMat) / length(reps), 2))
print(cnt, row.names = FALSE)

arr <- array(NA_real_, c(length(spp), length(yrs), length(reps)), dimnames = list(spp, yrs, reps))
arr[cbind(match(am$species, spp), match(am$year, yrs), match(am$replicate, reps))] <- am$index
sbi <- function(a) apply(a, c(2, 3), function(v) { v <- v[!is.na(v) & v > 0]; if (length(v)) exp(mean(log(v))) else NA_real_ })
summ <- function(m) data.frame(year = yrs, nReplicates = apply(m, 1, function(v) sum(!is.na(v))), mean = rowMeans(m, na.rm = TRUE),
                               lwr = apply(m, 1, quantile, probs = probs[1], na.rm = TRUE), upr = apply(m, 1, quantile, probs = probs[2], na.rm = TRUE))
out <- list()

# 2. affected species: interval with and without the constant replicates
aff <- spp[rowSums(constMat) > 0]
for (s in aff) {
  v <- arr[s, , ]
  out[[paste(s, "all")]] <- cbind(scope = s, variant = "all", summ(v))
  out[[paste(s, "without")]] <- cbind(scope = s, variant = "without constant replicates", summ(v[, !constMat[s, ], drop = FALSE]))
}

# 3. combined index three ways
arrCells <- arr
ij <- which(constMat, arr.ind = TRUE)
for (k in seq_len(nrow(ij))) arrCells[ij[k, 1], , ij[k, 2]] <- NA
keep <- colSums(constMat) == 0
out[["combined all"]] <- cbind(scope = "combined SBI", variant = "all replicates", summ(sbi(arr)))
out[["combined cells"]] <- cbind(scope = "combined SBI", variant = "constant species-replicate cells dropped", summ(sbi(arrCells)))
out[["combined reps"]] <- cbind(scope = "combined SBI", variant = "replicates with a constant species dropped", summ(sbi(arr[, , keep, drop = FALSE])))
res <- do.call(rbind, out); rownames(res) <- NULL
f <- file.path("outputs", run, paste0("sensitivity_constant_replicates_", tag, ".csv"))
write.csv(res, f, row.names = FALSE)

cat("\n=== intervals (", probs[1] * 100, "% - ", probs[2] * 100, "%), years ", paste(intersect(c(2015, 2025), yrs), collapse = " and "), "\n", sep = "")
shown <- res[res$year %in% c(2015, 2025), ]
shown[, c("mean", "lwr", "upr")] <- round(shown[, c("mean", "lwr", "upr")], 1)
print(shown, row.names = FALSE)
cat("\nreplicates kept when whole replicates are dropped:", sum(keep), "of", length(reps), "\n")
cat("full table written to", f, "\n")
cat("check: the 'combined SBI / all replicates' rows should match combined_index_uncertainty.csv (SBI) up to the quantile definition\n")
