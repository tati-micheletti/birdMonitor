# Is the neural network (nnet) well set up? Block-CV performance over a grid of hidden units and weight decay, plus how many fits hit the iteration limit.
#   Rscript tools/diagnoseNN.R <scale: climate|landscape|habitat> [species index, default 1] [--nrep 3]
# Run name: BIRDMONITOR_RUNNAME (default test4); BIRDMONITOR_SPECIES filters the roster as in the other tools. READ-ONLY (prints a table).
args <- commandArgs(trailingOnly = TRUE)
scale <- args[1]; idx <- if (length(args) >= 2 && !startsWith(args[2], "--")) as.integer(args[2]) else 1L
nRep <- if ("--nrep" %in% args) as.integer(args[which(args == "--nrep") + 1]) else 3L
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
suppressMessages({ library(terra); library(gbm); library(glmnet); library(nnet) })
runName <- if (nzchar(Sys.getenv("BIRDMONITOR_RUNNAME"))) Sys.getenv("BIRDMONITOR_RUNNAME") else "test4"
repoRoot <- normalizePath(getwd(), winslash = "/")
for (f in sort(list.files("modules/models_Monitor/R", pattern = "[.]R$", full.names = TRUE))) source(f)
source("tools/sharedConfig.R"); source("tools/sharedSpeciesConfig.R")
gen <- if (file.exists("data/speciesConfig_general.csv")) loadSpeciesGeneralConfig("data/speciesConfig_general.csv") else NULL
cfg <- uncCfgFromParams(inputRoot = file.path(repoRoot, "inputs"), outputRoot = file.path(repoRoot, "outputs", runName), species = sharedSpecies,
                        predictionYears = predictionYears,
                        habitatYears = resolveYearsPerSpecies(sharedSpecies, "habitat", extractYearsConfig(gen), sharedHabitatYears),
                        resolutionConfig = extractResolutionConfig(gen), climateResolutionM = sharedClimateResolutionM,
                        habitatResolutionM = sharedHabitatResolutionM, landscapeResolutionM = sharedLandscapeResolutionM,
                        climateWindowLength = sharedClimateWindowLength, reps = 1, codeRoot = repoRoot)
sp <- sharedSpecies[idx]; tbl <- uncTrainingTable(cfg, sp, scale); predSel <- ensPredictors(cfg, sp, scale)
cat(sp, "|", scale, "|", nrow(tbl), "records,", length(predSel), "predictors,", sum(tbl$occurrence == 1), "presences | starts per fit:", nRep, "\n")
folds <- sort(unique(tbl$foldID))
grid <- rbind(expand.grid(size = c(3, 10, 20), decay = c(0.01, 0.1, 1), maxit = 300), data.frame(size = 10, decay = 0.1, maxit = 1000))
out <- do.call(rbind, lapply(seq_len(nrow(grid)), function(i) {
  g <- grid[i, ]; t0 <- Sys.time(); cv <- rep(NA_real_, nrow(tbl)); notConv <- 0L; nFit <- 0L
  for (k in folds) {
    tr <- which(tbl$foldID != k); te <- which(tbl$foldID == k)
    fit <- algoFitNN(tbl[tr, , drop = FALSE], predSel, "occurrence", seed = stableSeed(c("diagNN", sp, scale, k, i)), size = g$size, decay = g$decay, nRep = nRep, maxit = g$maxit)
    notConv <- notConv + sum(vapply(fit$model$fits, function(m) m$convergence, numeric(1)) != 0); nFit <- nFit + nRep
    cv[te] <- algoPredictNN(fit, tbl[te, , drop = FALSE])
  }
  p <- evalSDM(tbl$occurrence, cv)
  data.frame(size = g$size, decay = g$decay, maxit = g$maxit, AUC = round(p$AUC, 3), TSS = round(p$TSS, 3), D2 = round(p$D2, 3),
             hitIterationLimit = sprintf("%d/%d", notConv, nFit), minutes = round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1))
}))
print(out, row.names = FALSE)
cat("\nReading: hitIterationLimit = fits that stopped at maxit WITHOUT converging. Compare AUC/D2 with the other members of this scale",
    "(see <sp>_perf_members_*.rds). The current setting is size 10, decay 0.1, maxit 300.\n")
