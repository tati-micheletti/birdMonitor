#!/usr/bin/env Rscript
# READ-ONLY: our predictions AT the survey plots of the landscape-scale training data, for every plot and year. Together with the observed presence (occurrence) and number of territories (Reviere)
# of the same plot-year this gives a same-plot panel: does the model follow the observed change where the birds were counted? (The analysis is done locally from the csv; this job only extracts.)
#   Rscript tools/panelTrendCheck.R --index <species number 1..11> [--run test4] [--ens-tag ens_brt-glm-gam-rf-nn]        (cluster: sbatch cluster/eve_panel_trend_check.sbatch, an array over the species)
# Records: inputs/response/processed/territories/<Species>_landscape_<year>.rds (one row per surveyed plot and year: ROUTENCODE, Jahr, occurrence, Reviere, x, y in EPSG:3035; the plot centroid).
# Predictions extracted at (x, y) from: climate / landscape / habitat scale ensemble maps and the final (meta-model) map of the same year (main model, as in tools/scaleTrendCheck.R).
# Output: outputs/<run>/panel_trend_check/<Species>.csv  (species, ROUTENCODE, year, occurrence, Reviere, x, y, climate, landscape, habitat, final)
Sys.setenv(OMP_NUM_THREADS = "1")
args <- commandArgs(trailingOnly = TRUE)
getArg <- function(flag, default = NULL) { i <- which(args == flag); if (length(i) == 0) default else args[i + 1] }
repoRoot <- normalizePath(getArg("--repo-root", getwd()), winslash = "/"); setwd(repoRoot)
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
suppressMessages(library(terra))
canon <- read.csv("data/speciesCanonical.csv", stringsAsFactors = FALSE); canon <- canon[nzchar(trimws(canon$include)), ]
sp <- getArg("--species"); if (is.null(sp)) { i <- as.integer(getArg("--index", Sys.getenv("SLURM_ARRAY_TASK_ID", NA))); if (is.na(i) || i < 1 || i > nrow(canon)) stop("--index must be 1..", nrow(canon)); sp <- canon$latin_name[i] }
run <- getArg("--run", Sys.getenv("BIRDMONITOR_RUNNAME", "test4")); tag <- getArg("--ens-tag", "ens_brt-glm-gam-rf-nn")
spc <- gsub(" ", "_", sp); root <- file.path("outputs", run)
recDir <- getArg("--records-dir", file.path("inputs", "response", "processed", "territories"))
cfg <- tryCatch(read.csv("data/speciesConfig_general.csv", stringsAsFactors = FALSE), error = function(e) NULL)
scaleLabel <- function(m) paste0("scale_", sub(".", "", as.character(m / 1000), fixed = TRUE))
scaleDir <- function(sc) { r <- if (is.null(cfg)) NA else cfg$resolution_m[cfg$species == sp & cfg$scale == sc]; file.path(root, if (length(r) && !is.na(r[1])) scaleLabel(r[1]) else c(climate = "scale_50", landscape = "scale_1", habitat = "scale_02")[[sc]]) }
firstExisting <- function(...) { p <- c(...); p <- p[file.exists(p)]; if (length(p)) p[1] else NA_character_ }
metaDir <- firstExisting(file.path(root, paste0("metamodel_02_1_50_", tag, "_germany")), file.path(root, paste0("metamodel_02_1_50_", tag)))
recFiles <- Sys.glob(file.path(recDir, paste0(spc, "_landscape_*.rds")))
if (!length(recFiles)) stop("no plot records found for ", sp, " in ", recDir)
rec <- do.call(rbind, lapply(recFiles, function(f) { d <- readRDS(f); if (!is.data.frame(d)) d <- d[[1]]
  data.frame(species = sp, ROUTENCODE = d$ROUTENCODE, year = as.integer(d$Jahr), occurrence = d$occurrence, Reviere = d$Reviere, x = d$x, y = d$y) }))
rec <- rec[!is.na(rec$x) & !is.na(rec$y), ]; rec <- rec[order(rec$year, rec$ROUTENCODE), ]
message(sp, ": ", nrow(rec), " plot-years, ", length(unique(rec$ROUTENCODE)), " plots, years ", min(rec$year), "-", max(rec$year))
atPoints <- function(f, xy) {                                              # value of band 1 of raster file f at the points (x, y in EPSG:3035); NA when the file is missing
  if (is.na(f) || !file.exists(f)) return(rep(NA_real_, nrow(xy)))
  r <- rast(f)[[1]]; p <- vect(xy, crs = "EPSG:3035"); if (!isTRUE(same.crs(r, p))) p <- project(p, crs(r))
  terra::extract(r, p)[, 2] }
for (sc in c("climate", "landscape", "habitat", "final")) rec[[sc]] <- NA_real_
for (yr in sort(unique(rec$year))) {
  i <- which(rec$year == yr); xy <- cbind(x = rec$x[i], y = rec$y[i])
  files <- c(climate = file.path(scaleDir("climate"), sprintf("%s_pred_%s_climate_%d.tif", spc, tag, yr)),
             landscape = file.path(scaleDir("landscape"), sprintf("%s_pred_%s_landscape_%d.tif", spc, tag, yr)),
             habitat = file.path(scaleDir("habitat"), sprintf("%s_pred_%s_habitat_%d.tif", spc, tag, yr)),
             final = if (is.na(metaDir)) NA_character_ else file.path(metaDir, sprintf("%s_meta_suitability_%d.tif", spc, yr)))
  for (sc in names(files)) rec[[sc]][i] <- atPoints(files[[sc]], xy)
  message(sp, " | ", yr, " | ", length(i), " plots | ", format(Sys.time(), "%H:%M:%S"))
}
dir.create(file.path(root, "panel_trend_check"), showWarnings = FALSE)
write.csv(rec, file.path(root, "panel_trend_check", paste0(spc, ".csv")), row.names = FALSE)
message("written ", file.path(root, "panel_trend_check", paste0(spc, ".csv")), " | missing predictions: ", paste(names(colSums(is.na(rec[, c("climate", "landscape", "habitat", "final")]))), colSums(is.na(rec[, c("climate", "landscape", "habitat", "final")])), collapse = ", "))
marker <- Sys.getenv("UNC_DONE_MARKER", ""); if (nzchar(marker)) writeLines("ok", marker)
