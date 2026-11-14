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
#'   BIRDMONITOR_NATIONAL_LAST_YEAR  last year of the published national indicator (default sharedNationalIndicatorLastYear in tools/sharedConfig.R); later years of the national trend are marked preliminary
#'   BIRDMONITOR_VIZ_DRY    1 = only report what would be written
#'   BIRDMONITOR_VIZ_FAIL   1 = error if a result the Monitor needs is missing (default: warning and <viz>/_missing.csv)
#'   BIRDMONITOR_SPECIES is NOT used here: the viz folder always needs the FULL roster.
#'   BIRDMONITOR_VIZ_GROUPS 1 = the "viz2" LAYOUT (2026-11-14; use with BIRDMONITOR_VIZ_PATH=/data/birds/viz2): every group of data/speciesGroups.csv gets its own, group-named group products, next to the
#'     per-species folders (identical to viz): richness_year_<group>/, msi_regional_<group>/, msi_regional_unc_<group>/, msi_regional_clear_<group>/, msi_national/msi_national_<group>.csv, a
#'     _missing_<group>.csv per group and _groups.csv (group, label, species). Unset (default) = the group "all" only, with the folder names viz always had. BIRDMONITOR_GROUP is NOT used here either.
Sys.setenv(OMP_NUM_THREADS = "1", GDAL_NUM_THREADS = "1")
suppressMessages(library(SpaDES.core))
terra::terraOptions(memmax = 4)                           # 2026-11-11: under SLURM terra sizes its memory from the whole node, not from the job (as in the completeness check of 29 Oct); the job has 16 GB, terra may use 4 (connector job 66162461 was OOM-killed at 8 GB)
args <- commandArgs(trailingOnly = TRUE)
getArg <- function(flag, default = NULL) { i <- which(args == flag); if (length(i) == 0) default else args[i + 1] }
repoRoot <- normalizePath(getArg("--repo-root", getwd()), winslash = "/")
setwd(repoRoot)
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
env <- function(name, default = "") { v <- Sys.getenv(name, ""); if (nzchar(v)) v else default }

Sys.unsetenv(c("BIRDMONITOR_SPECIES", "BIRDMONITOR_GROUP"))   # the full roster, always (see above); the groups are looped over below, never taken from the environment
source("tools/sharedConfig.R")                            # sharedSpecies, predictionYears
vizPath <- env("BIRDMONITOR_VIZ_PATH", "/data/birds/viz")
runsRoot <- env("BIRDMONITOR_RUNS_ROOT", "/data/birds/birdMonitor/outputs")
runs <- if (nzchar(env("BIRDMONITOR_VIZ_RUNS"))) trimws(strsplit(env("BIRDMONITOR_VIZ_RUNS"), ",", fixed = TRUE)[[1]]) else NULL
message("=== connector: viz folder ", vizPath, " | runs in ", runsRoot, " | ", length(sharedSpecies), " species | ", format(Sys.time(), "%Y-%m-%d %H:%M:%S"), " ===")
params <- list(vizPath = vizPath, runsRoot = runsRoot, tag = env("BIRDMONITOR_VIZ_TAG", "ens_brt-glm-gam-rf-nn"), species = sharedSpecies, years = predictionYears,
               nationalLastPublishedYear = as.integer(env("BIRDMONITOR_NATIONAL_LAST_YEAR", as.character(sharedNationalIndicatorLastYear))),
               dryRun = env("BIRDMONITOR_VIZ_DRY") == "1", failIfIncomplete = env("BIRDMONITOR_VIZ_FAIL") == "1")
if (!is.null(runs)) params$runFolders <- runs
# water mask (2026-11-05): ON by default for the Monitor (no probability of occurrence over lakes and big rivers). The file is sharedWaterMaskFile (tools/sharedConfig.R) or BIRDMONITOR_WATER_FILE;
# the value "none" switches it off ON PURPOSE (a missing file stops the job, so the mask is never dropped by accident). BIRDMONITOR_WATER_MIN_SHARE overrides sharedWaterMaskMinShare.
waterFile <- env("BIRDMONITOR_WATER_FILE", sharedWaterMaskFile)
if (tolower(waterFile) == "none") { message("=== water mask: OFF on purpose ==="); waterFile <- NA_character_ }
params$waterFile <- waterFile; params$waterMinShare <- as.numeric(env("BIRDMONITOR_WATER_MIN_SHARE", as.character(sharedWaterMaskMinShare)))
runOnce <- function(p) SpaDES.core::simInitAndSpades(times = list(start = 2005, end = 2005), modules = "connector_Monitor",
                                     paths = list(modulePath = file.path(repoRoot, "modules"), inputPath = file.path(repoRoot, "inputs"), outputPath = file.path(repoRoot, "outputs", "connector")),
                                     params = list(connector_Monitor = p))
if (env("BIRDMONITOR_VIZ_GROUPS") != "1") {
  sim <- runOnce(params)                                  # as always: the group "all", the folder names the viz folder always had
} else {
  # viz2 layout (2026-11-14): the per-species products are the same for every group and are brought in ONCE (with the first group); the group products get the group in their folder / file name
  message("=== viz2 layout: groups ", paste(sharedGroups, collapse = ", "), " ===")
  gtab <- list()
  for (g in sharedGroups) {
    pg <- params
    pg$groupSuffix <- groupSuffix(g)
    pg$folders <- list(meta_prob_year = "meta_prob_year", meta_unc_year = "meta_unc_year", richness_year = paste0("richness_year_", g),
                       msi_regional = paste0("msi_regional_", g), msi_regional_unc = paste0("msi_regional_unc_", g), msi_national = "msi_national",
                       msi_regional_clear = paste0("msi_regional_clear_", g))
    pg$nationalFile <- paste0("msi_national_", g, ".csv")
    pg$missingFile <- if (identical(g, sharedGroups[1])) "_missing.csv" else paste0("_missing_", g, ".csv")
    if (!identical(g, sharedGroups[1])) pg$species <- character(0)                     # species products already handled by the first group
    message("=== viz2: group '", g, "' (", speciesGroups$labels[[g]], ", ", length(speciesGroups$members[[g]]), " species) ===")
    sim <- runOnce(pg)
    gtab[[g]] <- data.frame(group = g, label = speciesGroups$labels[[g]], nSpecies = length(speciesGroups$members[[g]]), species = paste(speciesGroups$members[[g]], collapse = "; "),
                            richness = pg$folders$richness_year, regional = pg$folders$msi_regional, regionalUncertainty = pg$folders$msi_regional_unc,
                            regionalClear = pg$folders$msi_regional_clear, national = file.path(pg$folders$msi_national, pg$nationalFile), missing = pg$missingFile, stringsAsFactors = FALSE)
  }
  if (!isTRUE(params$dryRun)) { dir.create(vizPath, recursive = TRUE, showWarnings = FALSE); utils::write.csv(do.call(rbind, gtab), file.path(vizPath, "_groups.csv"), row.names = FALSE) }
}
marker <- Sys.getenv("UNC_DONE_MARKER", ""); if (nzchar(marker)) writeLines("ok", marker)
