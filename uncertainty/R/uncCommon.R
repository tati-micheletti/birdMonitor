#' Shared helpers for the uncertainty workflow (option B: spatial-block bootstrap of the BRTs)
#'
#' Plan, decisions and the exact method: improvements.md item 15, uncertainty/README.md and
#' DECISIONS.md (2026-10-06). Everything here is plain R (no SpaDES session): the tasks read the
#' finished baseline outputs (model_ready tables, main BRTs, covariates) and write ONLY under
#' outputs/<runName>/uncertainty/. Nothing in the baseline run is touched.

#' Source the baseline-module functions the uncertainty code re-uses unchanged
#'
#' Re-using the module's own loaders (not copies) guarantees the replicate predictions are built from the
#' exact same covariate stacks as the main maps.
#'
#' @param repoRoot Character. Repo root.
uncSourceDeps <- function(repoRoot) {
  files <- c("modules/models_Monitor/R/stableSeed.R", "modules/models_Monitor/R/scaleLabel.R", "modules/models_Monitor/R/metamodelLabel.R",
             "modules/models_Monitor/R/corineYearMap.R", "modules/models_Monitor/R/corineYear.R",
             "modules/models_Monitor/R/combineLayersSafely.R",
             "modules/models_Monitor/R/loadCovariates.R", "modules/models_Monitor/R/loadHabitatCovariates.R",
             "modules/models_Monitor/R/resolveResolutionM.R", "modules/models_Monitor/R/resolveScalePredictionYears.R",
             "modules/inputs_Monitor/R/determineBlockSize.R")
  for (f in files) source(file.path(repoRoot, f), local = FALSE)
  invisible(TRUE)
}

#' Read an environment variable with a default
uncEnv <- function(name, default = "") {
  v <- Sys.getenv(name, "")
  if (nzchar(v)) v else default
}

#' "1:50" -> 1:50 ; "7" -> 7
uncParseRange <- function(x) {
  p <- as.integer(strsplit(x, ":", fixed = TRUE)[[1]])
  if (length(p) == 1) p else p[1]:p[2]
}

#' "2005,2020:2025" -> c(2005, 2020:2025)
uncParseYears <- function(x) {
  parts <- strsplit(x, ",", fixed = TRUE)[[1]]
  sort(unique(unlist(lapply(trimws(parts), uncParseRange))))
}

#' Label of a replicate run, e.g. reps_001-050 (a later top-up run is e.g. reps_051-100)
uncRepLabel <- function(ids) sprintf("reps_%03d-%03d", min(ids), max(ids))

#' Run `expr` under a fixed RNG seed and restore the caller's RNG state afterwards
#'
#' So that seeding a replicate never changes the random numbers of whatever code runs next.
uncWithSeed <- function(seed, expr) {
  hadSeed <- exists(".Random.seed", envir = globalenv(), inherits = FALSE)
  if (hadSeed) oldSeed <- get(".Random.seed", envir = globalenv(), inherits = FALSE)
  on.exit({
    if (hadSeed) assign(".Random.seed", oldSeed, envir = globalenv())
    else if (exists(".Random.seed", envir = globalenv(), inherits = FALSE)) rm(".Random.seed", envir = globalenv())
  }, add = TRUE)
  set.seed(seed)
  force(expr)
}

#' Seed for the attempt-th redraw of a replicate (kept in the int range)
uncAttemptSeed <- function(seed, attempt) as.integer((as.numeric(seed) + attempt * 1000003) %% 2147483629 + 1)

#' Short git hashes of the repo and its submodules (for the replicate log)
uncGitInfo <- function(repoRoot) {
  one <- function(dir) tryCatch(system2("git", c("-C", shQuote(dir), "rev-parse", "--short", "HEAD"),
                                        stdout = TRUE, stderr = FALSE)[1], error = function(e) NA_character_,
                                warning = function(w) NA_character_)
  mods <- c("dataPrep_Monitor", "inputs_Monitor", "models_Monitor", "runIndex_Monitor")
  paste(c(paste0("root=", one(repoRoot)),
          paste0(mods, "=", vapply(mods, function(m) one(file.path(repoRoot, "modules", m)), character(1)))),
        collapse = ";")
}

