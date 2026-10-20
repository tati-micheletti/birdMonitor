#' Entry point of connector_Monitor: bring the newest results of every species into the viz folder the Bird Monitor reads
#'
#' Runs a small simInitAndSpades() with the connector_Monitor module (modules/connector_Monitor/README.md). Nothing is fitted or predicted; the run
#' folders are only read, the viz folder is only added to (nothing is deleted).
#'
#' Usage (from the repo root; on EVE through cluster/eve_connector.sbatch):
#'   Rscript tools/runConnector.R
#'
#' Settings come from environment variables:
#'   BIRDMONITOR_VIZ_PATH   the viz folder the Monitor reads (default /data/birds/viz)
#'   BIRDMONITOR_RUNS_ROOT  folder with the run folders to take results from (default /data/birds/birdMonitor/outputs, the permanent copy; NOT /work)
#'   BIRDMONITOR_VIZ_RUNS   comma-separated run folders to use (default: all except old test folders)
#'   BIRDMONITOR_VIZ_TAG    ensemble tag of the result folders (default ens_brt-glm-gam-rf-nn)
#'   BIRDMONITOR_VIZ_DRY    1 = only report what would be written
#'   BIRDMONITOR_VIZ_FAIL   1 = error if a result the Monitor needs is missing (default: warning and <viz>/_missing.csv)
#'   BIRDMONITOR_SPECIES is NOT used here: the viz folder always needs the FULL roster.
Sys.setenv(OMP_NUM_THREADS = "1", GDAL_NUM_THREADS = "1")
suppressMessages(library(SpaDES.core))
args <- commandArgs(trailingOnly = TRUE)
getArg <- function(flag, default = NULL) { i <- which(args == flag); if (length(i) == 0) default else args[i + 1] }
repoRoot <- normalizePath(getArg("--repo-root", getwd()), winslash = "/")
setwd(repoRoot)
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
env <- function(name, default = "") { v <- Sys.getenv(name, ""); if (nzchar(v)) v else default }

Sys.unsetenv("BIRDMONITOR_SPECIES")                       # the full roster, always (see above)
source("tools/sharedConfig.R")                            # sharedSpecies, predictionYears
vizPath <- env("BIRDMONITOR_VIZ_PATH", "/data/birds/viz")
runsRoot <- env("BIRDMONITOR_RUNS_ROOT", "/data/birds/birdMonitor/outputs")
runs <- if (nzchar(env("BIRDMONITOR_VIZ_RUNS"))) trimws(strsplit(env("BIRDMONITOR_VIZ_RUNS"), ",", fixed = TRUE)[[1]]) else NULL
message("=== connector: viz folder ", vizPath, " | runs in ", runsRoot, " | ", length(sharedSpecies), " species | ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " ===")
params <- list(vizPath = vizPath, runsRoot = runsRoot, tag = env("BIRDMONITOR_VIZ_TAG", "ens_brt-glm-gam-rf-nn"), species = sharedSpecies, years = predictionYears,
               dryRun = env("BIRDMONITOR_VIZ_DRY") == "1", failIfIncomplete = env("BIRDMONITOR_VIZ_FAIL") == "1")
if (!is.null(runs)) params$runFolders <- runs
sim <- SpaDES.core::simInitAndSpades(times = list(start = 2005, end = 2005), modules = "connector_Monitor",
                                     paths = list(modulePath = file.path(repoRoot, "modules"), inputPath = file.path(repoRoot, "inputs"), outputPath = file.path(repoRoot, "outputs", "connector")),
                                     params = list(connector_Monitor = params))
marker <- Sys.getenv("UNC_DONE_MARKER", ""); if (nzchar(marker)) writeLines("ok", marker)
