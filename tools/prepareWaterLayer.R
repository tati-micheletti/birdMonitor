# Prepares the WATER LAYER for the mask of the Monitor maps (connector_Monitor; DECISIONS 2026-11-05, improvements.md item 26). One-off, run where the file is made, then copy the result to inputs/ on EVE.
#   Rscript tools/prepareWaterLayer.R [--in inputs/predictors/raw/water/hotosm_deu_waterways_osm_shp/extracted/waterways_polygons.shp] [--out inputs/predictors/raw/water/water_bodies.gpkg]
# INPUT: OpenStreetMap water polygons of Germany from the HOT/oex export (hotosm_deu_waterways_osm_shp.zip, https://data.humdata.org/dataset/hotosm_deu_waterways, ODbL, snapshot 2026-10-09). Unzip only
#   waterways_polygons.* into its own folder (the zip also holds 1.8 million lines and 20,000 points that this step does not use).
# KEPT: natural = water (lakes, ponds, reservoirs, basins, river and canal areas, ...) and waterway polygons riverbank / dock / canal / river.
# NOT KEPT: natural = wetland (85,000 polygons: marsh and reed are bird habitat, the model is meant to predict there), natural = bay (marine), covered or tunnelled water, and water = fountain, reflecting_pool, pool, weir, lock,
#   fish_pass, groundwater (not surface water). Lines (small streams) are not used: only the share of a map cell that is covered by water polygons counts (connector_Monitor, waterMinShare).
# OUTPUT: a GeoPackage in EPSG:3035 (columns kind, water) and a text report next to it (what was kept and dropped, area). Nothing in the input is changed.
suppressMessages(library(terra))
args <- commandArgs(trailingOnly = TRUE); getArg <- function(k, d) { i <- match(k, args); if (is.na(i) || i == length(args)) d else args[i + 1] }
shp <- getArg("--in", "inputs/predictors/raw/water/hotosm_deu_waterways_osm_shp/extracted/waterways_polygons.shp"); out <- getArg("--out", "inputs/predictors/raw/water/water_bodies.gpkg")
stopifnot(file.exists(shp)); lyr <- tools::file_path_sans_ext(basename(shp)); rep <- character(); say <- function(...) { m <- paste0(...); message(m); rep <<- c(rep, m) }
say("water layer from ", normalizePath(shp, winslash = "/"), " (", format(file.size(shp) / 1e6, digits = 4), " MB), ", format(Sys.time(), "%Y-%m-%d %H:%M"))
t0 <- Sys.time()
v <- terra::vect(shp, query = sprintf("SELECT waterway, natural_cl, water, covered, tunnel FROM %s WHERE natural_cl = 'water' OR waterway IN ('riverbank', 'dock', 'canal', 'river')", lyr))
d <- as.data.frame(v); nIn <- nrow(d); say("candidate polygons (natural = water, or waterway riverbank/dock/canal/river): ", nIn, " (read in ", format(round(difftime(Sys.time(), t0, units = "mins"), 1)), " min)")
isTrue <- function(x) !is.na(x) & nzchar(x) & !x %in% "no"
notWater <- c("fountain", "reflecting_pool", "pool", "weir", "lock", "fish_pass", "groundwater")
drop <- isTrue(d$covered) | isTrue(d$tunnel) | d$water %in% notWater
say("dropped: covered or tunnelled ", sum(isTrue(d$covered) | isTrue(d$tunnel)), "; water = ", paste(notWater, collapse = "/"), " ", sum(d$water %in% notWater), "; total dropped ", sum(drop))
v <- v[!drop]; d <- d[!drop, , drop = FALSE]
v$kind <- ifelse(d$natural_cl == "water", "natural=water", "waterway polygon"); v <- v[, c("kind", "water")]
bad <- !terra::is.valid(v); say("invalid geometries repaired: ", sum(bad))
if (any(bad)) v <- rbind(v[!bad], terra::makeValid(v[bad]))
v <- terra::project(v, "EPSG:3035")
a <- terra::expanse(v, unit = "km"); say("kept: ", nrow(v), " polygons, ", format(round(sum(a)), big.mark = ","), " km2 (the polygons also include waters just outside the border; compare with an independent figure before quoting it)")
tab <- sort(table(ifelse(is.na(v$water) | !nzchar(v$water), "(no subtype)", v$water)), decreasing = TRUE); say("by type: ", paste0(names(tab)[1:min(12, length(tab))], " ", tab[1:min(12, length(tab))], collapse = "; "))
dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)
terra::writeVector(v, out, overwrite = TRUE)
say("written: ", out, " (", format(file.size(out) / 1e6, digits = 4), " MB); total ", format(round(difftime(Sys.time(), t0, units = "mins"), 1)), " min")
writeLines(rep, paste0(sub("[.]gpkg$", "", out), "_report.txt"))
