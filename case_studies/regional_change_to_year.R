# CASE STUDIES (not part of the workflow). On EVE, READ-ONLY: the regional index change "end year vs 2005" with its 90% interval, for an end year the pipeline did not use (default 2023,
# the last year before the new crop map). It calls the pipeline's own function (runIndex_Monitor/R/computeRegionalIndexUncertainty.R) on the stored replicates, so the maps are made
# exactly like the 2025 ones and can be compared with them; only the end year differs. Writes ONLY to outputs/<run>/case_studies/change_<year>_<group>/ (nothing of the run is touched).
#   BIRDMONITOR_RUNNAME=v3 sbatch --export=ALL case_studies/eve_regional_change_to_year.sbatch          (or: Rscript case_studies/regional_change_to_year.R --run v3 --year 2023)
# Result per group: regional_index_10km_unc_change_vsBaseline.tif (layers deltaMean, deltaSd, deltaLwr, deltaUpr, deltaWidth, shareDecrease, shareIncrease; end year minus 2005, index points).
suppressMessages(library(terra))
args <- commandArgs(trailingOnly = TRUE)
getArg <- function(flag, default = NULL) { i <- which(args == flag); if (length(i)) args[i + 1] else default }
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*")); if (length(libs)) .libPaths(c(libs, .libPaths()))
run <- getArg("--run", Sys.getenv("BIRDMONITOR_RUNNAME", "v3")); tag <- getArg("--tag", "ens_brt-glm-gam-rf-nn"); endYear <- as.integer(getArg("--year", 2023)); baseYear <- as.integer(getArg("--base-year", 2005))
for (f in sort(list.files("modules/models_Monitor/R", pattern = "[.]R$", full.names = TRUE))) source(f)
source("modules/runIndex_Monitor/R/computeRegionalIndexUncertainty.R"); source("tools/sharedSpeciesCanonical.R"); source("tools/sharedSpeciesGroups.R")
roster <- canonicalIncludedSpecies(loadSpeciesCanonical("data/speciesCanonical.csv")); groups <- loadSpeciesGroups("data/speciesGroups.csv", roster)
uncDir <- file.path("outputs", run, paste0("uncertainty_", tag))
for (g in c("farmland", "all")) {
  out <- file.path("outputs", run, "case_studies", sprintf("change_%d_%s", endYear, g)); message("=== ", g, ": ", length(groups$members[[g]]), " species, ", endYear, " vs ", baseYear, " -> ", out)
  computeRegionalIndexUncertainty(species = groups$members[[g]], uncertaintyDir = uncDir, outputDir = out, baselineYear = baseYear, currentYear = endYear, cellSizesM = 10000,
                                  probs = c(0.05, 0.95), minBaseline = 1e-6, baselineRegionalDir = NULL)
}
message("=== done")
marker <- Sys.getenv("UNC_DONE_MARKER", ""); if (nzchar(marker)) writeLines("ok", marker)
