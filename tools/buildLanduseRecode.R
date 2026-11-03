# Recode table CTM -> HCTM classes, fitted where the two crop type maps overlap (2017-2021), and its validation. READ-ONLY on the raw maps; writes two small CSV files.
#   Rscript tools/buildLanduseRecode.R [--points 2500000] [--fit-years 2017:2019] [--test-years 2020:2021] [--out-dir data]
# Why: the land-use layers of a run were a patchwork of two products (HCTM <= 2016, CTM v202 2017-2021, HCTM 2022-2023, CTM v302 2024-2025) that do not map the same
# area the same way (HCTM maps about 6 percentage points more grassland, 6 times more orchards, 1.8 times more fallow), which made the grassland share jump in 2017, 2022 and 2024.
# New rule (modules/dataPrep_Monitor/R/computeLanduse.R): HCTM for every year it exists (<= 2023); the CTM maps are used only where HCTM does not exist (2024-2025), and
# there the CTM class shares of each cell are turned into the shares HCTM would have mapped, with the matrix written here.
#
# Matrix: P[j, k] = share of the cells that CTM puts in class j and HCTM puts in class k (all points inside the German window, regular sample of the CTM grid, the years pooled).
# "other" = not mapped to one of our classes (also outside the mask of a product). Output 1: data/landuseRecodeCTMtoHCTM.csv (fitted on ALL overlap years, used by the pipeline);
# output 2: data/landuseRecodeCTMtoHCTM_validation.csv (fitted on --fit-years, checked on --test-years: national shares and, in 5 km blocks, correlation and error with and without the recode).
args <- commandArgs(trailingOnly = TRUE)
getArg <- function(flag, default = NULL) { i <- which(args == flag); if (length(i)) args[i + 1] else default }
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
suppressMessages(library(terra))
yrs <- function(s) { q <- as.integer(strsplit(s, ":", fixed = TRUE)[[1]]); if (length(q) == 1) q else q[1]:q[2] }
fitYears <- yrs(getArg("--fit-years", "2017:2019")); testYears <- yrs(getArg("--test-years", "2020:2021")); allYears <- sort(unique(c(fitYears, testYears)))
nPoints <- as.numeric(getArg("--points", 2.5e6)); outDir <- getArg("--out-dir", "data")
rawDir <- file.path("inputs", "predictors", "raw", "landuse")
for (f in c("landuseCategoriesCTM.R", "landuseCategoriesHCTM.R")) source(file.path("modules", "dataPrep_Monitor", "R", f))
inv <- function(l) { d <- do.call(rbind, lapply(names(l), function(n) data.frame(code = l[[n]], cat = n))); setNames(d$cat, d$code) }
iC <- inv(landuseCategoriesCTM()); iH <- inv(landuseCategoriesHCTM())
cats <- c(names(landuseCategoriesCTM()), "other")                                                   # rows and columns; HCTM has no "hedges" (its column is simply never filled)
say <- function(...) cat(format(Sys.time(), "%H:%M:%S"), ..., "\n")
ctmFile <- function(y) file.path(rawDir, sprintf("CTM_GER_%d_rst_v202_COG.tif", y)); hctmFile <- function(y) file.path(rawDir, sprintf("HCTM_GER_%d_rst_v101_COG.tif", y))
say("sampling", nPoints, "points on the CTM grid of", allYears[1])
xy <- terra::spatSample(terra::rast(ctmFile(allYears[1])), size = nPoints, method = "regular", xy = TRUE, values = FALSE)
pts <- setNames(lapply(allYears, function(y) {
  say("year", y); ex <- function(f) { z <- terra::extract(terra::rast(f), xy); z[[ncol(z)]] }
  vc <- ex(ctmFile(y)); vh <- ex(hctmFile(y)); cc <- unname(iC[as.character(vc)]); ch <- unname(iH[as.character(vh)]); cc[is.na(cc)] <- "other"; ch[is.na(ch)] <- "other"
  ok <- !(is.na(vc) & is.na(vh))                                                                    # inside the German window in at least one product
  data.frame(ctm = factor(cc[ok], cats), hctm = factor(ch[ok], cats), x = xy[ok, 1], y = xy[ok, 2]) }), allYears)
mat <- function(d) { t <- table(d$ctm, d$hctm) + 1e-9; unclass(t / rowSums(t)) }                    # P[j, k]
bl <- function(d, km) paste(floor(d$x / (km * 1000)), floor(d$y / (km * 1000)))
frac <- function(d, col, km) { tb <- table(bl(d, km), d[[col]]); tb / rowSums(tb) }
validate <- function(d, Pm, y, km = 5) {
  fc <- frac(d, "ctm", km); fh <- frac(d, "hctm", km)[rownames(fc), , drop = FALSE]; fr <- fc %*% Pm; colnames(fr) <- cats
  w <- as.vector(table(bl(d, km))[rownames(fc)]); w <- w / sum(w); r <- function(a, b) suppressWarnings(round(cor(a, b), 3)); rm <- function(a, b) round(100 * sqrt(sum(w * (a - b)^2)), 2)
  data.frame(testYear = y, class = cats, hctmSharePct = round(100 * colSums(fh * w), 2), ctmRawSharePct = round(100 * colSums(fc * w), 2), ctmRecodedSharePct = round(100 * colSums(fr * w), 2),
             blockCorrRaw = sapply(cats, function(k) r(fc[, k], fh[, k])), blockCorrRecoded = sapply(cats, function(k) r(fr[, k], fh[, k])),
             blockRmseRawPP = sapply(cats, function(k) rm(fc[, k], fh[, k])), blockRmseRecodedPP = sapply(cats, function(k) rm(fr[, k], fh[, k])), fitYears = paste(range(fitYears), collapse = "-")) }
Pfit <- mat(do.call(rbind, pts[as.character(fitYears)]))
val <- do.call(rbind, lapply(testYears, function(y) validate(pts[[as.character(y)]], Pfit, y)))
Pall <- mat(do.call(rbind, pts))
dir.create(outDir, showWarnings = FALSE, recursive = TRUE)
write.csv(data.frame(from_ctm_class = rownames(Pall), round(Pall, 6), check.names = FALSE), file.path(outDir, "landuseRecodeCTMtoHCTM.csv"), row.names = FALSE)
write.csv(val, file.path(outDir, "landuseRecodeCTMtoHCTM_validation.csv"), row.names = FALSE)
say("same-class agreement (share of each CTM class that HCTM maps to the same class):"); print(round(setNames(diag(Pall), rownames(Pall)), 2))
say("validation (fit", paste(range(fitYears), collapse = "-"), ", test", paste(range(testYears), collapse = "-"), "), national shares in %:"); print(val[val$class %in% c("grassland", "winter_cereals", "maize", "fallow", "orchards_and_berries"), 1:5], row.names = FALSE)
say("written:", file.path(outDir, "landuseRecodeCTMtoHCTM.csv"), "and", file.path(outDir, "landuseRecodeCTMtoHCTM_validation.csv"))
