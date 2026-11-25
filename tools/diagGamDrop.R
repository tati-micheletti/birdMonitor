# DIAGNOSTIC ONLY (2026-11-22), third step: sparsest predictors dropped (the last rung of the ladder), plus a separation check (counts of non-zero values per predictor and presence rate among them). tools/diagGamFolds.R showed that most landscape GAM fold refits of the Lapwing converge with the main settings in 0.3-0.5 min, but a few
# (replicate 4 fold 2, replicate 5 fold 1) run for many minutes with the main settings. Here the SAME training rows of those folds are fitted with the alternative settings of the
# robust ladder (algoFitGAM), each with a time cap, to see which one is fast. Writes only to outputs/<run>/_diag_gam_folds_<date>/alt_*.csv.
#   Rscript tools/diagGamDrop.R --step diag --index 1 --diagpairs 4:2,5:1 [--diagcap 25]
pre <- parse("tools/runUncertaintyTask.R")
stopAt <- which(vapply(pre, function(e) grepl('^if \\(step == "preflight"\\)', paste(deparse(e), collapse = " ")), logical(1)))[1]
for (e in pre[seq_len(stopAt - 1L)]) eval(e, globalenv())
diagSp <- getArg("--diagspecies", "Vanellus vanellus"); diagScale <- getArg("--diagscale", "landscape")
pairs <- lapply(strsplit(strsplit(getArg("--diagpairs", "4:2,5:1"), ",")[[1]], ":"), as.integer)
capMin <- as.numeric(getArg("--diagcap", "25"))
cfg <- makeCfg()
outDir <- file.path(outputRoot, paste0("_diag_gam_folds_", format(Sys.Date(), "%Y-%m-%d"))); dir.create(outDir, showWarnings = FALSE)
tbl <- uncTrainingTable(cfg, diagSp, diagScale)
mod <- readRDS(file.path(uncSpDir(cfg, diagSp, "models"), paste0(diagScale, "_", cfg$repLabel, ".rds")))
mainFit <- readRDS(ensFile(cfg, diagSp, diagScale, "gam", "model"))
used <- mainFit$predSel; response <- mainFit$response
f4 <- mainFit$formula
f3 <- stats::as.formula(paste(response, "~", paste0("s(", used, ", k = 3)", collapse = " + ")))
alts <- list(list(label = "drop 1 sparsest", nDrop = 1L, args = list()),
             list(label = "drop 2 sparsest", nDrop = 2L, args = list()),
             list(label = "drop 3 sparsest", nDrop = 3L, args = list()))
tstamp <- function() format(Sys.time(), "%H:%M:%S")
runOne <- function(b, k, al) {
  j <- which(mod$ids == b); tr <- mod$draws[[j]]; tr <- tr[tbl$foldID[tr] != k]; dat <- tbl[tr, , drop = FALSE]
  nz <- vapply(used, function(x) sum(dat[[x]] != 0, na.rm = TRUE), numeric(1))
  pres <- vapply(used, function(x) { i <- dat[[x]] != 0 & !is.na(dat[[x]]); if (any(i)) mean(dat[[response]][i]) else NA_real_ }, numeric(1))
  o <- order(nz)[1:6]
  message(tstamp(), " rep ", b, " fold ", k, " ", al$label, " | sparsest predictors (non-zero rows; presence rate among them): ",
          paste0(used[o], "=", nz[o], " (", round(pres[o], 2), ")", collapse = ", "), " | rows ", nrow(dat), ", presences ", sum(dat[[response]]))
  keep <- setdiff(used, used[order(nz)[seq_len(al$nDrop)]])
  fml <- stats::as.formula(paste(response, "~", paste0("s(", keep, ", k = 4)", collapse = " + ")))
  t0 <- Sys.time(); err <- ""
  m <- tryCatch({ setTimeLimit(elapsed = capMin * 60, transient = TRUE)
                  suppressWarnings(do.call(mgcv::gam, c(list(fml, family = "binomial", data = dat), al$args))) },
                error = function(e) { err <<- substr(conditionMessage(e), 1, 90); NULL })
  setTimeLimit(elapsed = Inf)
  mins <- as.numeric(difftime(Sys.time(), t0, units = "mins"))
  res <- data.frame(rep = b, fold = k, setting = al$label, minutes = round(mins, 2), converged = !is.null(m) && isTRUE(m$converged), capped = nzchar(err) && grepl("time limit", err),
                    error = err, outerIter = if (!is.null(m) && !is.null(m$outer.info$iter)) m$outer.info$iter else NA, stringsAsFactors = FALSE)
  message(tstamp(), " rep ", b, " fold ", k, " ", al$label, ": ", round(mins, 1), " min, converged = ", res$converged, if (nzchar(err)) paste0(" (", err, ")") else "")
  write.csv(res, file.path(outDir, sprintf("alt_rep%02d_fold%d_%s.csv", b, k, gsub("[^A-Za-z0-9]+", "_", al$label))), row.names = FALSE)
  res
}
grid <- do.call(rbind, lapply(pairs, function(p) data.frame(b = p[1], k = p[2], a = seq_along(alts))))
out <- parallel::mclapply(seq_len(nrow(grid)), function(i) runOne(grid$b[i], grid$k[i], alts[[grid$a[i]]]), mc.cores = min(nrow(grid), max(1L, cores)), mc.preschedule = FALSE)
ok <- vapply(out, is.data.frame, logical(1)); message("tasks that failed: ", sum(!ok))
print(do.call(rbind, out[ok]))
message("=== alt diag done ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " ===")
