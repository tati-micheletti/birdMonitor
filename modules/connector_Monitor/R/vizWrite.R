#' Names of the layers of a source file as the Monitor wants them (one file per layer, no multilayer maps)
#'
#' @param file Character. Source raster.
#' @param product Character. One of the products of `vizSources()`.
#' @return data.frame with the layer `index` in the source file and `label` used in the file name of the result (`""` = no suffix).
#'   For `msi_regional` the label is the YEAR of the layer (the regional index file has one layer per year).
vizLayers <- function(file, product) {
  r <- terra::rast(file); nm <- names(r); n <- length(nm)
  fiveNames <- c("mean", "sd", "lwr", "upr", "width")
  if (product == "meta_prob_year") {                         # keep the probability only (the file also holds the binary map)
    i <- which(nm == "meta_prob"); if (!length(i)) i <- grep("prob", nm, ignore.case = TRUE)[1]; if (is.na(i) || !length(i)) i <- 1L
    return(data.frame(index = i, label = "", stringsAsFactors = FALSE))
  }
  if (product == "msi_regional") {
    yr <- regmatches(nm, regexpr("[0-9]{4}", nm))
    if (length(yr) != n) stop("vizLayers(): the layers of ", file, " have no year in their names: ", paste(nm, collapse = ", "))
    return(data.frame(index = seq_len(n), label = yr, stringsAsFactors = FALSE))
  }
  lab <- if (all(nm %in% fiveNames)) nm else if (n == 5L) fiveNames else stop("vizLayers(): ", file, " has ", n, " layers named ", paste(nm, collapse = ", "), "; expected mean, sd, lwr, upr, width")
  data.frame(index = seq_len(n), label = lab, stringsAsFactors = FALSE)
}

#' Relative path of one result inside the viz folder
#' @param label Layer label from `vizLayers()` (the year for `msi_regional`).
vizDest <- function(product, species, year, label, folders, cellKm) {
  f <- folders[[product]]; km <- format(cellKm)
  switch(product,
         meta_prob_year   = file.path(f, species, sprintf("%s_%d.tif", species, year)),
         meta_unc_year    = file.path(f, species, sprintf("%s_%d_%s.tif", species, year, label)),
         richness_year    = file.path(f, sprintf("richness_%d_%s.tif", year, label)),
         msi_regional     = file.path(f, sprintf("msi_%skm_%s.tif", km, label)),
         msi_regional_unc = file.path(f, sprintf("msi_%skm_%d_%s.tif", km, year, label)),
         msi_regional_clear = file.path(f, sprintf("msi_%skm_%s.tif", km, label)))
}

#' The regional index of ONE year with the unclear cells set to the baseline (2026-11-11)
#'
#' A cell keeps its index only where the 90% interval over the replicates (layers `lwr` and `upr` of the uncertainty file of that year) lies entirely on one side of
#' `baseline` (lwr > baseline or upr < baseline: the change since the baseline year is clear). Every other cell is set to `baseline` ("little or no change" in the Monitor's legend).
#' NA stays NA. A cell with an index but no interval is set to `baseline` as well (nothing is claimed without an interval). The source files are never changed.
#' @param rawFile Character. Regional index of all years (one layer per year, 100 = baseline year). @param index Integer. Layer of `rawFile` for this year.
#' @param uncFile Character. Uncertainty file of the same year (5 layers: mean, sd, lwr, upr, width, in index points). @param dest Character. File to write. @param baseline Numeric (default 100).
vizWriteClearIndex <- function(rawFile, index, uncFile, dest, baseline = 100) {
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  r <- terra::rast(rawFile)[[index]]; u <- terra::rast(uncFile)
  if (!all(c("lwr", "upr") %in% names(u))) { if (terra::nlyr(u) == 5L) names(u) <- c("mean", "sd", "lwr", "upr", "width") else stop("vizWriteClearIndex(): ", uncFile, " has no layers lwr and upr.") }
  lwr <- u[["lwr"]]; upr <- u[["upr"]]
  if (!isTRUE(terra::compareGeom(r, lwr, stopOnError = FALSE))) { lwr <- terra::resample(lwr, r, method = "near"); upr <- terra::resample(upr, r, method = "near") }
  nNoInterval <- terra::global(!is.na(r) & (is.na(lwr) | is.na(upr)), "sum", na.rm = TRUE)[1, 1]          # an index without an interval should not happen (both come from the same replicates): reported, the cell is set to the baseline
  if (isTRUE(nNoInterval > 0)) warning("vizWriteClearIndex(): ", nNoInterval, " cell(s) of ", basename(dest), " have an index but no interval (not expected); set to ", baseline, call. = FALSE)
  clear <- terra::ifel(is.na(lwr) | is.na(upr), 0, terra::ifel((lwr > baseline) | (upr < baseline), 1, 0))
  out <- terra::ifel(is.na(r), NA, terra::ifel(clear == 1, r, baseline)); names(out) <- names(r)
  part <- paste0(dest, ".part")
  terra::writeRaster(out, part, filetype = "GTiff", overwrite = TRUE, datatype = "FLT4S", gdal = c("COMPRESS=DEFLATE", "PREDICTOR=3"))
  if (file.exists(dest)) file.remove(dest)
  file.rename(part, dest)
}

