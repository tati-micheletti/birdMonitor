#!/usr/bin/env Rscript
# READ-ONLY: where do the holes (NA pixels) inside Germany in the prediction maps come from? For every species and a few years it counts, inside the German outline,
#   - the NA pixels of the habitat-scale ensemble map (200 m), of the landscape-scale ensemble map (1 km) and of the final (meta-model) map (200 m),
#   - the NA pixels of the covariate layer landscape_heterogeneity of the same year (inputs/predictors/processed/scale_02), and how many of the habitat-map holes lie on them.
# Hypothesis (2026-10-20): the Simpson index of tools/ dataPrep_Monitor/R/computeHeterogeneityIndex.R is NA in cells where no land-use or land-cover category reaches 5%; models that use it
# (Emberiza citrinella, Lanius collurio, Lullula arborea, Sturnus vulgaris) cannot be predicted there (complete.cases), the ensemble mean has na.rm = FALSE, and the meta-model needs all scales.
#   Rscript tools/naHolesCheck.R [--run test4] [--years 2005,2012,2018,2022,2025]        (cluster: sbatch cluster/eve_na_holes_check.sbatch)
# Output: printed table and outputs/<run>/na_holes_check.csv
Sys.setenv(OMP_NUM_THREADS = "1")
args <- commandArgs(trailingOnly = TRUE)
getArg <- function(flag, default = NULL) { i <- which(args == flag); if (length(i) == 0) default else args[i + 1] }
repoRoot <- normalizePath(getArg("--repo-root", getwd()), winslash = "/"); setwd(repoRoot)
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
suppressMessages(library(terra))
source("modules/models_Monitor/R/uncRegional.R")                           # uncOutlineLAEA()
canon <- read.csv("data/speciesCanonical.csv", stringsAsFactors = FALSE); canon <- canon[nzchar(trimws(canon$include)), ]
run <- getArg("--run", Sys.getenv("BIRDMONITOR_RUNNAME", "test4")); tag <- "ens_brt-glm-gam-rf-nn"; root <- file.path("outputs", run)
years <- as.integer(strsplit(getArg("--years", "2005,2012,2018,2022,2025"), ",")[[1]])
cfg <- tryCatch(read.csv("data/speciesConfig_general.csv", stringsAsFactors = FALSE), error = function(e) NULL)
scaleLabel <- function(m) paste0("scale_", sub(".", "", as.character(m / 1000), fixed = TRUE))
scaleDir <- function(sp, sc) { r <- if (is.null(cfg)) NA else cfg$resolution_m[cfg$species == sp & cfg$scale == sc]; file.path(root, if (length(r) && !is.na(r[1])) scaleLabel(r[1]) else c(climate = "scale_50", landscape = "scale_1", habitat = "scale_02")[[sc]]) }
firstExisting <- function(...) { p <- c(...); p <- p[file.exists(p)]; if (length(p)) p[1] else NA_character_ }
metaDir <- firstExisting(file.path(root, paste0("metamodel_02_1_50_", tag, "_germany")), file.path(root, paste0("metamodel_02_1_50_", tag)))
hetDir <- file.path("inputs", "predictors", "processed", "scale_02")
outline <- NULL
naIn <- function(f, ref = NULL) {                                          # list(nNA, nInside, mask of NA inside Germany) of band 1 of file f; NULL when the file is missing
  if (is.na(f) || !file.exists(f)) return(NULL)
  r <- rast(f)[[1]]; if (is.null(outline)) outline <<- uncOutlineLAEA(file.path("inputs", "predictors", "raw", "gadm"), crs(r))
  m <- rasterize(outline, r, field = 1, background = NA); na <- is.na(r) & !is.na(m)
  list(nNA = global(na, "sum")[1, 1], nInside = global(!is.na(m), "sum")[1, 1], na = na) }
rows <- list()
for (sp in canon$latin_name) { spc <- gsub(" ", "_", sp)
  for (yr in years) {
    h <- naIn(file.path(scaleDir(sp, "habitat"), sprintf("%s_pred_%s_habitat_%d.tif", spc, tag, yr)))
    l <- naIn(file.path(scaleDir(sp, "landscape"), sprintf("%s_pred_%s_landscape_%d.tif", spc, tag, yr)))
    f <- naIn(if (is.na(metaDir)) NA_character_ else file.path(metaDir, sprintf("%s_meta_suitability_%d.tif", spc, yr)))
    g <- naIn(file.path(hetDir, sprintf("landscape_heterogeneity_%d_habitat_scale_02.tif", yr)))
    ov <- if (!is.null(h) && !is.null(g)) global(h$na & resample(g$na, h$na, method = "near"), "sum")[1, 1] else NA
    rows[[length(rows) + 1]] <- data.frame(species = sp, year = yr, insideGermany200m = if (is.null(h)) NA else h$nInside, habitatMapNA = if (is.null(h)) NA else h$nNA, landscapeMapNA_1km = if (is.null(l)) NA else l$nNA,
                                           finalMapNA = if (is.null(f)) NA else f$nNA, heterogeneityNA = if (is.null(g)) NA else g$nNA, habitatHolesOnHeterogeneityNA = ov)
    message(sp, " ", yr, " | ", format(Sys.time(), "%H:%M:%S")) } }
out <- do.call(rbind, rows); out$habitatHolesSharePct <- round(100 * out$habitatMapNA / out$insideGermany200m, 3)
write.csv(out, file.path(root, "na_holes_check.csv"), row.names = FALSE); print(out[, c("species", "year", "habitatMapNA", "landscapeMapNA_1km", "finalMapNA", "heterogeneityNA", "habitatHolesOnHeterogeneityNA", "habitatHolesSharePct")], row.names = FALSE)
marker <- Sys.getenv("UNC_DONE_MARKER", ""); if (nzchar(marker)) writeLines("ok", marker)
