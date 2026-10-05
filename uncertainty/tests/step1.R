# Local test, step 1: config + covariate cache + replicate fits + coarse predictions (Buteo buteo, test1 outputs)
Sys.setenv(BIRDMONITOR_RUNNAME = "utest", BIRDMONITOR_SPECIES = "Alauda arvensis", BIRDMONITOR_UNC_REPS = "0:3",
           BIRDMONITOR_UNC_YEARS = "2020:2025", BIRDMONITOR_UNC_BANDS = "40")
suppressMessages({library(terra); library(gbm); library(glmnet)})
for (f in list.files("uncertainty/R", full.names = TRUE)) source(f)
cfg <- uncCfg(getwd())
sp <- cfg$species
cat("species:", sp, "| habitatYears:", cfg$habitatYearsOf(sp), "| res:", cfg$resOf(sp), "| outYears:", cfg$outYears, "\n")
cat("years needing cache:", uncAllYears(cfg, sp), "\n")
t0 <- Sys.time(); uncCovcache(cfg); cat("covcache secs:", round(difftime(Sys.time(), t0, units = "secs")), "\n")
t0 <- Sys.time(); uncFitSpecies(cfg, sp); cat("fit secs:", round(difftime(Sys.time(), t0, units = "secs")), "\n")
t0 <- Sys.time(); uncCoarseSpecies(cfg, sp); cat("coarse secs:", round(difftime(Sys.time(), t0, units = "secs")), "\n")
