# Honest accuracy of the combined map for ONE species (see metaOutOfFoldCheck()).
#   Rscript tools/runMetaCheck.R --index 4            (index = species number in the roster; also $SLURM_ARRAY_TASK_ID)
#   Rscript tools/runMetaCheck.R --collect            (after all species: one table, outputs/<run>/meta_check/meta_check_all.csv)
# Run name: BIRDMONITOR_RUNNAME (default test4).
args <- commandArgs(trailingOnly = TRUE)
getArg <- function(flag, default = NULL) { i <- which(args == flag); if (length(i) == 0) default else args[i + 1] }
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
suppressMessages({ library(terra); library(gbm); library(glmnet) })
runName <- if (nzchar(Sys.getenv("BIRDMONITOR_RUNNAME"))) Sys.getenv("BIRDMONITOR_RUNNAME") else "test4"
repoRoot <- normalizePath(getArg("--repo-root", getwd()), winslash = "/"); setwd(repoRoot)
outDir <- file.path("outputs", runName, "meta_check"); dir.create(outDir, recursive = TRUE, showWarnings = FALSE)

if ("--collect" %in% args) {
  fs <- list.files(outDir, pattern = "_meta_check[.]csv$", full.names = TRUE)
  if (!length(fs)) stop("No per-species results in ", outDir)
  tab <- do.call(rbind, lapply(fs, utils::read.csv)); num <- vapply(tab, is.numeric, logical(1)); tab[num] <- lapply(tab[num], round, 3)
  utils::write.csv(tab, file.path(outDir, "meta_check_all.csv"), row.names = FALSE); print(tab, row.names = FALSE)
  cat("\n->", file.path(outDir, "meta_check_all.csv"), "\n"); quit(save = "no")
}

for (f in sort(list.files("modules/models_Monitor/R", pattern = "[.]R$", full.names = TRUE))) source(f)
source("tools/sharedConfig.R"); source("tools/sharedSpeciesConfig.R")
gen <- if (file.exists("data/speciesConfig_general.csv")) loadSpeciesGeneralConfig("data/speciesConfig_general.csv") else NULL
cfg <- uncCfgFromParams(inputRoot = file.path(repoRoot, "inputs"), outputRoot = file.path(repoRoot, "outputs", runName), species = sharedSpecies,
                        predictionYears = predictionYears,
                        habitatYears = resolveYearsPerSpecies(sharedSpecies, "habitat", extractYearsConfig(gen), sharedHabitatYears),
                        resolutionConfig = extractResolutionConfig(gen), climateResolutionM = sharedClimateResolutionM,
                        habitatResolutionM = sharedHabitatResolutionM, landscapeResolutionM = sharedLandscapeResolutionM,
                        climateWindowLength = sharedClimateWindowLength, reps = 1, codeRoot = repoRoot)
index <- as.integer(getArg("--index", Sys.getenv("SLURM_ARRAY_TASK_ID", NA)))
if (is.na(index) || index < 1 || index > length(sharedSpecies)) stop("--index must be 1..", length(sharedSpecies))
sp <- sharedSpecies[index]; message("=== meta-model out-of-fold check: ", sp, " (run ", runName, ") ===")
t0 <- Sys.time()
res <- metaOutOfFoldCheck(cfg, sp)
saveRDS(res, file.path(outDir, paste0(gsub(" ", "_", sp), "_meta_check.rds")))
utils::write.csv(res$performance, file.path(outDir, paste0(gsub(" ", "_", sp), "_meta_check.csv")), row.names = FALSE)
print(res$performance[, c("variant", "AUC", "TSS", "D2")], row.names = FALSE, digits = 3)
cat("\nRidge coefficients (intercept, climate, landscape, habitat):\n"); print(round(res$coefficients, 3))
cat("\nrecords used:", res$n, "| minutes:", round(as.numeric(difftime(Sys.time(), t0, units = "mins")), 1), "\n")