#' Write the national trend table for the Monitor
#'
#' Same numbers as the source (`combined_index_uncertainty.csv`: method, year, estimate, median, lwr, upr) plus the column `preliminary`: TRUE for every year AFTER
#' `lastPublishedYear` (the last year of the published national indicator). The Monitor draws those years dashed and labels them "Preliminary trend - subject to later update".
#' Only this national series is split that way; nothing else in the viz folder is marked. `lastPublishedYear` NA: nothing is marked (and a message says so).
#' @return Invisibly, the table written.
vizWriteNational <- function(src, dest, lastPublishedYear = NA_integer_) {
  d <- utils::read.csv(src, stringsAsFactors = FALSE)
  need <- c("method", "year", "estimate", "lwr", "upr"); if (!all(need %in% names(d))) stop("vizWriteNational(): ", src, " lacks column(s): ", paste(setdiff(need, names(d)), collapse = ", "))
  d$preliminary <- if (is.na(lastPublishedYear)) FALSE else d$year > lastPublishedYear
  if (is.na(lastPublishedYear)) message("vizWriteNational(): no last published indicator year given - no year is marked preliminary.")
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  part <- paste0(dest, ".part"); utils::write.csv(d, part, row.names = FALSE)
  if (file.exists(dest)) file.remove(dest)
  file.rename(part, dest); invisible(d)
}

vizWaterCache <- new.env(parent = emptyenv())

#' Share (0 to 1) of every cell of `template` that is water (2026-11-05)
#'
#' `waterFile`: polygons of lakes and wider rivers (any vector format terra reads: shapefile, GeoPackage, GeoJSON) or a raster (any value above 0 is water). The polygons are put on the grid of `template`
#' (`terra::rasterize(cover = TRUE)`: the fraction of the cell covered), so a river that fills most of a cell counts and a thin stream does not. Narrow waters that are only lines in the source are NOT used.
#' The result is kept per grid for the rest of the session (all species maps share one grid, so it is made once).
#' @param template SpatRaster whose grid is used. @param waterFile Character. Path of the water layer.
#' @return SpatRaster, one layer `waterShare`.
vizWaterShare <- function(template, waterFile) {
  tpl <- terra::rast(template)[[1]]
  key <- paste(c(normalizePath(waterFile, winslash = "/", mustWork = TRUE), file.size(waterFile), round(as.vector(terra::ext(tpl)), 3), terra::res(tpl), terra::crs(tpl, proj = TRUE)), collapse = "|")
  if (!is.null(vizWaterCache[[key]])) return(vizWaterCache[[key]])
  if (grepl("[.](tif|tiff|img|nc)$", waterFile, ignore.case = TRUE)) {
    wr <- terra::rast(waterFile)[[1]]; wr <- terra::ifel(is.na(wr), 0, terra::ifel(wr > 0, 1, 0))
    share <- terra::resample(wr, tpl, method = if (all(terra::res(wr) < terra::res(tpl))) "average" else "bilinear")
  } else {
    w <- terra::vect(waterFile)
    if (!identical(terra::geomtype(w), "polygons")) stop("vizWaterShare(): ", waterFile, " holds ", terra::geomtype(w), ", but polygons (lakes, rivers) are needed.")
    if (!nzchar(terra::crs(w))) stop("vizWaterShare(): ", waterFile, " has no coordinate reference system.")
    if (!terra::same.crs(w, tpl)) w <- terra::project(w, tpl)
    w <- terra::crop(w, terra::ext(tpl))
    share <- if (nrow(w) == 0) terra::init(tpl, 0) else terra::rasterize(w, tpl, cover = TRUE, background = 0)
  }
  share <- terra::clamp(share, 0, 1); names(share) <- "waterShare"
  vizWaterCache[[key]] <- share
  share
}

