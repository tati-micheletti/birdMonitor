#' Find every result file that the Bird Monitor shows, in every run folder
#'
#' The Monitor shows (a) the yearly probability map of each species, (b) its uncertainty layers, (c) the expected richness with its uncertainty and
#' (d) the regional (MSI) index map with its uncertainty. This function lists, for each of them, the files that exist in the run folders
#' (`<runsRoot>/<run>/...`), without opening any raster. The layout of the run folders is the one written by models_Monitor / runIndex_Monitor
#' (Germany-only versions, ensemble tag `tag`):
#'   species probability  <run>/metamodel_<resolutions>_<tag>_germany/<Species>_meta_suitability_<year>.tif   (two layers: probability and binary)
#'   species uncertainty  <run>/uncertainty_<tag>/<Species>/maps_germany/<Species>_unc_<year>.tif              (5 layers: mean, sd, lwr, upr, width)
#'   expected richness    <run>/uncertainty_<tag>/community_germany/richness_expected_unc_<year>.tif            (5 layers, the report year)
#'   regional index       <run>/regional_index_<tag>_germany/regional_index_<km>km_raw.tif                      (one layer per year)
#'   regional uncertainty <run>/uncertainty_<tag>/regional/regional_index_<km>km_unc_<year>.tif                 (5 layers)
#'
#' @param runsRoot Character. Folder that contains the run folders (e.g. `outputs`, or `/data/birds/birdMonitor/outputs`).
#' @param runs Character vector of run folder names, or NULL for every folder in `runsRoot` that is not matched by `excludeRuns`.
#' @param excludeRuns Character. Regular expression of run folders that are never used (test and check folders).
#' @param tag Character. Ensemble tag of the folders, e.g. `"ens_brt-glm-gam-rf-nn"`.
#' @param cellKm Numeric. Cell size (km) of the regional index shown in the Monitor.
#' @return data.frame with one row per source file: product, species ("" when not per species), year (NA when the file has several years or none),
#'   file, run, mtime (seconds since 1970).
vizSources <- function(runsRoot, runs = NULL, excludeRuns = "^(utest|test1|test2|test3|CHECK)", tag, cellKm = 10) {
  if (!dir.exists(runsRoot)) stop("vizSources(): runsRoot does not exist: ", runsRoot)
  allRuns <- list.dirs(runsRoot, recursive = FALSE, full.names = FALSE)
  runs <- if (is.null(runs) || !length(runs)) allRuns[!grepl(excludeRuns, allRuns)] else intersect(runs, allRuns)
  rows <- list()
  add <- function(product, files, run, species = NULL, year = NULL) {
    if (!length(files)) return(invisible(NULL))
    rows[[length(rows) + 1]] <<- data.frame(product = product, species = if (is.null(species)) "" else species, year = if (is.null(year)) NA_integer_ else year,
                                           file = files, run = run, mtime = as.numeric(file.mtime(files)), stringsAsFactors = FALSE)
  }
  yearOf <- function(f) as.integer(sub(".*_([0-9]{4})[.]tif$", "\\1", basename(f)))
  km <- format(cellKm)
  for (run in runs) {
    rd <- file.path(runsRoot, run)
    # species probability maps
    for (md in list.dirs(rd, recursive = FALSE, full.names = TRUE)) {
      if (!grepl(paste0("^metamodel_[0-9_]+_", tag, "_germany$"), basename(md))) next
      fs <- list.files(md, pattern = "_meta_suitability_[0-9]{4}[.]tif$", full.names = TRUE)
      if (length(fs)) add("meta_prob_year", fs, run, species = sub("_meta_suitability_[0-9]{4}[.]tif$", "", basename(fs)), year = yearOf(fs))
    }
    # species uncertainty maps
    fs <- Sys.glob(file.path(rd, paste0("uncertainty_", tag), "*", "maps_germany", "*_unc_[0-9][0-9][0-9][0-9].tif"))
    if (length(fs)) add("meta_unc_year", fs, run, species = sub("_unc_[0-9]{4}[.]tif$", "", basename(fs)), year = yearOf(fs))
    # expected richness with uncertainty
    fs <- Sys.glob(file.path(rd, paste0("uncertainty_", tag), "community_germany", "richness_expected_unc_[0-9][0-9][0-9][0-9].tif"))
    if (length(fs)) add("richness_year", fs, run, year = yearOf(fs))
    # regional index (one file, all years) and its uncertainty (one file per year)
    f <- file.path(rd, paste0("regional_index_", tag, "_germany"), sprintf("regional_index_%skm_raw.tif", km))
    if (file.exists(f)) add("msi_regional", f, run)
    fs <- Sys.glob(file.path(rd, paste0("uncertainty_", tag), "regional", sprintf("regional_index_%skm_unc_[0-9][0-9][0-9][0-9].tif", km)))
    if (length(fs)) add("msi_regional_unc", fs, run, year = yearOf(fs))
  }
  if (!length(rows)) return(data.frame(product = character(), species = character(), year = integer(), file = character(), run = character(), mtime = numeric(), stringsAsFactors = FALSE))
  do.call(rbind, rows)
}

#' For every result the Monitor shows, keep the newest source file
#'
#' Newest = latest modification time of the file; ties go to the run folder that sorts last. A species that was updated in a later run replaces the
#' older one, a species that was not touched keeps its file from the earlier run, so the result is complete as long as every species has been run once.
#'
#' @param src data.frame from `vizSources()`.
#' @return `src` reduced to one row per (product, species, year); a column `key` identifies the result.
vizLatest <- function(src) {
  if (!nrow(src)) return(cbind(src, key = character()))
  src$key <- paste(src$product, src$species, ifelse(is.na(src$year), "", src$year), sep = "|")
  src <- src[order(src$key, -src$mtime, -xtfrm(src$run)), ]                    # newest first; on equal times the run folder that sorts last
  src[!duplicated(src$key), , drop = FALSE]
}
