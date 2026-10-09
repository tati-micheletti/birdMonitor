# READ-ONLY diagnostic for the replicate-0 parity check (2026-10-09: Anthus pratensis and Sturnus vulgaris differ from the baseline map by up to 0.003).
# Replicate 0 = the main models pushed through the uncertainty machinery; the baseline meta-model and replicate 0 each fit their ridge on OUT-OF-FOLD inputs.
# For every species this compares
#   1. the ridge weights: baseline (<sp>_ridge_meta.rds, as the map uses them) vs replicate 0 (ridge_<run>.rds), and the penalty (lambda) each chose
#   2. the out-of-fold inputs the two ridges were trained on (baseline <sp>_meta_check.rds$oof$X vs replicate 0 oof_<run>.rds): which scale, how large, how many rows
# so that we can see WHERE the two paths diverge. Changes nothing.
#
#   Rscript tools/diagnoseParity.R [run, default test4] [uncertainty tag, default honest2] [replicate label, default reps_000-050]
args <- commandArgs(trailingOnly = TRUE)
runName <- if (length(args) >= 1) args[1] else "test4"; tag <- if (length(args) >= 2) args[2] else "honest2"; lab <- if (length(args) >= 3) args[3] else "reps_000-050"
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
suppressMessages(library(glmnet))
dirs <- list.dirs(file.path("outputs", runName), recursive = FALSE, full.names = TRUE)
metaDir <- dirs[grepl("^metamodel_[0-9_]+$", basename(dirs))]; uncDir <- file.path("outputs", runName, paste0("uncertainty_", tag))
cat("baseline meta folder:", metaDir, "| uncertainty folder:", uncDir, "| replicate label:", lab, "\n\n")
sps <- sub("^(.*)_meta_check[.]rds$", "\\1", list.files(metaDir, pattern = "_meta_check[.]rds$"))
rows <- list()
for (sp in sps) {
  r <- tryCatch({
    m <- readRDS(file.path(metaDir, paste0(sp, "_ridge_meta.rds")))
    cb <- as.vector(coef(m$model, s = m$lambda)); lamB <- m$lambda
    rr <- readRDS(file.path(uncDir, sp, "ridge", paste0("ridge_", lab, ".rds"))); j <- which(rr$ids == 0)
    c0 <- as.vector(rr$coef[j, ]); lam0 <- rr$info$lambda[j]
    chk <- readRDS(file.path(metaDir, paste0(sp, "_meta_check.rds")))
    oo <- readRDS(file.path(uncDir, sp, "oof", paste0("oof_", lab, ".rds")))
    S0 <- oo$S[, , which(oo$ids == 0)]; ok <- stats::complete.cases(S0); S0 <- S0[ok, , drop = FALSE]; Xb <- chk$oof$X
    dX <- if (nrow(S0) == nrow(Xb)) apply(abs(S0 - Xb), 2, max) else rep(NA_real_, 3)
    data.frame(species = sp, coefBase = paste(round(cb, 4), collapse = " "), coefRep0 = paste(round(c0, 4), collapse = " "), maxDCoef = signif(max(abs(cb - c0)), 3),
               lambdaBase = signif(lamB, 4), lambdaRep0 = signif(lam0, 4), rowsBase = nrow(Xb), rowsRep0 = nrow(S0),
               dClim = signif(dX[1], 3), dLand = signif(dX[2], 3), dHab = signif(dX[3], 3), stringsAsFactors = FALSE)
  }, error = function(e) data.frame(species = sp, coefBase = paste("ERROR:", conditionMessage(e)), stringsAsFactors = FALSE))
  rows[[sp]] <- r
}
res <- do.call(rbind, lapply(rows, function(d) { for (n in c("coefRep0", "maxDCoef", "lambdaBase", "lambdaRep0", "rowsBase", "rowsRep0", "dClim", "dLand", "dHab")) if (is.null(d[[n]])) d[[n]] <- NA; d }))
rownames(res) <- NULL
options(width = 250); print(res[, c("species", "maxDCoef", "lambdaBase", "lambdaRep0", "rowsBase", "rowsRep0", "dClim", "dLand", "dHab")], row.names = FALSE)
cat("\nCoefficients (intercept climate landscape habitat):\n")
for (i in seq_len(nrow(res))) cat(sprintf("%-22s base: %s\n%-22s rep0: %s\n", res$species[i], res$coefBase[i], "", res$coefRep0[i]))
cat("\nReading: maxDCoef = largest weight difference; lambda = ridge penalty each chose; dClim/dLand/dHab = largest difference of the out-of-fold input of that scale\n",
    "(NA = different numbers of rows). Species that pass the parity check should show ~0 everywhere.\n")
