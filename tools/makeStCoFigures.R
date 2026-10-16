#!/usr/bin/env Rscript
# READ-ONLY: every figure we may need to show or answer questions about (Steering Consortium meeting 2026-10-16), made from the files
# that already exist. Nothing is refitted and nothing in outputs/ is changed; the figures go to outputs/<run>/figures_fullreport/.
# Base R + terra only. Each figure is made independently: if an input is missing it is logged in skipped.csv and the rest continues.
#
#   Rscript tools/makeStCoFigures.R [--run test4] [--sections S1,S2,S3,S4,S5,S6,S7,S8] [--variants brt,big5] [--species "Alauda arvensis;Perdix perdix"]
#                                   [--base-year 2005] [--year 2025] [--map-years 2005,2015,2025] [--spot-points 3,5,10,15] [--alpha 0.05] [--out <folder>]
#   On EVE:  sbatch cluster/eve_figures.sbatch      (about 30-90 minutes; one task, nothing else running)
#
# Sections follow the methods figure (pdf_export/birdMonitor_schematic.png):
#   S1  Step 1  the three scale models and the meta-model: scale maps, accuracy (AUC), weights of the scales
#   S2  Step 1  the result: probability maps per species and year, presence/absence maps, expected richness
#   S3  Step 3  national indices: species indices, combined indices (SBI, MSI, chain), replicates, BRT-only against big 5
#   S4  Step 3  per-pixel change and trend maps per species, shown for all pixels and only where the 90% interval excludes zero; Mann-Kendall test (needs pixelTrendTest.R)
#   S5  Step 3  community maps: richness change, turnover, gain/loss
#   S6  Step 3  regional index (10/20/50 km): change in index points, cold and hot spots, trend, uncertainty
#   S7  Step 2  robustness: BRT-only against big 5 (regional pattern), spread among the five algorithms
#   S9  observed trends from the DDA territory data (abundance and occupancy, 2005-2024) against our modelled index; run locally, not part of the default sections
#   S8  Step 1/3 expected species richness with its uncertainty (2025: mean, 5th and 95th percentile, width) and the change in richness since 2005
# Files written: <out>/<section>/<id>.png, <out>/figures_manifest.csv (what each figure is and where its numbers come from),
# <out>/tables/*.csv (the numbers behind the figures), <out>/skipped.csv (what could not be made and why), <out>/figures.log.
Sys.setenv(OMP_NUM_THREADS = "1")
args <- commandArgs(trailingOnly = TRUE)
getArg <- function(flag, default = NULL) { i <- which(args == flag); if (length(i) == 0) default else args[i + 1] }
repoRoot <- normalizePath(getArg("--repo-root", getwd()), winslash = "/"); setwd(repoRoot)
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
suppressMessages(library(terra))
source("modules/models_Monitor/R/uncRegional.R")                       # uncOutlineLAEA(): the German outline without any GDAL/PROJ axis problem
speciesCanonical <- read.csv("data/speciesCanonical.csv", stringsAsFactors = FALSE)
speciesCanonical <- speciesCanonical[nzchar(trimws(speciesCanonical$include)), ]
allSpecies <- speciesCanonical$latin_name
english <- setNames(speciesCanonical$english_name, speciesCanonical$latin_name)

run        <- getArg("--run", Sys.getenv("BIRDMONITOR_RUNNAME", "test4"))
brtTag     <- getArg("--brt-tag", "honest2")
ensTag     <- getArg("--ens-tag", "ens_brt-glm-gam-rf-nn")
baseYear   <- as.integer(getArg("--base-year", 2005))
curYear    <- as.integer(getArg("--year", 2025))
mapYears   <- as.integer(strsplit(getArg("--map-years", paste(baseYear, 2015, curYear, sep = ",")), ",")[[1]])
hindcastEnd <- as.numeric(getArg("--hindcast-end", 2021.5))             # the habitat model has real data from 2022; earlier years are hindcast
spotPointsVec <- as.numeric(strsplit(getArg("--spot-points", "3,5,10,15"), ",")[[1]])   # cold/hot spot: regional index change of at least this many index points (one figure per value)
spotMain <- if (10 %in% spotPointsVec) 10 else spotPointsVec[1]
alpha <- as.numeric(getArg("--alpha", 0.05))                             # significance level of the Mann-Kendall test
minCoverage <- as.numeric(getArg("--min-coverage", 0.5))
sections   <- toupper(strsplit(getArg("--sections", "S1,S2,S3,S4,S5,S6,S7,S8"), ",")[[1]])
variants   <- strsplit(getArg("--variants", "brt,big5"), ",")[[1]]
species    <- allSpecies; if (!is.null(getArg("--species"))) species <- intersect(allSpecies, trimws(strsplit(getArg("--species"), ";")[[1]]))
cellKm     <- as.integer(strsplit(getArg("--cells-km", "10,20,50"), ",")[[1]])
root       <- file.path("outputs", run)
out        <- getArg("--out", file.path(root, "figures_fullreport"))
for (d in c(out, file.path(out, "tables"))) dir.create(d, recursive = TRUE, showWarnings = FALSE)
logFile <- file.path(out, "figures.log")
say <- function(...) { m <- paste0(format(Sys.time(), "%H:%M:%S"), " ", ...); message(m); cat(m, "\n", file = logFile, append = TRUE) }
say("=== makeStCoFigures | run ", run, " | sections ", paste(sections, collapse = ","), " | variants ", paste(variants, collapse = ","), " | ", length(species), " species")

