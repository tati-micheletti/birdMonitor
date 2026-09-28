################### PER-SPECIES/SCALE CONFIGURATION
# Loaders for the two CSVs that hold per-species, per-scale settings and
# candidate-predictor extensions -- see speciesConfig_general.csv and
# speciesConfig_predictors.csv at the repo root. Two separate files
# (general config vs. predictors), NOT one combined table: general config
# is exactly 3 rows per species (one per scale: climate/landscape/habitat),
# while predictors is a variable number of rows per species (one per extra
# predictor being added for that species), so cramming both into one wide
# table conflates two different things with two different shapes.
#
# Governing principle (2026-09-28): these CSVs hold "ecological" decisions
# -- predictors, data origin/source, scales/resolution, which species are
# included, per-species evidence filters, the spatial-term opt-in.
# "Technical" decisions about how the optimizer/algorithm itself behaves
# (a BRT's one-time cold-start learning rate, which predictor-selection
# algorithm to run) live as simple module-level constants instead -- see
# DECISIONS.md's 2026-09-28 entry for the full rationale (`brt_start_lr`
# and `predictor_mode` were both removed from this file's columns for
# exactly this reason).

#' Load the per-species, per-scale general config table
#'
#' One row per species per scale -- EXACTLY 3 rows per species
#' (climate/landscape/habitat). Columns beyond species/scale:
#' `resolution_m` (wired -- see `extractResolutionConfig()` below),
#' `data_source` (a real, validated value -- see below; wired, feeds
#' `perSpeciesDataSource` in dataPrep_Monitor), `thinning_dist_m` (wired --
#' feeds `perSpeciesThinDist` in dataPrep_Monitor), `brutzeitcode_filter`
#' (wired -- feeds `brutzeitcodeFilter` in dataPrep_Monitor; blank = no
#' filter beyond the scale's existing global one; meaningful at habitat
#' scale for any species, and at landscape scale only for MhB-routed
#' species -- the raw MhB CSV's actual column is `ATLAS_CODE`, e.g.
#' "C11a"/"C12" for confirmed breeding, NOT literally "Brutzeitcode"; a
#' filter value here is matched as a PREFIX, e.g. "C" keeps every code
#' starting with C), `spatial_term` (wired -- see below).
#'
#' `hedges_treatment` is deliberately NOT a column here -- it's already
#' unconditionally included as a candidate predictor in code
#' (`covariatePredictorColumns()`); per-species hedges inclusion goes
#' entirely through `speciesConfig_predictors.csv` (list "hedges" for
#' whichever species should get it).
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
#' `spatial_term` ("X" or blank): whether that species+scale gets
#' projected x/y coordinates added as an extra BRT predictor (a spatial
#' trend-surface term -- NOT a formal random effect, see DECISIONS.md's
#' 2026-09-26 entries). Deliberately scoped to individual species+scale
#' rather than applied blanket-wide, since it can just as easily hurt a
#' model (overfitting to historical geography, reduced transportability
#' to future climate-scale predictions, diluted variable-importance
#' interpretation) as help it -- see DECISIONS.md. Blank is a deliberate,
#' valid "no spatial term" decision for most species, not a gap -- no
#' validation flags it.
#'
#' @param path Character. Path to the general-config CSV.
#' @return Nested list `config[[species]][[scale]]`, each a named list of
#'   the row's other columns (numeric columns coerced, blanks as NA).
loadSpeciesGeneralConfig <- function(path) {
  df <- utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character")

  requiredCols <- c("species", "scale", "resolution_m", "data_source",
                     "thinning_dist_m", "brutzeitcode_filter", "spatial_term")
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

  validDataSources <- c("EBBA2/CHELSA", "MhB point counts", "DDA territories")
  badSources <- setdiff(unique(df$data_source[nzchar(df$data_source)]), validDataSources)
  if (length(badSources) > 0) {
    stop("speciesConfig_general.csv has invalid data_source value(s): ",
         paste(badSources, collapse = ", "), " -- must be one of: ",
         paste(validDataSources, collapse = ", "))
  }

  badSpatialTerm <- unique(df$spatial_term[!df$spatial_term %in% c("", "X")])
  if (length(badSpatialTerm) > 0) {
    stop("speciesConfig_general.csv's spatial_term column has invalid value(s): ",
         paste(badSpatialTerm, collapse = ", "), " -- must be \"X\" or blank.")
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

  numericCols <- c("resolution_m", "thinning_dist_m")
  blankToNA <- function(x) if (!nzchar(trimws(x))) NA_character_ else x

  config <- list()
  for (i in seq_len(nrow(df))) {
    sp <- df$species[i]
    sc <- df$scale[i]
    row <- as.list(df[i, setdiff(names(df), c("species", "scale"))])
    for (col in numericCols) {
      raw <- blankToNA(row[[col]])
      # Strip thousands-separator commas and surrounding whitespace before
      # parsing (e.g. " 100,000 ") -- as.numeric() doesn't understand comma
      # separators at all and silently returns NA for them, which would
      # otherwise silently fall back to that scale's shared default
      # thinning distance instead of erroring -- exactly the kind of silent
      # config/code mismatch that caused the original speciesLookup() bug
      # (see DECISIONS.md). Loud failure here instead: if the ORIGINAL
      # value was non-blank but still fails to parse as a number after
      # stripping commas, that's a real typo, not a legitimate blank.
      cleaned <- if (is.na(raw)) NA_character_ else gsub(",", "", trimws(raw))
      parsed <- suppressWarnings(as.numeric(cleaned))
      if (!is.na(raw) && is.na(parsed)) {
        stop("speciesConfig_general.csv: ", sp, " (", sc, ") has a non-numeric ",
             "value in column '", col, "': \"", raw, "\"")
      }
      row[[col]] <- parsed
    }
    for (col in c("data_source", "brutzeitcode_filter")) {
      row[[col]] <- blankToNA(row[[col]])
    }
    row$spatial_term <- identical(row$spatial_term, "X")
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
#' This is the ONLY source of a species' candidate predictors -- passed as
#' `collinearityCheckGerHabitat()`/`GerLandscape()`/`Europe()`'s
#' `speciesPredictorTable` argument. A species absent from this file is a
#' hard error at collinearityCheck time, not a silent fallback.
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

#' Pull the spatial_term column out of the general config, per species+scale
#'
#' `collinearityCheckGerHabitat()`/`GerLandscape()`/`Europe()`'s
#' `spatialTermSpecies` argument takes exactly this shape (species -> scale
#' -> TRUE/FALSE) directly -- this just reshapes `loadSpeciesGeneralConfig()`'s
#' richer per-scale settings down to the one field those functions actually
#' need.
#'
#' @param generalConfig Return value of `loadSpeciesGeneralConfig()`, or NULL.
#' @return Nested list `config[[species]][[scale]]` -> TRUE/FALSE, or NULL
#'   if `generalConfig` is NULL.
extractSpatialTermSpecies <- function(generalConfig) {
  if (is.null(generalConfig)) return(NULL)
  lapply(generalConfig, function(sp) lapply(sp, function(scaleRow) scaleRow$spatial_term))
}

#' Pull the resolution_m column out of the general config, per species+scale
#'
#' @param generalConfig Return value of `loadSpeciesGeneralConfig()`, or NULL.
#' @return Nested list `config[[species]][[scale]]` -> numeric resolution
#'   (metres), or NA if that species+scale left it blank (falls back to
#'   that scale's shared default resolution -- see `runMe.R`'s
#'   `distinctResolutions()`). NULL if `generalConfig` is NULL.
extractResolutionConfig <- function(generalConfig) {
  if (is.null(generalConfig)) return(NULL)
  lapply(generalConfig, function(sp) lapply(sp, function(scaleRow) scaleRow$resolution_m))
}
