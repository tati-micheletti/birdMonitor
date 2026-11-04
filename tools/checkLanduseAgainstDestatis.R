# Land-use series against Destatis crop areas (audit table row S2-69; 4 November 2026). READ-ONLY. Run from the repository root: Rscript tools/checkLanduseAgainstDestatis.R
# Sums the class areas (thousand ha) of HCTM 2021-2023 and of CTM v202 2021 / v302 2024-2025 (raw and recoded with data/landuseRecodeCTMtoHCTM.csv) over a regular sample of 2.5 million points (about 23.7 ha per point).
# Destatis national areas to compare with (thousand ha; sources: Destatis time series of crop areas, BMEL Erntebericht 2024 Table 1, Deutsches Maiskomitee press release 04/2024):
#   winter cereals (winter wheat + winter barley + rye):  2023 = 4,742 (2,826 + 1,291 + 625)   2024 = about 4,315 (about 2,481 + 1,298 + 535.6)
#   winter rapeseed:  2023 = about 1,155 (back-calculated from -5.8%)   2024 = 1,088.3
#   maize (silage + grain, incl. corn-cob mix):  2023 = 2,466.4   2024 = 2,547.1 (2,048.7 + 498.4)
# Result of 4 November 2026: recoded 2023 -> 2024 change winter cereals -8.4% (Destatis -9.0%), rapeseed -6.7% (-5.8%), maize +13% (+3.3%).
# Class areas (1000 ha) of the land-use maps, for the comparison with Destatis acreage statistics (scratch, read-only on the inputs)
suppressMessages(library(terra))

source("modules/dataPrep_Monitor/R/landuseCategoriesCTM.R"); source("modules/dataPrep_Monitor/R/landuseCategoriesHCTM.R")
inv <- function(l) { d <- do.call(rbind, lapply(names(l), function(n) data.frame(code = l[[n]], cat = n))); setNames(d$cat, d$code) }
iC <- inv(landuseCategoriesCTM()); iH <- inv(landuseCategoriesHCTM())
dir <- "inputs/predictors/raw/landuse"
rc0 <- rast(file.path(dir, "CTM_GER_2017_rst_v202_COG.tif"))
N <- 2.5e6
xy <- spatSample(rc0, size = N, method = "regular", xy = TRUE, values = FALSE)
cellHa <- ncell(rc0) * prod(res(rc0)) / nrow(xy) / 1e4               # hectares represented by one regular sample point
cat("ha per sample point:", round(cellHa, 2), " points:", nrow(xy), "\n")
rec <- read.csv("data/landuseRecodeCTMtoHCTM.csv", check.names = FALSE); Pm <- as.matrix(rec[, -1]); rownames(Pm) <- rec[[1]]; cats <- rownames(Pm)
ex <- function(f) { z <- extract(rast(file.path(dir, f)), xy); z[[ncol(z)]] }
areaH <- function(v) { cc <- unname(iH[as.character(v)]); ok <- !is.na(v); cc[ok & is.na(cc)] <- "other"; cc <- cc[ok]
  a <- as.vector(table(factor(cc, cats))) * cellHa / 1000; setNames(a, cats) }
areaC <- function(v, recode) { cc <- unname(iC[as.character(v)]); ok <- !is.na(v); cc[ok & is.na(cc)] <- "other"; cc <- cc[ok]
  if (recode) colSums(Pm[as.character(factor(cc, cats)), , drop = FALSE]) * cellHa / 1000 else setNames(as.vector(table(factor(cc, cats))) * cellHa / 1000, cats) }
out <- data.frame(cat = cats)
for (y in 2021:2023) out[[paste0("HCTM", y)]] <- areaH(ex(sprintf("HCTM_GER_%d_rst_v101_COG.tif", y)))
out$CTM2021raw <- areaC(ex("CTM_GER_2021_rst_v202_COG.tif"), FALSE)
v24 <- ex("CTM_GER_2024_rst_v302_COG.tif"); v25 <- ex("CTM_GER_2025_rst_v302_2025_08_COG.tif")
out$v302_2024raw <- areaC(v24, FALSE); out$v302_2024rec <- areaC(v24, TRUE)
out$v302_2025raw <- areaC(v25, FALSE); out$v302_2025rec <- areaC(v25, TRUE)
tot <- colSums(out[, -1]); out <- rbind(out, data.frame(cat = "TOTAL mapped (1000 ha)", t(tot)))
options(width = 250); print(cbind(out[1], round(out[-1])), row.names = FALSE)

