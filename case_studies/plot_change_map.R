# CASE STUDIES (not part of the workflow). JUST the map "Germany: where the change is clear" (regional index change since 2005, 10 km cells).
#   Rscript case_studies/plot_change_map.R --tif <change tif> [--out map.png] [--area <areas_3035.gpkg>:<layer>] [--lim 15] [--all-cells] [--title "..."]
# Examples (from the repo root):
#   Rscript case_studies/plot_change_map.R --tif outputs_downloaded/v3_2026-11-14/regional/change_farmland.tif --out map_only/change_2025_farmland.png
#   Rscript case_studies/plot_change_map.R --tif outputs_downloaded/v3_2026-11-14/regional/change2023_farmland.tif --out map_only/change_2023_farmland.png --area outputs_downloaded/v3_2026-11-14/regional/areas_3035.gpkg:Schorfheide
# --tif   a regional_index_10km_unc_change_vsBaseline.tif (layers deltaMean, deltaLwr, deltaUpr, ...), e.g. /data/birds/viz2/msi_regional_change_farmland/ or a case_studies/regional_change_to_year.R result
# --area  optional outline to draw (a GeoPackage layer made by case_studies/build_areas.R); --all-cells colours every cell instead of only the clear ones; --lim = colour range, index points (default 15)
suppressMessages(library(terra))
args <- commandArgs(trailingOnly = TRUE)
getArg <- function(flag, default = NULL) { i <- which(args == flag); if (length(i)) args[i + 1] else default }
tif <- getArg("--tif", "outputs_downloaded/v3_2026-11-14/regional/change_farmland.tif"); out <- getArg("--out", "change_map.png"); lim <- as.numeric(getArg("--lim", 15)); allCells <- "--all-cells" %in% args
title <- getArg("--title", "Change of the regional bird index since 2005 (index points)"); area <- getArg("--area", NULL)
dir.create(dirname(out), showWarnings = FALSE, recursive = TRUE)
ch <- rast(tif)
clear <- ch[["deltaLwr"]] > 0 | ch[["deltaUpr"]] < 0                                  # the 90% interval (5th-95th percentile over the 25 replicates) excludes zero
shown <- if (allCells) ch[["deltaMean"]] else ifel(clear, ch[["deltaMean"]], NA)
ger0 <- project(unwrap(readRDS("inputs/predictors/raw/gadm/gadm/gadm41_DEU_0_pk.rds")), crs(ch)); ger1 <- project(unwrap(readRDS("inputs/predictors/raw/gadm/gadm/gadm41_DEU_1_pk.rds")), crs(ch))
pal <- colorRampPalette(c("#67001f", "#d6604d", "#fddbc7", "#f7f7f7", "#d1e5f0", "#4393c3", "#053061"))(101)       # red = decline, blue = increase, symmetric around 0
png(out, width = 1300, height = 1600, res = 200, type = "cairo"); par(mar = c(0.5, 0.5, 3, 5))
plot(ch[["deltaMean"]] * 0, col = "grey88", legend = FALSE, axes = FALSE, mar = c(0.5, 0.5, 3, 5), main = title, cex.main = 1)    # grey = cell inside Germany, no clear change
plot(clamp(shown, -lim, lim), col = pal, range = c(-lim, lim), add = TRUE, legend = TRUE, plg = list(title = "points", cex = 0.8))
lines(ger1, col = "grey55", lwd = 0.4); lines(ger0, col = "grey20", lwd = 0.8)
if (!is.null(area)) { p <- strsplit(area, ":", fixed = TRUE)[[1]]; lines(vect(p[1], layer = p[2]), col = "black", lwd = 3) }
if (!allCells) legend("topleft", "grey: no clear change\n(90% interval includes zero)", fill = "grey88", bty = "n", cex = 0.7)
mtext(sprintf("%s. %d of %d cells inside Germany show a clear change.", basename(tif), sum(values(clear), na.rm = TRUE), sum(!is.na(values(ch[["deltaMean"]])))), side = 1, line = -1, cex = 0.55, col = "grey30")
dev.off(); message("written: ", out)
