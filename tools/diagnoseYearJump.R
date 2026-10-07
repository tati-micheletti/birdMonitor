# Why does a species' index jump in the last years?  READ-ONLY diagnostic (writes nothing but a printout and, optionally, a CSV).
#   Rscript tools/diagnoseYearJump.R "Anthus pratensis,Lullula arborea" [--tag honest] [--years 2005,2015,2019:2025] [--top 6]
# Run name: BIRDMONITOR_RUNNAME (default test4).
#
# For every species it prints, in order:
#   A. the country mean (inside Germany) and the number of valid cells of each scale's prediction and of the meta-model, per year
#      -> which scale (climate / landscape / habitat) carries the jump, and does the valid-cell count change?
#   B. the replicate spread of the area mean per year (uncertainty run) -> do ALL replicates drop, or only a few?
#   C. for the most influential predictors of each scale (gbm relative influence): the country mean of the covariate per year, and
#      the share of cells OUTSIDE the range of the training data -> does a covariate change at the jump, does the model extrapolate?
args <- commandArgs(trailingOnly = TRUE)
getArg <- function(flag, default = NULL) { i <- which(args == flag); if (length(i)) args[i + 1] else default }
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
suppressMessages({ library(terra); library(gbm); library(glmnet) })
runName <- if (nzchar(Sys.getenv("BIRDMONITOR_RUNNAME"))) Sys.getenv("BIRDMONITOR_RUNNAME") else "test4"
repoRoot <- normalizePath(getwd(), winslash = "/")
for (f in sort(list.files("modules/models_Monitor/R", pattern = "[.]R$", full.names = TRUE))) source(f)
source("tools/sharedConfig.R"); source("tools/sharedSpeciesConfig.R")
gen <- if (file.exists("data/speciesConfig_general.csv")) loadSpeciesGeneralConfig("data/speciesConfig_general.csv") else NULL
cfg <- uncCfgFromParams(inputRoot = file.path(repoRoot, "inputs"), outputRoot = file.path(repoRoot, "outputs", runName), species = sharedSpecies,
                        predictionYears = predictionYears,
                        habitatYears = resolveYearsPerSpecies(sharedSpecies, "habitat", extractYearsConfig(gen), sharedHabitatYears),
                        resolutionConfig = extractResolutionConfig(gen), climateResolutionM = sharedClimateResolutionM,
                        habitatResolutionM = sharedHabitatResolutionM, landscapeResolutionM = sharedLandscapeResolutionM,
                        climateWindowLength = sharedClimateWindowLength, reps = 1, codeRoot = repoRoot)
spList <- trimws(strsplit(if (length(args) && !startsWith(args[1], "--")) args[1] else "Anthus pratensis,Lullula arborea", ",")[[1]])
tag <- getArg("--tag", "honest"); topN <- as.integer(getArg("--top", 6))
yrSpec <- getArg("--years", "2005,2010,2015,2019:2025")
rng <- function(x) { p <- as.integer(strsplit(x, ":", fixed = TRUE)[[1]]); if (length(p) == 1) p else p[1]:p[2] }
years <- sort(unique(unlist(lapply(trimws(strsplit(yrSpec, ",")[[1]]), rng))))
options(width = 200, digits = 4)