## ---- where things are --------------------------------------------------------------------------------------------------------------------
firstExisting <- function(...) { p <- c(...); p <- p[file.exists(p)]; if (length(p)) p[1] else NA_character_ }
dirOf <- function(prefix, tag, germany = TRUE) {                        # outputs/<run>/<prefix>[_<tag>][_germany], falls back to the rectangle version
  base <- file.path(root, paste0(prefix, if (nzchar(tag)) paste0("_", tag) else ""))
  firstExisting(if (germany) paste0(base, "_germany"), base)
}
metaFolder <- function(tag, germany) {                                  # metamodel_<resolutions>[_<tag>][_germany]
  d <- list.dirs(root, recursive = FALSE, full.names = TRUE)
  d <- d[grepl(paste0("^metamodel_[0-9_]+", if (nzchar(tag)) paste0("_", tag) else "", if (germany) "_germany", "$"), basename(d))]
  if (length(d)) d[1] else NA_character_
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
V <- list(
  brt  = list(id = "brt",  label = "BRT only",  full = "BRT only (50 replicates)",       tag = "",     unc = firstExisting(file.path(root, paste0("uncertainty_", brtTag)), file.path(root, "uncertainty"))),
  big5 = list(id = "big5", label = "Model ensemble", full = "Model ensemble (25 replicates)", tag = ensTag, unc = file.path(root, paste0("uncertainty_", ensTag))))
for (k in names(V)) {
  v <- V[[k]]
  V[[k]]$metaGer  <- metaFolder(v$tag, TRUE)
  V[[k]]$metaBase <- metaFolder(v$tag, FALSE)
  V[[k]]$report   <- dirOf("annual_report", v$tag)
  V[[k]]$regional <- dirOf("regional_index", v$tag)
  V[[k]]$uncComm  <- firstExisting(file.path(v$unc, "community_germany"), file.path(v$unc, "community"))
  V[[k]]$uncReg   <- file.path(v$unc, "regional")
}
uncMapsDir <- function(k, sp) firstExisting(file.path(V[[k]]$unc, gsub(" ", "_", sp), "maps_germany"), file.path(V[[k]]$unc, gsub(" ", "_", sp), "maps"))
variants <- intersect(variants, names(V))
for (k in variants) say("variant ", k, ": meta ", basename(V[[k]]$metaGer %||% "-"), " | report ", basename(V[[k]]$report %||% "-"), " | regional ", basename(V[[k]]$regional %||% "-"), " | uncertainty ", basename(V[[k]]$unc %||% "-"))
spc <- function(sp) gsub(" ", "_", sp)
nm  <- function(sp) sprintf("%s (%s)", english[[sp]], sp)

## ---- bookkeeping ---------------------------------------------------------------------------------------------------------------------------
manifest <- list(); skipped <- list()
oldManifest <- if (file.exists(file.path(out, "figures_manifest.csv"))) read.csv(file.path(out, "figures_manifest.csv"), stringsAsFactors = FALSE) else NULL
oldSkipped <- if (file.exists(file.path(out, "skipped.csv"))) read.csv(file.path(out, "skipped.csv"), stringsAsFactors = FALSE) else NULL
note <- function(what, why) { skipped[[length(skipped) + 1]] <<- data.frame(what = what, why = why); say("SKIPPED ", what, ": ", why) }
saveBook <- function() {                                                  # rows of earlier runs are kept unless this run made (or failed to make) the same figure again
  newM <- if (length(manifest)) do.call(rbind, manifest) else NULL; newS <- if (length(skipped)) do.call(rbind, skipped) else NULL
  m <- rbind(if (!is.null(oldManifest)) oldManifest[!oldManifest$id %in% c(newM$id, newS$what), ], newM)
  if (!is.null(m) && nrow(m)) write.csv(m, file.path(out, "figures_manifest.csv"), row.names = FALSE)
  s <- rbind(if (!is.null(oldSkipped)) oldSkipped[!oldSkipped$what %in% c(newM$id, newS$what), ], newS)
  if (!is.null(s) && nrow(s)) write.csv(s, file.path(out, "skipped.csv"), row.names = FALSE) else if (file.exists(file.path(out, "skipped.csv"))) file.remove(file.path(out, "skipped.csv"))
}
need <- function(...) { p <- c(...); bad <- p[is.na(p) | !file.exists(p)]; if (length(bad)) stop("missing: ", paste(unique(bad), collapse = " | "), call. = FALSE); invisible(p) }
dropLab <- function(s) {                                                  # with one run only, the run is not named in titles and explanations
  if (length(variants) != 1) return(s); l <- V[[variants]]$label
  s <- gsub(paste0("[[:space:]]*[(]", l, "[)]"), "", s); s <- gsub(paste0(",[[:space:]]*", l, "(?=[)])"), "", s, perl = TRUE); gsub(paste0("[,:][[:space:]]*", l, "[[:space:]]*$"), "", s)
}
figure <- function(section, id, title, what, source, draw, w = 13, h = 7.2, variant = "") {
  title <- dropLab(title); what <- dropLab(what)
  dir.create(file.path(out, section), showWarnings = FALSE)
  f <- file.path(out, section, paste0(id, ".png"))
  ok <- tryCatch({
    png(f, width = w, height = h, units = "in", res = 170, type = if (capabilities("cairo")) "cairo" else "windows")
    draw(); dev.off(); TRUE
  }, error = function(e) { while (dev.cur() > 1) dev.off(); if (file.exists(f)) file.remove(f); note(id, conditionMessage(e)); FALSE })
  if (ok) { manifest[[length(manifest) + 1]] <<- data.frame(section = section, id = id, variant = variant, file = file.path(section, paste0(id, ".png")), title = title, what = what, source = source)
            say("made ", file.path(section, paste0(id, ".png"))); saveBook() }
  invisible(ok)
}
tableOut <- function(x, name) { write.csv(x, file.path(out, "tables", paste0(name, ".csv")), row.names = FALSE); say("table ", name, ".csv") }

## ---- outline, colours, map helpers -----------------------------------------------------------------------------------------------------
outline <- tryCatch(uncOutlineLAEA(file.path("inputs", "predictors", "raw", "gadm"), "EPSG:3035"), error = function(e) { say("NO OUTLINE: ", conditionMessage(e)); NULL })
palProb <- hcl.colors(100, "Viridis")
palDiv  <- rev(hcl.colors(100, "Blue-Red 3"))                          # low = red = decline, high = blue = increase (as in the briefing)
palSeq  <- hcl.colors(100, "YlOrRd", rev = TRUE)
palRich <- hcl.colors(100, "Mako")
colDec <- "#c0392b"; colInc <- "#2c6fbb"; colNone <- "#e3e3e3"
mapMargin <- c(1, 1, 3, 5.5)
clampIn <- function(r, lo, hi) { e <- 1e-4 * (hi - lo); clamp(r, lo + e, hi - e) }       # values beyond the colour range keep the end colour (terra leaves values at/below the range minimum blank)
bm <- 6.4                                                               # bottom margin of panels that carry a legend below the map
ger <- function(r, n = 1.2e6) {                                          # German window, thinned for display (nearest cell), outside the outline NA
  if (!is.null(outline)) r <- crop(r, ext(outline), snap = "out")
  if (ncell(r) > n) r <- spatSample(r, n, method = "regular", as.raster = TRUE)
  if (!is.null(outline)) r <- mask(r, outline)
  r
}
lay <- function(r, cand, pos) { for (n in cand) if (n %in% names(r)) return(r[[n]]); r[[pos]] }
symLim <- function(r, q = 0.99) { v <- abs(values(r, na.rm = TRUE)); if (!length(v)) 1 else max(quantile(v, q), 1e-9) }
drawMap <- function(r, main, pal = palProb, zlim = NULL, sub = NULL, mb = 1) {
  if (is.null(zlim)) zlim <- range(values(r, na.rm = TRUE)); if (!all(is.finite(zlim)) || zlim[1] == zlim[2]) zlim <- zlim + c(-1, 1) * 1e-6
  r <- clampIn(r, zlim[1], zlim[2])
  plot(r, col = pal, range = zlim, main = main, axes = FALSE, box = FALSE, mar = c(mb, 1, 3, 5.5), cex.main = 1.15)
  if (!is.null(outline)) lines(outline, lwd = 0.9, col = "grey25")
  if (!is.null(sub)) mtext(sub, side = 1, line = -0.4, cex = 0.8, col = "grey30")
}
legendBelow <- function(r, labels, cols, pch = NULL) {                    # legend under the map (never on top of it)
  e <- ext(r); fl <- if (is.null(pch)) cols else ifelse(is.na(pch), cols, NA)
  legend(x = e$xmin, y = e$ymin - 0.03 * (e$ymax - e$ymin), xpd = NA, yjust = 1, legend = labels, fill = fl, border = if (is.null(pch)) "grey40" else ifelse(is.na(pch), "grey40", NA),
         pch = pch, col = if (is.null(pch)) NULL else ifelse(is.na(pch), NA, "black"), bty = "n", cex = 0.9)
}
drawClasses <- function(r, main, labels, cols, sub = NULL, legendPos = NULL) {   # r holds integer classes 1..k
  k <- length(cols)
  plot(r, col = cols, breaks = seq(0.5, k + 0.5, 1), legend = FALSE, main = main, axes = FALSE, box = FALSE, mar = c(bm, 1, 3, 1), cex.main = 1.15)
  if (!is.null(outline)) lines(outline, lwd = 0.9, col = "grey25")
  legendBelow(r, labels, cols)
  if (!is.null(sub)) mtext(sub, side = 1, line = -0.4, cex = 0.8, col = "grey30")
}
bigTitle <- function(s) mtext(dropLab(s), outer = TRUE, side = 3, line = 0.4, font = 2, cex = 1.45)
footnote <- function(s) mtext(s, outer = TRUE, side = 1, line = 0.6, cex = 0.85, col = "grey30")
# "clear" classes from a 90% replicate interval: 1 = whole interval below zero, 2 = whole interval above zero, 3 = interval includes zero
clearClass <- function(lwr, upr) ifel(is.na(upr), NA, ifel(upr < 0, 1, ifel(lwr > 0, 2, 3)))
pct <- function(x) sprintf("%.0f%%", 100 * x)
clearMask <- function(lwr, upr) ifel(is.na(upr), NA, ifel((upr < 0) | (lwr > 0), 1, 0))   # 1 = the 90% interval excludes zero
# the values drawn only where the interval excludes zero; every other cell inside Germany is light grey
drawClearOnly <- function(v, clr, main, zlim, extra = NULL, extraCols = NULL) {
  base <- ifel(is.na(v), NA, 1)
  plot(base, col = colNone, legend = FALSE, main = main, axes = FALSE, box = FALSE, mar = c(bm, 1, 3, 5.5), cex.main = 1.15)
  plot(ifel(clr == 1, clampIn(v, zlim[1], zlim[2]), NA), col = palDiv, range = zlim, add = TRUE)
  if (!is.null(outline)) lines(outline, lwd = 0.9, col = "grey25")
  legendBelow(base, c("grey: the 90% interval includes zero", extra), c(colNone, extraCols))
}
areaShares <- function(lwr, upr) {                                       # exact shares over ALL cells of the file (not the thinned display raster)
  n <- global(!is.na(upr), "sum")[1, 1]
  c(decline = global(upr < 0, "sum", na.rm = TRUE)[1, 1] / n, increase = global(lwr > 0, "sum", na.rm = TRUE)[1, 1] / n, nCells = n)
}
readCsv <- function(f) { need(f); read.csv(f, check.names = FALSE, stringsAsFactors = FALSE) }
hindcastBox <- function(yrs, ylim) { rect(min(yrs) - 0.5, ylim[1] - 50, hindcastEnd, ylim[2] + 50, col = "#ececec", border = NA) }

## ---- per-species scale folders: the folder name comes from each species' own resolution in data/speciesConfig_general.csv (e.g. Lanius collurio landscape 700 m -> scale_07, Buteo buteo 5 km -> scale_5)
speciesCfg <- tryCatch(read.csv("data/speciesConfig_general.csv", stringsAsFactors = FALSE), error = function(e) NULL)
scaleLabelOf <- function(resolutionM) paste0("scale_", sub(".", "", as.character(resolutionM / 1000), fixed = TRUE))
scaleDirOf <- function(sp, sc) {
  r <- if (is.null(speciesCfg)) NA else speciesCfg$resolution_m[speciesCfg$species == sp & speciesCfg$scale == sc]
  lab <- if (length(r) && !is.na(r[1])) scaleLabelOf(r[1]) else c(climate = "scale_50", landscape = "scale_1", habitat = "scale_02")[[sc]]
  file.path(root, lab)
}

## ---- the index tables (read once; used by S3, S6, S7) ------------------------------------------------------------------------------------
loadIdx <- function(k) {
  v <- V[[k]]; o <- list()
  o$main  <- tryCatch({ x <- readCsv(file.path(v$report, "species_index.csv")); rownames(x) <- x[[1]]; x[[1]] <- NULL; x }, error = function(e) NULL)
  o$spUnc <- tryCatch(readCsv(file.path(v$report, "species_index_uncertainty.csv")), error = function(e) NULL)
  o$comb  <- tryCatch(readCsv(file.path(v$report, "combined_index_uncertainty.csv")), error = function(e) NULL)
  o$sbi   <- tryCatch({ x <- readCsv(file.path(v$report, "combined_index_sbi.csv")); names(x) <- tolower(names(x)); x }, error = function(e) NULL)
  o$chainR <- tryCatch(readCsv(file.path(v$report, "combined_index_chain_restricted.csv")), error = function(e) NULL)
  # replicate area means -> species index per replicate (the same arithmetic as the reported numbers; replicate 0 = main model)
  rows <- lapply(species, function(sp) { f <- firstExisting(file.path(v$unc, spc(sp), "area_mean_replicates_germany.csv"), file.path(v$unc, spc(sp), "area_mean_replicates.csv"))
                                          if (is.na(f)) NULL else read.csv(f, stringsAsFactors = FALSE) })
  rows <- do.call(rbind, rows)
  if (!is.null(rows) && nrow(rows)) {
    key <- paste(rows$species, rows$replicate); base <- rows[rows$year == baseYear, ]
    rows$index <- 100 * rows$areaMean / base$areaMean[match(paste(rows$species, rows$replicate), paste(base$species, base$replicate))]
    o$rep <- rows[rows$replicate != 0, ]; o$rep0 <- rows[rows$replicate == 0, ]
    o$nRep <- length(unique(o$rep$replicate))
  }
  o
}
IDX <- setNames(lapply(variants, loadIdx), variants)
nRepOf <- function(k) if (is.null(IDX[[k]]$nRep)) NA else IDX[[k]]$nRep
repSBI <- function(k) {                                                  # combined index (geometric mean of species indices) per replicate and year
  r <- IDX[[k]]$rep; if (is.null(r)) stop("no replicate area means for ", k)
  a <- aggregate(log(index) ~ replicate + year, data = r, FUN = mean); names(a)[3] <- "lg"; a$SBI <- exp(a$lg); a
}
interval <- function(a, p = c(0.05, 0.95)) do.call(rbind, lapply(split(a, a$year), function(d) data.frame(year = d$year[1], mean = mean(d$SBI), lwr = quantile(d$SBI, p[1]), upr = quantile(d$SBI, p[2]))))
cmbCol <- c(SBI = "#1f4e79", MSI = "#2d8a4e", Chain = "#d9822b"); cmbLty <- c(SBI = 1, MSI = 3, Chain = 2)
varCol <- c(brt = "#1f4e79", big5 = "#c4551f")

## =================================================================================================================================================
## S1  three scale models, meta-model
## =================================================================================================================================================
if ("S1" %in% sections) {
  say("--- S1 ---")
  scaleTag  <- c(climate = "EU", landscape = "landscape", habitat = "habitat")
  for (k in variants) for (sp in species) {
    v <- V[[k]]; yr <- curYear
    f <- c(climate = if (k == "brt") file.path(scaleDirOf(sp, "climate"), sprintf("%s_pred_EU_%d.tif", spc(sp), yr)) else file.path(scaleDirOf(sp, "climate"), sprintf("%s_pred_%s_climate_%d.tif", spc(sp), v$tag, yr)),
           landscape = if (k == "brt") file.path(scaleDirOf(sp, "landscape"), sprintf("%s_pred_landscape_%d.tif", spc(sp), yr)) else file.path(scaleDirOf(sp, "landscape"), sprintf("%s_pred_%s_landscape_%d.tif", spc(sp), v$tag, yr)),
           habitat = if (k == "brt") file.path(scaleDirOf(sp, "habitat"), sprintf("%s_pred_habitat_%d.tif", spc(sp), yr)) else file.path(scaleDirOf(sp, "habitat"), sprintf("%s_pred_%s_habitat_%d.tif", spc(sp), v$tag, yr)),
           final = file.path(v$metaGer, sprintf("%s_meta_suitability_%d.tif", spc(sp), yr)))
    figure("S1_models", sprintf("S1_scales_%s_%s", spc(sp), k), sprintf("%s: the three scale models and the final map, %d (%s)", nm(sp), yr, V[[k]]$label),
           "Step 1 of the methods figure: probability of occurrence from the climate (50 km), landscape (1 km) and habitat (200 m) models and the final map the meta-model makes from them. Same colour scale in all four panels.",
           paste(f, collapse = "; "), variant = k, w = 15, h = 5.6, draw = function() {
      need(f); par(mfrow = c(1, 4), oma = c(1, 0, 2.6, 0))
      ttl <- c(climate = "Climate model (50 km)", landscape = "Landscape model (1 km)", habitat = "Habitat model (200 m)", final = "Final map (meta-model)")
      for (n in names(f)) { r <- ger(lay(rast(f[[n]]), c("mean_prob", "meta_prob"), 1)); drawMap(r, ttl[[n]], palProb, c(0, 1)) }
      bigTitle(sprintf("%s, %d: probability of occurrence, %s", nm(sp), yr, V[[k]]$label))
    })
  }
  # accuracy: block-CV AUC of each scale (BRT and, if present, the big 5 ensemble) and the honest AUC of the meta-model
  aucTab <- do.call(rbind, lapply(species, function(sp) do.call(rbind, lapply(c("climate", "landscape", "habitat", "meta"), function(sc) do.call(rbind, lapply(variants, function(k) {
    f <- if (sc == "meta") file.path(V[[k]]$metaBase %||% "", sprintf("%s_perf_meta.rds", spc(sp)))
         else if (k == "brt") file.path(scaleDirOf(sp, sc), sprintf("%s_perf_%s.rds", spc(sp), scaleTag[[sc]]))
         else file.path(scaleDirOf(sp, sc), sprintf("%s_perf_%s_%s.rds", spc(sp), V[[k]]$tag, sc))
    if (!file.exists(f)) return(NULL)
    p <- readRDS(f); if (sc == "meta" && !identical(p$evalBasis, "out-of-fold inputs")) return(NULL)
    data.frame(species = sp, scale = sc, variant = k, AUC = p$AUC[1], TSS = p$TSS[1], file = f) }))))))
  if (!is.null(aucTab) && nrow(aucTab)) {
    tableOut(aucTab[, c("species", "scale", "variant", "AUC", "TSS")], "S1_auc_by_scale")
    figure("S1_models", "S1_auc_by_scale", "Accuracy (AUC) of each scale model and of the meta-model, per species",
           paste0("Held-out (block cross-validation) AUC of the climate, landscape and habitat models, and the honest AUC of the final combined map (out-of-fold inputs).", if (length(variants) > 1) " Circle = BRT only, triangle = model ensemble." else "", " Higher is better; 0.5 = no skill."),
           "scale_*/<Sp>_perf_*.rds, metamodel_*/<Sp>_perf_meta.rds", variant = paste(variants, collapse = "+"), w = 14, h = 6.2, draw = function() {
      par(mfrow = c(1, 4), mar = c(4, 11, 3, 1), oma = c(1, 0, 2.6, 0))
      ord <- rev(seq_along(species)); yl <- c(0.5, length(species) + 0.5)
      for (sc in c("climate", "landscape", "habitat", "meta")) {
        plot(NA, xlim = c(0.5, 1), ylim = yl, yaxt = "n", xlab = "AUC", ylab = "", main = c(climate = "Climate (50 km)", landscape = "Landscape (1 km)", habitat = "Habitat (200 m)", meta = "Final map (meta-model)")[[sc]], las = 1)
        abline(v = c(0.7, 0.8, 0.9), col = "grey88"); abline(h = seq_along(species), col = "grey94")
        axis(2, at = seq_along(species), labels = rev(english[species]), las = 1, cex.axis = 0.9)
        for (k in variants) { d <- aucTab[aucTab$scale == sc & aucTab$variant == k, ]; y <- match(d$species, rev(species))
                              points(d$AUC, y, pch = if (k == "brt") 16 else 17, col = varCol[[k]], cex = 1.5) }
        if (sc == "meta") legend("bottomleft", legend = sapply(variants, function(k) V[[k]]$label), pch = ifelse(variants == "brt", 16, 17), col = varCol[variants], bty = "n", cex = 1)
      }
      bigTitle("Model accuracy on held-out data")
    })
  } else note("S1_auc_by_scale", "no perf files found")
  # weights of the three scales in the meta-model
  wt <- do.call(rbind, lapply(variants, function(k) do.call(rbind, lapply(species, function(sp) {
    f <- file.path(V[[k]]$metaBase %||% "", sprintf("%s_varimp_meta.rds", spc(sp))); if (!file.exists(f)) return(NULL)
    x <- readRDS(f); data.frame(variant = k, species = sp, climate = x$imp_climate, landscape = x$imp_landscape, habitat = x$imp_habitat) }))))
  if (!is.null(wt) && nrow(wt)) {
    tableOut(wt, "S1_scale_weights")
    figure("S1_models", "S1_scale_weights", "How much each scale contributes to the final map (meta-model), per species",
           "Share of each of the three scale models in the meta-model (importance, sums to 1 per species). The habitat model carries most species; a large climate share means the final map follows the coarse Europe-wide model.",
           "metamodel_*/<Sp>_varimp_meta.rds", variant = paste(variants, collapse = "+"), w = 13, h = 6, draw = function() {
      par(mfrow = c(1, length(unique(wt$variant))), mar = c(4, 11, 3, 1), oma = c(1, 0, 2.6, 0))
      for (k in unique(wt$variant)) { d <- wt[wt$variant == k, ]; d <- d[match(rev(species), d$species), ]; d <- d[!is.na(d$species), ]
        m <- t(as.matrix(d[, c("climate", "landscape", "habitat")])); colnames(m) <- english[d$species]
        barplot(m, horiz = TRUE, las = 1, col = c("#8fb4d9", "#e0b25c", "#4a8f5a"), border = NA, xlab = "Share of the final map", main = V[[k]]$full, xlim = c(0, 1)) }
      legend("bottomright", legend = c("Climate", "Landscape", "Habitat"), fill = c("#8fb4d9", "#e0b25c", "#4a8f5a"), bty = "n"); bigTitle("Weights of the three scales in the meta-model")
    })
  } else note("S1_scale_weights", "no varimp_meta files found")
}

## =================================================================================================================================================
## S2  probability maps
## =================================================================================================================================================
if ("S2" %in% sections) {
  say("--- S2 ---")
  for (k in variants) for (sp in species) {
    v <- V[[k]]
    fs <- file.path(v$metaGer, sprintf("%s_meta_suitability_%d.tif", spc(sp), mapYears))
    figure("S2_maps", sprintf("S2_prob_%s_%s", spc(sp), k), sprintf("%s: probability of occurrence %s (%s)", nm(sp), paste(mapYears, collapse = ", "), v$label),
           "The final probability map (best estimate = main model) for three years, same colour scale. 2005-2021 are hindcast years (the habitat model has real data from 2022).",
           paste(fs, collapse = "; "), variant = k, w = 5.2 * length(fs) + 1, h = 5.6, draw = function() {
      need(fs); par(mfrow = c(1, length(fs)), oma = c(1, 0, 2.6, 0))
      for (i in seq_along(fs)) drawMap(ger(rast(fs[i])[["meta_prob"]]), as.character(mapYears[i]), palProb, c(0, 1))
      bigTitle(sprintf("%s: probability of occurrence (%s)", nm(sp), v$label))
    })
    fb <- file.path(v$metaGer, sprintf("%s_meta_suitability_%d.tif", spc(sp), c(baseYear, curYear)))
    figure("S2_maps", sprintf("S2_binary_%s_%s", spc(sp), k), sprintf("%s: presence/absence map %d and %d (%s)", nm(sp), baseYear, curYear, v$label),
           "Presence/absence map: the probability map cut at the species' own threshold (from the honest evaluation). Used only for the gain/loss maps.",
           paste(fb, collapse = "; "), variant = k, w = 9.5, h = 5.6, draw = function() {
      need(fb); par(mfrow = c(1, 2), oma = c(1, 0, 2.6, 0))
      for (i in 1:2) { r <- ger(rast(fb[i])[["binary"]]) + 1; drawClasses(r, as.character(c(baseYear, curYear)[i]), c("absent", "present"), c("#f0f0f0", "#2d6a4f")) }
      bigTitle(sprintf("%s: predicted presence (%s)", nm(sp), v$label))
    })
  }
  for (k in variants) {
    v <- V[[k]]; sr <- file.path(v$report, sprintf("SR_map_%d.tif", curYear)); ru <- file.path(v$uncComm %||% "", sprintf("richness_expected_unc_%d.tif", curYear))
    figure("S2_maps", sprintf("S2_richness_%s", k), sprintf("Expected species richness %d (%s)", curYear, v$label),
           "Sum of the probabilities of the 11 species per pixel (expected richness) with the width of its 90% interval over the replicates.",
           paste(sr, ru, sep = "; "), variant = k, w = 11, h = 6, draw = function() {
      need(ru); par(mfrow = c(1, 2), oma = c(1, 0, 2.6, 0))
      r <- rast(ru); drawMap(ger(lay(r, "mean", 1)), "Expected richness (mean over replicates)", palRich)
      drawMap(ger(lay(r, "width", 5)), "Width of the 90% interval", palSeq); bigTitle(sprintf("Expected richness of the 11 species, %d (%s)", curYear, v$label))
    })
  }
}

## =================================================================================================================================================
## S3  national indices
## =================================================================================================================================================
if ("S3" %in% sections) {
  say("--- S3 ---")
  # (a) species indices, small multiples
  speciesGrid <- function(ks, title) {
    par(mfrow = c(3, 4), mar = c(3, 3.6, 2.4, 0.6), oma = c(1.5, 0, 3, 0), mgp = c(2.2, 0.7, 0))
    for (sp in species) {
      allv <- c(100); for (k in ks) { u <- IDX[[k]]$spUnc; u <- u[u$species == sp, ]; allv <- c(allv, u$indexLwr, u$indexUpr, unlist(IDX[[k]]$main[sp, ])) }
      yl <- range(allv, na.rm = TRUE); yl <- yl + c(-1, 1) * 0.04 * diff(yl); yrs <- as.integer(names(IDX[[ks[1]]]$main))
      plot(NA, xlim = range(yrs), ylim = yl, xlab = "", ylab = "Index (2005 = 100)", main = english[[sp]], cex.main = 1.1, bty = "l", las = 1)
      hindcastBox(yrs, yl); abline(h = 100, lty = 3, col = "grey40")
      for (k in ks) { u <- IDX[[k]]$spUnc; u <- u[u$species == sp, ]; u <- u[order(u$year), ]
        polygon(c(u$year, rev(u$year)), c(u$indexLwr, rev(u$indexUpr)), col = adjustcolor(varCol[[k]], 0.22), border = NA)
        lines(yrs, unlist(IDX[[k]]$main[sp, ]), col = varCol[[k]], lwd = 2.4) }
    }
    plot.new(); legend("center", legend = c(unlist(lapply(ks, function(k) c(paste0(V[[k]]$label, ": main model"), paste0(V[[k]]$label, ": 90% interval")))), "hindcast years"),
                       col = c(unlist(lapply(ks, function(k) c(varCol[[k]], adjustcolor(varCol[[k]], 0.35)))), "#ececec"), lwd = c(rep(c(2.4, 8), length(ks)), 8), bty = "n", cex = 1.05)
    bigTitle(title)
  }
  for (k in variants) if (!is.null(IDX[[k]]$main) && !is.null(IDX[[k]]$spUnc))
    figure("S3_indices", sprintf("S3_species_index_%s", k), sprintf("Species indices 2005-%d with 90%% interval (%s)", curYear, V[[k]]$label),
           "Index of each species (area mean probability in Germany, 2005 = 100): line = main model (best estimate), band = 5th-95th percentile of the replicates. Grey = hindcast years.",
           file.path(V[[k]]$report, "species_index.csv + species_index_uncertainty.csv"), variant = k, w = 14, h = 9, draw = function() speciesGrid(k, sprintf("Species indices, Germany (%s)", V[[k]]$full)))
  if (all(c("brt", "big5") %in% variants) && all(sapply(c("brt", "big5"), function(k) !is.null(IDX[[k]]$main) && !is.null(IDX[[k]]$spUnc))))
    figure("S3_indices", "S3_species_index_brt_vs_big5", "Species indices: BRT only against big 5",
           "The same species indices for both runs in one panel per species (blue = BRT only, orange = big 5). Shows where adding the other four algorithms changes the picture.",
           "annual_report_germany and annual_report_<ens>_germany: species_index(_uncertainty).csv", variant = "both", w = 14, h = 9, draw = function() speciesGrid(c("brt", "big5"), "Species indices, Germany: BRT only against big 5")
    )
  # (b) combined indices (same as tools/plotCombinedIndices.R, from the annual report files)
  combPanel <- function(k, showLegend, ylim = NULL, title = NULL) {
    ix <- IDX[[k]]; x <- ix$comb; yrs <- sort(unique(x$year))
    rng <- range(x$lwr[x$method %in% names(cmbCol)], x$upr[x$method %in% names(cmbCol)], ix$sbi$sbi, na.rm = TRUE) + c(-0.4, 0.4)
    if (!is.null(ylim)) rng <- ylim
    plot(NA, xlim = range(yrs), ylim = rng, xlab = "Year", ylab = "Index (2005 = 100)", main = if (is.null(title)) V[[k]]$full else title, cex.main = 1.3, bty = "l", las = 1)
    hindcastBox(yrs, rng); text(mean(c(min(yrs), hindcastEnd)), if (is.null(ylim)) rng[2] - 0.05 else 50, "hindcast 2005-2021", col = "grey45", cex = 0.95, adj = c(0.5, 1)); abline(h = 100, lty = 3, col = "grey40")
    for (m in names(cmbCol)) { d <- x[x$method == m, ]; d <- d[order(d$year), ]
      if (m == "SBI") polygon(c(d$year, rev(d$year)), c(d$lwr, rev(d$upr)), col = adjustcolor(cmbCol[[m]], 0.2), border = NA)
      else { lines(d$year, d$lwr, col = cmbCol[[m]], lty = cmbLty[[m]], lwd = 1.6); lines(d$year, d$upr, col = cmbCol[[m]], lty = cmbLty[[m]], lwd = 1.6) } }
    lines(ix$sbi$year, ix$sbi$sbi, col = "black", lwd = 3)
    if (showLegend) legend("bottomleft", c("Best estimate (main model)", "90% interval, SBI (percentiles over the replicates)", "90% interval, chain index (equal to SBI)", "90% interval, MSI (Monte Carlo)"),
                           col = c("black", adjustcolor(cmbCol[["SBI"]], 0.5), cmbCol[["Chain"]], cmbCol[["MSI"]]), lty = c(1, 1, cmbLty[["Chain"]], cmbLty[["MSI"]]), lwd = c(3, 8, 1.6, 1.6), bty = "n", cex = 0.9)
  }
  okc <- variants[sapply(variants, function(k) !is.null(IDX[[k]]$comb) && !is.null(IDX[[k]]$sbi))]
  txtCmb <- "Black line: main model (fitted once on all training data).\nBands/lines: 90% interval over the replicates (SBI, chain) or Monte Carlo (MSI).\nSBI and chain coincide when no species is missing."
  for (sel in list(okc, "big5", "brt")) { sel <- intersect(sel, okc); if (!length(sel) || (length(sel) == 1 && length(okc) == 1 && !identical(sel, okc))) next
    id <- if (length(sel) == 2) "S3_combined_both" else paste0("S3_combined_", sel)
    if (length(sel) == 1 && length(okc) == 1 && id %in% sapply(manifest, function(m) m$id)) next
    figure("S3_indices", id, paste("Combined multi-species index (SBI, MSI, chain):", paste(sapply(sel, function(k) V[[k]]$label), collapse = " and ")),
           "The combined index of the 11 species: geometric mean of the species indices, three ways of drawing the 90% interval. Black = main model.",
           "annual_report*_germany/combined_index_uncertainty.csv + combined_index_sbi.csv", variant = paste(sel, collapse = "+"), w = if (length(sel) == 2) 15 else 9.5, h = 6.6, draw = function() {
      par(mfrow = c(1, length(sel)), mar = c(4.2, 4.6, 3.2, 1), oma = c(5, 0, 2.6, 0))
      for (i in seq_along(sel)) combPanel(sel[i], i == 1)
      bigTitle("Combined multi-species indices, 11 species, Germany only"); mtext(txtCmb, outer = TRUE, side = 1, line = 2.2, cex = 0.85, col = "grey30")
    })
  }
  # (b2) the same combined index on the full axis (0 to 102): how small the movement is against the range of the index
  for (k in intersect(c("big5", "brt"), okc)) figure("S3_indices", sprintf("S3_combined_%s_axis0", k), sprintf("Combined multi-species index on the full axis 0-102 (%s)", V[[k]]$label),
         "The same combined index (main model, 90% intervals) with the y axis running from 0 to 102 instead of being cut to the data. A decline of about 7 index points is small against the full range of the scale.",
         "annual_report*_germany/combined_index_uncertainty.csv + combined_index_sbi.csv", variant = k, w = 9.5, h = 6.6, draw = function() {
    par(mar = c(4.2, 4.6, 3.2, 1), oma = c(1, 0, 4, 0)); combPanel(k, TRUE, ylim = c(0, 102), title = c(big5 = "Ensemble model (25 replicates)", brt = "BRT only (50 replicates)")[[k]])
    mtext("Multi-species indicator for 11 farmland bird species
in 1st iteration of the BirdMonitor", outer = TRUE, side = 3, line = 0.2, font = 2, cex = 1.35) })
  # (b3) our combined index (MSI, big 5) next to the European Farmland Bird Index (PECBMS/EBCC, abundance). Two versions: the European axis from 1980 with our index anchored to the
  #      European value of the base year, and our axis (base year = 100, from 40 to 102) with the European index re-based to the base year.
  refFile <- file.path("data", "reference", "pecbms_farmland_bird_index_1980base.csv")
  vsK <- if ("big5" %in% okc) "big5" else okc[1]
  vsFigure <- function(id, title, what, from1980) figure("S3_indices", id, title, what, paste(refFile, "annual_report*_germany/combined_index_uncertainty.csv", sep = "; "), variant = vsK, w = 11.5, h = 6.8, draw = function() {
    ref <- read.csv(refFile); ref <- ref[ref$region == "Europe", ]; ref <- ref[order(ref$year), ]; a0 <- ref$smoothed[ref$year == baseYear]
    x <- IDX[[vsK]]$comb; x <- x[x$method == "MSI", ]; x <- x[order(x$year), ]
    if (from1980) { for (cn in c("estimate", "lwr", "upr")) x[[cn]] <- x[[cn]] * a0 / 100 }
    else { ref <- ref[ref$year >= baseYear, ]; for (cn in c("smoothed", "lowerCL", "upperCL", "unsmoothed")) ref[[cn]] <- 100 * ref[[cn]] / a0 }
    yl <- if (from1980) { r <- range(ref$lowerCL, ref$upperCL, ref$unsmoothed, x$lwr, x$upr, na.rm = TRUE); c(floor(r[1] / 5) * 5 - 2, 105) } else c(40, 102)
    par(mar = c(4.2, 4.6, 3, 1), oma = c(5, 0, 1, 0)); plot(NA, xlim = c(min(ref$year), max(ref$year, x$year)), ylim = yl, xlab = "Year", ylab = if (from1980) "Index (Europe: 1980 = 100)" else sprintf("Index (%d = 100)", baseYear), bty = "l", las = 1)
    if (!from1980) { rect(baseYear - 0.5, yl[1] - 5, hindcastEnd, yl[2] + 5, col = "#ececec", border = NA); text(mean(c(baseYear, hindcastEnd)), 60, "our hindcast years", col = "grey45", cex = 0.9) }
    abline(h = 100, lty = 3, col = "grey40"); if (from1980) abline(v = baseYear, lty = 2, col = "grey60")
    polygon(c(ref$year, rev(ref$year)), c(ref$lowerCL, rev(ref$upperCL)), col = adjustcolor("black", 0.15), border = NA)
    lines(ref$year, ref$unsmoothed, col = "grey55", lwd = 1.2); lines(ref$year, ref$smoothed, lwd = 3.5, col = "black")
    polygon(c(x$year, rev(x$year)), c(x$lwr, rev(x$upr)), col = adjustcolor(varCol[[vsK]], 0.25), border = NA); lines(x$year, x$estimate, col = varCol[[vsK]], lwd = 3)
    if (from1980) text(baseYear, yl[2], sprintf("our index starts in %d", baseYear), col = "grey35", cex = 0.85, adj = c(-0.05, 1))
    lab <- c(sprintf("European Farmland Bird Index (PECBMS), abundance (%.0f in %d)", ref$smoothed[nrow(ref)], max(ref$year)), "  its confidence limits (shaded) and unsmoothed values (grey)",
             sprintf("Our MSI, Germany, 11 species, occurrence (%.0f in %d)", x$estimate[nrow(x)], max(x$year)))
    legend("bottomleft", lab, col = c("black", "grey55", varCol[[vsK]]), lwd = c(3.5, 1.5, 3), bty = "n", cex = 0.9)
    mtext(if (from1980) sprintf("Our index is set to the European value of %d (%.1f) so that both fit on one scale.
Our band: 90%% Monte Carlo interval from the spread of 25 replicates; theirs: confidence limits of the smoothed indicator.
Europe: PECBMS/EBCC 2025 update, abundance, 1980-2024. Ours: probability of occurrence, 11 species, Germany only.", baseYear, a0)
          else sprintf("The European index is set to 100 in %d (its value that year: %.1f on the 1980 scale); its limits are scaled the same way.
Our band: 90%% Monte Carlo interval from the spread of 25 replicates; theirs: confidence limits of the smoothed indicator.
Europe: PECBMS/EBCC 2025 update, abundance, to 2024. Ours: probability of occurrence, 11 species, Germany only.", baseYear, a0),
          outer = TRUE, side = 1, line = 1.6, cex = 0.8, col = "grey30") })
  if (file.exists(refFile) && length(okc)) {
    vsFigure("S3_vs_european_farmland_index", "Our combined index (MSI) against the European Farmland Bird Index, 1980-2025",
             sprintf("European Farmland Bird Index (PECBMS/EBCC; abundance; smoothed line, its confidence limits and the unsmoothed values; 1980 = 100) with our MSI for the 11 species in Germany (probability of occurrence, %s) from %d. Our index is set to the European value of %d so that both lines are on one scale. They are different quantities.", V[[vsK]]$label, baseYear, baseYear), TRUE)
    vsFigure("S3_vs_european_farmland_index_from2005", sprintf("Our combined index (MSI) and the European Farmland Bird Index, both %d = 100", baseYear),
             sprintf("The same comparison on our axis: both indices set to 100 in %d, y axis from 40 to 102. European Farmland Bird Index (PECBMS/EBCC, abundance, smoothed with confidence limits and unsmoothed values) against our MSI for the 11 species in Germany (probability of occurrence, %s). Grey = our hindcast years.", baseYear, V[[vsK]]$label), FALSE)
  }
  # (b4) the same comparison with the German farmland indicator (UBA/BfN Agrarland, abundance of selected farmland birds, to 2023) added; all three set to 100 in the base year
  gerFile <- file.path("data", "reference", "uba_agrarland_subindex_Germany.csv")
  if (file.exists(refFile) && file.exists(gerFile) && length(okc)) figure("S3_indices", "S3_vs_german_and_european_index", sprintf("Our combined index (MSI) against the German and the European farmland bird indicators, %d = 100", baseYear),
         sprintf("Three series set to 100 in %d: our MSI for the 11 species in Germany (probability of occurrence; band = 90%% interval), the German national indicator Agrarland (UBA/BfN, DDA; abundance of selected farmland birds; to 2023) and the European Farmland Bird Index (PECBMS/EBCC; abundance of 39 species; to 2024). Different quantities and species sets.", baseYear),
         paste(refFile, gerFile, "annual_report*_germany/combined_index_uncertainty.csv", sep = "; "), variant = vsK, w = 11.5, h = 6.8, draw = function() {
    ref <- read.csv(refFile); ref <- ref[ref$region == "Europe" & ref$year >= baseYear, ]; ref <- ref[order(ref$year), ]; a0 <- ref$smoothed[ref$year == baseYear]
    for (cn in c("smoothed", "lowerCL", "upperCL")) ref[[cn]] <- 100 * ref[[cn]] / a0
    ger <- read.csv(gerFile); ger <- ger[ger$year >= baseYear, ]; ger$idx <- 100 * ger$agrarland_pct_of_target / ger$agrarland_pct_of_target[ger$year == baseYear]
    x <- IDX[[vsK]]$comb; x <- x[x$method == "MSI", ]; x <- x[order(x$year), ]
    yl <- c(40, 102); par(mar = c(4.2, 4.6, 3, 1), oma = c(5, 0, 1, 0))
    plot(NA, xlim = c(baseYear, max(ref$year, ger$year, x$year)), ylim = yl, xlab = "Year", ylab = sprintf("Index (%d = 100)", baseYear), bty = "l", las = 1)
    abline(h = 100, lty = 3, col = "grey40")
    polygon(c(ref$year, rev(ref$year)), c(ref$lowerCL, rev(ref$upperCL)), col = adjustcolor("black", 0.12), border = NA); lines(ref$year, ref$smoothed, lwd = 3.5, col = "black")
    lines(ger$year, ger$idx, lwd = 3.5, col = "#6a3d9a", lty = 1)
    polygon(c(x$year, rev(x$year)), c(x$lwr, rev(x$upr)), col = adjustcolor(varCol[[vsK]], 0.25), border = NA); lines(x$year, x$estimate, col = varCol[[vsK]], lwd = 3)
    lab <- c(sprintf("European Farmland Bird Index (PECBMS), abundance, 39 species (%.0f in %d)", ref$smoothed[nrow(ref)], max(ref$year)),
             sprintf("German farmland indicator Agrarland (UBA/BfN), abundance (%.0f in %d)", ger$idx[nrow(ger)], max(ger$year)),
             sprintf("Our MSI, Germany, 11 species, occurrence (%.0f in %d)", x$estimate[nrow(x)], max(x$year)))
    legend("bottomleft", lab, col = c("black", "#6a3d9a", varCol[[vsK]]), lwd = 3.5, bty = "n", cex = 0.9)
    mtext(sprintf("All series set to 100 in %d. German indicator: percent of target value (UBA/BfN 2025, DDA data), divided by its %d value; about ten selected species.
Europe: PECBMS/EBCC 2025 update, smoothed, with confidence limits. Ours: probability of occurrence, 11 species, Germany only, band = 90%% interval over the replicates.", baseYear, baseYear),
          outer = TRUE, side = 1, line = 1.6, cex = 0.8, col = "grey30") })
  # (c) replicates (spaghetti) and the replicate distribution in the last year
  for (k in variants) if (!is.null(IDX[[k]]$rep)) {
    figure("S3_indices", sprintf("S3_combined_replicates_%s", k), sprintf("Combined index of every replicate (%s)", V[[k]]$label),
           "What the interval is made of: the combined index (SBI) of each replicate (thin lines) with the main model (black) and the 5th/95th percentiles (dashed).",
           paste0(V[[k]]$unc, "/<Sp>/area_mean_replicates_germany.csv (recomputed)"), variant = k, w = 9.5, h = 6.4, draw = function() {
      a <- repSBI(k); iv <- interval(a); mm <- IDX[[k]]$sbi; yrs <- sort(unique(a$year))
      par(mar = c(4.2, 4.6, 3.4, 1)); plot(NA, xlim = range(yrs), ylim = range(a$SBI, mm$sbi, 100), xlab = "Year", ylab = "Index (2005 = 100)", main = V[[k]]$full, bty = "l", las = 1)
      hindcastBox(yrs, range(a$SBI, 100)); abline(h = 100, lty = 3, col = "grey40")
      for (r in unique(a$replicate)) { d <- a[a$replicate == r, ]; lines(d$year, d$SBI, col = adjustcolor(varCol[[k]], 0.25), lwd = 1) }
      lines(iv$year, iv$lwr, lty = 2, lwd = 2, col = varCol[[k]]); lines(iv$year, iv$upr, lty = 2, lwd = 2, col = varCol[[k]])
      if (!is.null(mm)) lines(mm$year, mm$sbi, lwd = 3, col = "black")
      legend("bottomleft", c("Main model", "One replicate", "5th and 95th percentile"), lwd = c(3, 1, 2), lty = c(1, 1, 2), col = c("black", adjustcolor(varCol[[k]], 0.5), varCol[[k]]), bty = "n")
    })
    figure("S3_indices", sprintf("S3_replicates_%d_%s", curYear, k), sprintf("Species index %d: every replicate against the main model (%s)", curYear, V[[k]]$label),
           "For each species the index of every replicate in the last year (dots) and the main model (red diamond). Dots stacked at exactly 100 are replicates with a constant map (Perdix perdix).",
           paste0(V[[k]]$unc, "/<Sp>/area_mean_replicates_germany.csv"), variant = k, w = 9.5, h = 6.8, draw = function() {
      r <- IDX[[k]]$rep; r <- r[r$year == curYear, ]; r0 <- IDX[[k]]$rep0; r0 <- r0[r0$year == curYear, ]
      par(mar = c(4, 11, 3, 1)); plot(NA, xlim = range(r$index, r0$index, 100, na.rm = TRUE), ylim = c(0.5, length(species) + 0.5), yaxt = "n", xlab = sprintf("Index %d (2005 = 100)", curYear), ylab = "", main = V[[k]]$full)
      axis(2, at = seq_along(species), labels = rev(english[species]), las = 1); abline(v = 100, lty = 3, col = "grey40")
      set.seed(1); for (i in seq_along(species)) { d <- r[r$species == rev(species)[i], ]; points(d$index, i + runif(nrow(d), -0.18, 0.18), pch = 16, cex = 0.8, col = adjustcolor(varCol[[k]], 0.55))
        m <- r0$index[r0$species == rev(species)[i]]; if (length(m)) points(m, i, pch = 18, cex = 1.9, col = "#b22222") }
      legend("bottomright", c("Replicate", "Main model"), pch = c(16, 18), col = c(varCol[[k]], "#b22222"), bty = "n")
    })
  }
  # (d) species index in the last year: main model + interval, both runs; and the table behind it
  rowsLast <- do.call(rbind, lapply(variants, function(k) { u <- IDX[[k]]$spUnc; if (is.null(u) || is.null(IDX[[k]]$main)) return(NULL); u <- u[u$year == curYear, ]
    data.frame(variant = k, species = u$species, main = unlist(IDX[[k]]$main[u$species, as.character(curYear)]), lwr = u$indexLwr, upr = u$indexUpr, repMean = u$indexMean) }))
  if (!is.null(rowsLast) && nrow(rowsLast)) {
    cmb <- do.call(rbind, lapply(variants, function(k) { x <- IDX[[k]]$comb; s <- IDX[[k]]$sbi; if (is.null(x) || is.null(s)) return(NULL); d <- x[x$method == "SBI" & x$year == curYear, ]
      data.frame(variant = k, species = "COMBINED (SBI)", main = s$sbi[s$year == curYear], lwr = d$lwr, upr = d$upr, repMean = d$estimate) }))
    tab <- rbind(rowsLast, cmb); tab$english <- ifelse(tab$species %in% names(english), english[tab$species], tab$species); tab$declinePct <- round(100 - tab$main, 1)
    tableOut(tab, sprintf("S3_species_index_%d", curYear))
    figure("S3_indices", sprintf("S3_species_%d_summary", curYear), sprintf("Index %d for every species and the combined index, with 90%% interval", curYear),
           "Main-model index in the last year (dot) with the 5th-95th percentile over the replicates (line). Below 100 = lower than in 2005. The combined index is the bottom row.",
           "species_index.csv, species_index_uncertainty.csv, combined_index_uncertainty.csv", variant = paste(variants, collapse = "+"), w = 10, h = 7, draw = function() {
      ord <- order(tab$main[tab$variant == variants[length(variants)] & tab$species != "COMBINED (SBI)"]); sps <- tab$species[tab$variant == variants[length(variants)] & tab$species != "COMBINED (SBI)"][ord]
      sps <- c(rev(sps), "COMBINED (SBI)"); sps <- rev(sps)                    # combined at the bottom
      par(mar = c(4, 11, 1, 1), oma = c(0, 0, 2.6, 0)); plot(NA, xlim = range(tab$lwr, tab$upr, 100, na.rm = TRUE), ylim = c(0.5, length(sps) + 0.5), yaxt = "n", xlab = sprintf("Index %d (2005 = 100)", curYear), ylab = "", main = "")
      axis(2, at = seq_along(sps), labels = ifelse(sps %in% names(english), english[sps], "Combined index"), las = 1, font = 1); abline(v = 100, lty = 3, col = "grey40"); abline(h = 1.5, col = "grey70")
      off <- if (length(variants) == 2) c(-0.15, 0.15) else 0
      for (j in seq_along(variants)) { d <- tab[tab$variant == variants[j], ]; y <- match(d$species, sps) + off[j]
        segments(d$lwr, y, d$upr, y, lwd = 3, col = adjustcolor(varCol[[variants[j]]], 0.6)); points(d$main, y, pch = 16, cex = 1.4, col = varCol[[variants[j]]]) }
      legend("topleft", sapply(variants, function(k) V[[k]]$full), pch = 16, col = varCol[variants], bty = "n", cex = 0.9); bigTitle(sprintf("Index in %d against 2005", curYear))
    })
  } else note("S3_species_summary", "no species index files")
  # (e) restricted chain (hindcast-robustness) if the file exists: both versions re-based to the first real-data year (= 100)
  for (k in variants) if (!is.null(IDX[[k]]$chainR)) figure("S3_indices", sprintf("S3_chain_restricted_%s", k), sprintf("Chain index from the years with real habitat data only (%s)", V[[k]]$label),
         "Robustness check: the chain index built with only the years that have real habitat-scale data (2022-2025, black dashed) against the chain index of the full series cut to the same years (colour); both set to 100 in 2022. Agreement means the hindcast years do not drive the result.",
         file.path(V[[k]]$report, "combined_index_chain_restricted.csv"), variant = k, w = 8.5, h = 6, draw = function() {
    cr <- IDX[[k]]$chainR; names(cr) <- tolower(names(cr)); full <- IDX[[k]]$comb; full <- full[full$method == "Chain" & full$year %in% cr$year, ]; full <- full[order(full$year), ]
    y0 <- min(cr$year); fullRel <- 100 * full$estimate / full$estimate[full$year == y0]; crRel <- 100 * cr$chainindex / cr$chainindex[cr$year == y0]
    par(mar = c(4.2, 4.6, 3.2, 1)); plot(NA, xlim = range(cr$year), ylim = range(fullRel, crRel, 100, na.rm = TRUE), xlab = "Year", ylab = sprintf("Chain index (%d = 100)", y0), main = V[[k]]$full, bty = "l", las = 1, xaxt = "n"); axis(1, at = cr$year)
    abline(h = 100, lty = 3, col = "grey40"); lines(full$year, fullRel, lwd = 3, col = varCol[[k]]); lines(cr$year, crRel, lwd = 3, col = "black", lty = 2)
    legend("bottomleft", c("Full series, cut to these years", "Built from these years only"), lwd = 3, lty = c(1, 2), col = c(varCol[[k]], "black"), bty = "n") })
  # sanity line: replicate-derived SBI against the reported one (the figures above use the reported tables)
  for (k in variants) if (!is.null(IDX[[k]]$rep) && !is.null(IDX[[k]]$comb)) { iv <- interval(repSBI(k)); rp <- IDX[[k]]$comb; rp <- rp[rp$method == "SBI" & rp$year == curYear, ]
    say("CHECK ", k, ": replicate SBI ", curYear, " mean/lwr/upr = ", paste(round(unlist(iv[as.character(curYear), c("mean", "lwr", "upr")]), 3), collapse = " / "), " | reported ", paste(round(c(rp$estimate, rp$lwr, rp$upr), 3), collapse = " / ")) }
}

## =================================================================================================================================================
## S4  per-pixel change and trend per species (maps of Germany only)
## =================================================================================================================================================
comps <- c(vsBaseline = baseYear, vs5YearsAgo = curYear - 5L, vsLastYear = curYear - 1L)
compLabel <- c(vsBaseline = sprintf("%d vs %d", curYear, baseYear), vs5YearsAgo = sprintf("%d vs %d", curYear, curYear - 5L), vsLastYear = sprintf("%d vs %d", curYear, curYear - 1L))
areaRows <- list(); ttRows <- list()
if ("S4" %in% sections) {
  say("--- S4 ---")
  for (k in variants) for (sp in species) {
    v <- V[[k]]; md <- uncMapsDir(k, sp)
    for (cp in names(comps)) {
      fu <- if (is.na(md)) NA_character_ else file.path(md, sprintf("%s_unc_change_%s.tif", spc(sp), cp)); fm <- file.path(v$report, sprintf("change_%s_%s.tif", cp, spc(sp)))
      figure("S4_species_change", sprintf("S4_change_%s_%s_%s", cp, spc(sp), k), sprintf("%s: change in probability of occurrence, %s (%s)", nm(sp), compLabel[[cp]], v$label),
             "Left: change in probability of occurrence of the main model (best estimate), every pixel; red = decline, blue = increase. Right: the same values, coloured only where the change is clear, i.e. the 90% interval over the replicates lies entirely below or entirely above zero; grey = the interval includes zero.",
             paste(fm, fu, sep = "; "), variant = k, w = 12, h = 6.6, draw = function() {
        need(fu); u <- rast(fu); l <- lay(u, "deltaLwr", 3); up <- lay(u, "deltaUpr", 4); sh <- areaShares(l, up)
        areaRows[[length(areaRows) + 1]] <<- data.frame(variant = k, species = sp, what = paste0("change_", cp), clearDecline = sh[["decline"]], clearIncrease = sh[["increase"]], nCells = sh[["nCells"]])
        useMain <- file.exists(fm) && isTRUE(compareGeom(rast(fm)[[1]], l, stopOnError = FALSE))
        d <- ger(if (useMain) lay(rast(fm), "deltaP", 1) else lay(u, "deltaMean", 1)); lim <- symLim(d); clr <- ger(clearMask(l, up))
        par(mfrow = c(1, 2), oma = c(1, 0, 2.6, 0))
        drawMap(d, if (useMain) "Main model: change in probability" else "Replicate mean: change in probability", palDiv, c(-lim, lim), mb = bm)
        drawClearOnly(d, clr, "Only where the change is clear", c(-lim, lim))
        bigTitle(sprintf("%s: change %s (%s)", nm(sp), compLabel[[cp]], v$label))
      })
    }
    fu <- if (is.na(md)) NA_character_ else file.path(md, sprintf("%s_unc_trend_per_decade.tif", spc(sp)))
    figure("S4_species_trend", sprintf("S4_trend_%s_%s", spc(sp), k), sprintf("%s: trend per decade at every pixel, %d-%d (%s)", nm(sp), baseYear, curYear, v$label),
           "Per-pixel linear trend of the probability of occurrence (change per decade), computed in every replicate. Left: mean over the replicates, every pixel (red = decline). Right: the same values only where the trend is clear, i.e. the 90% interval of the slope over the replicates excludes zero; grey = it includes zero.",
           fu, variant = k, w = 12, h = 6.6, draw = function() {
      need(fu); u <- rast(fu); l <- lay(u, "slopeLwr", 3); up <- lay(u, "slopeUpr", 4); sh <- areaShares(l, up)
      areaRows[[length(areaRows) + 1]] <<- data.frame(variant = k, species = sp, what = "trend", clearDecline = sh[["decline"]], clearIncrease = sh[["increase"]], nCells = sh[["nCells"]])
      d <- ger(lay(u, "slopeMean", 1)); lim <- symLim(d); clr <- ger(clearMask(l, up)); par(mfrow = c(1, 2), oma = c(1, 0, 2.6, 0))
      drawMap(d, "Trend per decade (probability), every pixel", palDiv, c(-lim, lim), mb = bm); drawClearOnly(d, clr, "Only where the trend is clear", c(-lim, lim))
      bigTitle(sprintf("%s: trend per decade, %d-%d (%s)", nm(sp), baseYear, curYear, v$label))
    })
    # classical test (Mann-Kendall + Sen slope) from the yearly main-model maps, next to the replicate criterion (needs tools/pixelTrendTest.R to have been run)
    ft <- file.path(root, paste0("pixel_trend_test_", k), sprintf("%s_pixel_trend_test.tif", spc(sp)))
    figure("S4_species_trend", sprintf("S4_trendtest_%s_%s", spc(sp), k), sprintf("%s: Mann-Kendall test of the trend at every pixel (%s)", nm(sp), v$label),
           sprintf("Left: Sen slope per decade of the main model's yearly maps, every pixel. Middle: the same values only where the Mann-Kendall test gives p < %g. Right: agreement with the replicate criterion (90%% interval of the slope excludes zero). The test only compares the predicted values with their own year-to-year variation; it ignores the uncertainty of the model and flags many pixels by construction, so the replicate criterion is the primary one.", alpha),
           paste(ft, fu, sep = "; "), variant = k, w = 17, h = 6.6, draw = function() {
      need(ft, fu); tt <- rast(ft); u <- rast(fu); l <- lay(u, "slopeLwr", 3); up <- lay(u, "slopeUpr", 4)
      if (!isTRUE(compareGeom(tt[[1]], l, stopOnError = FALSE))) stop("the test maps and the trend maps are not on the same grid")
      sen <- lay(tt, "senSlope", 1); p <- lay(tt, "pValue", 3); sigF <- ifel(is.na(p), NA, ifel(p < alpha, 1, 0)); clrF <- clearMask(l, up)
      n <- global(!is.na(p), "sum")[1, 1]
      ttRows[[length(ttRows) + 1]] <<- data.frame(variant = k, species = sp, alpha = alpha, nCells = n, sigShare = global(sigF == 1, "sum", na.rm = TRUE)[1, 1] / n, replicateClearShare = global(clrF == 1, "sum", na.rm = TRUE)[1, 1] / n,
                                                  bothShare = global((sigF == 1) & (clrF == 1), "sum", na.rm = TRUE)[1, 1] / n)
      d <- ger(sen); lim <- symLim(d); sig <- ger(sigF); clr <- ger(clrF); cls <- ifel(is.na(sig) | is.na(clr), NA, ifel((clr == 1) & (sig == 1), 1, ifel(clr == 1, 2, ifel(sig == 1, 3, 4))))
      par(mfrow = c(1, 3), oma = c(1, 0, 2.6, 0))
      drawMap(d, "Sen slope per decade, every pixel", palDiv, c(-lim, lim), mb = bm)
      drawClearOnly(d, sig, sprintf("Only where p < %g", alpha), c(-lim, lim))
      drawClasses(cls, "Agreement of the two criteria", c("both", "only the replicate interval", "only the Mann-Kendall test", "neither"), c("#4a2c82", colDec, "#e8a33d", colNone))
      bigTitle(sprintf("%s: trend per decade, two criteria (%s)", nm(sp), v$label))
    })
  }
  if (length(areaRows)) { ar <- do.call(rbind, areaRows); ar$notClear <- 1 - ar$clearDecline - ar$clearIncrease; tableOut(ar, "S4_area_clear_change_and_trend") }
  if (length(ttRows)) tableOut(do.call(rbind, ttRows), "S4_trendtest_shares")
}

## =================================================================================================================================================
## S5  community maps
## =================================================================================================================================================
if ("S5" %in% sections) {
  say("--- S5 ---")
  for (k in variants) {
    v <- V[[k]]; cm <- v$uncComm %||% ""; fmean <- file.path(cm, "community_meanDeltaP_unc_vsBaseline.tif"); fturn <- file.path(cm, "community_turnoverBC_unc_vsBaseline.tif")
    fcc <- file.path(v$report, "change_vsBaseline_community.tif")
    figure("S5_community", sprintf("S5_community_change_%s", k), sprintf("Community change %d vs %d: mean change, turnover, gains and losses (%s)", curYear, baseYear, v$label),
           "Top left: mean change in probability over the 11 species (red = decline). Top middle: the same only where the 90% interval over the replicates excludes zero (grey otherwise). Top right: Bray-Curtis turnover (0 = same community, 1 = no species in common). Bottom: number of species gained, number lost and the net (presence/absence maps).",
           paste(fmean, fturn, fcc, sep = "; "), variant = k, w = 14, h = 9, draw = function() {
      need(fmean); par(mfrow = c(2, 3), oma = c(1, 0, 2.8, 0))
      u <- rast(fmean); l <- lay(u, "deltaLwr", 3); up <- lay(u, "deltaUpr", 4)
      d <- ger(lay(u, "deltaMean", 1)); lim <- symLim(d); drawMap(d, "Mean change in probability", palDiv, c(-lim, lim), mb = bm)
      drawClearOnly(d, ger(clearMask(l, up)), "Only where the change is clear", c(-lim, lim))
      if (file.exists(fturn)) drawMap(ger(lay(rast(fturn), "mean", 1)), "Turnover (Bray-Curtis)", palSeq, c(0, 1), mb = bm) else plot.new()
      if (file.exists(fcc)) { cc <- rast(fcc); for (n in c("gainCount", "lossCount", "netGainLoss")) { r <- ger(lay(cc, n, 1))
          if (n == "netGainLoss") drawMap(r, "Net gain (+) or loss (-) of species", palDiv, c(-1, 1) * max(symLim(r), 1)) else drawMap(r, c(gainCount = "Number of species gained", lossCount = "Number of species lost")[[n]], palSeq, c(0, max(1, symLim(r, 1)))) } }
      else { for (i in 1:3) plot.new() }
      bigTitle(sprintf("Community change, %d vs %d (%s)", curYear, baseYear, v$label))
    })
    for (sp in species) { fg <- file.path(v$report, sprintf("change_vsBaseline_%s.tif", spc(sp)))
      figure("S5_community", sprintf("S5_gainloss_%s_%s", spc(sp), k), sprintf("%s: gain and loss of presence %d vs %d (%s)", nm(sp), curYear, baseYear, v$label),
             "Presence/absence maps compared: pixels where the species is predicted lost (red) or gained (blue) between the two years, stable present (green) or stable absent (light grey).",
             fg, variant = k, w = 6.5, h = 6.4, draw = function() {
        need(fg); r <- ger(lay(rast(fg), "gainLoss", 2)) + 1                    # 0..3 -> 1..4
        drawClasses(r, nm(sp), c("stable absent", "loss", "gain", "stable present"), c("#f5f5f5", colDec, colInc, "#2d6a4f")) })
    }
  }
}

## =================================================================================================================================================
## S6  regional index: change, cold/hot spots, trend, uncertainty
## =================================================================================================================================================
regionalChange <- function(k, km) {                                      # best estimate (main model) change in index points, from the baseline regional raster
  f <- file.path(V[[k]]$regional %||% "", sprintf("regional_index_%dkm_raw.tif", km)); need(f); r <- rast(f)
  b <- as.character(baseYear); y <- as.character(curYear); if (!all(c(b, y) %in% names(r))) stop("years ", b, "/", y, " not in ", basename(f))
  list(chg = r[[y]] - r[[b]], idx = r[[y]], file = f)
}
spotClass <- function(chg, thr) ifel(is.na(chg), NA, ifel(chg <= -thr, 1, ifel(chg < 0, 2, ifel(chg < thr, 3, 4))))
spotCols <- c("#8b1a1a", "#f0a8a0", "#a9c6ea", "#0b3d91")
spotLabels <- function(thr) c(sprintf("cold spot: index fell by %g points or more", thr), "smaller decline", "smaller increase", sprintf("hot spot: index rose by %g points or more", thr))
regionalClear <- function(k, km, chg, name = "change_vsBaseline") {        # 1 where the 90% interval of the replicate change/trend excludes zero, on the grid of `chg`
  f <- file.path(V[[k]]$uncReg, sprintf("regional_index_%dkm_unc_%s.tif", km, name)); if (!file.exists(f)) return(NULL)
  u <- rast(f); l <- lay(u, c("deltaLwr", "slopeLwr"), 3); up <- lay(u, c("deltaUpr", "slopeUpr"), 4)
  if (!isTRUE(compareGeom(l, chg, stopOnError = FALSE))) { l <- resample(l, chg, "near"); up <- resample(up, chg, "near") }
  clearMask(l, up)
}
lowCoverage <- function(k, km, chg) {
  f <- file.path(V[[k]]$uncReg, sprintf("regional_index_%dkm_coverage.tif", km)); if (!file.exists(f)) return(NULL)
  cv <- rast(f)[[1]]; if (!isTRUE(compareGeom(cv, chg, stopOnError = FALSE))) cv <- resample(cv, chg, "near"); p <- as.polygons(ifel(cv < minCoverage, 1, NA), dissolve = FALSE); if (nrow(p)) p else NULL
}
spotRows <- list()
if ("S6" %in% sections) {
  say("--- S6 ---")
  for (k in variants) for (km in cellKm) {
    v <- V[[k]]; fu <- file.path(v$uncReg, sprintf("regional_index_%dkm_unc_change_vsBaseline.tif", km)); fc <- file.path(v$uncReg, sprintf("regional_index_%dkm_coverage.tif", km))
    src <- paste(file.path(v$regional %||% "", sprintf("regional_index_%dkm_raw.tif", km)), fu, fc, sep = "; ")
    figure("S6_regional", sprintf("S6_regional_index_%dkm_%s", km, k), sprintf("Regional index %d (%d km cells, %s)", curYear, km, v$label),
           "Combined index of the 11 species per grid cell in the last year (main model, 2005 = 100 in every cell). Red = below 2005, blue = above.",
           file.path(v$regional %||% "", sprintf("regional_index_%dkm_raw.tif", km)), variant = k, w = 6.8, h = 6.6, draw = function() {
      rc <- regionalChange(k, km); par(oma = c(1, 0, 2.6, 0)); lim <- max(symLim(rc$idx - 100), 5); drawMap(rc$idx, sprintf("Regional index %d (2005 = 100)", curYear), palDiv, 100 + c(-1, 1) * lim); bigTitle(sprintf("%d km cells (%s)", km, v$label)) })
    figure("S6_regional", sprintf("S6_change_%dkm_%s", km, k), sprintf("Regional index: change %d vs %d, every cell and only the clear cells (%d km cells, %s)", curYear, baseYear, km, v$label),
           "Left: change of the regional index in index points (main model; index 2025 minus index 2005, which is 100 in every cell), every cell. Right: the same values, coloured only in the cells where the 90% interval of the change over the replicates excludes zero; grey = it includes zero. Red = decline, blue = increase.",
           src, variant = k, w = 12.5, h = 6.8, draw = function() {
      rc <- regionalChange(k, km); chg <- rc$chg; clr <- regionalClear(k, km, chg); if (is.null(clr)) stop("no replicate change file"); low <- lowCoverage(k, km, chg)
      lim <- max(symLim(chg), 5); par(mfrow = c(1, 2), oma = c(2.6, 0, 2.6, 0))
      drawMap(chg, "Change of the regional index (index points)", palDiv, c(-lim, lim), mb = bm); if (!is.null(low)) lines(low, col = "grey40", lwd = 1)
      drawClearOnly(chg, clr, "Only where the change is clear", c(-lim, lim), if (!is.null(low)) sprintf("grey outline: less than %d%% of the cell inside Germany", round(100 * minCoverage)), if (!is.null(low)) "white")
      if (!is.null(low)) lines(low, col = "grey40", lwd = 1)
      bigTitle(sprintf("Regional index (%d km): change %d vs %d (%s)", km, curYear, baseYear, v$label)); footnote("Index points: a cell at 85 in 2025 has lost 15 points relative to its own 2005 value (= 100), i.e. 15% of it.") })
    for (thr in spotPointsVec) {
      figure("S6_regional", sprintf("S6_coldhot_%dkm_%s_%gpts", km, k, thr), sprintf("Cold and hot spots of the regional index, change of %g index points or more (%d km cells, %s)", thr, km, v$label),
             sprintf("Cold spots = cells whose index fell by %g points or more between %d and %d (index 2005 = 100 in every cell, so %g points = %g%% of the cell's 2005 level); hot spots = rose by %g points or more. Left: by size of the change only. Right: only the cells where, in addition, the 90%% interval over the replicates excludes zero are coloured; grey = not clear.", thr, baseYear, curYear, thr, thr, thr),
             src, variant = k, w = 12.5, h = 7.2, draw = function() {
        rc <- regionalChange(k, km); chg <- rc$chg; cls <- spotClass(chg, thr); clr <- regionalClear(k, km, chg); low <- lowCoverage(k, km, chg)
        cnt <- table(factor(values(cls, na.rm = TRUE), levels = 1:4)); tot <- sum(cnt); nClearCold <- NA; nClearHot <- NA
        cls2 <- NULL; if (!is.null(clr)) { cls2 <- ifel(is.na(cls), NA, ifel(clr == 1, cls, 5)); cc <- table(factor(values(cls2, na.rm = TRUE), levels = 1:5)); nClearCold <- cc[[1]]; nClearHot <- cc[[4]] }
        spotRows[[length(spotRows) + 1]] <<- data.frame(variant = k, km = km, spotPoints = thr, nCells = tot, coldSpot = cnt[[1]], smallerDecline = cnt[[2]], smallerIncrease = cnt[[3]], hotSpot = cnt[[4]],
                                                        coldSpotAndClear = nClearCold, hotSpotAndClear = nClearHot, meanChange = mean(values(chg), na.rm = TRUE))
        par(mfrow = c(1, 2), oma = c(2.6, 0, 2.6, 0))
        drawClasses(cls, "By size of the change", spotLabels(thr), spotCols); if (!is.null(low)) lines(low, col = "grey40", lwd = 1)
        if (!is.null(cls2)) { drawClasses(cls2, "Only where the change is also clear", c(spotLabels(thr), "not clear (interval includes zero)"), c(spotCols, colNone)); if (!is.null(low)) lines(low, col = "grey40", lwd = 1) } else plot.new()
        bigTitle(sprintf("Regional index (%d km): cold and hot spots, %d vs %d (%s)", km, curYear, baseYear, v$label)); footnote(sprintf("Index points: a cell at 90 in 2025 has lost 10 points relative to its own 2005 value (= 100). Threshold in this figure: %g points.", thr)) })
    }
    ft <- file.path(v$uncReg, sprintf("regional_index_%dkm_unc_trend_per_decade.tif", km))
    figure("S6_regional", sprintf("S6_trend_%dkm_%s", km, k), sprintf("Regional index: trend per decade, every cell and only the clear cells (%d km cells, %s)", km, v$label),
           "Linear trend of the regional index over all years (index points per decade; mean over the replicates, red = decline). Left: every cell. Right: only the cells where the 90% interval of the slope over the replicates excludes zero; grey = it includes zero.",
           ft, variant = k, w = 12.5, h = 6.8, draw = function() {
      need(ft); u <- rast(ft); l <- lay(u, "slopeLwr", 3); up <- lay(u, "slopeUpr", 4); d <- lay(u, "slopeMean", 1); lim <- max(symLim(d), 1); par(mfrow = c(1, 2), oma = c(1, 0, 2.6, 0))
      drawMap(d, "Trend per decade (index points), every cell", palDiv, c(-lim, lim), mb = bm); drawClearOnly(d, clearMask(l, up), "Only where the trend is clear", c(-lim, lim))
      bigTitle(sprintf("Regional index (%d km): trend per decade (%s)", km, v$label)) })
    figure("S6_regional", sprintf("S6_uncertainty_%dkm_%s", km, k), sprintf("Regional index: how uncertain is the change? (%d km cells, %s)", km, v$label),
           "Left: width of the 90% interval of the change in index points over the replicates (wide = uncertain). Right: the share of replicates in which the cell's index is lower than in 2005 (secondary information).",
           fu, variant = k, w = 12.5, h = 6.2, draw = function() {
      need(fu); u <- rast(fu); par(mfrow = c(1, 2), oma = c(1, 0, 2.6, 0)); drawMap(lay(u, "deltaWidth", 5), "Width of the 90% interval (index points)", palSeq)
      drawMap(lay(u, "shareDecrease", 6), "Share of replicates with a decrease", palSeq, c(0, 1)); bigTitle(sprintf("Regional index (%d km): uncertainty of the change (%s)", km, v$label)) })
  }
  if (length(spotRows)) tableOut(do.call(rbind, spotRows), "S6_cold_hot_spot_counts")
}

## =================================================================================================================================================
## S7  robustness: BRT only against big 5; spread among algorithms
## =================================================================================================================================================
if ("S7" %in% sections) {
  say("--- S7 ---")
  if (all(c("brt", "big5") %in% variants)) for (km in cellKm) figure("S7_robustness", sprintf("S7_regional_brt_vs_big5_%dkm", km), sprintf("Does the cold/hot spot pattern depend on the algorithm? (%d km cells)", km),
        sprintf("Regional change %d vs %d (index points) for BRT only and for the big 5, their difference (big 5 minus BRT only), and the cells where the cold/hot class (threshold %g points) is the same in both runs.", curYear, baseYear, spotMain),
        "regional_index_<km>km_raw.tif of both runs", variant = "both", w = 13, h = 9, draw = function() {
    a <- regionalChange("brt", km)$chg; b <- regionalChange("big5", km)$chg; if (!isTRUE(compareGeom(a, b, stopOnError = FALSE))) b <- resample(b, a, "near")
    lim <- max(symLim(a), symLim(b), spotMain); par(mfrow = c(2, 2), oma = c(1, 0, 2.8, 0))
    drawMap(a, "BRT only", palDiv, c(-lim, lim)); drawMap(b, "Big 5", palDiv, c(-lim, lim))
    dd <- b - a; dl <- max(symLim(dd), 1); drawMap(dd, "Big 5 minus BRT only (index points)", palDiv, c(-dl, dl))
    ca <- spotClass(a, spotMain); cb <- spotClass(b, spotMain); agree <- ifel(is.na(ca) | is.na(cb), NA, ifel(ca == cb, 1, 2))
    drawClasses(agree, "Same cold/hot class in both runs?", c("same class", "different class"), c("#cfe3d6", "#b22222"))
    bigTitle(sprintf("BRT only against big 5, regional change %d vs %d (%d km)", curYear, baseYear, km)) })
  for (sp in species) {
    fs <- c(climate = file.path(scaleDirOf(sp, "climate"), sprintf("%s_sd_%s_climate_%d.tif", spc(sp), ensTag, curYear)), landscape = file.path(scaleDirOf(sp, "landscape"), sprintf("%s_sd_%s_landscape_%d.tif", spc(sp), ensTag, curYear)),
            habitat = file.path(scaleDirOf(sp, "habitat"), sprintf("%s_sd_%s_habitat_%d.tif", spc(sp), ensTag, curYear)))
    figure("S7_robustness", sprintf("S7_algorithm_spread_%s", spc(sp)), sprintf("%s: disagreement among the five algorithms, %d", nm(sp), curYear),
           "Standard deviation of the predicted probability across BRT, GLM, GAM, random forest and neural network, at each scale (before the meta-model). Dark = the algorithms disagree.",
           paste(fs, collapse = "; "), variant = "big5", w = 14, h = 5.6, draw = function() {
      need(fs); par(mfrow = c(1, 3), oma = c(1, 0, 2.6, 0)); zl <- c(0, max(sapply(fs, function(f) symLim(ger(rast(f)[[1]], 3e5), 1))))
      for (n in names(fs)) drawMap(ger(rast(fs[[n]])[[1]]), c(climate = "Climate (50 km)", landscape = "Landscape (1 km)", habitat = "Habitat (200 m)")[[n]], palSeq, zl)
      bigTitle(sprintf("%s: spread among algorithms, %d", nm(sp), curYear)) })
  }
}

## =================================================================================================================================================
## S8  expected species richness with uncertainty, and its change
## =================================================================================================================================================
if ("S8" %in% sections) {
  say("--- S8 ---")
  nSp <- length(allSpecies)                                              # expected richness = sum of the probabilities of ALL species; the mean change in probability times nSp is the change in richness
  for (k in variants) {
    v <- V[[k]]; ru <- file.path(v$uncComm %||% "", sprintf("richness_expected_unc_%d.tif", curYear)); fmean <- file.path(v$uncComm %||% "", "community_meanDeltaP_unc_vsBaseline.tif")
    figure("S2_maps", sprintf("S8_richness_interval_%s", k), sprintf("Expected species richness %d with its 90%% interval (%s)", curYear, v$label),
           sprintf("Expected richness = the sum of the probabilities of the %d species in each pixel, computed in every replicate. Top left: mean over the replicates. Top right and bottom left: 5th and 95th percentile (the 90%% interval). Bottom right: width of the interval (wide = uncertain). Only %d has an uncertainty layer.", nSp, curYear),
           ru, variant = k, w = 12, h = 10, draw = function() {
      need(ru); r <- rast(ru); par(mfrow = c(2, 2), oma = c(1, 0, 2.8, 0)); zl <- c(0, max(values(ger(lay(r, "upr", 4), 5e5), na.rm = TRUE)))
      drawMap(ger(lay(r, "mean", 1)), "Mean over the replicates", palRich, zl); drawMap(ger(lay(r, "lwr", 3)), "5th percentile (lower end)", palRich, zl)
      drawMap(ger(lay(r, "upr", 4)), "95th percentile (upper end)", palRich, zl); drawMap(ger(lay(r, "width", 5)), "Width of the 90% interval", palSeq)
      bigTitle(sprintf("Expected richness of the %d species, %d (%s)", nSp, curYear, v$label)) })
    if (!is.null(IDX[[k]]$rep)) figure("S2_maps", sprintf("S8_richness_national_%s", k), sprintf("Expected richness of Germany per year with its 90%% interval (%s)", v$label),
           "Mean expected richness over German pixels (sum over the species of each species' area mean probability), main model (line) and the 5th-95th percentile over the replicates (band), for every year. Grey = hindcast years.",
           paste0(v$unc, "/<Sp>/area_mean_replicates_germany.csv"), variant = k, w = 9.5, h = 6, draw = function() {
      r <- IDX[[k]]$rep; r0 <- IDX[[k]]$rep0; sr <- aggregate(areaMean ~ replicate + year, r, sum); sr0 <- aggregate(areaMean ~ replicate + year, r0, sum); yrs <- sort(unique(sr$year))
      q <- do.call(rbind, lapply(split(sr, sr$year), function(d) data.frame(year = d$year[1], lwr = quantile(d$areaMean, 0.05), upr = quantile(d$areaMean, 0.95)))); yl <- range(q$lwr, q$upr, sr0$areaMean)
      par(mar = c(4.2, 4.6, 3, 1)); plot(NA, xlim = range(yrs), ylim = yl, xlab = "Year", ylab = "Expected richness (species per pixel)", main = v$full, bty = "l", las = 1); hindcastBox(yrs, yl)
      polygon(c(q$year, rev(q$year)), c(q$lwr, rev(q$upr)), col = adjustcolor(varCol[[k]], 0.25), border = NA); sr0 <- sr0[order(sr0$year), ]; lines(sr0$year, sr0$areaMean, lwd = 3, col = "black")
      legend("bottomleft", c("Main model", "90% interval over the replicates"), lwd = c(3, 8), col = c("black", adjustcolor(varCol[[k]], 0.4)), bty = "n") })
    figure("S5_community", sprintf("S8_richness_change_%s", k), sprintf("Change in expected richness %d vs %d, in number of species (%s)", curYear, baseYear, v$label),
           sprintf("Change of expected richness between %d and %d in number of species (mean change in probability over the species times %d). Left: every pixel (red = fewer species expected). Right: only where the 90%% interval over the replicates excludes zero; grey = it includes zero.", baseYear, curYear, nSp),
           fmean, variant = k, w = 12, h = 6.6, draw = function() {
      need(fmean); u <- rast(fmean); l <- lay(u, "deltaLwr", 3); up <- lay(u, "deltaUpr", 4); d <- ger(nSp * lay(u, "deltaMean", 1)); lim <- symLim(d)
      par(mfrow = c(1, 2), oma = c(1, 0, 2.6, 0)); drawMap(d, "Change in expected richness (species)", palDiv, c(-lim, lim), mb = bm); drawClearOnly(d, ger(clearMask(l, up)), "Only where the change is clear", c(-lim, lim))
      bigTitle(sprintf("Expected richness: change %d vs %d (%s)", curYear, baseYear, v$label)) })
  }
}

## =================================================================================================================================================
## S9  observed trends from the DDA territory data (2005-2024): abundance against occupancy, and against our modelled index (needs inputs/response/processed/territories_csv;
##     run locally: Rscript tools/makeStCoFigures.R --run test4 --variants big5 --sections S9 --out outputs/test4/figures_fullreport)
##     Rules as in Kamp et al. 2021 (J Ornithol 162): only plots surveyed in at least two years, the first year of each plot series is dropped, the reference year is 2006.
##     Not done: the observer correction (no observer id in the file) and the TRIM-GEE error model; the model here is a plain log-linear model with plot and year effects.
## =================================================================================================================================================
if ("S9" %in% sections) {
  say("--- S9 ---")
  vsK <- if ("big5" %in% variants) "big5" else variants[1]
  obsBase <- as.integer(getArg("--obs-base-year", 2006))
  vf <- file.path("inputs", "response", "processed", "territories_csv", "dda_visits.csv"); df <- file.path("inputs", "response", "processed", "territories_csv", "dda_data.csv")
  if (!all(file.exists(vf, df)) || !requireNamespace("data.table", quietly = TRUE)) note("S9", "needs data.table and the csv copies of the DDA territory files in inputs/response/processed/territories_csv") else {
    suppressMessages(library(data.table))
    vis <- fread(vf); dat <- fread(df); dat[, year := as.integer(substr(Countdate, 1, 4))]
    plotYears <- unique(vis[, .(plot = ROUTENCODE, year = Jahr)])
    nSurveyed <- plotYears[, .N, by = plot]; plotYears <- plotYears[plot %in% nSurveyed[N >= 2, plot]]                  # only plots surveyed in at least two years
    plotYears <- merge(plotYears, plotYears[, .(first = min(year)), by = plot], by = "plot")[year > first, .(plot, year)]   # the first year of each plot series is dropped (observer learning)
    yrsObs <- sort(unique(plotYears$year)); plots <- sort(unique(plotYears$plot)); bi <- match(obsBase, yrsObs)
    # TRIM-like model without covariates: expected value of plot p in year y = a_p * b_y (iterative scaling over the surveyed plot-years); index = 100 * b_y / b_reference year.
    # Run on the territory counts (abundance) and on presence/absence (occupancy) with the same model, so that the two differ only by the data.
    ipf <- function(M, S) {
      M0 <- M; M0[!S] <- 0; b <- rep(1, ncol(M))
      keep <- rowSums(M0) > 0; M0 <- M0[keep, , drop = FALSE]; Sk <- S[keep, , drop = FALSE] * 1
      for (it in 1:2000) { a <- rowSums(M0) / as.vector(Sk %*% b); b2 <- colSums(M0) / as.vector(t(Sk) %*% a); b2 <- b2 / b2[bi]; if (max(abs(b2 - b)) < 1e-9) { b <- b2; break }; b <- b2 }
      100 * b
    }
    chain <- function(M, S) {                                           # matched plots, year to year, chained from the first year, then set to 100 in the reference year (robustness check)
      idx <- numeric(ncol(M)); idx[1] <- 100
      for (j in 2:ncol(M)) { m <- S[, j - 1] & S[, j]; r <- if (sum(m) > 0 && mean(M[m, j - 1]) > 0) mean(M[m, j]) / mean(M[m, j - 1]) else 1; idx[j] <- idx[j - 1] * r }
      100 * idx / idx[bi]
    }
    S <- matrix(FALSE, length(plots), length(yrsObs), dimnames = list(plots, yrsObs)); S[cbind(match(plotYears$plot, plots), match(plotYears$year, yrsObs))] <- TRUE
    seriesRows <- list()
    for (sp in allSpecies) {
      e <- speciesCanonical$euring_code[speciesCanonical$latin_name == sp]; d <- dat[EURING == e, .(n = sum(Reviere)), by = .(plot = ROUTENCODE, year)]
      d <- d[!is.na(match(d$plot, plots)) & !is.na(match(d$year, yrsObs)), ]
      Mn <- matrix(0, length(plots), length(yrsObs), dimnames = list(plots, yrsObs)); Mn[cbind(match(d$plot, plots), match(d$year, yrsObs))] <- d$n; Mn[!S] <- NA
      Mp <- (Mn > 0) * 1
      seriesRows[[sp]] <- data.frame(species = sp, year = yrsObs, abundance = ipf(Mn, S), occupancy = ipf(Mp, S), abundanceChain = chain(Mn, S), occupancyChain = chain(Mp, S), plotsSurveyed = colSums(S))
    }
    ser <- do.call(rbind, seriesRows); rownames(ser) <- NULL
    ours <- IDX[[vsK]]$main                                              # main-model species index, species x years (2005 = 100); set to 100 in the reference year here
    ser$modelled <- mapply(function(sp, y) 100 * ours[sp, as.character(y)] / ours[sp, as.character(obsBase)], ser$species, ser$year)
    geo <- function(v) exp(mean(log(pmax(v, 1e-3))))
    comb <- function(spp) do.call(rbind, lapply(yrsObs, function(y) { d <- ser[ser$year == y & ser$species %in% spp, ]
      data.frame(year = y, abundance = geo(d$abundance), occupancy = geo(d$occupancy), modelled = geo(d$modelled)) }))
    germanList <- c("Saxicola rubetra", "Alauda arvensis", "Emberiza citrinella", "Emberiza calandra", "Lullula arborea", "Vanellus vanellus", "Lanius collurio")   # species of the German indicator that are also in our 11
    c11 <- comb(allSpecies); c7 <- comb(germanList)
    ser$english <- english[ser$species]; tableOut(ser[, c("species", "english", "year", "abundance", "occupancy", "abundanceChain", "occupancyChain", "modelled", "plotsSurveyed")], "S9_observed_vs_modelled_series")
    at <- function(y) { do.call(rbind, lapply(allSpecies, function(sp) { d <- ser[ser$species == sp & ser$year == y, ]; data.frame(species = sp, english = english[[sp]], year = y, observedAbundance = d$abundance, observedOccupancy = d$occupancy, modelled = d$modelled) })) }
    addComb <- function(tb, y) rbind(tb, data.frame(species = "COMBINED (11 species)", english = "Combined (11 species)", year = y, observedAbundance = c11$abundance[c11$year == y], observedOccupancy = c11$occupancy[c11$year == y], modelled = c11$modelled[c11$year == y]),
                                          data.frame(species = "COMBINED (7 species of the German indicator)", english = "Combined (7 species of the German indicator)", year = y, observedAbundance = c7$abundance[c7$year == y], observedOccupancy = c7$occupancy[c7$year == y], modelled = c7$modelled[c7$year == y]))
    last <- max(yrsObs); tableOut(addComb(at(last), last), "S9_observed_vs_modelled_species_last_year"); tableOut(addComb(at(2018), 2018), "S9_observed_vs_modelled_species_2018")
    gerFile <- file.path("data", "reference", "uba_agrarland_subindex_Germany.csv"); gerCol <- "#6a3d9a"
    col3 <- c(abundance = "black", occupancy = "#2d8a4e", modelled = varCol[[vsK]])
    figure("S3_indices", "S9_observed_vs_modelled_combined", sprintf("Observed abundance and occupancy (DDA territory data) against our modelled index, %d-%d", min(yrsObs), last),
           sprintf("From the DDA territory data (%s plots): the same plot-based model (plot and year effects) applied to the number of territories (abundance) and to presence/absence (occupancy), against the modelled combined index. Left: our 11 species. Right: the 7 of them that are in the German farmland indicator, with that indicator. All set to 100 in %d.", format(length(plots), big.mark = ","), obsBase),
           paste(vf, df, "annual_report*_germany/species_index.csv", sep = "; "), variant = vsK, w = 14, h = 6.6, draw = function() {
      par(mfrow = c(1, 2), mar = c(4.2, 4.6, 3.2, 1), oma = c(5, 0, 2.4, 0))
      for (pn in 1:2) { cb <- if (pn == 1) c11 else c7; yl <- c(40, max(110, max(cb[, c("abundance", "occupancy", "modelled")], na.rm = TRUE) + 3))
        plot(NA, xlim = range(yrsObs), ylim = yl, xlab = "Year", ylab = sprintf("Index (%d = 100)", obsBase), main = if (pn == 1) "11 species" else "7 species of the German indicator", bty = "l", las = 1); abline(h = 100, lty = 3, col = "grey40")
        for (n in names(col3)) lines(cb$year, cb[[n]], lwd = 3, col = col3[[n]])
        if (pn == 2 && file.exists(gerFile)) { g <- read.csv(gerFile); g <- g[g$year >= obsBase & g$year <= last, ]; lines(g$year, 100 * g$agrarland_pct_of_target / g$agrarland_pct_of_target[g$year == obsBase], lwd = 2.5, col = gerCol, lty = 2) }
        legend("bottomleft", c("observed abundance (territories)", "observed occupancy (presence)", "our modelled index", if (pn == 2) "German indicator Agrarland (UBA/BfN)"), col = c(col3, if (pn == 2) gerCol), lwd = c(3, 3, 3, if (pn == 2) 2.5), lty = c(1, 1, 1, if (pn == 2) 2), bty = "n", cex = 0.9) }
      bigTitle("Observed and modelled trends")
      mtext(sprintf("DDA territory data: plots surveyed in at least two years, first year of each plot dropped, reference year %d (as Kamp et al. 2021); plain log-linear model with plot and year effects, no observer correction.\nOur index: main model, probability of occurrence; its landscape scale is fitted on part of these data. The German indicator is percent of a target value divided by its %d value.", obsBase, obsBase), outer = TRUE, side = 1, line = 2.2, cex = 0.8, col = "grey30") })
    # the closest like-for-like comparison: same 11 species, same country, same years, same metric (occurrence) and, for reference, abundance; our MSI with its 90% interval
    xm <- IDX[[vsK]]$comb; xm <- xm[xm$method == "MSI" & xm$year %in% yrsObs, ]; xm <- xm[order(xm$year), ]; fm <- 100 / xm$estimate[xm$year == obsBase]
    cmpV <- merge(data.frame(year = xm$year, ourMSI = xm$estimate * fm, ourMSI_lwr90 = xm$lwr * fm, ourMSI_upr90 = xm$upr * fm), data.frame(year = c11$year, observedOccupancy = c11$occupancy, observedAbundance = c11$abundance), by = "year", all.x = TRUE)
    if (file.exists(gerFile)) { g0 <- read.csv(gerFile); cmpV <- merge(cmpV, data.frame(year = g0$year, germanIndicatorAgrarland = 100 * g0$agrarland_pct_of_target / g0$agrarland_pct_of_target[g0$year == obsBase]), by = "year", all.x = TRUE) }
    tableOut(cmpV, "S9_closest_comparison_values")                       # the plotted values, index with the reference year = 100
    for (withGer in c(FALSE, TRUE)) figure("S3_indices", if (withGer) "S9_closest_comparison_german" else "S9_closest_comparison", sprintf("Our combined index and the observed trends of the same 11 species in Germany, %d = 100%s", obsBase, if (withGer) ", with the German indicator" else ""),
           sprintf("The closest comparison we can make: the same 11 species in Germany. Observed occupancy (presence on the surveyed DDA plots, same quantity as our probability of occurrence) and observed abundance (number of territories), from the DDA territory data (%s plots), against our MSI (geometric mean of the species indices, each the mean of 25 bootstrap replicates; band = 90%% Monte Carlo interval from the spread of the replicates)%s. All set to 100 in %d.", format(length(plots), big.mark = ","), if (withGer) ", with the German indicator Agrarland (UBA/BfN, abundance of selected farmland birds, to 2023)" else "", obsBase),
           paste(vf, df, "annual_report*_germany/combined_index_uncertainty.csv", sep = "; "), variant = vsK, w = 11.5, h = 6.8, draw = function() {
      par(mar = c(4.2, 4.6, 3, 1), oma = c(if (withGer) 8.4 else 6.2, 0, 1, 0)); yl <- c(40, max(110, c11$abundance, c11$occupancy, xm$upr * fm, na.rm = TRUE) + 3)
      plot(NA, xlim = range(yrsObs), ylim = yl, xlab = "Year", ylab = sprintf("Index (%d = 100)", obsBase), bty = "l", las = 1); abline(h = 100, lty = 3, col = "grey40")
      polygon(c(xm$year, rev(xm$year)), c(xm$lwr * fm, rev(xm$upr * fm)), col = adjustcolor(varCol[[vsK]], 0.25), border = NA)
      lines(xm$year, xm$estimate * fm, col = varCol[[vsK]], lwd = 3.5); lines(c11$year, c11$occupancy, col = "#2d8a4e", lwd = 3); lines(c11$year, c11$abundance, col = "black", lwd = 3, lty = 2)
      gerOk <- withGer && file.exists(gerFile); if (gerOk) { g <- read.csv(gerFile); g <- g[g$year >= obsBase & g$year <= last, ]; g$idx <- 100 * g$agrarland_pct_of_target / g$agrarland_pct_of_target[g$year == obsBase]; lines(g$year, g$idx, lwd = 3, col = gerCol, lty = 4) }
      legend("bottomleft", c(sprintf("Our MSI, 11 species, probability of occurrence (%.0f in %d)", (xm$estimate * fm)[nrow(xm)], max(xm$year)), "  its 90% interval (Monte Carlo from the spread of the 25 replicates)",
                             sprintf("Observed occupancy, same 11 species, DDA plots (%.0f in %d)", c11$occupancy[nrow(c11)], max(c11$year)), sprintf("Observed abundance, same 11 species, DDA territories (%.0f in %d)", c11$abundance[nrow(c11)], max(c11$year)),
                             if (gerOk) sprintf("German indicator Agrarland (UBA/BfN), abundance, about 10 species (%.0f in %d)", g$idx[nrow(g)], max(g$year))),
             col = c(varCol[[vsK]], adjustcolor(varCol[[vsK]], 0.25), "#2d8a4e", "black", if (gerOk) gerCol), lwd = c(3.5, 8, 3, 3, if (gerOk) 3), lty = c(1, 1, 1, 2, if (gerOk) 4), bty = "n", cex = 0.9)
      mtext(sprintf("Observed series: DDA territory data, plots surveyed in at least two years, first year of each plot dropped, reference year %d (rules of Kamp et al. 2021);\nplain log-linear model with plot and year effects, no observer correction. Observed and modelled series are geometric means over the 11 species.\nOur MSI: the species indices are the means of 25 bootstrap replicates of the model ensemble (probability of occurrence, Germany).\n%sOur landscape scale is fitted on part of these data, so this is not an independent test.", obsBase, if (gerOk) "The German indicator (UBA/BfN, DDA data) is percent of a target value divided by its reference-year value; its species are not the same as ours.\n" else ""), outer = TRUE, side = 1, line = if (gerOk) 3.6 else 2.4, cex = 0.8, col = "grey30") })
    figure("S3_indices", "S9_observed_vs_modelled_species", sprintf("Observed abundance and occupancy against our modelled index, per species, %d-%d", min(yrsObs), last),
           sprintf("The same three series for each of the 11 species: observed abundance (DDA territories), observed occupancy (presence on the surveyed plots) and our modelled index. All set to 100 in %d.", obsBase),
           paste(vf, df, "annual_report*_germany/species_index.csv", sep = "; "), variant = vsK, w = 14, h = 9, draw = function() {
      par(mfrow = c(3, 4), mar = c(3, 3.6, 2.4, 0.6), oma = c(1.5, 0, 3, 0), mgp = c(2.2, 0.7, 0))
      for (sp in allSpecies) { d <- ser[ser$species == sp, ]; yl <- range(c(d$abundance, d$occupancy, d$modelled, 100), na.rm = TRUE); yl <- yl + c(-1, 1) * 0.04 * diff(yl)
        plot(NA, xlim = range(yrsObs), ylim = yl, xlab = "", ylab = sprintf("Index (%d = 100)", obsBase), main = english[[sp]], cex.main = 1.1, bty = "l", las = 1); abline(h = 100, lty = 3, col = "grey40")
        for (n in names(col3)) lines(d$year, d[[n]], lwd = 2.4, col = col3[[n]]) }
      plot.new(); legend("center", c("observed abundance (territories)", "observed occupancy (presence)", "our modelled index"), col = col3, lwd = 3, bty = "n", cex = 1.05)
      bigTitle("Observed and modelled index, per species") })
  }
}

saveBook()
say("=== done: ", length(manifest), " figures, ", length(skipped), " skipped | ", out, " ===")
if (length(skipped)) say("See ", file.path(out, "skipped.csv"))
marker <- Sys.getenv("UNC_DONE_MARKER", ""); if (nzchar(marker)) writeLines("ok", marker)
