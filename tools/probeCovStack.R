# Diagnostic (EVE): run the REAL buildHabitatCovStackOneYear() for one year and report, per layer of the
# resulting stack, how many of a species' bird points get NA. Pinpoints which layer empties the table.
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
suppressMessages(library(terra))
cat("terra", as.character(packageVersion("terra")), "| GDAL/PROJ/GEOS:", paste(unlist(gdal(lib = TRUE)[1, 1:3]), collapse = " / "), "\n")
cat("tempdir:", tempdir(), "\n\n")
a <- commandArgs(trailingOnly = TRUE)
yr <- as.integer(if (length(a) >= 1) a[1] else 2022)
sp <- if (length(a) >= 2) a[2] else "Emberiza_citrinella"
modR <- "modules/dataPrep_Monitor/R"
for (f in c("combineLayersSafely", "corineYear", "corineYearMap", "isCachedNull", "scaleLabel"))
  if (file.exists(file.path(modR, paste0(f, ".R")))) source(file.path(modR, paste0(f, ".R")))
# only the function we need from occurrencePrepGerHabitat.R (the file also defines others; sourcing is fine)
source(file.path(modR, "occurrencePrepGerHabitat.R"))

pts <- as.matrix(readRDS(sprintf("inputs/response/processed/MhB/%s_habitat_%d.rds", sp, yr))[, c("x", "y")])
cat("points:", nrow(pts), "\n")
t0 <- Sys.time()
covStack <- withCallingHandlers(
  buildHabitatCovStackOneYear(yr, "inputs/predictors/processed/scale_02"),
  warning = function(w) { message("WARN: ", conditionMessage(w)); invokeRestart("muffleWarning") })
cat("built in", round(as.numeric(difftime(Sys.time(), t0, units = "secs"))), "s;", nlyr(covStack), "layers; cells:", ncell(covStack), "\n\n")
env <- terra::extract(covStack, pts)
env <- env[, names(env) != "ID", drop = FALSE]
cat(sprintf("%-28s %8s %10s %10s\n", "layer", "NA%", "min", "max"))
for (n in names(env)) {
  v <- env[[n]]
  cat(sprintf("%-28s %7.1f%% %10.3g %10.3g\n", n, 100 * mean(is.na(v)), suppressWarnings(min(v, na.rm = TRUE)), suppressWarnings(max(v, na.rm = TRUE))))
}
nonHedge <- names(covStack)[!grepl("^hedges", names(covStack))]
cat("\ncomplete cases (excluding hedges):", sum(stats::complete.cases(env[, nonHedge])), "of", nrow(env), "\n")
