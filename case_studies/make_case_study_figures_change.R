# CASE STUDIES (not part of the workflow). Step 2b, local: the case-study figures with the CHANGE of the regional index (end year vs 2005, index points) instead of its TREND per decade.
#   Rscript case_studies/make_case_study_figures_change.R [--data <folder>] [--out <folder>] [--tiles <cache folder>] [--set farmland|all]
# Writes into its OWN folder (default outputs_downloaded/v3_2026-11-14/case_study_figures_change); the trend figures of make_case_study_figures.R are not touched.
# Needs in --data (default outputs_downloaded/v3_2026-11-14/regional): areas_3035.gpkg, yearly_all/, yearly_farmland/, species_site_year.csv, landuse_site_year.csv, model_response.csv (as for the trend figures), and the change maps
#   change_<set>.tif       = 2025 vs 2005, the pipeline product (outputs/<run>/uncertainty_*/regional*/regional_index_10km_unc_change_vsBaseline.tif)
#   change2023_<set>.tif   = 2023 vs 2005, made with the same pipeline function by case_studies/regional_change_to_year.R (the last year before the new crop map of 2024-2025)
# Per case: 0 outline check on the unfaded OpenStreetMap map (outline + 10 km grid + a few places: for checking only), 1 change map to 2023, 1b change map to 2025, 2 index series, 3 species, 4a crops, 4b model response.
suppressMessages(library(terra))
args <- commandArgs(trailingOnly = TRUE)
getArg <- function(flag, default = NULL) { i <- which(args == flag); if (length(i)) args[i + 1] else default }
dat <- getArg("--data", "outputs_downloaded/v3_2026-11-14/regional"); out <- getArg("--out", "outputs_downloaded/v3_2026-11-14/case_study_figures_change"); cache <- getArg("--tiles", file.path(dat, "tile_cache")); mapSet <- getArg("--set", "farmland")
dir.create(out, recursive = TRUE, showWarnings = FALSE); dir.create(cache, recursive = TRUE, showWarnings = FALSE)
areasFile <- file.path(dat, "areas_3035.gpkg"); lay <- function(l) vect(areasFile, layer = l)
ger0 <- project(unwrap(readRDS("inputs/predictors/raw/gadm/gadm/gadm41_DEU_0_pk.rds")), "EPSG:3035"); ger1 <- project(unwrap(readRDS("inputs/predictors/raw/gadm/gadm/gadm41_DEU_1_pk.rds")), "EPSG:3035")
canon <- read.csv("data/speciesCanonical.csv"); english <- setNames(canon$english_name, gsub(" ", "_", canon$latin_name))
spec <- read.csv(file.path(dat, "species_site_year.csv")); luse <- read.csv(file.path(dat, "landuse_site_year.csv")); resp <- read.csv(file.path(dat, "model_response.csv"))
yrs <- 2005:2025; lim <- 15; last <- 2023                                                 # last year before the new crop map
setName <- if (mapSet == "farmland") "Farmland species (12, without the raptors)" else "All 14 species"
pal <- colorRampPalette(c("#67001f", "#d6604d", "#fddbc7", "#f7f7f7", "#d1e5f0", "#4393c3", "#053061"))(101); palA <- adjustcolor(pal, alpha.f = 0.62)
cases <- list(
  Schorfheide = list(label = "Schorfheide-Chorin Biosphere Reserve (Brandenburg)", sub = "the official outline of the reserve, 1,292 km²", control = "control_Schorfheide", ctlName = "Brandenburg without the reserve", col = "#1b7837", resp = c("Alauda_arvensis", "Emberiza_calandra"),
                     places = data.frame(name = c("Brodowin", "Kloster Chorin", "Parsteiner See", "Eberswalde", "Angermünde", "Prenzlau", "Schwedt/Oder"), lon = c(13.8167, 13.8706, 13.9667, 13.8167, 13.9981, 13.8667, 14.2833), lat = c(52.9167, 52.8786, 52.9667, 52.8333, 53.0167, 53.3167, 53.0667))),
  Muensterland = list(label = "Münsterland (North Rhine-Westphalia)", sub = "3 × 3 cells of the 10 km grid, 900 km²", control = "control_Muensterland", ctlName = "North Rhine-Westphalia without the area", col = "#b2182b", resp = c("Vanellus_vanellus", "Saxicola_rubetra"),
                      places = data.frame(name = c("Münster", "Coesfeld", "Warendorf", "Rheine", "Osnabrück"), lon = c(7.6261, 7.1667, 7.9917, 7.4400, 8.0472), lat = c(51.9607, 51.9500, 51.9567, 52.2800, 52.2800)))
)
fmt <- function(v, d = 1) sprintf(paste0("%+.", d, "f"), v)
newPng <- function(f) png(file.path(out, f), width = 1920, height = 1080, res = 150, type = "cairo")
foot <- function(s) mtext(paste(strwrap(s, width = 215), collapse = "\n"), side = 1, outer = TRUE, line = 1.6, cex = 0.6, col = "grey35", adj = 0.01)
halo <- function(x, y, labels, r, col = "black", ...) { for (dx in c(-1, 0, 1) * r) for (dy in c(-1, 0, 1) * r) text(x + dx, y + dy, labels, col = "white", ...); text(x, y, labels, col = col, ...) }
## base map: OpenStreetMap standard tiles (c) OpenStreetMap contributors, mosaicked and warped to EPSG:3035; pale grey for the maps, unfaded colours for the check figure -----------------------------------------
getBasemap <- function(win, z, pale = TRUE) {
  b <- as.vector(ext(project(as.polygons(win, crs = "EPSG:3035"), "EPSG:4326"))); n <- 2^z
  tx <- function(lon) floor((lon + 180) / 360 * n); ty <- function(lat) { r <- lat * pi / 180; floor((1 - log(tan(r) + 1 / cos(r)) / pi) / 2 * n) }
  size <- 2 * 20037508.342789244 / n; rs <- list()
  for (x in tx(b[1]):tx(b[2])) for (y in ty(b[4]):ty(b[3])) {
    f <- file.path(cache, sprintf("osm_%d_%d_%d.png", z, x, y))
    if (!file.exists(f)) { try(download.file(sprintf("https://tile.openstreetmap.org/%d/%d/%d.png", z, x, y), f, mode = "wb", quiet = TRUE, method = "libcurl", headers = c("User-Agent" = "case-study-research-script/1.0")), silent = TRUE); Sys.sleep(0.2) }
    if (!file.exists(f) || file.size(f) < 100) stop("tile missing: ", f)
    r <- rast(f); if (has.colors(r)) r <- colorize(r, "rgb"); r <- r[[1:3]]; names(r) <- c("red", "green", "blue")
    ext(r) <- c(-20037508.342789244 + x * size, -20037508.342789244 + (x + 1) * size, 20037508.342789244 - (y + 1) * size, 20037508.342789244 - y * size); crs(r) <- "EPSG:3857"; rs[[length(rs) + 1]] <- r }
  m <- do.call(merge, rs)
  if (pale) { lum <- 0.3 * m[[1]] + 0.59 * m[[2]] + 0.11 * m[[3]]; g <- 255 - (255 - lum) * 0.6; m <- c(g, g, g); names(m) <- c("red", "green", "blue") }
  crop(project(m, "EPSG:3035", method = "bilinear"), win)
}
winFor <- function(poly, margin = 20000, aspect = 1.35) { e <- as.vector(ext(poly)); cx <- mean(e[1:2]); cy <- mean(e[3:4]); w <- max(diff(e[1:2]) + 2 * margin, (diff(e[3:4]) + 2 * margin) * aspect); h <- w / aspect; ext(cx - w / 2, cx + w / 2, cy - h / 2, cy + h / 2) }
to3035 <- function(lon, lat) crds(project(vect(cbind(lon, lat), crs = "EPSG:4326"), "EPSG:3035"))
clearOf <- function(r) ifel(r[["deltaLwr"]] > 0 | r[["deltaUpr"]] < 0, r[["deltaMean"]], NA)
numbers <- list()
for (key in names(cases)) {
  cs <- cases[[key]]; col <- cs$col; area <- lay(key); ctl <- lay(cs$control); win <- winFor(area); r1 <- diff(as.vector(win)[1:2]) / 700; grid10 <- rast(file.path(dat, "change_all.tif"))[[1]]
  ## 0. outline check: unfaded base map, the outline, the 10 km grid, a few places (names only here, to check the position) --------------------------------------------------------------------------------------
  bmc <- getBasemap(win, 12, pale = FALSE); newPng(sprintf("%s_0_outline_check.png", key)); par(mar = c(0.5, 0.5, 3, 0.5), oma = c(2, 0, 0, 0))
  plotRGB(bmc, r = 1, g = 2, b = 3, maxcell = 2e7, axes = FALSE, mar = c(0.5, 0.5, 3, 0.5), main = sprintf("Check of the position: %s", cs$label), cex.main = 1.1)
  gc <- crop(grid10, win); lines(as.polygons(gc, dissolve = FALSE), col = adjustcolor("black", 0.45), lwd = 0.8); lines(area, col = "#d7191c", lwd = 4); pl <- to3035(cs$places$lon, cs$places$lat)
  points(pl, pch = 21, bg = "yellow", cex = 1.3); halo(pl[, 1] + 1500, pl[, 2] + 1500, cs$places$name, r1, cex = 0.9, font = 2, adj = c(0, 0))
  mtext(sprintf("Red = %s. Thin black lines = the 10 km cells of the regional index. Yellow dots = places known to lie inside or outside (for checking only). Map: (c) OpenStreetMap contributors (ODbL).", cs$sub), outer = TRUE, side = 1, line = 0.3, cex = 0.7, col = "grey25")
  dev.off()
  ## 1. change maps: Germany + zoom on a pale base map; to 2023 and to 2025 ---------------------------------------------------------------------------------------------------------------------------
  bm <- getBasemap(win, 11); cellTab <- list()
  for (endY in c(2023, 2025)) {
    f <- file.path(dat, if (endY == 2025) sprintf("change_%s.tif", mapSet) else sprintf("change%d_%s.tif", endY, mapSet)); if (!file.exists(f)) { message("missing ", f, ": figure for ", endY, " skipped"); next }; ch <- rast(f)
    newPng(sprintf("%s_%s_location_change_%d.png", key, if (endY == 2023) "1" else "1b", endY)); layout(matrix(1:2, 1), widths = c(1, 1.3)); par(oma = c(3, 0, 4, 0), mar = c(0.5, 0.5, 2, 0.5))
    plot(ch[["deltaMean"]] * 0, col = "grey88", legend = FALSE, axes = FALSE, mar = c(0.5, 0.5, 2, 0.5), main = "Germany: where the change is clear", cex.main = 1.1)
    plot(clamp(clearOf(ch), -lim, lim), col = pal, range = c(-lim, lim), add = TRUE, legend = FALSE); lines(ger1, col = "grey55", lwd = 0.4); lines(ger0, col = "grey20", lwd = 0.8); lines(area, col = "black", lwd = 3)
    par(mar = c(0.5, 0.5, 2, 4.5)); plotRGB(bm, r = 1, g = 2, b = 3, maxcell = 2e7, axes = FALSE, mar = c(0.5, 0.5, 2, 4.5), main = sprintf("Zoom: change of the 10 km cells, %d vs 2005 (index points)", endY), cex.main = 1.1)
    zt <- crop(ch, win); nc <- ifel(is.na(clearOf(zt)) & !is.na(zt[["deltaMean"]]), 1, NA)
    plot(nc, col = adjustcolor("grey80", 0.55), add = TRUE, legend = FALSE); plot(clamp(clearOf(zt), -lim, lim), col = palA, range = c(-lim, lim), add = TRUE, legend = TRUE, plg = list(title = "points", cex = 0.8))
    lines(crop(ger1, win), col = "grey35", lwd = 1); lines(area, col = "black", lwd = 3.5)
    inA <- extract(zt, area, cells = TRUE, xy = TRUE); inA <- inA[!is.na(inA$deltaMean), ]; clr <- inA$deltaLwr > 0 | inA$deltaUpr < 0
    halo(inA$x, inA$y, ifelse(clr, fmt(inA$deltaMean), paste0("(", fmt(inA$deltaMean), ")")), r1, cex = 0.8, font = ifelse(clr, 2, 1), col = ifelse(clr, "black", "grey30"))
    legend("topleft", c("clear change (coloured)", "not clear (grey, in brackets)"), fill = c("#d6604d", adjustcolor("grey80", 0.8)), bty = "n", cex = 0.7, bg = "white")
    mtext(cs$label, outer = TRUE, side = 3, line = 1.6, font = 2, cex = 1.15); mtext(sprintf("Change of the regional bird index, %d vs 2005, %s (black outline = %s; numbers = change of the cells inside)", endY, tolower(setName), cs$sub), outer = TRUE, side = 3, line = 0.2, cex = 0.75, col = "grey25")
    foot(sprintf("Change = index in %d minus index in 2005 (each cell's own 2005 level = 100), in each of 25 replicates; shown = mean; clear = the 5th-95th percentile range of the 25 changes excludes zero. %s Source: birdMonitor run v3. Base map%s: (c) OpenStreetMap contributors (ODbL).",
                endY, if (endY == 2025) "2024-2025 use a different crop map (CTM v302, recoded), so this end year carries that caveat." else "2023 is the last year before the new crop map of 2024-2025.", if (key == "Schorfheide") " and reserve outline" else ""))
    dev.off()
    for (g in c("all", "farmland")) { fg <- file.path(dat, if (endY == 2025) sprintf("change_%s.tif", g) else sprintf("change%d_%s.tif", endY, g)); if (!file.exists(fg)) next; rg <- rast(fg)
      v <- extract(rg, area, ID = FALSE); v <- v[!is.na(v$deltaMean), ]; w <- extract(rg, ctl, ID = FALSE); w <- w[!is.na(w$deltaMean), ]
      cellTab[[length(cellTab) + 1]] <- data.frame(endYear = endY, group = g, cellsInArea = nrow(v), clearUp = sum(v$deltaLwr > 0), clearDown = sum(v$deltaUpr < 0), notClear = sum(v$deltaLwr <= 0 & v$deltaUpr >= 0), meanChangeArea = mean(v$deltaMean),
                                                   meanChangeControl = mean(w$deltaMean), shareControlCellsWorseThanAreaMean = mean(w$deltaMean < mean(v$deltaMean)), controlCells = nrow(w)) }
  }
  cellTab <- do.call(rbind, cellTab)
  ## 2. time series: area, control, Germany; the change to 2023 in the legend -----------------------------------------------------------------------------------------------------------------------------
  ts <- lapply(c(all = "all", farmland = "farmland"), function(g) { r <- rast(file.path(dat, paste0("yearly_", g), sprintf("msi_10km_%d.tif", yrs))); V <- function(poly) { v <- extract(r, poly, ID = FALSE); colMeans(v[complete.cases(v), , drop = FALSE]) }
    data.frame(year = yrs, area = as.numeric(V(area)), control = as.numeric(V(ctl)), germany = as.numeric(global(r, "mean", na.rm = TRUE)[, 1])) })
  newPng(sprintf("%s_2_index_vs_control.png", key)); par(mfrow = c(1, 2), mar = c(4, 4.4, 3, 1), oma = c(3, 0, 4, 0))
  for (g in names(ts)) { d <- ts[[g]]; yl <- range(c(d$area, d$control, d$germany, 100)) + c(-1, 1) * 1.2; h <- d$year <= last
    plot(NA, xlim = range(yrs), ylim = yl, xlab = "Year", ylab = "Regional index (2005 = 100)", las = 1, bty = "l", main = if (g == "all") "All 14 species" else "Farmland species (12, without the raptors)", cex.main = 1.1)
    rect(last + 0.5, yl[1] - 50, 2026, yl[2] + 50, col = adjustcolor("#fdb863", 0.25), border = NA); abline(h = 100, lty = 3, col = "grey40")
    for (nm in c("germany", "control", "area")) { cc <- c(germany = "grey55", control = "black", area = col)[[nm]]; lw <- c(germany = 3, control = 3, area = 4.5)[[nm]]; lt <- c(germany = 1, control = 2, area = 1)[[nm]]
      lines(d$year[h], d[[nm]][h], lwd = lw, col = cc, lty = lt); lines(d$year[d$year >= last], d[[nm]][d$year >= last], lwd = lw, col = adjustcolor(cc, 0.55), lty = 3) }
    ch <- function(nm) d[[nm]][d$year == last] - 100
    legend("topleft", c(sprintf("Area: %s points", fmt(ch("area"))), sprintf("%s: %s", cs$ctlName, fmt(ch("control"))), sprintf("Germany: %s", fmt(ch("germany")))), col = c(col, "black", "grey55"), lwd = c(4.5, 3, 3), lty = c(1, 2, 1), bty = "n", cex = 0.8, title = sprintf("Change 2005 to %d", last), title.adj = 0)
    text(2024.5, yl[1] + 0.09 * diff(yl), "new crop\nmap", cex = 0.65, col = "#8c510a") }
  mtext(sprintf("%s: the area against its state and Germany", cs$label), outer = TRUE, side = 3, line = 1.6, font = 2, cex = 1.15); mtext("Mean regional index of the 10 km cells (relative to each cell's own 2005 level); change = index in 2023 minus 100; 2024-2025 dotted", outer = TRUE, side = 3, line = 0.2, cex = 0.75, col = "grey25")
  foot("Orange band: 2024-2025 use a different crop map (CTM v302, recoded to the classes of the earlier map), so steps in these two years should be read with care. Control = the federal state without the area (not matched for soil or climate). Source: birdMonitor run v3 (/data/birds/viz2/msi_regional_*).")
  dev.off()
  ## 3. species: change of the mean probability of occurrence 2005 to 2023, area against control state (Germany as a tick) -------------------------------------------------------------------------------
  sp <- spec[spec$site %in% c(key, cs$control, "Germany") & spec$year <= last, ]; sp$idx <- ave(sp$meanProb, sp$species, sp$site, FUN = function(v) 100 * v / v[1])
  sl <- do.call(rbind, lapply(split(sp, sp$species), function(x) { f <- function(s) { y <- x[x$site == s, ]; y$idx[y$year == last] - 100 }
    data.frame(species = x$species[1], english = english[[x$species[1]]], area = f(key), control = f(cs$control), germany = f("Germany")) }))
  sl$betterControl <- sl$area > sl$control; sl$betterGermany <- sl$area > sl$germany; sl <- sl[order(sl$area - sl$control), ]; rownames(sl) <- NULL; n <- nrow(sl); yy <- seq_len(n)
  newPng(sprintf("%s_3_species_vs_control.png", key)); par(mar = c(4.2, 11, 1, 1), oma = c(3, 0, 5, 0)); xl <- range(c(sl$area, sl$control, sl$germany, 0), na.rm = TRUE) + c(-1, 1) * 3
  plot(NA, xlim = xl, ylim = c(0.5, n + 0.5), yaxt = "n", ylab = "", xlab = "Change of the species' mean probability of occurrence, 2005 to 2023 (index points, 2005 = 100)", bty = "l", cex.lab = 0.9)
  abline(v = 0, lty = 3, col = "grey40"); segments(sl$control, yy, sl$area, yy, col = ifelse(sl$betterControl, col, "#bdbdbd"), lwd = 2.5)
  points(sl$germany, yy, pch = 18, col = "grey45", cex = 1.4); points(sl$control, yy, pch = 21, bg = "white", col = "black", cex = 1.6); points(sl$area, yy, pch = 21, bg = ifelse(sl$betterControl, col, "grey60"), col = "black", cex = 1.9); axis(2, at = yy, labels = sl$english, las = 1, tick = FALSE, cex.axis = 0.95)
  legend("bottomright", c("Area", cs$ctlName, "Germany", "area better than its state", "area worse than its state"), pch = c(21, 21, 18, NA, NA), pt.bg = c(col, "white", NA, NA, NA), col = c("black", "black", "grey45", col, "#bdbdbd"), lwd = c(NA, NA, NA, 2.5, 2.5), bty = "n", cex = 0.78)
  mtext(sprintf("%s: how each species changes in the area", cs$label), outer = TRUE, side = 3, line = 2.7, font = 2, cex = 1.1)
  mtext(sprintf("%d of %d species change more favourably in the area than in the rest of the state (and %d of %d more favourably than Germany)", sum(sl$betterControl), n, sum(sl$betterGermany), n), outer = TRUE, side = 3, line = 1.1, cex = 0.85, col = "grey20")
  foot("Mean probability of occurrence per species and year (final ensemble maps), set to 100 in 2005; change = value in 2023 minus 100 (2024-2025 left out: different crop map). The model shows direction and relative contrast, not the size of real population change. The state is not matched for soil or climate.")
  dev.off()
  ## 4a. the crops in the area over time (unchanged) -------------------------------------------------------------------------------------------------------------------------------------------------------------
  cls <- c(winter_cereals = "Winter cereals", summer_cereals = "Summer cereals", maize = "Maize", grassland = "Grassland", fallow = "Fallow"); luStat <- list()
  newPng(sprintf("%s_4a_crops_over_time.png", key)); par(mfrow = c(2, 3), mar = c(3.6, 4.4, 2.6, 0.8), oma = c(3, 0, 4, 0))
  for (cl in names(cls)) { g <- function(s) { d <- luse[luse$site == s & luse$class == cl, ]; d[order(d$year), ] }; a <- g(key); b <- g("Germany"); cc <- g(cs$control); yl <- range(c(a$share, b$share, cc$share)) * 100; yl <- yl + c(-1, 1) * 0.08 * diff(yl)
    plot(NA, xlim = range(yrs), ylim = yl, xlab = "", ylab = "Share of the land (%)", las = 1, bty = "l", main = cls[[cl]], cex.main = 1.15); rect(last + 0.5, yl[1] - 50, 2026, yl[2] + 50, col = adjustcolor("#fdb863", 0.25), border = NA)
    lines(b$year, b$share * 100, lwd = 3, col = "grey55"); lines(cc$year, cc$share * 100, lwd = 3, col = "black", lty = 2); lines(a$year, a$share * 100, lwd = 3.5, col = col)
    st <- function(d) 100 * (d$share[d$year == 2024] / d$share[d$year == 2023] - 1); text(2024.5, yl[2] - 0.02 * diff(yl), sprintf("2023-24:\n%+.0f%%\n(state %+.0f%%)", st(a), st(cc)), cex = 0.62, col = "#8c510a", adj = c(0.5, 1))
    luStat[[cl]] <- data.frame(class = cl, area2005 = a$share[1], area2023 = a$share[a$year == 2023], changeArea0523 = 100 * (a$share[a$year == 2023] - a$share[1]), changeControl0523 = 100 * (cc$share[cc$year == 2023] - cc$share[1]), changeGermany0523 = 100 * (b$share[b$year == 2023] - b$share[1]),
                               change2023to24Area = st(a), change2023to24Control = st(cc), change2023to24Germany = st(b)) }
  plot.new(); legend("center", c("Area", cs$ctlName, "Germany", "2024-25: new crop map, recoded"), col = c(col, "black", "grey55", "#fdb863"), lwd = c(3.5, 3, 3, 8), lty = c(1, 2, 1, 1), bty = "n", cex = 1.05)
  mtext(sprintf("%s: the crops in the area, 2005-2025", cs$label), outer = TRUE, side = 3, line = 1.6, font = 2, cex = 1.15); mtext("Mean share of each crop class in the 1 km land-use layers that the landscape models are given", outer = TRUE, side = 3, line = 0.2, cex = 0.75, col = "grey25")
  foot("Land-use layers: HCTM crop-type maps to 2023, CTM v302 recoded to HCTM classes for 2024-2025 (DECISIONS.md, 2026-11-03). A switch of crops that is real shows as a steady change 2005-2023, not as a step in 2024.")
  dev.off(); luStat <- do.call(rbind, luStat)
  ## 4b. what the models say about the crops (unchanged) ---------------------------------------------------------------------------------------------------------------------------------------------------------
  vs <- c("winter_cereals", "summer_cereals", "maize", "grassland", "fallow"); rs <- cs$resp
  newPng(sprintf("%s_4b_model_response_to_crops.png", key)); par(mfrow = c(length(rs), length(vs)), mar = c(3.6, 4.6, 2.4, 0.6), oma = c(4.6, 0, 4, 0))
  for (s in rs) for (v in vs) { d <- resp[resp$species == gsub("_", " ", s) & resp$kind == "partial_dependence" & resp$variable == v & resp$scale == "landscape", ]; d <- d[d$x <= 0.6, ]
    plot(NA, xlim = c(0, 60), ylim = range(c(d$y, 0), na.rm = TRUE) * c(1, 1.05), xlab = if (s == rs[length(rs)]) "Share of the crop in the surroundings (%)" else "", ylab = if (v == vs[1]) paste0(english[[s]], "\npredicted probability") else "", las = 1, bty = "l", main = if (s == rs[1]) cls[[v]] else "", cex.main = 1.15)
    for (y2 in c(2005, 2023)) { xv <- 100 * luse$share[luse$site == key & luse$class == v & luse$year == y2]; abline(v = xv, lty = 3, col = col); text(xv, par("usr")[4], if (y2 == 2005) "05 " else " 23", col = col, cex = 0.7, adj = c(if (y2 == 2005) 1 else 0, 1.2), font = 2) }
    if (nrow(d) > 4) { lo <- lowess(d$x * 100, d$y, f = 0.35); lines(lo$x, lo$y, lwd = 4, col = col) } else if (nrow(d)) lines(d$x * 100, d$y, lwd = 4, col = col) }
  mtext(sprintf("What the fitted models say about the crops: %s", paste(english[rs], collapse = " and ")), outer = TRUE, side = 3, line = 1.6, font = 2, cex = 1.15)
  mtext("Predicted probability of occurrence against the share of the crop in the surroundings (1 km landscape model, other predictors at their observed values; smoothed). Dotted lines: the area's own share in 2005 (05) and 2023 (23)", outer = TRUE, side = 3, line = 0.2, cex = 0.72, col = "grey25")
  foot("Fitted BRT (gbm) landscape model of run v3, trained on DDA territories 2005-2024; partial dependence, x axis cut at 60 % where there are few cells. A response curve shows what the model has learnt, not proof that the crop causes the change; the model has no layer for organic farming, nest losses or predation.")
  dev.off()
  write.csv(sl, file.path(out, sprintf("%s_numbers_species_change.csv", key)), row.names = FALSE); write.csv(luStat, file.path(out, sprintf("%s_numbers_landuse.csv", key)), row.names = FALSE); write.csv(cellTab, file.path(out, sprintf("%s_numbers_cells_change.csv", key)), row.names = FALSE)
  write.csv(do.call(rbind, lapply(names(ts), function(g) data.frame(group = g, ts[[g]]))), file.path(out, sprintf("%s_numbers_index_series.csv", key)), row.names = FALSE)
  numbers[[key]] <- list(cells = cellTab, species = sl, ts = ts); message("done: ", key)
}
for (k in names(numbers)) { cat("\n=====", k, "\n"); print(numbers[[k]]$cells, row.names = FALSE, digits = 3)
  for (g in names(numbers[[k]]$ts)) { d <- numbers[[k]]$ts[[g]]; ch <- function(nm, y) d[[nm]][d$year == y] - 100; cat(sprintf("index change 2005 to 2023 (%s): area %s | control %s | Germany %s;  to 2025: area %s | control %s | Germany %s\n", g, fmt(ch("area", 2023)), fmt(ch("control", 2023)), fmt(ch("germany", 2023)), fmt(ch("area", 2025)), fmt(ch("control", 2025)), fmt(ch("germany", 2025)))) }
  cat("species with a more favourable change than the control state:", sum(numbers[[k]]$species$betterControl), "| than Germany:", sum(numbers[[k]]$species$betterGermany), "of", nrow(numbers[[k]]$species), "\n") }
