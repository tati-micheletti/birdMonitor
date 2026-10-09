# READ-ONLY diagnostic, step 2 of the replicate-0 parity check. Step 1 (tools/diagnoseParity.R) showed that the ridge weights, the penalty and the out-of-fold inputs are
# IDENTICAL for the baseline and replicate 0, also for the two species that differ (Anthus pratensis, Sturnus vulgaris). So the difference must be in the three
# scale PREDICTION MAPS the weights are applied to. At random German pixels this compares, per year and species:
#   climate / landscape : the baseline map (<scale dir>/<sp>_pred_EU_<year>.tif, _pred_landscape_) against replicate 0's coarse prediction (coarse/<label>/<scale>_<year>.tif, layer rep_0)
#   habitat             : the baseline map (<sp>_pred_habitat_<year>.tif) against replicate 0's habitat prediction (computed from the covariate cache)
#   final map           : the baseline meta map against replicate 0's (replicate scale inputs + replicate 0 weights)
# and how much each scale contributes to the difference (weight x mean absolute difference, on the logit scale).
#
#   Rscript tools/diagnoseParityMaps.R [run test4] [tag honest2] [label reps_000-050] [years 2025,2015] [species ";"-separated, default the three below] [points 3000]
args <- commandArgs(trailingOnly = TRUE)
a <- function(i, d) if (length(args) >= i && nzchar(args[i])) args[i] else d
runName <- a(1, "test4"); tag <- a(2, "honest2"); lab <- a(3, "reps_000-050")
years <- as.integer(strsplit(a(4, "2025,2015"), ",")[[1]]); species <- strsplit(a(5, "Alauda arvensis;Anthus pratensis;Sturnus vulgaris"), ";")[[1]]; nPts <- as.integer(a(6, "3000"))
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
suppressMessages({ library(terra); library(gbm); library(glmnet) })
Sys.setenv(BIRDMONITOR_RUNNAME = runName, BIRDMONITOR_UNC_TAG = if (tag == "none") "" else tag, BIRDMONITOR_UNC_REPS = "0:50", BIRDMONITOR_UNC_YEARS = paste(years, collapse = ","))
repoRoot <- normalizePath(getwd(), winslash = "/")
source("modules/models_Monitor/tests/uncertainty/helper.R")          # sources the module functions and builds the configuration like the cluster tasks do
cfg <- testCfg(); cfg$repLabel <- lab
dirs <- list.dirs(file.path("outputs", runName), recursive = FALSE, full.names = TRUE)
metaDir <- dirs[grepl("^metamodel_[0-9_]+$", basename(dirs))]
modelDir <- list(climate = file.path("outputs", runName, "scale_50"), landscape = file.path("outputs", runName, "scale_1"), habitat = file.path("outputs", runName, "scale_02"))
fileOf <- function(sp, scale, yr) file.path(modelDir[[scale]], sprintf("%s_pred_%s_%d.tif", gsub(" ", "_", sp), c(climate = "EU", landscape = "landscape", habitat = "habitat")[[scale]], yr))
res <- list()
for (sp in species) for (yr in years) {
  r <- tryCatch({
    spC <- gsub(" ", "_", sp)
    base <- terra::rast(file.path(metaDir, sprintf("%s_meta_suitability_%d.tif", spC, yr)))[["meta_prob"]]
    set.seed(1); pts <- terra::spatSample(base, nPts, method = "random", na.rm = TRUE, xy = TRUE); xy <- as.matrix(pts[, c("x", "y")]); bm <- pts[[3]]
    atB <- function(f, lyr = 1) terra::extract(terra::rast(f)[[lyr]], xy, method = "bilinear")[, 1]
    sb <- cbind(climate = atB(fileOf(sp, "climate", yr)), landscape = atB(fileOf(sp, "landscape", yr)), habitat = atB(fileOf(sp, "habitat", yr)))
    ridge <- readRDS(file.path(uncSpDir(cfg, sp, "ridge"), paste0("ridge_", lab, ".rds"))); j <- which(ridge$ids == 0); w <- ridge$coef[j, ]
    cd <- file.path(uncSpDir(cfg, sp, "coarse", lab))
    sr <- cbind(climate = terra::extract(terra::rast(file.path(cd, sprintf("climate_%d.tif", yr)))[["rep_0"]], xy, method = "bilinear")[, 1],
                landscape = terra::extract(terra::rast(file.path(cd, sprintf("landscape_%d.tif", yr)))[["rep_0"]], xy, method = "bilinear")[, 1])
    ctx <- uncContext(cfg, sp); pos <- which(ctx$ids == 0); win <- uncBands(cfg, sp)$window
    S <- uncBandSuitability(cfg, sp, ctx, yr, win, pos, ptsXY = xy); cells <- terra::cellFromXY(win, xy)
    sr <- cbind(sr, habitat = S$hab[cells, 1])
    rep0 <- stats::plogis(w[1] + w[2] * S$clim[cells, 1] + w[3] * S$land[cells, 1] + w[4] * S$hab[cells, 1])
    bAppl <- stats::plogis(w[1] + w[2] * sb[, "climate"] + w[3] * sb[, "landscape"] + w[4] * sb[, "habitat"])
    d <- abs(sr - sb); ok <- stats::complete.cases(sb, sr)
    out <- data.frame(species = sp, year = yr, points = sum(ok),
      climMax = signif(max(d[ok, "climate"]), 3), landMax = signif(max(d[ok, "landscape"]), 3), habMax = signif(max(d[ok, "habitat"]), 3),
      climMean = signif(mean(d[ok, "climate"]), 3), landMean = signif(mean(d[ok, "landscape"]), 3), habMean = signif(mean(d[ok, "habitat"]), 3),
      mapMaxDiff = signif(max(abs(rep0[ok] - bm[ok])), 3), mapMeanDiff = signif(mean(abs(rep0[ok] - bm[ok])), 3),
      baseScalesRidgeVsMap = signif(max(abs(bAppl[ok] - bm[ok])), 3),
      logitShare_clim = signif(abs(w[2]) * mean(d[ok, "climate"]), 3), logitShare_land = signif(abs(w[3]) * mean(d[ok, "landscape"]), 3), logitShare_hab = signif(abs(w[4]) * mean(d[ok, "habitat"]), 3))
    out
  }, error = function(e) data.frame(species = sp, year = yr, points = NA, climMax = conditionMessage(e)))
  res[[paste(sp, yr)]] <- r
}
for (n in names(res)) { d <- res[[n]]; cat("\n---", n, "---\n"); print(t(d[1, , drop = FALSE]), quote = FALSE) }
cat("\nReading: xxxMax / xxxMean = largest / mean absolute difference of that scale's input (replicate 0 minus baseline) at random German pixels; mapMaxDiff = largest difference of the final",
    "\nmap; baseScalesRidgeVsMap = check that the baseline scale maps + the baseline weights reproduce the baseline meta map (should be ~0); logitShare_* = weight x mean difference:",
    "\nthe scale with the largest share is where the two paths diverge.\n")