#' Configuration of one uncertainty task (from the shared config files + environment variables)
#'
#' Environment variables (all optional):
#'   BIRDMONITOR_RUNNAME          run folder of the baseline (default test4)
#'   BIRDMONITOR_UNC_TAG          optional: write to outputs/<run>/uncertainty_<tag>/ (timing and test runs)
#'   BIRDMONITOR_UNC_REPS         replicate ids of THIS run, e.g. 0:50 (default), later 51:100 to add replicates.
#'                                Id 0 = "replicate 0": the main models, no resampling. It is a built-in consistency
#'                                check against the baseline maps and is excluded from every interval.
#'   BIRDMONITOR_UNC_YEARS        years to map, e.g. 2005,2020:2025 (default: all prediction years)
#'   BIRDMONITOR_UNC_BANDS        number of horizontal bands the country is cut into (default 16)
#'   BIRDMONITOR_UNC_REPBATCH     replicates held in memory at once (default 10)
#'   BIRDMONITOR_UNC_CORES        cores for forked prediction (default SLURM_CPUS_PER_TASK or 1)
#'   BIRDMONITOR_UNC_BASELINE     baseline year of the index (default 2005, as runIndex_Monitor; only change it for tests)
#'   BIRDMONITOR_UNC_BLOCKMULT    multiplier on the resampling block size (default 1; sensitivity test)
#'   BIRDMONITOR_UNC_PROBS        interval percentiles (default 0.05,0.95 = 90% interval)
#'
#' @param repoRoot Character. Repo root (also the working directory: the shared config files use relative paths).
uncCfg <- function(repoRoot = getwd()) {
  setwd(repoRoot)
  uncSourceDeps(repoRoot)
  env <- new.env(parent = globalenv())
  sys.source("tools/sharedConfig.R", envir = env)
  sys.source("tools/sharedSpeciesConfig.R", envir = env)
  gen <- if (file.exists("data/speciesConfig_general.csv")) env$loadSpeciesGeneralConfig("data/speciesConfig_general.csv") else NULL
  resolutionConfig <- env$extractResolutionConfig(gen)
  habitatYearsConfig <- env$extractYearsConfig(gen)

  reps <- uncParseRange(uncEnv("BIRDMONITOR_UNC_REPS", "0:50"))
  outYears <- if (nzchar(uncEnv("BIRDMONITOR_UNC_YEARS"))) uncParseYears(uncEnv("BIRDMONITOR_UNC_YEARS")) else env$predictionYears
  cores <- as.integer(uncEnv("BIRDMONITOR_UNC_CORES", Sys.getenv("SLURM_CPUS_PER_TASK", "1")))
  if (.Platform$OS.type == "windows") cores <- 1L

  list(
    repoRoot = normalizePath(repoRoot, winslash = "/"),
    runName = uncEnv("BIRDMONITOR_RUNNAME", "test4"),
    tag = uncEnv("BIRDMONITOR_UNC_TAG", ""),
    species = env$sharedSpecies,
    outYears = outYears,
    predictionYears = env$predictionYears,
    baselineYear = as.integer(uncEnv("BIRDMONITOR_UNC_BASELINE", "2005")),
    currentYear = max(env$sharedHabitatYears),
    habitatYearsOf = function(sp) env$resolveYearsPerSpecies(sp, "habitat", habitatYearsConfig, env$sharedHabitatYears)[[sp]],
    resOf = function(sp) c(climate = resolveResolutionM(sp, "climate", resolutionConfig, env$sharedClimateResolutionM),
                           landscape = resolveResolutionM(sp, "landscape", resolutionConfig, env$sharedLandscapeResolutionM),
                           habitat = resolveResolutionM(sp, "habitat", resolutionConfig, env$sharedHabitatResolutionM)),
    climateWindowLength = env$sharedClimateWindowLength,
    sharedRes = c(europe = env$sharedClimateResolutionM, habitat = env$sharedHabitatResolutionM, landscape = env$sharedLandscapeResolutionM),
    reps = reps, repLabel = uncRepLabel(reps),
    nBands = as.integer(uncEnv("BIRDMONITOR_UNC_BANDS", "16")),
    repBatch = as.integer(uncEnv("BIRDMONITOR_UNC_REPBATCH", "10")),
    cores = max(1L, cores),
    blockMult = as.numeric(uncEnv("BIRDMONITOR_UNC_BLOCKMULT", "1")),
    probs = as.numeric(strsplit(uncEnv("BIRDMONITOR_UNC_PROBS", "0.05,0.95"), ",")[[1]])
  )
}

# ---- paths ----------------------------------------------------------------------------------------------

.uncModelSuffix <- c(climate = "EU", landscape = "landscape", habitat = "habitat")