for (sp in spList) {
  spClean <- gsub(" ", "_", sp); res <- cfg$resOf(sp)
  cat("\n", strrep("=", 100), "\n", sp, "\n", strrep("=", 100), "\n", sep = "")
  predFile <- function(scale, yr) switch(scale,
    climate = file.path(uncMainDir(cfg, sp, "climate"), sprintf("%s_pred_EU_%d.tif", spClean, yr)),
    landscape = file.path(uncMainDir(cfg, sp, "landscape"), sprintf("%s_pred_landscape_%d.tif", spClean, yr)),
    habitat = file.path(uncMainDir(cfg, sp, "habitat"), sprintf("%s_pred_habitat_%d.tif", spClean, yr)),
    meta = file.path(cfg$outputRoot, metamodelLabel(cfg$sharedRes), sprintf("%s_meta_suitability_%d.tif", spClean, yr)))
  yr1 <- years[file.exists(predFile("habitat", years))][1]
  win <- terra::ext(terra::rast(predFile("habitat", yr1)))      # the Germany window the habitat predictions cover

  # ---- A. country mean and valid cells per scale and year --------------------------------------------------------------------
  cat("\nA. COUNTRY MEAN of each scale's prediction (inside the Germany window) and number of valid cells\n")
  A <- do.call(rbind, lapply(years, function(yr) {
    one <- function(scale) {
      f <- predFile(scale, yr); if (!file.exists(f)) return(c(NA_real_, NA_real_))
      r <- terra::rast(f)[[1]]; if (scale %in% c("climate", "landscape")) r <- terra::crop(r, win)
      g <- terra::global(r, c("mean", "notNA"), na.rm = TRUE); c(g[1, 1], g[1, 2])
    }
    v <- unlist(lapply(c("climate", "landscape", "habitat", "meta"), one))
    data.frame(year = yr, climate = v[1], landscape = v[3], habitat = v[5], meta = v[7], nValidMeta = v[8], nValidHabitat = v[6])
  }))
  print(A, row.names = FALSE)
  base <- A[A$year == min(A$year), ]
  cat("change relative to", min(A$year), "(%): ", paste(c("climate", "landscape", "habitat", "meta"),
      round(100 * (A[nrow(A), c("climate", "landscape", "habitat", "meta")] / base[c("climate", "landscape", "habitat", "meta")] - 1), 1), collapse = " | "), "\n")

  # ---- B. replicate spread ---------------------------------------------------------------------------------------------------
  amF <- file.path(cfg$outputRoot, paste0("uncertainty", if (nzchar(tag)) paste0("_", tag) else ""), spClean, "area_mean_replicates.csv")
  if (file.exists(amF)) {
    cat("\nB. REPLICATES: area mean per year across replicates (index = 100 x area mean / area mean of", min(A$year), ")\n")
    am <- read.csv(amF); b0 <- am[am$year == min(am$year), c("replicate", "areaMean")]; names(b0)[2] <- "base"
    am <- merge(am, b0, by = "replicate"); am$index <- 100 * am$areaMean / am$base
    B <- do.call(rbind, lapply(split(am, am$year), function(d) data.frame(year = d$year[1], n = nrow(d), min = min(d$index), q05 = quantile(d$index, .05), median = median(d$index),
                                                                         q95 = quantile(d$index, .95), max = max(d$index), nBelow90 = sum(d$index < 90), replicate0 = d$index[d$replicate == 0][1])))
    print(B[B$year %in% years, ], row.names = FALSE)
  } else cat("\nB. (no area_mean_replicates.csv at", amF, ")\n")

  # ---- C. predictors ---------------------------------------------------------------------------------------------------------
  procRoot <- file.path(cfg$inputRoot, "predictors", "processed")
  covOf <- function(scale, yr) {
    lab <- scaleLabel(res[[scale]]); dir <- file.path(procRoot, lab)
    cov <- switch(scale,
      climate = { f <- file.path(dir, paste0("bioclim_", yr - (cfg$climateWindowLength - 1), "-", yr, "_", lab, ".tif")); if (file.exists(f)) terra::rast(f) else NULL },
      landscape = { cv <- loadCovariates(yr, dir, NULL); if (!is.null(cv)) names(cv) <- gsub("_[0-9]{4}$", "", names(cv)); cv },
      habitat = { f <- uncCovcacheFile(cfg, sp, yr); if (file.exists(f)) terra::rast(f) else NULL })
    if (!is.null(cov) && scale != "habitat") cov <- terra::crop(cov, win)
    cov
  }
  for (scale in c("habitat", "landscape", "climate")) {
    m <- tryCatch(uncMainModel(cfg, sp, scale), error = function(e) NULL); if (is.null(m)) next
    imp <- summary(m, n.trees = m$gbm.call$best.trees, plotit = FALSE)
    imp <- imp[!imp$var %in% c("x", "y"), ]; top <- head(as.character(imp$var), topN)
    tr <- uncTrainingTable(cfg, sp, scale)
    cat("\nC. ", toupper(scale), ": top predictors by relative influence: ", paste0(top, " (", round(imp$rel.inf[match(top, imp$var)], 1), "%)", collapse = ", "), "\n", sep = "")
    cat("   COUNTRY MEAN of each predictor per year  |  last column = share of cells OUTSIDE the training range, in the last year\n")
    M <- matrix(NA_real_, length(top), length(years), dimnames = list(top, years)); out <- setNames(rep(NA_real_, length(top)), top)
    for (j in seq_along(years)) {
      cov <- covOf(scale, years[j]); if (is.null(cov)) next
      for (p in intersect(top, names(cov))) {
        M[p, j] <- terra::global(cov[[p]], "mean", na.rm = TRUE)[1, 1]
        if (j == length(years)) { lo <- min(tr[[p]], na.rm = TRUE); hi <- max(tr[[p]], na.rm = TRUE)
          out[p] <- terra::global((cov[[p]] < lo) | (cov[[p]] > hi), "mean", na.rm = TRUE)[1, 1] }
      }
    }
    D <- data.frame(predictor = top, signif(M, 4), outsideTrainingRange = round(out, 4), check.names = FALSE); rownames(D) <- NULL
    print(D, row.names = FALSE)
  }
}
cat("\nHow to read it: a jump in ONE scale's country mean (A) points at that scale; if all replicates drop together (B) the cause is in the inputs,\nif only a few do, the models are unstable there; a predictor whose country mean jumps in the same year (C), or many cells outside the\ntraining range, is the first suspect.\n")
