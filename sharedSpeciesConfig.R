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
#' `resolution_m`, `data_source` (a real, validated value -- see below,
#' NOT yet wired to actual effect), `thinning_dist_m` (wired -- feeds
#' `perSpeciesThinDist` in dataPrep_Monitor), `brt_start_lr` (wired -- feeds
#' `perSpeciesLR` in models_Monitor), `brutzeitcode_filter` (wired -- feeds
#' `brutzeitcodeFilter` in dataPrep_Monitor; blank = no filter beyond
#' `occurrencePrepGerHabitat()`'s existing global one; only meaningful for
#' habitat rows -- the raw MhB CSV's actual column is `ATLAS_CODE`, e.g.
#' "C11a"/"C12" for confirmed breeding, NOT literally "Brutzeitcode"; a
#' filter value here is matched as a PREFIX, e.g. "C" keeps every code
#' starting with C), `predictor_mode` (wired -- see
#' `resolvePerSpeciesPredictors()` below; blank defaults to `"table"`).
#'
#' `hedges_treatment` is deliberately NOT a column here -- it's a single
#' shared value tuned directly in code (inputs_Monitor's `hedgesTreatment`
#' parameter), not per-species. Per-species hedges inclusion instead goes
#' through `speciesConfig_predictors.csv` (list "hedges" for whichever
#' species should get it as a candidate, once the code-level setting is
#' "backfill" so the column exists at all to list).
#'
#' `data_source` is a real, validated value, not free text -- one of
#' `"EBBA2/CHELSA"` (climate rows only), `"MhB point counts"`, or
#' `"DDA territories"` (habitat/landscape rows). It records which raw
#' dataset that species+scale should use -- e.g. Buteo buteo and Sturnus
#' vulgaris use `"MhB point counts"` at landscape scale instead of the
#' `"DDA territories"` every other species uses, per the 2026-09-25
#' improvement notes. Exact string match, case-sensitive, no fuzzy
#' matching -- a typo is rejected at load time rather than silently
#' becoming an unrecognized value downstream.
#'
#' NOTE on what's actually wired to per-species effect as of 2026-09-25:
#' `brt_start_lr`, `thinning_dist_m`, `brutzeitcode_filter`, and
#' `predictor_mode` all reach real code now (see each parameter's own
#' docstring for exactly where). Two columns are STILL captured here for a
#' human to read/edit but have NO consuming code yet, because both need a
#' genuinely new code path, not just a parameter: (1) `resolution_m` --
#' per-species covariate resolution needs the `Cache()`-based redesign in
#' `improvements.md` item 4 (today's shared-per-resolution covariate
#' directories would collide across species at different resolutions);
#' (2) `data_source` for Buteo buteo/Sturnus vulgaris's landscape rows --
#' routing them through MhB point-count data instead of DDA territories
#' needs a new construction path in `occurrencePrepGerLandscape.R` (today
#' it always loads DDA territories for every species, regardless of this
#' column) -- this is a real methodological choice (how to define
#' presence/absence from point-count data at 1km resolution), not just
#' plumbing, so it's deliberately not guessed at without confirming the
#' exact method first.
#'
#' @param path Character. Path to the general-config CSV.
#' @return Nested list `config[[species]][[scale]]`, each a named list of
#'   the row's other columns (numeric columns coerced, blanks as NA).
loadSpeciesGeneralConfig <- function(path) {
  df <- utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character")

  requiredCols <- c("species", "scale", "resolution_m", "data_source",
                     "thinning_dist_m", "brt_start_lr", "brutzeitcode_filter",
                     "predictor_mode")
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

  validPredictorModes <- c("table", "auto")
  badModes <- setdiff(unique(df$predictor_mode[nzchar(df$predictor_mode)]), validPredictorModes)
  if (length(badModes) > 0) {
    stop("speciesConfig_general.csv has invalid predictor_mode value(s): ",
         paste(badModes, collapse = ", "), " -- must be one of: ",
         paste(validPredictorModes, collapse = ", "), " (or blank, defaulting to \"table\")")
  }

  validDataSources <- c("EBBA2/CHELSA", "MhB point counts", "DDA territories")
  badSources <- setdiff(unique(df$data_source[nzchar(df$data_source)]), validDataSources)
  if (length(badSources) > 0) {
    stop("speciesConfig_general.csv has invalid data_source value(s): ",
         paste(badSources, collapse = ", "), " -- must be one of: ",
         paste(validDataSources, collapse = ", "))
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
    for (col in c("data_source", "brutzeitcode_filter")) {
      row[[col]] <- blankToNA(row[[col]])
    }
    row$predictor_mode <- if (!nzchar(row$predictor_mode)) "table" else row$predictor_mode
    config[[sp]][[sc]] <- row
  }
  config
}

