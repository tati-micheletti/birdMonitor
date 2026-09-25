################### PER-SPECIES/SCALE CONFIGURATION
# Loaders for the two CSVs that hold per-species, per-scale settings and
# candidate-predictor extensions -- see speciesConfig_general.csv and
# speciesConfig_predictors.csv at the repo root. Two separate files
# (general config vs. predictors), NOT one combined table: general config
# is exactly 3 rows per species (one per scale: climate/landscape/habitat),
# while predictors is a variable number of rows per species (one per extra
# predictor being added for that species), so cramming both into one wide
# table conflates two different things with two different shapes.

#' Load the per-species, per-scale general config table
#'
#' One row per species per scale -- EXACTLY 3 rows per species
#' (climate/landscape/habitat). Columns beyond species/scale:
#' `resolution_m`, `data_source` (informational), `thinning_dist_m`,
#' `brt_start_lr`, `hedges_treatment` ("drop"/"backfill", blank for
#' climate rows -- hedges isn't a climate covariate), `brutzeitcode_filter`
#' (blank = no filter; only meaningful for habitat rows, MhB point counts
#' carry a Brutzeitcode).
#'
#' NOTE on what's actually wired to per-species effect as of 2026-09-25:
#' `brt_start_lr` (feeds `perSpeciesLR` in models_Monitor) and
#' `hedges_treatment` (feeds a per-species override in inputs_Monitor) ARE
#' consumed per-species. `resolution_m` and `thinning_dist_m` are captured
#' here for future use but NOT yet wired to per-species effect --
#' `occurrencePrepGerHabitat()`/`GerLandscape()`/`Europe()` still take one
#' shared thinning distance for every species per run, and per-species
#' resolution needs the `Cache()`-based redesign described in
#' `improvements.md` item 4 (a species at a non-default resolution would
#' need its own covariate rasters, not the shared per-resolution ones every
#' species currently reads). `brutzeitcode_filter` has no consuming code at
#' all yet -- no part of the pipeline filters by Brutzeitcode currently.
#'
#' @param path Character. Path to the general-config CSV.
#' @return Nested list `config[[species]][[scale]]`, each a named list of
#'   the row's other columns (numeric columns coerced, blanks as NA).
loadSpeciesGeneralConfig <- function(path) {
  df <- utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character")

  requiredCols <- c("species", "scale", "resolution_m", "data_source",
                     "thinning_dist_m", "brt_start_lr", "hedges_treatment",
                     "brutzeitcode_filter")
  missingCols <- setdiff(requiredCols, names(df))
  if (length(missingCols) > 0) {
    stop("speciesConfig_general.csv is missing column(s): ", paste(missingCols, collapse = ", "))
  }

  validScales <- c("climate", "landscape", "habitat")
  badScales <- setdiff(unique(df$scale), validScales)
  if (length(badScales) > 0) {
    stop("speciesConfig_general.csv has invalid scale value(s): ",
         paste(badScales, collapse = ", "), " -- must be one of: ",
         paste(validScales, collapse = ", "))
  }

  rowCounts <- table(df$species)
  badCounts <- rowCounts[rowCounts != 3]
  if (length(badCounts) > 0) {
    stop("speciesConfig_general.csv: species without exactly 3 rows (one per ",
         "climate/landscape/habitat scale): ", paste(names(badCounts), collapse = ", "))
  }

  dupKey <- paste(df$species, df$scale)
  dupRows <- unique(dupKey[duplicated(dupKey)])
  if (length(dupRows) > 0) {
    stop("speciesConfig_general.csv has duplicate species+scale row(s): ",
         paste(dupRows, collapse = "; "))
  }

  numericCols <- c("resolution_m", "thinning_dist_m", "brt_start_lr")
  blankToNA <- function(x) if (!nzchar(x)) NA_character_ else x

  config <- list()
  for (i in seq_len(nrow(df))) {
    sp <- df$species[i]
    sc <- df$scale[i]
    row <- as.list(df[i, setdiff(names(df), c("species", "scale"))])
    for (col in numericCols) {
      row[[col]] <- suppressWarnings(as.numeric(blankToNA(row[[col]])))
    }
    for (col in c("data_source", "hedges_treatment", "brutzeitcode_filter")) {
      row[[col]] <- blankToNA(row[[col]])
    }
    config[[sp]][[sc]] <- row
  }
  config
}

#' Load the per-species extra-candidate-predictors table (additive)
#'
#' Each row is ONE extra predictor for ONE species, placed in whichever
#' scale column(s) it applies to (blank elsewhere on that row). This
#' EXTENDS a scale's default candidate pool
#' (`covariatePredictorColumns()`/`bioclimPredictorColumns()`) for that
#' species specifically -- it does not replace it, and the extended pool
#' still goes through the normal collinearity selection
#' (`select07Blockcv()`) afterward, same as every other candidate. A
#' species with no rows here simply uses each scale's unmodified default
#' pool. This is deliberately additive, not a full override: `predictorsToUse`
#' (the existing NULL/"all"/vector override, still available) is a much
#' blunter instrument that bypasses collinearity selection entirely --
#' this table is for "make sure this specific covariate is even considered
#' for this species," not "dictate the final model."
#'
#' @param path Character. Path to the predictors CSV.
#' @return Nested list `extras[[species]][[scale]]`, each a character vector
#'   of extra predictor names for that species+scale. A species/scale
#'   combination with no rows is simply absent from the list.
loadSpeciesPredictorExtras <- function(path) {
  df <- utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character")

  requiredCols <- c("species", "climate", "landscape", "habitat")
  missingCols <- setdiff(requiredCols, names(df))
  if (length(missingCols) > 0) {
    stop("speciesConfig_predictors.csv is missing column(s): ", paste(missingCols, collapse = ", "))
  }

  extras <- list()
  for (i in seq_len(nrow(df))) {
    sp <- df$species[i]
    for (sc in c("climate", "landscape", "habitat")) {
      val <- df[[sc]][i]
      if (nzchar(val)) {
        extras[[sp]][[sc]] <- unique(c(extras[[sp]][[sc]], val))
      }
    }
  }
  extras
}
