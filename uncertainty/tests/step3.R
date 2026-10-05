# Local test, step 3: assembly (area means, index uncertainty, community, combined indices) and the command-line entry point.
# Needs step 2 first. (The assembly's area-mean part of the parity check is NOT meaningful here: the stats of one band are copied
# to all 40 bands. The full-country parity is checked by e2e_local.sh.) Only band 13 holds real results; its stats files are copied to the other bands to exercise the sums.
Sys.setenv(BIRDMONITOR_RUNNAME = "utest", BIRDMONITOR_SPECIES = "Alauda arvensis", BIRDMONITOR_UNC_REPS = "0:3",
           BIRDMONITOR_UNC_YEARS = "2020:2025", BIRDMONITOR_UNC_BANDS = "40", BIRDMONITOR_UNC_TAG = "")
suppressMessages({library(terra); library(gbm); library(glmnet)})
for (f in list.files("uncertainty/R", full.names = TRUE)) source(f)
cfg <- uncCfg(getwd()); sp <- cfg$species; spClean <- gsub(" ", "_", sp)
cfg$baselineYear <- 2020L                      # the real baseline year (2005) is not mapped in this test
predDir <- file.path(uncSpDir(cfg, sp), "pred", cfg$repLabel)
for (yr in cfg$outYears) for (k in setdiff(1:40, 13)) file.copy(file.path(predDir, sprintf("stats_%d_band13.rds", yr)), file.path(predDir, sprintf("stats_%d_band%02d.rds", yr, k)), overwrite = TRUE)

band <- uncBands(cfg, sp)$bands[[13]]
uncSummarizeSpeciesBand(cfg, sp, band)        # second call: nothing to redo
uncCommunityBand(cfg, band)
uncAssembleSpecies(cfg, sp)
uncAssembleAll(cfg)
cat("
--- parity check (band 13 holds the real results)
"); uncParityCheck(cfg, sp, kMid = 13); cat(readLines(file.path(uncSpDir(cfg, sp), "parity_check.txt")), sep = "
")

root <- uncRoot(cfg)
cat("\n--- species_index_uncertainty.csv\n"); print(utils::read.csv(file.path(uncSpDir(cfg, sp), "species_index_uncertainty.csv")))
cat("\n--- combined_index_uncertainty.csv\n"); print(utils::read.csv(file.path(root, "combined_index_uncertainty.csv")))
cat("\n--- layer names of the stitched maps\n")
print(names(rast(file.path(uncSpDir(cfg, sp, "maps"), sprintf("%s_unc_2025.tif", spClean)))))
print(names(rast(file.path(uncSpDir(cfg, sp, "maps"), sprintf("%s_unc_change_vs5YearsAgo.tif", spClean)))))
print(list.files(file.path(root, "community")))

# the command-line entry point, exactly as the cluster scripts call it
rs <- file.path(R.home("bin"), "Rscript")
for (a in list(c("--step", "preflight"), c("--step", "assemble", "--index", "1"), c("--step", "summarize", "--index", "13"))) {
  cat("\n=== CLI:", paste(a, collapse = " "), "\n")
  out <- suppressWarnings(system2(rs, c("tools/runUncertaintyTask.R", a), stdout = TRUE, stderr = TRUE))
  cat(tail(out[!grepl("built under|libPaths|setupOff", out)], 6), sep = "\n")
}
cat("\nDONE step 3\n")