#' Root of all uncertainty outputs of this run (BIRDMONITOR_UNC_TAG=timing gives a separate "uncertainty_timing" folder
#' for test runs, so they can never mix with the real replicates)
uncRoot <- function(cfg) file.path(cfg$repoRoot, "outputs", cfg$runName, paste0("uncertainty", if (nzchar(cfg$tag)) paste0("_", cfg$tag) else ""))

#' Per-species output folder (created)
uncSpDir <- function(cfg, sp, ...) {
  d <- file.path(uncRoot(cfg), gsub(" ", "_", sp), ...)
  dir.create(d, recursive = TRUE, showWarnings = FALSE)
  d
}

#' Folder with the baseline outputs of one scale (main BRT, predictions)
uncMainDir <- function(cfg, sp, scaleKey) file.path(cfg$repoRoot, "outputs", cfg$runName, scaleLabel(cfg$resOf(sp)[[scaleKey]]))

#' The baseline's main BRT of one species and scale
uncMainModel <- function(cfg, sp, scaleKey) {
  f <- file.path(uncMainDir(cfg, sp, scaleKey), paste0(gsub(" ", "_", sp), "_BRT_", .uncModelSuffix[[scaleKey]], ".rds"))
  if (!file.exists(f)) stop("Main BRT missing: ", f, " (has the baseline model array run for this species/scale?)")
  readRDS(f)
}

#' The model-ready training table of one species and scale (inputs_Monitor output)
uncTrainingTable <- function(cfg, sp, scaleKey) {
  f <- file.path(cfg$repoRoot, "inputs", "model_ready", scaleLabel(cfg$resOf(sp)[[scaleKey]]),
                 paste0(gsub(" ", "_", sp), "_inputs.rds"))
  if (!file.exists(f)) stop("Training table missing: ", f)
  readRDS(f)
}

#' Habitat covariate cache file (all layers of one year, written once by uncCovcache())
uncCovcacheFile <- function(cfg, sp, year) {
  lab <- scaleLabel(cfg$resOf(sp)[["habitat"]])
  file.path(cfg$repoRoot, "outputs", cfg$runName, "uncertainty", "covcache", lab, paste0("habitat_", year, ".tif"))   # shared by all tags
}

#' Years for which coarse (climate/landscape) predictions and the habitat cache are needed
uncAllYears <- function(cfg, sp) sort(unique(c(cfg$outYears, cfg$habitatYearsOf(sp))))

# ---- spatial windows -----------------------------------------------------------------------------------

#' The country window on the 200 m reference grid, cut into `nBands` horizontal bands
#'
#' The reference grid is the static solar-radiation raster the baseline meta-model resamples every scale onto;
#' the bands partition ITS cells, so every output cell belongs to exactly one band.
#'
#' @return List: `window` (template SpatRaster of the whole window), `bands` (list of per-band
#'   templates, each with `$ext`), `res`.
uncBands <- function(cfg, sp) {
  firstYear <- uncAllYears(cfg, sp)[1]
  cov1 <- terra::rast(uncCovcacheFile(cfg, sp, firstYear))
  habLab <- scaleLabel(cfg$resOf(sp)[["habitat"]])
  ref <- terra::rast(file.path(cfg$repoRoot, "inputs", "predictors", "processed", habLab,
                               paste0("solar_radiation_habitat_", habLab, ".tif")))
  win <- terra::crop(ref, terra::ext(cov1), snap = "out")
  win <- terra::rast(win)                       # geometry only
  nr <- terra::nrow(win); r <- terra::res(win)
  edges <- unique(round(seq(0, nr, length.out = cfg$nBands + 1)))
  bands <- lapply(seq_len(length(edges) - 1), function(k) {
    r1 <- edges[k] + 1; r2 <- edges[k + 1]
    ymaxB <- terra::ymax(win) - (r1 - 1) * r[2]; yminB <- terra::ymax(win) - r2 * r[2]
    tmpl <- terra::rast(xmin = terra::xmin(win), xmax = terra::xmax(win), ymin = yminB, ymax = ymaxB,
                        resolution = r, crs = terra::crs(win))
    list(k = k, rows = c(r1, r2), template = tmpl)
  })
  list(window = win, bands = bands, res = r)
}

# ---- bootstrap pieces -----------------------------------------------------------------------------------

#' Resampling-block id of every training row (square grid of `blockSizeM`, anchored at 0)
uncBlockIds <- function(x, y, blockSizeM) paste(floor(x / blockSizeM), floor(y / blockSizeM), sep = "_")