#' Set the cells of a raster that are mostly water to NA (2026-11-05): no probability of occurrence over lakes and big rivers
#' @param r SpatRaster (one layer). @param waterFile Character. See `vizWaterShare()`. @param minShare Numeric. A cell is masked when its water share is at least this (default 0.5).
vizApplyWater <- function(r, waterFile, minShare = 0.5) {
  share <- vizWaterShare(r, waterFile); nm <- names(r)
  out <- terra::ifel(share >= minShare, NA, r); names(out) <- nm
  out
}

#' Put one layer of a source raster into the viz folder as its own single-layer file
#'
#' Written to a `.part` file first and then renamed, so a reader (the upload to the bucket) never sees a half-written file. With `waterFile` the cells that are mostly water are set to NA in this copy.
vizWriteLayer <- function(src, index, dest, waterFile = NULL, waterMinShare = 0.5) {
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  r <- terra::rast(src)[[index]]
  if (!is.null(waterFile)) r <- vizApplyWater(r, waterFile, waterMinShare)        # only the COPY in the viz folder is masked; the source file is never changed
  part <- paste0(dest, ".part")
  terra::writeRaster(r, part, filetype = "GTiff", overwrite = TRUE, datatype = "FLT4S", gdal = c("COMPRESS=DEFLATE", "PREDICTOR=3"))
  if (file.exists(dest)) file.remove(dest)
  file.rename(part, dest)
}

#' Link (or copy) a whole source file into the viz folder
#'
#' A symbolic link costs no space and is always the newest file. It is only used for files that already are what the Monitor wants (a single layer).
#' A link to a path under `/work` would break when EVE deletes old files there (60 days), so that is refused unless `allowWorkSources` is TRUE.
#' If the link cannot be made (e.g. Windows without the privilege), the file is copied and a warning says so.
#' @return "link" or "copy".
vizLink <- function(src, dest, linkMode = "symlink", allowWorkSources = FALSE) {
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  srcAbs <- normalizePath(src, winslash = "/", mustWork = TRUE)
  if (linkMode == "symlink") {
    if (!allowWorkSources && grepl("^/work/", srcAbs)) stop("vizLink(): refusing to link to ", srcAbs, " (EVE deletes files under /work after 60 days and the link would break). ",
                                                             "Copy the results to /data/birds first and point runsRoot there, or set allowWorkSources = TRUE.")
    tmp <- paste0(dest, ".newlink")
    if (file.exists(tmp) || nzchar(Sys.readlink(tmp))) file.remove(tmp)
    ok <- suppressWarnings(file.symlink(srcAbs, tmp))
    if (isTRUE(ok)) {
      if (file.exists(dest) || nzchar(Sys.readlink(dest))) file.remove(dest)
      file.rename(tmp, dest); return("link")
    }
    warning("vizLink(): could not make a symbolic link for ", basename(dest), "; copying the file instead.", call. = FALSE)
  }
  if (file.exists(dest)) file.remove(dest)
  file.copy(srcAbs, dest, overwrite = TRUE); "copy"
}
