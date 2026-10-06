# Replicate 0 of the uncertainty run is the main models run through the replicate machinery, so its ridge weights must equal the
# baseline meta-model's weights (both are trained on the same out-of-fold inputs). One row per species; "maxDiff" should be ~0.
#   Rscript tools/checkRidgeParity.R [tag, default honest]      run name: BIRDMONITOR_RUNNAME (default test4)
args <- commandArgs(trailingOnly = TRUE)
tag <- if (length(args)) args[1] else "honest"
runName <- if (nzchar(Sys.getenv("BIRDMONITOR_RUNNAME"))) Sys.getenv("BIRDMONITOR_RUNNAME") else "test4"
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
suppressMessages(library(glmnet))
root <- file.path("outputs", runName)
uncDir <- file.path(root, paste0("uncertainty", if (nzchar(tag)) paste0("_", tag) else ""))
spDirs <- list.dirs(uncDir, recursive = FALSE); spDirs <- spDirs[file.exists(file.path(spDirs, "ridge"))]
rows <- lapply(spDirs, function(d) {
  sp <- basename(d)
  rf <- list.files(file.path(d, "ridge"), pattern = "^ridge_.*[.]rds$", full.names = TRUE)
  bf <- Sys.glob(file.path(root, "metamodel_*", paste0(sp, "_ridge_meta.rds")))
  if (!length(rf) || !length(bf)) return(data.frame(species = sp, note = "ridge or baseline file missing"))
  r <- readRDS(rf[1]); m <- readRDS(bf[1])
  base <- as.vector(coef(m$model, s = m$lambda))
  rep0 <- as.numeric(r$coef["rep_0", ])
  data.frame(species = sp, basis = if (is.null(m$trainBasis)) "?" else m$trainBasis,
             base_clim = round(base[2], 4), rep0_clim = round(rep0[2], 4),
             base_land = round(base[3], 4), rep0_land = round(rep0[3], 4),
             base_hab = round(base[4], 4), rep0_hab = round(rep0[4], 4),
             maxDiff = signif(max(abs(base - rep0)), 3), minWeight = round(min(rep0[-1], na.rm = TRUE), 4),
             stringsAsFactors = FALSE)
})
out <- do.call(rbind, lapply(rows, function(x) { for (n in c("basis", "base_clim", "rep0_clim", "base_land", "rep0_land", "base_hab", "rep0_hab", "maxDiff", "minWeight", "note"))
  if (is.null(x[[n]])) x[[n]] <- NA; x[, c("species", "basis", "base_clim", "rep0_clim", "base_land", "rep0_land", "base_hab", "rep0_hab", "maxDiff", "minWeight", "note")] }))
print(out, row.names = FALSE)
cat("\nOK when: basis = 'out-of-fold inputs' for every species, maxDiff ~ 0, minWeight >= 0.\n")
