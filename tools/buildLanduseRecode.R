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
windowMode <- getArg("--window", "germany")      # 2026-11-06: "germany" = sample points INSIDE the German outline and keep points where both products have no data (the recode is applied to every cell of Germany); "bbox" = the old fit (points with a value in at least one product)
rawDir <- file.path("inputs", "predictors", "raw", "landuse")
for (f in c("landuseCategoriesCTM.R", "landuseCategoriesHCTM.R")) source(file.path("modules", "dataPrep_Monitor", "R", f))
inv <- function(l) { d <- do.call(rbind, lapply(names(l), function(n) data.frame(code = l[[n]], cat = n))); setNames(d$cat, d$code) }
iC <- inv(landuseCategoriesCTM()); iH <- inv(landuseCategoriesHCTM())
cats <- c(names(landuseCategoriesCTM()), "other")                                                   # COLUMNS (HCTM classes); HCTM has no "hedges" (its column is simply never filled)
rcats <- if (windowMode == "germany") c(names(landuseCategoriesCTM()), "other_mapped", "nodata") else cats      # ROWS (CTM): 2026-11-06 "other" is split: CTM mapped but not one of our classes / CTM has no data (outside its mask)
say <- function(...) cat(format(Sys.time(), "%H:%M:%S"), ..., "\n")
ctmFile <- function(y) file.path(rawDir, sprintf("CTM_GER_%d_rst_v202_COG.tif", y)); hctmFile <- function(y) file.path(rawDir, sprintf("HCTM_GER_%d_rst_v101_COG.tif", y))
say("sampling", nPoints, "points on the CTM grid of", allYears[1])
xy <- terra::spatSample(terra::rast(ctmFile(allYears[1])), size = nPoints, method = "regular", xy = TRUE, values = FALSE)
if (windowMode == "germany") {                                                              # 2026-11-06
  for (f in c("laeaAnalytic.R", "studyArea.R")) source(file.path("modules", "dataPrep_Monitor", "R", f))
  area <- buildStudyArea(list(label = "Germany", countries = "DEU"), file.path("inputs", "predictors", "raw", "gadm")); keepPt <- insideStudyArea(xy, area, 0)
  say("points inside the German outline:", sum(keepPt), "of", nrow(xy)); xy <- xy[keepPt, , drop = FALSE]
}
pts <- setNames(lapply(allYears, function(y) {
  say("year", y); ex <- function(f) { z <- terra::extract(terra::rast(f), xy); z[[ncol(z)]] }
  vc <- ex(ctmFile(y)); vh <- ex(hctmFile(y)); cc <- unname(iC[as.character(vc)]); ch <- unname(iH[as.character(vh)]); ch[is.na(ch)] <- "other"
  if (windowMode == "germany") { cc[!is.na(vc) & is.na(cc)] <- "other_mapped"; cc[is.na(vc)] <- "nodata" } else cc[is.na(cc)] <- "other"      # 2026-11-06
  ok <- if (windowMode == "germany") rep(TRUE, length(vc)) else !(is.na(vc) & is.na(vh))                                                                    # inside the German window in at least one product
  data.frame(ctm = factor(cc[ok], rcats), hctm = factor(ch[ok], cats), x = xy[ok, 1], y = xy[ok, 2]) }), allYears)
mat <- function(d) { t <- table(d$ctm, d$hctm) + 1e-9; unclass(t / rowSums(t)) }                    # P[j, k]
bl <- function(d, km) paste(floor(d$x / (km * 1000)), floor(d$y / (km * 1000)))
frac <- function(d, col, km) { tb <- table(bl(d, km), d[[col]]); tb / rowSums(tb) }
validate <- function(d, Pm, y, km = 5) {
  fc <- frac(d, "ctm", km); fh <- frac(d, "hctm", km)[rownames(fc), , drop = FALSE]; fr <- fc %*% Pm; colnames(fr) <- cats
  fcR <- if (windowMode == "germany") cbind(fc[, setdiff(colnames(fc), c("other_mapped", "nodata")), drop = FALSE], other = fc[, "other_mapped"] + fc[, "nodata"]) else fc      # 2026-11-06: raw CTM compared by HCTM class names
  w <- as.vector(table(bl(d, km))[rownames(fc)]); w <- w / sum(w); r <- function(a, b) suppressWarnings(round(cor(a, b), 3)); rm <- function(a, b) round(100 * sqrt(sum(w * (a - b)^2)), 2)
  data.frame(testYear = y, class = cats, hctmSharePct = round(100 * colSums(fh * w), 2), ctmRawSharePct = round(100 * colSums(fcR * w), 2), ctmRecodedSharePct = round(100 * colSums(fr * w), 2),
             blockCorrRaw = sapply(cats, function(k) r(fcR[, k], fh[, k])), blockCorrRecoded = sapply(cats, function(k) r(fr[, k], fh[, k])),
             blockRmseRawPP = sapply(cats, function(k) rm(fcR[, k], fh[, k])), blockRmseRecodedPP = sapply(cats, function(k) rm(fr[, k], fh[, k])), fitYears = paste(range(fitYears), collapse = "-")) }