#' Row indices of one block-bootstrap draw
#'
#' Draws as many blocks as there are blocks, with replacement; all rows of a drawn block enter (a block drawn
#' twice contributes its rows twice). A draw lacking presences or absences is redrawn (deterministically).
#'
#' @return Integer row indices; attributes `attempts` and `nBlocks`.
uncRowIndex <- function(blockIds, occurrence, seed, minPerClass = 10, maxAttempts = 50) {
  rowsByBlock <- split(seq_along(blockIds), blockIds)
  nBlocks <- length(rowsByBlock)
  for (attempt in 0:(maxAttempts - 1)) {
    idx <- uncWithSeed(uncAttemptSeed(seed, attempt),
                       unlist(rowsByBlock[sample.int(nBlocks, nBlocks, replace = TRUE)], use.names = FALSE))
    if (sum(occurrence[idx] == 1) >= minPerClass && sum(occurrence[idx] == 0) >= minPerClass)
      return(structure(idx, attempts = attempt + 1L, nBlocks = nBlocks))
  }
  stop("uncRowIndex(): no usable draw after ", maxAttempts, " attempts (too few blocks/records?).")
}

#' Refit a BRT on a bootstrap sample with the main fit's FIXED hyperparameters
#'
#' @param spPa data.frame with `occurrence` and the predictors.
#' @param predSel Character. Predictor columns.
#' @param brtM The main `gbm.step()` model (tree count, learning rate, bag fraction and tree complexity are read from it).
#' @param idx Integer row indices of the draw.
#' @return A `gbm` fitted with `keep.data = FALSE` (small).
uncFitBRT <- function(spPa, predSel, brtM, idx) {
  d <- spPa[idx, c("occurrence", predSel), drop = FALSE]
  gbm::gbm(formula = occurrence ~ ., distribution = "bernoulli", data = d,
           n.trees = brtM$gbm.call$best.trees, shrinkage = brtM$gbm.call$learning.rate,
           bag.fraction = brtM$gbm.call$bag.fraction, interaction.depth = brtM$gbm.call$tree.complexity,
           weights = rep(1, nrow(d)), verbose = FALSE, keep.data = FALSE)
}

#' Predict many gbm models on one data.frame (forked over models) -> matrix cells x models
uncPredictMany <- function(models, df, nTrees, cores = 1L) {
  one <- function(m) gbm::predict.gbm(m, df, n.trees = nTrees, type = "response")
  res <- if (cores > 1L && length(models) > 1L) parallel::mclapply(models, one, mc.cores = min(cores, length(models))) else lapply(models, one)
  bad <- vapply(res, function(r) inherits(r, "try-error") || is.null(r), logical(1))
  if (any(bad)) stop("uncPredictMany(): prediction failed in ", sum(bad), " of ", length(models), " models.")
  do.call(cbind, res)
}

#' Complete-case cells of a covariate stack as a data.frame (same selection as predictBRTToRaster())
#'
#' @param covStack SpatRaster.
#' @param predictors Character. Predictor columns (may include "x","y", which come from the cell coordinates).
#' @param keepCells Optional integer vector of cell numbers: only these cells are considered.
#' @return List: `df` (complete cells), `idx` (their cell numbers in `covStack`).
uncCells <- function(covStack, predictors, keepCells = NULL) {
  rasterPredictors <- setdiff(predictors, c("x", "y"))
  predRast <- covStack[[rasterPredictors]]
  if (is.null(keepCells)) {
    predDf <- as.data.frame(predRast, xy = TRUE, na.rm = FALSE)
    cellIds <- seq_len(nrow(predDf))
  } else {
    cellIds <- sort(unique(keepCells[!is.na(keepCells)]))
    predDf <- cbind(as.data.frame(terra::xyFromCell(predRast, cellIds)), terra::extract(predRast, cellIds))
  }
  complete <- stats::complete.cases(predDf[, predictors, drop = FALSE])
  list(df = predDf[complete, predictors, drop = FALSE], idx = cellIds[complete])
}

#' Row/column-neighbourhood (+-`reach` cells) of a set of cells, as cell numbers
uncNeighbourCells <- function(r, cells, reach = 2L) {
  cells <- cells[!is.na(cells)]
  if (!length(cells)) return(integer(0))
  rc <- terra::rowColFromCell(r, cells)
  nr <- terra::nrow(r); nc <- terra::ncol(r)
  out <- lapply(-reach:reach, function(dr) lapply(-reach:reach, function(dc) {
    rr <- rc[, 1] + dr; cc <- rc[, 2] + dc
    ok <- rr >= 1 & rr <= nr & cc >= 1 & cc <= nc
    terra::cellFromRowCol(r, rr[ok], cc[ok])
  }))
  sort(unique(unlist(out)))
}
