#' Bring the newest results of every species into the folder the Bird Monitor reads (always complete)
#'
#' Whatever is NOT in `vizPath` is not shown in the Monitor, so the folder must always hold the newest version of EVERYTHING, also when only one species
#' (or one scale) was run last. For every result the Monitor shows, the newest source file in any run folder is used (`vizSources()`, `vizLatest()`);
#' a species that was not part of the last run keeps its file from the earlier run. Results that are already in `vizPath` and still current are not
#' touched; a result is replaced only by a NEWER source file; nothing is ever deleted. Multilayer rasters are split: one file per layer.
#' The folder gets a `_manifest.csv` (every file, the source it came from, the run, the time) and a `_missing.csv` (what is expected but not there).
#'
#' Layout of `vizPath` (folder names in `folders`):
#'   meta_prob_year/<Species>/<Species>_<year>.tif                     probability of occurrence
#'   meta_unc_year/<Species>/<Species>_<year>_<layer>.tif              layer = mean, sd, lwr, upr, width
#'   richness_year/richness_<year>_<layer>.tif                         expected richness (mean) and its uncertainty
#'   msi_regional/msi_<km>km_<year>.tif                                regional index (MSI), raw
#'   msi_regional_unc/msi_<km>km_<year>_<layer>.tif                    its uncertainty
#'
#' @param runsRoot Character. Folder with the run folders (e.g. `/data/birds/birdMonitor/outputs`).
#' @param vizPath Character. The folder of the Monitor (e.g. `/data/birds/viz`); created if needed.
#' @param tag Character. Ensemble tag of the result folders (`"ens_brt-glm-gam-rf-nn"`).
#' @param species Character. Latin names of the full species roster (what the Monitor must be able to show).
#' @param years Integer vector. Years expected for every species.
#' @param cellKm Numeric. Regional index cell size (km).
#' @param runs,excludeRuns See `vizSources()`.
#' @param folders Named list of folder names (see above).
#' @param linkMode "symlink" (default) or "copy" for files that need no splitting.
#' @param allowWorkSources Logical. Allow links to files under `/work` (they break when EVE cleans `/work`).
#' @param dryRun Logical. Only report what would be done.
#' @param failIfIncomplete Logical. Stop with an error when something expected is missing (default: warn and write `_missing.csv`).
#' @return Invisibly, a list with `manifest`, `missing` and `done` (number of files written or linked in this call).
connectViz <- function(runsRoot, vizPath, tag, species, years, cellKm = 10, runs = NULL, excludeRuns = "^(utest|test1|test2|test3|CHECK)",
                       folders = list(meta_prob_year = "meta_prob_year", meta_unc_year = "meta_unc_year", richness_year = "richness_year",
                                      msi_regional = "msi_regional", msi_regional_unc = "msi_regional_unc"),
                       linkMode = "symlink", allowWorkSources = FALSE, dryRun = FALSE, failIfIncomplete = FALSE) {
  spUnder <- gsub(" ", "_", species)
  src <- vizSources(runsRoot, runs, excludeRuns, tag, cellKm)
  if (!nrow(src)) stop("connectViz(): no result files for tag '", tag, "' found in the run folders of ", runsRoot)
  perSpecies <- src$product %in% c("meta_prob_year", "meta_unc_year")
  other <- setdiff(unique(src$species[perSpecies]), spUnder)
  if (length(other)) message("connectViz(): species in the results but not in the roster are ignored: ", paste(other, collapse = ", "))
  src <- src[!perSpecies | src$species %in% spUnder, ]
  src <- src[is.na(src$year) | src$year %in% years | !src$product %in% c("meta_prob_year", "meta_unc_year"), ]
  latest <- vizLatest(src)
  message("connectViz(): ", nrow(src), " source files in ", length(unique(src$run)), " run folder(s) -> ", nrow(latest), " results (newest of each)")

  manFile <- file.path(vizPath, "_manifest.csv")
  man <- if (file.exists(manFile)) utils::read.csv(manFile, stringsAsFactors = FALSE) else NULL
  cols <- c("product", "species", "year", "layer", "dest", "src", "srcMtime", "run", "mode", "written")
  if (is.null(man)) man <- data.frame(product = character(), species = character(), year = integer(), layer = character(), dest = character(), src = character(),
                                      srcMtime = numeric(), run = character(), mode = character(), written = character(), stringsAsFactors = FALSE)
  man$species[is.na(man$species)] <- ""; man$layer[is.na(man$layer)] <- ""
  done <- 0L; plan <- 0L
  for (i in seq_len(nrow(latest))) {
    row <- latest[i, ]
    lay <- vizLayers(row$file, row$product)
    nl <- terra::nlyr(terra::rast(row$file))
    yrs <- if (row$product == "msi_regional") as.integer(lay$label) else rep(row$year, nrow(lay))
    for (j in seq_len(nrow(lay))) {
      dest <- vizDest(row$product, row$species, yrs[j], lay$label[j], folders, cellKm); destAbs <- file.path(vizPath, dest)
      k <- which(man$dest == dest)
      current <- length(k) == 1L && file.exists(destAbs) && file.exists(man$src[k]) && !(row$mtime > man$srcMtime[k] + 1)
      if (current) next
      plan <- plan + 1L
      if (dryRun) { message("would write ", dest, "  <-  ", row$run, "/", basename(row$file)); next }
      mode <- if (nl == 1L && row$product == "meta_prob_year") vizLink(row$file, destAbs, linkMode, allowWorkSources) else { vizWriteLayer(row$file, lay$index[j], destAbs); "written" }
      entry <- data.frame(product = row$product, species = row$species, year = yrs[j], layer = lay$label[j], dest = dest, src = normalizePath(row$file, winslash = "/"),
                          srcMtime = row$mtime, run = row$run, mode = mode, written = format(Sys.time(), "%Y-%m-%d %H:%M:%S"), stringsAsFactors = FALSE)
      man <- rbind(man[man$dest != dest, , drop = FALSE], entry[, cols]); done <- done + 1L
    }
    if (!dryRun && i %% 25 == 0) message("  ", i, " of ", nrow(latest), " results checked, ", done, " files written so far")
  }
  if (dryRun) { message("connectViz(): dry run, ", plan, " files would be written or linked"); return(invisible(list(manifest = man, missing = NULL, done = 0L))) }
  dir.create(vizPath, recursive = TRUE, showWarnings = FALSE)
  man <- man[order(man$product, man$species, man$year, man$layer), ]
  utils::write.csv(man, manFile, row.names = FALSE)

  # what the Monitor needs but the folder does not have
  need <- rbind(expand.grid(product = "meta_prob_year", species = spUnder, year = years, label = "", stringsAsFactors = FALSE),
                expand.grid(product = "meta_unc_year", species = spUnder, year = years, label = c("mean", "sd", "lwr", "upr", "width"), stringsAsFactors = FALSE))
  have <- paste(man$product, man$species, man$year, ifelse(man$product == "meta_unc_year", man$layer, ""))
  miss <- need[!paste(need$product, need$species, need$year, need$label) %in% have, , drop = FALSE]
  noOther <- vapply(c("richness_year", "msi_regional", "msi_regional_unc"), function(p) any(man$product == p), logical(1))
  extra <- if (any(!noOther)) data.frame(product = names(noOther)[!noOther], species = "", year = NA_integer_, label = "", stringsAsFactors = FALSE) else need[0, ]
  miss <- rbind(miss, extra); names(miss)[names(miss) == "label"] <- "layer"
  utils::write.csv(miss, file.path(vizPath, "_missing.csv"), row.names = FALSE)
  message("connectViz(): ", done, " files written or linked now; ", nrow(man), " in the manifest; missing: ", nrow(miss), if (nrow(miss)) paste0(" (see ", file.path(vizPath, "_missing.csv"), ")") else "")
  if (nrow(miss)) {
    msg <- paste0("the viz folder is NOT complete: ", nrow(miss), " expected results missing, e.g. ", paste(utils::head(paste(miss$product, miss$species, miss$year, miss$layer), 3), collapse = "; "))
    if (failIfIncomplete) stop("connectViz(): ", msg, call. = FALSE) else warning("connectViz(): ", msg, call. = FALSE)
  }
  invisible(list(manifest = man, missing = miss, done = done))
}
