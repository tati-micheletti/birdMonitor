# The model values at the survey routes (DDA territory-mapping plots), every year.  READ-ONLY: writes one CSV and nothing else.
#   Rscript tools/modelAtRoutes.R ["Vanellus vanellus,Alauda arvensis"] [--ens ens_brt-glm-gam-rf-nn] [--years 2005:2025] [--out outputs/<run>/diagnostics/model_at_routes.csv]
# Run name: BIRDMONITOR_RUNNAME (default test4). Without a species list, the roster (data/speciesCanonical.csv, column include) is used.
#
# Why: the comparison "observed against modelled index" (S9 of tools/makeResultFigures.R) uses the area mean of ALL of Germany, while the observed series come from a
# changing set of survey routes (305 in 2006, about 1,400 later). Here the ensemble maps are read at the routes themselves, in every year, so that the observed and the
# modelled series can be built from the same routes and years (the comparison itself is made on the PC, with the S9 estimator, from this CSV).
#
# One row per species x route x year:
#   landscape  ensemble map of the landscape scale (1 km), value of the cell of the route centre
#   climate    ensemble map of the climate scale (50 km), value of the cell of the route centre
#   habitat    ensemble map of the habitat scale (200 m), mean over the 1 km square of the route (the 25 cells of 200 m around the centre)
#   meta       ensemble meta-model map (200 m, the final product), mean over the same 1 km square
# Routes: ROUTENCODE, x, y (EPSG:3035) from the landscape training tables of the species that were trained on the DDA territory data (the point-count species Common Buzzard and
# Common Starling have other sites in their landscape tables and are skipped for the route list but still evaluated at the DDA routes).
args <- commandArgs(trailingOnly = TRUE)
getArg <- function(flag, default = NULL) { i <- which(args == flag); if (length(i)) args[i + 1] else default }
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
suppressMessages({ library(terra) })
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
ensName <- getArg("--ens", "ens_brt-glm-gam-rf-nn")
yrSpec <- getArg("--years", "2005:2025")
years <- sort(unique(unlist(lapply(trimws(strsplit(yrSpec, ",")[[1]]), function(p) { q <- as.integer(strsplit(p, ":", fixed = TRUE)[[1]]); if (length(q) == 1) q else q[1]:q[2] }))))
outFile <- getArg("--out", file.path("outputs", runName, "diagnostics", "model_at_routes.csv"))
canon <- read.csv("data/speciesCanonical.csv", stringsAsFactors = FALSE, fileEncoding = "UTF-8")
spList <- if (length(args) && !startsWith(args[1], "--")) trimws(strsplit(args[1], ",")[[1]]) else canon$latin_name[nzchar(trimws(canon$include))]
say <- function(...) cat(format(Sys.time(), "%H:%M:%S"), ..., "\n", sep = " ")
say("=== modelAtRoutes | run", runName, "| ensemble", ensName, "|", length(spList), "species |", length(years), "years")

# ---- the routes: ROUTENCODE, x, y of every route that is in a DDA-territory landscape training table --------------------------------------------------------------
routes <- do.call(rbind, lapply(spList, function(sp) {
  tr <- tryCatch(uncTrainingTable(cfg, sp, "landscape"), error = function(e) NULL)
  if (is.null(tr) || !all(c("ROUTENCODE", "x", "y") %in% names(tr))) return(NULL)
  unique(data.frame(ROUTENCODE = tolower(as.character(tr$ROUTENCODE)), x = tr$x, y = tr$y, stringsAsFactors = FALSE)) }))
routes <- unique(routes); routes <- routes[!duplicated(routes$ROUTENCODE), ]
if (is.null(routes) || !nrow(routes)) stop("no route coordinates found in the landscape training tables")
say("routes:", nrow(routes))
n <- nrow(routes)
sq <- cbind(geom = rep(seq_len(n), each = 5), part = 1,                                                   # the 1 km square around every route centre
            x = as.vector(rbind(routes$x - 500, routes$x + 500, routes$x + 500, routes$x - 500, routes$x - 500)),
            y = as.vector(rbind(routes$y - 500, routes$y - 500, routes$y + 500, routes$y + 500, routes$y - 500)), hole = 0)
squares <- terra::vect(sq, type = "polygons", crs = "EPSG:3035")
centres <- terra::vect(cbind(routes$x, routes$y), crs = "EPSG:3035")

atPoint  <- function(f) { if (!file.exists(f)) return(rep(NA_real_, n)); r <- terra::rast(f)[[1]]; v <- terra::extract(r, centres); v[[ncol(v)]] }
atSquare <- function(f) { if (!file.exists(f)) return(rep(NA_real_, n)); r <- terra::rast(f)[[1]]; v <- terra::extract(r, squares, fun = mean, na.rm = TRUE); v[[ncol(v)]] }

res <- list(); nMissing <- 0L
for (sp in spList) {
  spClean <- gsub(" ", "_", sp); say("--", sp)
  ensMap <- function(scale, yr) file.path(uncMainDir(cfg, sp, scale), sprintf("%s_pred_%s_%s_%d.tif", spClean, ensName, scale, yr))
  metaMap <- function(yr) file.path(cfg$outputRoot, paste0(metamodelLabel(cfg$sharedRes), "_", ensName), sprintf("%s_meta_suitability_%d.tif", spClean, yr))
  for (yr in years) {
    fs <- c(ensMap("landscape", yr), ensMap("climate", yr), ensMap("habitat", yr), metaMap(yr)); nMissing <- nMissing + sum(!file.exists(fs))
    res[[length(res) + 1]] <- data.frame(species = sp, ROUTENCODE = routes$ROUTENCODE, x = routes$x, y = routes$y, year = yr,
      landscape = atPoint(fs[1]), climate = atPoint(fs[2]), habitat = atSquare(fs[3]), meta = atSquare(fs[4]), stringsAsFactors = FALSE)
  }
}
out <- do.call(rbind, res)
dir.create(dirname(outFile), recursive = TRUE, showWarnings = FALSE)
write.csv(out, outFile, row.names = FALSE)
say("=== done:", nrow(out), "rows |", nMissing, "map files missing |", outFile)
if (nMissing) say("NOTE: rows of missing maps are NA")
if (nzchar(Sys.getenv("UNC_DONE_MARKER"))) file.create(Sys.getenv("UNC_DONE_MARKER"))
