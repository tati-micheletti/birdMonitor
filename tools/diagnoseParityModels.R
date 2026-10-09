# READ-ONLY diagnostic, step 3 of the replicate-0 parity check (2026-10-09). Step 2 showed that for Anthus pratensis the CLIMATE-scale prediction of replicate 0 differs from the baseline
# in every year (also 2015, which the climate-data fix did not touch), while landscape and habitat are identical. Hypothesis: replicate 0 holds a COPY of the main BRT made before the
# europe array refitted the climate model on 2026-10-08, and the refit is not identical for every species.
# For every species and scale this compares the baseline main BRT (outputs/<run>/<scale dir>/<sp>_BRT_*.rds) with the model stored as replicate 0 (uncertainty_<tag>/<sp>/models/<scale>_<label>.rds):
# number of trees, predictions on the first 500 training records, and the file times. Changes nothing.
#
#   Rscript tools/diagnoseParityModels.R [run test4] [tag honest2] [label reps_000-050]
args <- commandArgs(trailingOnly = TRUE)
a <- function(i, d) if (length(args) >= i && nzchar(args[i])) args[i] else d
runName <- a(1, "test4"); tag <- a(2, "honest2"); lab <- a(3, "reps_000-050")
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
suppressMessages({ library(terra); library(gbm); library(glmnet) })
Sys.setenv(BIRDMONITOR_RUNNAME = runName, BIRDMONITOR_UNC_TAG = if (tag == "none") "" else tag, BIRDMONITOR_UNC_REPS = "0:50", BIRDMONITOR_UNC_YEARS = "2025")
source("modules/models_Monitor/tests/uncertainty/helper.R")
cfg <- testCfg(); cfg$repLabel <- lab
nTr <- function(m) if (!is.null(m$gbm.call$best.trees)) m$gbm.call$best.trees else m$n.trees
rows <- list()
for (sp in cfg$species) for (sc in c("climate", "landscape", "habitat")) {
  rows[[paste(sp, sc)]] <- tryCatch({
    mb <- uncMainModel(cfg, sp, sc)
    f0 <- file.path(uncSpDir(cfg, sp, "models"), paste0(sc, "_", lab, ".rds")); mr <- readRDS(f0); m0 <- mr$models[[which(mr$ids == 0)]]
    tb <- uncTrainingTable(cfg, sp, sc); tb <- tb[seq_len(min(500, nrow(tb))), , drop = FALSE]
    pb <- gbm::predict.gbm(mb, tb[, mr$predSel, drop = FALSE], n.trees = nTr(mb), type = "response")
    p0 <- gbm::predict.gbm(m0, tb[, mr$predSel, drop = FALSE], n.trees = nTr(m0), type = "response")
    fb <- file.path(uncMainDir(cfg, sp, sc), paste0(gsub(" ", "_", sp), "_BRT_", .uncModelSuffix[[sc]], ".rds"))
    data.frame(species = sp, scale = sc, treesBaseline = nTr(mb), treesRep0 = nTr(m0), maxPredDiff = signif(max(abs(pb - p0)), 3),
               baselineModelTime = format(file.mtime(fb), "%m-%d %H:%M"), rep0ModelTime = format(file.mtime(f0), "%m-%d %H:%M"), stringsAsFactors = FALSE)
  }, error = function(e) data.frame(species = sp, scale = sc, treesBaseline = NA, treesRep0 = NA, maxPredDiff = NA, baselineModelTime = conditionMessage(e), rep0ModelTime = "", stringsAsFactors = FALSE))
}
res <- do.call(rbind, rows); rownames(res) <- NULL
options(width = 250); print(res, row.names = FALSE)
cat("\nReading: maxPredDiff = largest difference between the baseline model and the replicate-0 model on 500 training records (0 = the same model).",
    "\nA non-zero value, or different numbers of trees, means replicate 0 is NOT the baseline's current model; the file times show which one is older.\n")
