# Multi-species indicator (MSI) of the PECBMS kind: the point estimate is the geometric mean of the species indices of the MAIN model; the confidence band comes from a Monte Carlo
# simulation (Soldaat et al. 2017), in which every species index is drawn from a normal distribution on the log scale with its standard error. Here the standard error of a species index is
# the standard deviation of that index across the bootstrap replicates (the same rule as the "MSI" rows of combined_index_uncertainty.csv, modules/runIndex_Monitor/R/computeIndexUncertainty.R,
# which centres the band on the replicate mean instead of on the main model).
#   est <- msiMonteCarlo(center, sd)       center, sd: species x year matrices (same dimnames), the index of each species and its standard deviation
# Returns a data.frame (year, estimate, lwr, upr, nSpecies); the interval is the 5th to 95th percentile of nSim draws of the geometric mean. set.seed(seed) once, years in the order of the columns.
msiMonteCarlo <- function(center, sd, nSim = 1000, probs = c(0.05, 0.95), seed = 42) {
  stopifnot(identical(dim(center), dim(sd)))
  set.seed(seed)
  do.call(rbind, lapply(seq_len(ncol(center)), function(j) {
    ix <- center[, j]; se <- sd[, j]; ok <- !is.na(ix) & !is.na(se) & ix > 0; ix <- ix[ok]; se <- se[ok]; nT <- length(ix)
    if (nT == 0) return(NULL)
    sims <- vapply(seq_len(nSim), function(i) exp(mean(stats::rnorm(nT, mean = log(ix), sd = se / ix))), numeric(1))
    data.frame(year = as.integer(colnames(center)[j]), estimate = exp(mean(log(ix))), lwr = unname(stats::quantile(sims, probs[1])), upr = unname(stats::quantile(sims, probs[2])), nSpecies = nT)
  }))
}
