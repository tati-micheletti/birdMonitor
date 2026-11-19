# SERIES 2 helper (2026-11-19): ONE (year, scale) of the land-use preparation, so that the years of the CTM v302 series can be computed IN PARALLEL instead of one class after the other in the single preparation job.
# It calls the module's own computeLanduse() with exactly the arguments the preparation uses (rule: CTM first, no recode; target CRS from tools/sharedConfig.R) for ONE scale only; the preparation, when it reaches that
# year, finds the file valid ("cache hit -- skipping") and does not recompute it. Nothing else is touched: derived layers (heterogeneity, unmapped share, hedges fixing, study-area crop) stay the preparation's job.
#   BIRDMONITOR_INPUT_ROOT=$PWD/inputs_s2 Rscript cluster/s2_landuse_task.R <year> <habitat|landscape> <resolution m> [--main-log logs/prep_<id>.err] [--scratch <dir> --compare <existing tif>]
#   --main-log   the log of the running preparation: the task STOPS if that preparation has already reached this year (never two writers on one file)
#   --scratch    validation run: compute into <dir>/ (a scratch processed root) instead of inputs_s2, then compare the result cell by cell with --compare <the file the preparation made>
args <- commandArgs(trailingOnly = TRUE)
getArg <- function(f, d = NULL) { i <- which(args == f); if (length(i)) args[i + 1] else d }
year <- as.integer(args[1]); scaleName <- args[2]; res <- as.numeric(args[3])
stopifnot(!is.na(year), scaleName %in% c("habitat", "landscape"), !is.na(res))
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*")); if (length(libs)) .libPaths(c(libs, .libPaths()))
suppressMessages(library(terra))
repoRoot <- normalizePath(getwd(), winslash = "/"); inputRoot <- Sys.getenv("BIRDMONITOR_INPUT_ROOT", "")
if (!nzchar(inputRoot) || normalizePath(inputRoot, winslash = "/") == normalizePath(file.path(repoRoot, "inputs"), winslash = "/")) stop("STOP: BIRDMONITOR_INPUT_ROOT must be an own inputs folder (inputs_s2), never inputs/")
scratch <- getArg("--scratch"); mainLog <- getArg("--main-log")
if (is.null(scratch) && !is.null(mainLog)) {
  stopifnot(file.exists(mainLog)); if (any(grepl(sprintf("prepareLanduse Year: %d\\s*$", year), readLines(mainLog, warn = FALSE)))) stop(sprintf("STOP: the preparation (%s) has already reached year %d; this year is left to it", mainLog, year))
}
for (f in sort(list.files("modules/dataPrep_Monitor/R", pattern = "[.]R$", full.names = TRUE))) tryCatch(source(f), error = function(e) message("could not source ", basename(f), ": ", conditionMessage(e)))
sh <- new.env(); sys.source("tools/sharedConfig.R", envir = sh); targetCRS <- get("sharedTargetCRS", envir = sh)
processedRoot <- if (!is.null(scratch)) scratch else file.path(inputRoot, "predictors", "processed")
cat(sprintf("computeLanduse: year %d, %s %g m, processed root %s, CRS %s, rule CTM first (no recode)\n", year, scaleName, res, processedRoot, targetCRS)); t0 <- Sys.time()
computeLanduse(year = year, landuseRawDir = file.path(inputRoot, "predictors", "raw", "landuse"), processedRoot = processedRoot,
               habitatResolutions = if (scaleName == "habitat") res else numeric(0), landscapeResolutions = if (scaleName == "landscape") res else numeric(0),
               targetCRS = targetCRS, force = FALSE, preferHCTM = FALSE, recodeFile = file.path("data", "landuseRecodeCTMtoHCTM.csv"))
cat(sprintf("done in %.1f min\n", as.numeric(difftime(Sys.time(), t0, units = "mins"))))
cmp <- getArg("--compare")
if (!is.null(scratch) && !is.null(cmp)) {
  mine <- list.files(scratch, pattern = sprintf("^landuse_%d_%s_.*[.]tif$", year, scaleName), recursive = TRUE, full.names = TRUE); stopifnot(length(mine) == 1, file.exists(cmp))
  a <- rast(mine); b <- rast(cmp); same <- isTRUE(compareGeom(a, b, stopOnError = FALSE)); cat("same geometry:", same, "| layers:", nlyr(a), nlyr(b), "| names equal:", identical(names(a), names(b)), "\n")
  if (same) { d <- vapply(seq_len(nlyr(a)), function(i) global(abs(a[[i]] - b[[i]]), "max", na.rm = TRUE)[1, 1], numeric(1)); cat("max abs difference over all layers:", max(d, na.rm = TRUE), "\n"); cat(if (max(d, na.rm = TRUE) < 1e-6) "VALIDATION: IDENTICAL\n" else "VALIDATION: DIFFERENT\n") }
  else cat("VALIDATION: DIFFERENT (geometry)\n")
}
