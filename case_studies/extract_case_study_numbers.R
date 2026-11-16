# CASE STUDIES (not part of the workflow). Step 1, on EVE, READ-ONLY: the numbers behind the two case studies.
#   BIRDMONITOR_RUNNAME=v3 sbatch --export=ALL case_studies/eve_case_study.sbatch      (or: Rscript case_studies/extract_case_study_numbers.R --run v3)
#   Needs outputs/<run>/case_studies/areas_3035.gpkg (made locally by case_studies/build_areas.R and copied to EVE). Writes only to outputs/<run>/case_studies/.
# For each area (the two case areas, their state without the area as control) and for the whole of Germany, the mean over the cells whose centre lies inside the area:
#   1. species_site_year.csv  probability of occurrence per species and year (final ensemble maps, /data/birds/viz2/meta_prob_year, the files the website reads)
#   2. landuse_site_year.csv  share of every land-use class per year (inputs/predictors/processed/scale_1/landuse_<year>_landscape_scale_1.tif, what the 1 km models are given)
#   3. model_response.csv     what the fitted BRT models (gbm) say about the crops: partial dependence on the crop shares + relative influence (skipped with --no-response)
suppressMessages(library(terra))
args <- commandArgs(trailingOnly = TRUE)
getArg <- function(flag, default = NULL) { i <- which(args == flag); if (length(i)) args[i + 1] else default }
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*")); if (length(libs)) .libPaths(c(libs, .libPaths()))
run <- getArg("--run", Sys.getenv("BIRDMONITOR_RUNNAME", "v3")); viz <- getArg("--viz", "/data/birds/viz2")
out <- file.path("outputs", run, "case_studies"); dir.create(out, recursive = TRUE, showWarnings = FALSE)
areasFile <- getArg("--areas", file.path(out, "areas_3035.gpkg")); lyrs <- c("Schorfheide", "Muensterland", "control_Schorfheide", "control_Muensterland")
polys <- do.call(rbind, lapply(lyrs, function(l) { v <- vect(areasFile, layer = l); values(v) <- data.frame(site = l); v }))
## 1. species x year x area ------------------------------------------------------------------------------------------------------------------------------------------------
root <- file.path(viz, "meta_prob_year"); spp <- list.dirs(root, full.names = FALSE, recursive = FALSE); spp <- spp[nzchar(spp)]; res <- list()
for (sp in spp) for (yr in 2005:2025) {
  f <- file.path(root, sp, sprintf("%s_%d.tif", sp, yr)); if (!file.exists(f)) next
  r <- rast(f)[[1]]; e <- extract(r, project(polys, crs(r)), fun = mean, na.rm = TRUE)
  res[[length(res) + 1]] <- data.frame(species = sp, year = yr, site = c(lyrs, "Germany"), meanProb = c(e[, 2], global(r, "mean", na.rm = TRUE)[1, 1])); message("species ", sp, " ", yr)
}
write.csv(do.call(rbind, res), file.path(out, "species_site_year.csv"), row.names = FALSE)
## 2. land use x year x area ---------------------------------------------------------------------------------------------------------------------------------------------
lu <- list()
for (yr in 2005:2025) {
  f <- file.path("inputs", "predictors", "processed", "scale_1", sprintf("landuse_%d_landscape_scale_1.tif", yr)); if (!file.exists(f)) next
  r <- rast(f); e <- extract(r, project(polys, crs(r)), fun = mean, na.rm = TRUE); g <- as.numeric(global(r, "mean", na.rm = TRUE)[, 1])
  for (cl in names(r)) lu[[length(lu) + 1]] <- data.frame(site = c(lyrs, "Germany"), year = yr, class = cl, share = c(e[[cl]], g[match(cl, names(r))])); message("landuse ", yr)
}
write.csv(do.call(rbind, lu), file.path(out, "landuse_site_year.csv"), row.names = FALSE)
## 3. what the models say about the crops --------------------------------------------------------------------------------------------------------------------------------
if (!("--no-response" %in% args)) {
  suppressMessages(library(gbm)); resp <- list()
  for (sp in c("Vanellus vanellus", "Alauda arvensis", "Emberiza calandra", "Saxicola rubetra")) for (sc in c("landscape", "habitat")) {
    f <- file.path("outputs", run, if (sc == "landscape") "scale_1" else "scale_02", sprintf("%s_BRT_%s.rds", gsub(" ", "_", sp), sc)); if (!file.exists(f)) { message("no model: ", f); next }
    m <- readRDS(f); if (!inherits(m, "gbm")) next
    ri <- summary(m, plotit = FALSE); resp[[length(resp) + 1]] <- data.frame(species = sp, scale = sc, kind = "relative_influence", variable = ri$var, x = NA, y = ri$rel.inf)
    for (v in intersect(c("winter_cereals", "summer_cereals", "maize", "grassland", "fallow", "rapeseed", "root_crops"), m$var.names)) {
      pd <- tryCatch(plot(m, i.var = v, n.trees = m$n.trees, type = "response", continuous.resolution = 40, return.grid = TRUE), error = function(e) NULL)
      if (!is.null(pd)) resp[[length(resp) + 1]] <- data.frame(species = sp, scale = sc, kind = "partial_dependence", variable = v, x = pd[[v]], y = pd$y)
    }
  }
  write.csv(do.call(rbind, resp), file.path(out, "model_response.csv"), row.names = FALSE)
}
message("=== done: ", out)
marker <- Sys.getenv("UNC_DONE_MARKER", ""); if (nzchar(marker)) writeLines("ok", marker)
