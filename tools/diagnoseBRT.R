# Why does the BRT of one species and scale fail? Runs the SAME fit the model arrays run, with every warning printed.
#   Rscript tools/diagnoseBRT.R "Vanellus vanellus" climate        (scale: climate | landscape | habitat)
# Light enough for a login node at the climate scale (a few hundred rows); use a compute node for habitat.
options(warn = 1)
args <- commandArgs(trailingOnly = TRUE)
sp <- if (length(args) >= 1) args[1] else "Vanellus vanellus"
scale <- if (length(args) >= 2) args[2] else "climate"
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
suppressMessages({ library(gbm); library(dismo) })
for (f in c("stableSeed", "scaleLabel", "optimizeBRT", "brtLearningRateState", "explDeviance", "fitDevRatio")) source(file.path("modules/models_Monitor/R", paste0(f, ".R")))
source("modules/models_Monitor/R/modelGerLandscape.R")      # fitBRTOneSpecies()
source("tools/sharedSpeciesConfig.R")
spClean <- gsub(" ", "_", sp)
res <- c(climate = 50000, landscape = 1000, habitat = 200)[[scale]]
gen <- if (file.exists("data/speciesConfig_general.csv")) loadSpeciesGeneralConfig("data/speciesConfig_general.csv") else NULL
rc <- extractResolutionConfig(gen)
if (!is.null(rc[[sp]][[scale]]) && !is.na(rc[[sp]][[scale]])) res <- rc[[sp]][[scale]]
dir <- file.path("inputs", "model_ready", scaleLabel(res))
d <- readRDS(file.path(dir, paste0(spClean, "_inputs.rds"))); p <- readRDS(file.path(dir, paste0(spClean, "_predictors.rds")))
cat("\n== DATA ==\nrows:", nrow(d), "| presences:", sum(d$occurrence == 1), "| absences:", sum(d$occurrence == 0), "| predictors:", length(p), "\n")
cat("NA values in predictors:", sum(is.na(d[, p, drop = FALSE])), "| non-finite:", sum(!is.finite(as.matrix(d[, p, drop = FALSE]))), "\n")
cat("constant predictors:", paste(p[vapply(d[, p, drop = FALSE], function(x) length(unique(x)) < 2, logical(1))], collapse = ", "), "\n")
cat("duplicated rows in predictors:", sum(duplicated(d[, p, drop = FALSE])), "\n")
cat("foldID counts:", paste(names(table(d$foldID)), table(d$foldID), sep = ":", collapse = "  "), "\n")
cat("\n== FIT (as the model array does it) ==\n")
for (lr in c(0.01, 0.005, 0.001)) {
  cat("\n-- starting learning rate", lr, "--\n")
  m <- tryCatch(fitBRTOneSpecies(sp, d, p, lr), error = function(e) { cat("ERROR:", conditionMessage(e), "\n"); NULL })
  cat("RESULT:", if (is.null(m)) "gave up (NULL)" else paste("fitted: trees", m$gbm.call$best.trees, "| lr", m$gbm.call$learning.rate), "\n")
  if (!is.null(m)) break
}
