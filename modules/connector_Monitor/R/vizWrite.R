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
         msi_regional_unc = file.path(f, sprintf("msi_%skm_%d_%s.tif", km, year, label)))
}

#' Put one layer of a source raster into the viz folder as its own single-layer file
#'
#' Written to a `.part` file first and then renamed, so a reader (the upload to the bucket) never sees a half-written file.
vizWriteLayer <- function(src, index, dest) {
  dir.create(dirname(dest), recursive = TRUE, showWarnings = FALSE)
  r <- terra::rast(src)[[index]]
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
