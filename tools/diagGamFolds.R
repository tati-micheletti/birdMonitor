# DIAGNOSTIC ONLY (2026-11-22). Why are some landscape-scale GAM fold refits of the out-of-fold step so slow?
# Refits the GAM exactly as uncOof.R does (algoRefit(): main fit's settings first, then the robust ladder of algoFitGAM()), for the chosen replicates and ALL folds,
# and records for every fit and every ladder attempt: time, converged, error. Writes ONLY to outputs/<run>/_diag_gam_folds_<date>/ ; reads the training table, the
# replicate draws and the main GAM; touches nothing else (no model, oof or checkpoint file of the real run).
#   Rscript tools/diagGamFolds.R --step diag --index 1 --diagreps 4,5,1 [--diagspecies "Vanellus vanellus"] [--diagscale landscape]
# Needs the environment of the chain (BIRDMONITOR_RUNNAME, INPUT_ROOT, years, UNC_MEMBERS, UNC_REPS ...): see cluster/eve_diag_gam_folds.sbatch.
# The set-up (configuration, makeCfg()) is the PREAMBLE of tools/runUncertaintyTask.R, evaluated up to its step dispatch, so nothing is re-implemented here.
pre <- parse("tools/runUncertaintyTask.R")
stopAt <- which(vapply(pre, function(e) grepl('^if \\(step == "preflight"\\)', paste(deparse(e), collapse = " ")), logical(1)))[1]
for (e in pre[seq_len(stopAt - 1L)]) eval(e, globalenv())

diagSp <- getArg("--diagspecies", "Vanellus vanellus"); diagScale <- getArg("--diagscale", "landscape")
diagReps <- as.integer(strsplit(getArg("--diagreps", "4,5,1"), ",")[[1]])
cfg <- makeCfg()
outDir <- file.path(outputRoot, paste0("_diag_gam_folds_", format(Sys.Date(), "%Y-%m-%d"))); dir.create(outDir, showWarnings = FALSE)
message("diag: ", diagSp, " | scale ", diagScale, " | replicates ", paste(diagReps, collapse = ","), " | out ", outDir)

tbl <- uncTrainingTable(cfg, diagSp, diagScale)
mod <- readRDS(file.path(uncSpDir(cfg, diagSp, "models"), paste0(diagScale, "_", cfg$repLabel, ".rds")))
mainFit <- readRDS(ensFile(cfg, diagSp, diagScale, "gam", "model"))
folds <- sort(unique(tbl$foldID))
message("training rows ", nrow(tbl), " | folds ", paste(folds, collapse = ","), " | main GAM predictors ", length(mainFit$predSel), " | main gamArgs: ", length(mainFit$gamArgs))

tstamp <- function() format(Sys.time(), "%H:%M:%S")
attemptRow <- function(b, k, step, elapsed, m, err) data.frame(rep = b, fold = k, step = step, minutes = round(elapsed, 2),
  converged = !is.null(m) && isTRUE(m$converged), error = if (is.null(err)) "" else substr(conditionMessage(err), 1, 80),
  outerIter = if (!is.null(m) && !is.null(m$outer.info$iter)) m$outer.info$iter else NA, pirls = if (!is.null(m)) m$iter else NA, stringsAsFactors = FALSE)
timedGam <- function(formula, args, dat) {
  t0 <- Sys.time(); err <- NULL
  m <- tryCatch(suppressWarnings(do.call(mgcv::gam, c(list(formula, family = "binomial", data = dat), args))), error = function(e) { err <<- e; NULL })
  list(m = m, err = err, mins = as.numeric(difftime(Sys.time(), t0, units = "mins")))
}
runOne <- function(b, k) {
  j <- which(mod$ids == b); tr <- mod$draws[[j]]; tr <- tr[tbl$foldID[tr] != k]
  dat <- tbl[tr, , drop = FALSE]; rows <- list()
  message(tstamp(), " start rep ", b, " fold ", k, " (", nrow(dat), " rows)")
  a0 <- timedGam(mainFit$formula, mainFit$gamArgs, dat)                       # what algoRefit() tries first
  rows[[1]] <- attemptRow(b, k, "main settings", a0$mins, a0$m, a0$err)
  message(tstamp(), " rep ", b, " fold ", k, " main settings: ", round(a0$mins, 1), " min, converged = ", rows[[1]]$converged)
  if (!rows[[1]]$converged) {                                                  # then the ladder of algoFitGAM(), same order, timed per attempt
    used <- mainFit$predSel; response <- mainFit$response; spent <- a0$mins
    attempts <- list(list(label = "default", args = list()),
                     list(label = "REML 500 it", args = list(method = "REML", control = mgcv::gam.control(maxit = 500))),
                     list(label = "REML efs", args = list(method = "REML", optimizer = "efs", control = mgcv::gam.control(maxit = 500))))
    done <- FALSE
    repeat {
      for (kk in c(4, 3)) for (at in attempts) {
        if (spent > 180) { rows[[length(rows) + 1L]] <- data.frame(rep = b, fold = k, step = "BUDGET 180 min exceeded", minutes = round(spent, 2), converged = NA, error = "", outerIter = NA, pirls = NA); done <- TRUE; break }
        f <- stats::as.formula(paste(response, "~", paste0("s(", used, ", k = ", kk, ")", collapse = " + ")))
        a <- timedGam(f, at$args, dat); spent <- spent + a$mins
        lab <- paste0("ladder: ", at$label, ", k=", kk, ", ", length(used), " predictors")
        rows[[length(rows) + 1L]] <- attemptRow(b, k, lab, a$mins, a$m, a$err)
        message(tstamp(), " rep ", b, " fold ", k, " ", lab, ": ", round(a$mins, 1), " min, converged = ", rows[[length(rows)]]$converged)
        if (rows[[length(rows)]]$converged) { done <- TRUE; break }
      }
      if (done) break
      nz <- vapply(used, function(x) sum(dat[[x]] != 0, na.rm = TRUE), numeric(1)); used <- setdiff(used, used[which.min(nz)])
      if (length(used) <= 1L) break
    }
  }
  res <- do.call(rbind, rows)
  write.csv(res, file.path(outDir, sprintf("rep%02d_fold%d.csv", b, k)), row.names = FALSE)       # one file per (replicate, fold), written as soon as it is done
  res
}
grid <- expand.grid(k = folds, b = diagReps)
out <- parallel::mclapply(seq_len(nrow(grid)), function(i) runOne(grid$b[i], grid$k[i]), mc.cores = max(1L, cores), mc.preschedule = FALSE)
ok <- vapply(out, is.data.frame, logical(1)); if (any(!ok)) message("tasks that failed: ", sum(!ok))
all <- do.call(rbind, out[ok]); write.csv(all, file.path(outDir, "all_attempts.csv"), row.names = FALSE)
message("=== diag done ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " ===")
print(aggregate(minutes ~ rep + fold, all, sum))