#' Load the per-species predictor-set table (full override, not additive)
#'
#' Each row is ONE predictor for ONE species, placed in whichever scale
#' column(s) it applies to for that species (blank elsewhere on that row,
#' and blank/absent entirely if that species doesn't use it at any scale).
#' Meant to list ALL candidate predictors a species should consider at each
#' scale -- e.g. every one of `covariatePredictorColumns()`'s ~20 land use/
#' cover/DEM names under `habitat`/`landscape`, every one of
#' `bioclimPredictorColumns()`'s 19 bioclim names under `climate` -- so a
#' predictor can be toggled off for a species simply by deleting/blanking
#' its row for that species+scale (or the whole row, if it applies nowhere
#' for that species), letting you compare "with vs. without" directly.
#'
#' This is a FULL override once a species is listed here, same all-or-
#' nothing semantics as the existing `predictorsToUse` parameter (NOT
#' additive on top of collinearity selection) -- see
#' `collinearityCheckGerHabitat()`/`GerLandscape()`/`Europe()`'s
#' `predictorsToUse` argument, which this feeds per-species. A species
#' absent from this file entirely falls through to that scale's normal
#' `runCollinearityCheck`/global `predictorsToUse` default instead.
#'
#' @param path Character. Path to the predictors CSV.
#' @return Nested list `config[[species]][[scale]]`, each a character vector
#'   of predictor names that species uses at that scale. A species/scale
#'   combination with no rows is simply absent from the list.
loadSpeciesPredictorConfig <- function(path) {
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

#' Combine the general config's predictor_mode toggle with the predictor
#' table, producing the final per-species-per-scale predictorsToUse input
#'
#' `speciesConfig_general.csv`'s `predictor_mode` column decides, per
#' species+scale, whether to use `speciesConfig_predictors.csv`'s exact list
#' (`"table"`, the default) or ignore it entirely and let
#' `runCollinearityCheck` pick automatically from ALL available covariates,
#' dropping super-collinear ones the normal way (`"auto"`). This function
#' applies that toggle: a species+scale marked `"auto"` is DROPPED from the
#' result regardless of what `speciesConfig_predictors.csv` lists for it, so
#' it falls through to `collinearityCheckGerHabitat()`/`GerLandscape()`/
#' `Europe()`'s normal `runCollinearityCheck` behavior -- exactly the same
#' path an unlisted species already takes.
#'
#' @param generalConfig Return value of `loadSpeciesGeneralConfig()`.
#' @param predictorConfig Return value of `loadSpeciesPredictorConfig()`.
#' @return Nested list `config[[species]][[scale]]`, filtered to only
#'   `"table"`-mode species+scale combinations -- pass this (not
#'   `predictorConfig` directly) as inputs_Monitor's `perSpeciesPredictors`.
resolvePerSpeciesPredictors <- function(generalConfig, predictorConfig) {
  if (is.null(generalConfig) || is.null(predictorConfig)) return(predictorConfig)

  result <- list()
  for (sp in names(predictorConfig)) {
    for (sc in names(predictorConfig[[sp]])) {
      mode <- generalConfig[[sp]][[sc]]$predictor_mode
      if (is.null(mode) || identical(mode, "table")) {
        result[[sp]][[sc]] <- predictorConfig[[sp]][[sc]]
      }
      # "auto": deliberately omitted -- falls through to runCollinearityCheck.
    }
  }
  result
}
