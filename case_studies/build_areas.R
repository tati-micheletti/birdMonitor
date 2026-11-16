# CASE STUDIES (not part of the workflow). Step 0: the areas of the two case studies, as polygons in EPSG:3035.
#   Rscript case_studies/build_areas.R [--data <folder with trend_all.tif>] [--out <areas file>]
# Layers written to the GeoPackage:
#   Schorfheide          the Biosphere Reserve Schorfheide-Chorin, official outline as published in OpenStreetMap (relation 215277, 1,291.8 km2 = the official 1,292 km2)
#   Muensterland         3 x 3 cells of the 10 km regional grid around 7.70 E, 52.05 N (30 x 30 km, ALIGNED with the grid cells of the regional index; Muensterland has no official outline)
#   control_Schorfheide  Brandenburg without the reserve (GADM level 1)
#   control_Muensterland North Rhine-Westphalia without the block
suppressMessages(library(terra))
args <- commandArgs(trailingOnly = TRUE)
getArg <- function(flag, default = NULL) { i <- which(args == flag); if (length(i)) args[i + 1] else default }
dat <- getArg("--data", "outputs_downloaded/v3_2026-11-14/regional"); outFile <- getArg("--out", file.path(dat, "areas_3035.gpkg"))
reserve <- project(vect("case_studies/data/schorfheide_chorin_reserve_osm_R215277.geojson")[1], "EPSG:3035"); reserve <- aggregate(reserve)
grid <- rast(file.path(dat, "trend_all.tif"))[[1]]                                    # the 10 km grid of the regional index
ctr <- crds(project(vect(cbind(7.70, 52.05), crs = "EPSG:4326"), "EPSG:3035")); e0 <- as.vector(ext(grid)); if (!(ctr[1] >= e0[1] && ctr[1] <= e0[2])) ctr <- ctr[, 2:1, drop = FALSE]
rc <- rowColFromCell(grid, cellFromXY(grid, ctr)); h <- res(grid)[1] / 2
xmin <- xFromCol(grid, rc[2] - 1) - h; xmax <- xFromCol(grid, rc[2] + 1) + h; ymin <- yFromRow(grid, rc[1] + 1) - h; ymax <- yFromRow(grid, rc[1] - 1) + h
block <- as.polygons(ext(xmin, xmax, ymin, ymax), crs = "EPSG:3035")
ger1 <- project(unwrap(readRDS("inputs/predictors/raw/gadm/gadm/gadm41_DEU_1_pk.rds")), "EPSG:3035")
bb <- ger1[ger1$NAME_1 == "Brandenburg"]; nrw <- ger1[ger1$NAME_1 == "Nordrhein-Westfalen"]
lay <- list(Schorfheide = reserve, Muensterland = block, control_Schorfheide = erase(aggregate(bb), reserve), control_Muensterland = erase(aggregate(nrw), block))
first <- TRUE; for (k in names(lay)) { v <- lay[[k]]; values(v) <- data.frame(name = k); writeVector(v, outFile, layer = k, overwrite = first, insert = !first); first <- FALSE }
cat(sprintf("%-22s %8.1f km2\n", names(lay), sapply(lay, function(v) expanse(v, unit = "km"))), sep = ""); cat("block corners (EPSG:3035):", xmin, xmax, ymin, ymax, "\nwritten:", outFile, "\n")
