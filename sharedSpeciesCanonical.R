################### CANONICAL SPECIES ROSTER + NAME LOOKUP
# ONE canonical source for (1) which species the pipeline runs and (2) the
# Latin<->German name mapping the raw MhB/DDA files need -- see
# speciesCanonical.csv at the repo root. Replaces two previously separate,
# manually-synced things that had no validation tying them together:
# sharedConfig.R's old hardcoded `sharedSpecies` vector, and
# dataPrep_Monitor's old speciesLookup() data.frame. That split is exactly
# why adding Anthus pratensis to one (sharedConfig.R, 2026-09-24) didn't
# update the other (speciesLookup(), a completely different file) --
# nothing checked they still agreed, so it silently produced 0 presences
# at habitat/landscape scale for weeks until caught live during a test run
# (2026-09-26).

#' Load the canonical species roster + name lookup table
#'
#' @param path Character. Path to speciesCanonical.csv.
#' @return data.frame with columns `latin_name`, `english_name`,
#'   `german_name`, `euring_code` (numeric, the standardized EURING species
#'   code -- e.g. useful for cross-referencing against DDA's own `EURING`
#'   column, or any future data source keyed by it rather than a name),
#'   `include` ("X" or blank), one row per species this project has ever
#'   tracked (not just currently-included ones -- see
#'   `canonicalIncludedSpecies()` to get just the active roster).
loadSpeciesCanonical <- function(path) {
  df <- utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character")

  requiredCols <- c("latin_name", "english_name", "german_name", "euring_code", "include")
  missingCols <- setdiff(requiredCols, names(df))
  if (length(missingCols) > 0) {
    stop("speciesCanonical.csv is missing column(s): ", paste(missingCols, collapse = ", "))
  }

  dupes <- unique(df$latin_name[duplicated(df$latin_name)])
  if (length(dupes) > 0) {
    stop("speciesCanonical.csv has duplicate latin_name value(s): ", paste(dupes, collapse = ", "))
  }

  badInclude <- unique(df$include[!df$include %in% c("", "X")])
  if (length(badInclude) > 0) {
    stop("speciesCanonical.csv's include column has invalid value(s): ",
         paste(badInclude, collapse = ", "), " -- must be \"X\" or blank.")
  }

  missingGerman <- df$latin_name[df$include == "X" & !nzchar(df$german_name)]
  if (length(missingGerman) > 0) {
    stop("speciesCanonical.csv: species included (include = \"X\") but missing a ",
         "german_name -- landscape scale (occurrencePrepGerLandscape()) cannot run ",
         "without one, since the raw DDA data has no Latin-name column at all: ",
         paste(missingGerman, collapse = ", "))
  }

  badEuring <- df$latin_name[nzchar(df$euring_code) & is.na(suppressWarnings(as.numeric(df$euring_code)))]
  if (length(badEuring) > 0) {
    stop("speciesCanonical.csv has non-numeric euring_code value(s) for: ",
         paste(badEuring, collapse = ", "))
  }
  df$euring_code <- suppressWarnings(as.numeric(df$euring_code))

  df
}

#' The currently-active species roster (replaces the old hardcoded
#' `sharedSpecies` vector)
#'
#' @param canonical Return value of `loadSpeciesCanonical()`.
#' @return Character vector of Latin names where `include == "X"`.
canonicalIncludedSpecies <- function(canonical) {
  canonical$latin_name[canonical$include == "X"]
}

#' Latin -> German name mapping for a set of species (replaces the old
#' `speciesLookup()`)
#'
#' @param canonical Return value of `loadSpeciesCanonical()`.
#' @param species Character vector of Latin names to look up (typically the
#'   subset of the roster a given run actually covers).
#' @return Named character vector, `species` -> german_name, in the same
#'   order as `species`. Errors immediately (rather than silently dropping
#'   the species, which is exactly what caused the original bug) if any
#'   requested species has no entry, or an entry with a blank german_name,
#'   in `canonical`.
canonicalGermanNames <- function(canonical, species) {
  missing <- setdiff(species, canonical$latin_name)
  if (length(missing) > 0) {
    stop("canonicalGermanNames(): these species are not in speciesCanonical.csv at all: ",
         paste(missing, collapse = ", "))
  }
  result <- stats::setNames(canonical$german_name[match(species, canonical$latin_name)], species)
  blank <- names(result)[!nzchar(result)]
  if (length(blank) > 0) {
    stop("canonicalGermanNames(): these species have no german_name in speciesCanonical.csv: ",
         paste(blank, collapse = ", "))
  }
  result
}
