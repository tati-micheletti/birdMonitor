# Local test, step 2: ridge + band prediction + PARITY with the baseline's meta-model maps (replicate 0 = main models)
# then the summaries on that one band. Run step1.R first (same species/run).
Sys.setenv(BIRDMONITOR_RUNNAME = "utest", BIRDMONITOR_SPECIES = "Alauda arvensis", BIRDMONITOR_UNC_REPS = "0:3",
           BIRDMONITOR_UNC_YEARS = "2020:2025", BIRDMONITOR_UNC_BANDS = "40", BIRDMONITOR_UNC_REPBATCH = "2")
suppressMessages({library(terra); library(gbm); library(glmnet)})
for (f in list.files("uncertainty/R", full.names = TRUE)) source(f)
cfg <- uncCfg(getwd()); sp <- cfg$species; spClean <- gsub(" ", "_", sp)
cat("replicate label:", cfg$repLabel, "| years:", cfg$outYears, "\n")

uncPreflight(cfg)
uncCovcache(cfg)                 # the extra years (cached ones are skipped)
uncFitSpecies(cfg, sp)           # exists -> skipped
uncCoarseSpecies(cfg, sp)        # extra years
uncRidgeSpecies(cfg, sp)

# ---- parity of the ridge coefficients with the baseline's -------------------------------------------------------
ridge <- readRDS(file.path(uncSpDir(cfg, sp, "ridge"), paste0("ridge_", cfg$repLabel, ".rds")))
mainRidge <- readRDS(file.path("outputs", cfg$runName, "metamodel_02_1_50", paste0(spClean, "_ridge_meta.rds")))
mainCoef <- as.vector(coef(mainRidge$model, s = mainRidge$lambda))
cat("\nRIDGE COEFFICIENTS (intercept, climate, landscape, habitat)\n  baseline  : ", signif(mainCoef, 6),
    "\n  replicate0: ", signif(ridge$coef["rep_0", ], 6), "\n  replicates: \n"); print(round(ridge$coef, 4))
print(ridge$info)

# ---- one band with many training records ---------------------------------------------------------------------------
bands <- uncBands(cfg, sp)$bands
spPa <- uncTrainingTable(cfg, sp, "habitat")
cnt <- vapply(bands, function(b) sum(!is.na(terra::cellFromXY(b$template, cbind(spPa$x, spPa$y)))), numeric(1))
band <- bands[[which.max(cnt)]]; cat("\nband", band$k, "with", max(cnt), "training records; cells:", terra::ncell(band$template), "\n")

ctx <- uncContext(cfg, sp)
for (yr in cfg$outYears) {
  t0 <- Sys.time(); st <- uncPredictBandYear(cfg, sp, ctx, ridge, yr, band)
  cat("year", yr, st, round(as.numeric(difftime(Sys.time(), t0, units = "secs"))), "s\n")
}

# ---- parity of the maps: replicate 0 vs the baseline's meta_prob ---------------------------------------------------
for (yr in c(min(cfg$outYears), max(cfg$outYears))) {
  p <- uncReadInt16(file.path(uncSpDir(cfg, sp, "pred", cfg$repLabel), sprintf("%d_band%02d.rds", yr, band$k)))
  main <- terra::rast(file.path("outputs", cfg$runName, "metamodel_02_1_50", sprintf("%s_meta_suitability_%d.tif", spClean, yr)))[["meta_prob"]]
  xy <- terra::xyFromCell(band$template, p$idx)
  mv <- terra::extract(main, xy)[, 1]
  r0 <- p$P[, which(p$ids == 0)]
  ok <- !is.na(mv) & !is.na(r0)
  cat(sprintf("\nPARITY %d: valid cells replicate0 %d | baseline %d | both %d\n", yr, sum(!is.na(r0)), sum(!is.na(mv)), sum(ok)))
  cat(sprintf("  max |diff| = %.5f | mean |diff| = %.6f | correlation = %.6f\n", max(abs(r0[ok] - mv[ok])), mean(abs(r0[ok] - mv[ok])), cor(r0[ok], mv[ok])))
  cat("  baseline cells valid but not in replicate 0:", sum(!is.na(mv) & is.na(r0)), "\n")
  cat("  spread among bootstrap replicates (mean width of range over cells):",
      round(mean(apply(p$P[, p$ids != 0, drop = FALSE], 1, function(v) diff(range(v))), na.rm = TRUE), 4), "\n")
}

# ---- summaries for this band ---------------------------------------------------------------------------------------
uncSummarizeSpeciesBand(cfg, sp, band)
cat("\npieces written:\n"); print(list.files(uncSpDir(cfg, sp, "pieces")))
uncAssembleSpecies(cfg, sp)
cat("\nmaps:\n"); print(list.files(uncSpDir(cfg, sp, "maps")))
tr <- terra::rast(file.path(uncSpDir(cfg, sp, "maps"), sprintf("%s_unc_trend_per_decade.tif", spClean)))
print(tr); print(terra::global(tr, "mean", na.rm = TRUE))
cat("\nDONE step 2\n")
