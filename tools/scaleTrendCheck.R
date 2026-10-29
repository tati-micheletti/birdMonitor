#!/usr/bin/env Rscript
# READ-ONLY: where is the temporal change lost? For one species, the mean probability over Germany of the climate, landscape and habitat prediction and of the final (meta-model) map,
# for every year 2005-2025, and each of them as an index (2005 = 100). Compare the four lines with each other and with the observed abundance and occupancy (DDA territory data, section S9
# of tools/makeResultFigures.R): does the landscape model (fitted on the territory data of 2005-2024) follow the observed change? does the habitat model? does the meta-model combination damp it?
#   Rscript tools/scaleTrendCheck.R --index <species number 1..11> [--variants big5,brt] [--run test4]        (cluster: sbatch cluster/eve_scale_trend_check.sbatch, an array over the species)
# Output: outputs/<run>/scale_trend_check/<Species>_<variant>.csv  (species, variant, scale, year, meanProb, index)
Sys.setenv(OMP_NUM_THREADS = "1")
args <- commandArgs(trailingOnly = TRUE)
getArg <- function(flag, default = NULL) { i <- which(args == flag); if (length(i) == 0) default else args[i + 1] }
repoRoot <- normalizePath(getArg("--repo-root", getwd()), winslash = "/"); setwd(repoRoot)
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
suppressMessages(library(terra))
source("modules/models_Monitor/R/uncRegional.R")                         # uncOutlineLAEA()
canon <- read.csv("data/speciesCanonical.csv", stringsAsFactors = FALSE); canon <- canon[nzchar(trimws(canon$include)), ]
sp <- getArg("--species"); if (is.null(sp)) { i <- as.integer(getArg("--index", Sys.getenv("SLURM_ARRAY_TASK_ID", NA))); if (is.na(i) || i < 1 || i > nrow(canon)) stop("--index must be 1..", nrow(canon)); sp <- canon$latin_name[i] }
run <- getArg("--run", Sys.getenv("BIRDMONITOR_RUNNAME", "test4")); ensTag <- getArg("--ens-tag", "ens_brt-glm-gam-rf-nn"); variants <- strsplit(getArg("--variants", "big5"), ",")[[1]]
years <- as.integer(strsplit(getArg("--years", "2005:2025"), ":")[[1]]); years <- if (length(years) == 2) years[1]:years[2] else years
spc <- gsub(" ", "_", sp); root <- file.path("outputs", run)
cfg <- tryCatch(read.csv("data/speciesConfig_general.csv", stringsAsFactors = FALSE), error = function(e) NULL)
scaleLabel <- function(m) paste0("scale_", sub(".", "", as.character(m / 1000), fixed = TRUE))
scaleDir <- function(sc) { r <- if (is.null(cfg)) NA else cfg$resolution_m[cfg$species == sp & cfg$scale == sc]; file.path(root, if (length(r) && !is.na(r[1])) scaleLabel(r[1]) else c(climate = "scale_50", landscape = "scale_1", habitat = "scale_02")[[sc]]) }
firstExisting <- function(...) { p <- c(...); p <- p[file.exists(p)]; if (length(p)) p[1] else NA_character_ }
outline <- NULL
meanIn <- function(f) {                                                    # mean of band 1 over Germany (cells inside the outline)
  if (is.na(f)) return(NA_real_)
  r <- rast(f)[[1]]; if (is.null(outline)) outline <<- uncOutlineLAEA(file.path("inputs", "predictors", "raw", "gadm"), crs(r))
  r <- mask(crop(r, ext(outline), snap = "out"), outline); global(r, "mean", na.rm = TRUE)[1, 1]
}
dir.create(file.path(root, "scale_trend_check"), showWarnings = FALSE); rows <- list()
for (v in variants) {
  tag <- if (v == "big5") ensTag else ""
  metaDir <- firstExisting(file.path(root, paste0("metamodel_02_1_50", if (nzchar(tag)) paste0("_", tag), "_germany")), file.path(root, paste0("metamodel_02_1_50", if (nzchar(tag)) paste0("_", tag))))
  for (yr in years) {
    f <- c(climate = if (v == "brt") file.path(scaleDir("climate"), sprintf("%s_pred_EU_%d.tif", spc, yr)) else file.path(scaleDir("climate"), sprintf("%s_pred_%s_climate_%d.tif", spc, tag, yr)),
           landscape = if (v == "brt") file.path(scaleDir("landscape"), sprintf("%s_pred_landscape_%d.tif", spc, yr)) else file.path(scaleDir("landscape"), sprintf("%s_pred_%s_landscape_%d.tif", spc, tag, yr)),
           habitat = if (v == "brt") file.path(scaleDir("habitat"), sprintf("%s_pred_habitat_%d.tif", spc, yr)) else file.path(scaleDir("habitat"), sprintf("%s_pred_%s_habitat_%d.tif", spc, tag, yr)),
           final = if (is.na(metaDir)) NA_character_ else file.path(metaDir, sprintf("%s_meta_suitability_%d.tif", spc, yr)))
    for (sc in names(f)) rows[[length(rows) + 1]] <- data.frame(species = sp, variant = v, scale = sc, year = yr, meanProb = meanIn(if (!is.na(f[[sc]]) && file.exists(f[[sc]])) f[[sc]] else NA_character_))
    message(sp, " | ", v, " | ", yr, " | ", format(Sys.time(), "%H:%M:%S"))
  }
}
out <- do.call(rbind, rows); out$index <- ave(out$meanProb, out$variant, out$scale, FUN = function(x) 100 * x / x[1])
write.csv(out, file.path(root, "scale_trend_check", paste0(spc, ".csv")), row.names = FALSE)
message("written ", file.path(root, "scale_trend_check", paste0(spc, ".csv")))
marker <- Sys.getenv("UNC_DONE_MARKER", ""); if (nzchar(marker)) writeLines("ok", marker)