Pfit <- mat(do.call(rbind, pts[as.character(fitYears)]))
val <- do.call(rbind, lapply(testYears, function(y) validate(pts[[as.character(y)]], Pfit, y)))
Pall <- mat(do.call(rbind, pts))
dir.create(outDir, showWarnings = FALSE, recursive = TRUE)
write.csv(data.frame(from_ctm_class = rownames(Pall), round(Pall, 6), check.names = FALSE), file.path(outDir, "landuseRecodeCTMtoHCTM.csv"), row.names = FALSE)
write.csv(val, file.path(outDir, "landuseRecodeCTMtoHCTM_validation.csv"), row.names = FALSE)
say("same-class agreement (share of each CTM class that HCTM maps to the same class):"); print(round(sapply(cats, function(k) if (k %in% rownames(Pall)) Pall[k, k] else NA_real_), 2))      # 2026-11-06: rows and columns differ now
say("validation (fit", paste(range(fitYears), collapse = "-"), ", test", paste(range(testYears), collapse = "-"), "), national shares in %:"); print(val[val$class %in% c("grassland", "winter_cereals", "maize", "fallow", "orchards_and_berries"), 1:5], row.names = FALSE)
say("written:", file.path(outDir, "landuseRecodeCTMtoHCTM.csv"), "and", file.path(outDir, "landuseRecodeCTMtoHCTM_validation.csv"))

# ---- 2026-11-06: does the recode, APPLIED the way computeLanduse() applies it, continue the HCTM series? CTM v302 2024 vs HCTM 2023 (and 2021), points inside Germany. The matrix in data/ (as applied now: every cell without CTM class = "other") against the new one. ----
if (windowMode == "germany") {
  ev <- function(f) { z <- terra::extract(terra::rast(f), xy); z[[ncol(z)]] }
  c24 <- ev(file.path(rawDir, "CTM_GER_2024_rst_v302_COG.tif")); h23 <- ev(file.path(rawDir, "HCTM_GER_2023_rst_v101_COG.tif")); h21 <- ev(file.path(rawDir, "HCTM_GER_2021_rst_v101_COG.tif"))
  r24 <- unname(iC[as.character(c24)]); r24[!is.na(c24) & is.na(r24)] <- "other_mapped"; r24[is.na(c24)] <- "nodata"
  shNew <- colSums(Pall[r24, ]) / length(r24)
  Pold <- as.matrix(read.csv(file.path("data", "landuseRecodeCTMtoHCTM.csv"), row.names = 1, check.names = FALSE)); rOld <- ifelse(r24 %in% c("other_mapped", "nodata"), "other", r24); shOld <- colSums(Pold[rOld, ]) / length(rOld)
  hsh <- function(v) { a <- unname(iH[as.character(v)]); a[is.na(a)] <- "other"; as.vector(prop.table(table(factor(a, cats)))) }
  raw <- as.vector(prop.table(table(factor(ifelse(r24 %in% c("other_mapped", "nodata"), "other", r24), cats))))
  tab <- data.frame(class = cats, HCTM_2021 = round(100 * hsh(h21), 2), HCTM_2023 = round(100 * hsh(h23), 2), CTM_v302_2024_raw = round(100 * raw, 2), recoded_CURRENT_matrix = round(100 * shOld[cats], 2), recoded_NEW_matrix = round(100 * shNew[cats], 2))
  tab$NEW_over_HCTM2023 <- round(tab$recoded_NEW_matrix / tab$HCTM_2023, 2); tab$CURRENT_over_HCTM2023 <- round(tab$recoded_CURRENT_matrix / tab$HCTM_2023, 2); tab$HCTM2023_over_2021 <- round(tab$HCTM_2023 / tab$HCTM_2021, 2)
  options(width = 250); say("national shares in % of the points inside Germany (the processed layers are shares of the whole cell, so these are comparable to their country means):"); print(tab, row.names = FALSE)
  major <- tab$class %in% c("grassland", "winter_cereals", "other");   # the rule of the continuity check (cluster/eve_landuse_check.sbatch); the other classes change by 10-25% between HCTM years themselves (column HCTM2023_over_2021)
   bad <- tab$class[major & abs(tab$NEW_over_HCTM2023 - 1) > 0.10]; badOld <- tab$class[major & abs(tab$CURRENT_over_HCTM2023 - 1) > 0.10]
  say("VERDICT new matrix:", if (length(bad)) paste("FAIL, more than 10% from HCTM 2023:", paste(bad, collapse = ", ")) else "PASS (grassland, winter_cereals and other within 10% of HCTM 2023)", "| current matrix, as applied now:", if (length(badOld)) paste("FAIL:", paste(badOld, collapse = ", ")) else "PASS")
  write.csv(tab, file.path(outDir, "landuseRecode_application_test.csv"), row.names = FALSE)
}
