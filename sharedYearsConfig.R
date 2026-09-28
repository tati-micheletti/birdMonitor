################### SHARED YEAR-DEPENDENCY HELPERS
# Small, reusable helpers for the fitting-years/prediction-years split (see
# DECISIONS.md's 2026-09-28 "Decouple fitting years from prediction years"
# entry). Mirrors sharedSpeciesConfig.R's pattern: sourced once by runMe.R
# and tools/runClusterTask.R, not module-owned.

#' Extra reference years the hedges-backfill logic structurally needs
#'
#' `loadCovariates()`/`occurrencePrepGerHabitat()`'s hedges-backfill rule
#' hardcodes reference years (2017 for any requested year <= 2016; 2021 for
#' any requested year in `c(2022, 2023)`) and unconditionally tries to open
#' that reference year's landuse file. If a restricted `landuseYears` set
#' doesn't already include those reference years, that lookup errors on a
#' file that was never generated. This computes which reference years must
#' ALSO be generated -- they never need to appear as a predictable year
#' anywhere downstream, only as a raster-generation year.
#'
#' @param years Integer vector. The years actually being requested (fitting
#'   and/or prediction years, already unioned by the caller).
#' @return Integer vector, 0-2 extra reference years to add to that union.
computeHedgesBackfillYears <- function(years) {
  extra <- integer(0)
  if (any(years <= 2016)) extra <- c(extra, 2017L)
  if (any(years %in% c(2022, 2023))) extra <- c(extra, 2021L)
  extra
}

#' Warn (not error) if a year vector falls outside a known real-data range
#'
#' Used for `sharedHabitatYears`/`sharedLandscapeYears`, whose real
#' bounds are set by actual survey data availability, not a modeler
#' choice -- a year outside that range produces zero training rows (or,
#' worse, garbage if data happens to exist there by coincidence). A
#' `warning()`, not `stop()`, so a deliberate edge-case test isn't blocked.
#'
#' @param years Integer vector. The years actually configured.
#' @param validRange Integer vector. The known real-data range, e.g. `2022:2025`.
#' @param label Character. Name of the setting being checked, for the message.
#' @return Invisible NULL. Called for its `warning()` side effect.
warnIfOutsideRealDataRange <- function(years, validRange, label) {
  outside <- setdiff(years, validRange)
  if (length(outside) > 0) {
    warning(label, " includes year(s) outside the real-data range (",
            min(validRange), "-", max(validRange), "): ",
            paste(outside, collapse = ", "),
            " -- these will produce zero training rows (or garbage, if data ",
            "happens to exist there by coincidence).", call. = FALSE)
  }
  invisible(NULL)
}
