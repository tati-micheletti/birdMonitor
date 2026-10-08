# Germany-only COPIES of the meta-model maps (the baseline stays untouched): mask every <species>_meta_suitability_<year>.tif of the meta-model folder
# with the German outline and write it to <folder>_germany/ (same names). The index run on those copies (BIRDMONITOR_INDEX_TAG=germany ->
# annual_report_germany/, regional_index_germany/) then averages German pixels only, for every index, map and change layer.
#
# Why: the prediction window is the bounding box of Germany; seven of the eleven species are predicted across all of it (about 35% of the pixels lie
# outside Germany), four only inside (their models use German-only layers). See DECISIONS.md 2026-10-08. TEMPORARY: the proper fix is to cut every
# input to the study-area outline at the source, so nothing is computed outside Germany (planned after the Steering Consortium meeting).
#
#   Rscript tools/maskMetaModels.R --index <species number 1..11>        (cluster: cluster/eve_mask_meta.sbatch, an array over the species)
#   [BIRDMONITOR_RUNNAME=test4]  [--species "Genus species"] instead of --index for a local test
# The outline comes from a closed-form transformation (no GDAL/PROJ axis problem on EVE, see uncOutlineLAEA()); touches = TRUE like the baseline mask.
Sys.setenv(OMP_NUM_THREADS = "1")
args <- commandArgs(trailingOnly = TRUE)
getArg <- function(flag, default = NULL) { i <- which(args == flag); if (length(i) == 0) default else args[i + 1] }
repoRoot <- normalizePath(getArg("--repo-root", getwd()), winslash = "/"); setwd(repoRoot)
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
suppressMessages(library(terra))
source("modules/models_Monitor/R/uncRegional.R")
source("tools/sharedConfig.R"); source("tools/sharedSpeciesConfig.R")
runName <- Sys.getenv("BIRDMONITOR_RUNNAME", "test4")
sp <- getArg("--species")
if (is.null(sp)) { i <- as.integer(getArg("--index", Sys.getenv("SLURM_ARRAY_TASK_ID", NA))); if (is.na(i) || i < 1 || i > length(sharedSpecies)) stop("--index must be 1..", length(sharedSpecies)); sp <- sharedSpecies[i] }
spClean <- gsub(" ", "_", sp)
dirs <- list.dirs(file.path("outputs", runName), recursive = FALSE, full.names = TRUE)
metaDir <- dirs[grepl("^metamodel_[0-9_]+$", basename(dirs))]
if (length(metaDir) != 1) stop("Expected exactly one metamodel_<resolutions> folder under outputs/", runName, ", found: ", paste(basename(metaDir), collapse = ", "))
outDir <- paste0(metaDir, "_germany"); dir.create(outDir, showWarnings = FALSE)
fs <- sort(list.files(metaDir, pattern = paste0("^", spClean, "_meta_suitability_[0-9]{4}[.]tif$"), full.names = TRUE))
if (!length(fs)) stop("No meta_suitability files for ", sp, " in ", metaDir)
message("=== mask to Germany: ", sp, " | ", length(fs), " maps | ", metaDir, " -> ", outDir, " | ", format(Sys.time(), "%H:%M:%S"), " ===")

r1 <- terra::rast(fs[1])
outline <- uncOutlineLAEA(file.path("inputs", "predictors", "raw", "gadm"), terra::crs(r1))
mk <- terra::rasterize(outline, r1[[1]], field = 1, touches = TRUE)
message("German pixels in the window: ", format(sum(!is.na(terra::values(mk)[, 1])), big.mark = ","), " of ", format(terra::ncell(mk), big.mark = ","))
for (f in fs) {
  out <- file.path(outDir, basename(f))
  if (file.exists(out)) { message("  exists: ", basename(out)); next }
  r <- terra::rast(f)
  m <- if (isTRUE(terra::compareGeom(r, mk, stopOnError = FALSE))) mk else terra::rasterize(outline, r[[1]], field = 1, touches = TRUE)
  part <- sub("[.]tif$", ".part.tif", out)
  terra::writeRaster(terra::mask(r, m), part, overwrite = TRUE, datatype = terra::datatype(r)[1], gdal = c("COMPRESS=DEFLATE"))
  file.rename(part, out)
  message("  ", basename(out), " | ", format(Sys.time(), "%H:%M:%S"))
}
message("=== done: ", sp, " ===")
marker <- Sys.getenv("UNC_DONE_MARKER", ""); if (nzchar(marker)) writeLines("ok", marker)
