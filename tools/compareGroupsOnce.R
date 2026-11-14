#!/usr/bin/env Rscript
# ONE-OFF LOOK (2026-11-14), not part of the pipeline: the species groups side by side. READ-ONLY, uses terra + base R only and changes nothing in outputs/<run>/ except its own folder.
#   Rscript tools/compareGroupsOnce.R [--run v3] [--ens-tag ens_brt-glm-gam-rf-nn] [--base-year 2005] [--year 2025]      On EVE: sbatch cluster/eve_compare_groups.sbatch
# Writes outputs/<run>/figures_groups_compare/: richness_2005_vs_2025.png, regional_index_by_group_10km.png, national_index_by_group.png, richness_by_group.csv, national_index_by_group.csv.
# Reads, for every group of data/speciesGroups.csv, the ensemble results: uncertainty_<tag>/community<_group>_germany (richness), regional_index_<tag>_germany<_group> + uncertainty_<tag>/regional<_group>,
# annual_report_<tag>_germany<_group>. Delete this script and its sbatch when the look is done.
Sys.setenv(OMP_NUM_THREADS = "1")
args <- commandArgs(trailingOnly = TRUE); getArg <- function(f, d) { i <- which(args == f); if (length(i)) args[i + 1] else d }
setwd(normalizePath(getArg("--repo-root", getwd()), winslash = "/"))
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*")); if (length(libs)) .libPaths(c(libs, .libPaths()))
suppressMessages(library(terra))
source("modules/models_Monitor/R/uncRegional.R"); for (f in c("laeaAlias.R", "studyArea.R")) source(file.path("modules/models_Monitor/R", f))
source("tools/sharedSpeciesCanonical.R"); source("tools/sharedSpeciesGroups.R")
run <- getArg("--run", Sys.getenv("BIRDMONITOR_RUNNAME", "v3")); ensTag <- getArg("--ens-tag", "ens_brt-glm-gam-rf-nn"); y0 <- as.integer(getArg("--base-year", 2005)); y1 <- as.integer(getArg("--year", 2025))
root <- file.path("outputs", run); out <- file.path(root, "figures_groups_compare"); dir.create(out, showWarnings = FALSE)
roster <- canonicalIncludedSpecies(loadSpeciesCanonical("data/speciesCanonical.csv")); sg <- loadSpeciesGroups("data/speciesGroups.csv", roster)
firstExisting <- function(...) { p <- c(...); p <- p[file.exists(p)]; if (length(p)) p[1] else NA_character_ }
unc <- file.path(root, paste0("uncertainty_", ensTag))
GP <- lapply(setNames(sg$groups, sg$groups), function(g) { s <- groupSuffix(g); b <- function(pre) file.path(root, paste0(pre, "_", ensTag, "_germany", s))
  list(g = g, label = sg$labels[[g]], n = length(sg$members[[g]]), comm = firstExisting(file.path(unc, paste0("community", s, "_germany"))), reg = b("regional_index"), report = b("annual_report"), uncReg = file.path(unc, paste0("regional", s))) })
GP <- GP[sapply(GP, function(p) !is.na(p$comm) && dir.exists(p$reg) && dir.exists(p$report))]; stopifnot(length(GP) >= 2)
message("groups: ", paste(names(GP), collapse = ", "), " | out ", out)
outline <- tryCatch(uncOutlineLAEA(file.path("inputs", "predictors", "raw", "gadm"), "EPSG:3035"), error = function(e) NULL)
palDiv <- rev(hcl.colors(100, "Blue-Red 3")); palRich <- hcl.colors(100, "Mako"); colNone <- "#e3e3e3"
ger <- function(r, n = 1.2e6) { if (!is.null(outline)) r <- crop(r, ext(outline), snap = "out"); if (ncell(r) > n) r <- spatSample(r, n, method = "regular", as.raster = TRUE); if (!is.null(outline)) r <- mask(r, outline); r }
lay <- function(r, cand, pos) { for (n in cand) if (n %in% names(r)) return(r[[n]]); r[[pos]] }
symLim <- function(r, q = 0.99) { v <- abs(values(r, na.rm = TRUE)); if (!length(v)) 1 else max(quantile(v, q), 1e-9) }
clampIn <- function(r, lo, hi) { e <- 1e-4 * (hi - lo); clamp(r, lo + e, hi - e) }
clearMask <- function(lwr, upr) ifel(is.na(upr), NA, ifel((upr < 0) | (lwr > 0), 1, 0))
drawMap <- function(r, main, pal, zlim, mb = 6.4) { r <- clampIn(r, zlim[1], zlim[2]); plot(r, col = pal, range = zlim, main = main, axes = FALSE, box = FALSE, mar = c(mb, 1, 3, 5.5), cex.main = 1.1); if (!is.null(outline)) lines(outline, lwd = 0.9, col = "grey25") }
drawClear <- function(v, clr, main, zlim) { plot(ifel(is.na(v), NA, 1), col = colNone, legend = FALSE, main = main, axes = FALSE, box = FALSE, mar = c(6.4, 1, 3, 5.5), cex.main = 1.1)
  plot(ifel(clr == 1, clampIn(v, zlim[1], zlim[2]), NA), col = palDiv, range = zlim, add = TRUE); if (!is.null(outline)) lines(outline, lwd = 0.9, col = "grey25") }
png1 <- function(name, w, h, draw) { f <- file.path(out, name); ok <- tryCatch({ png(f, width = w, height = h, units = "in", res = 150, type = if (capabilities("cairo")) "cairo" else "windows"); draw(); dev.off(); TRUE },
  error = function(e) { while (dev.cur() > 1) dev.off(); message("FAILED ", name, ": ", conditionMessage(e)); FALSE }); if (ok) message("made ", f) }
txt <- function(s) mtext(s, outer = TRUE, side = 3, line = 0.4, font = 2, cex = 1.3); foot <- function(s) mtext(s, outer = TRUE, side = 1, line = 0.6, cex = 0.8, col = "grey30")
grpTxt <- paste(sapply(GP, function(p) sprintf("%s: %d species", p$label, p$n)), collapse = "; ")
fRich <- function(p, y) file.path(p$comm, sprintf("richness_expected_unc_%d.tif", y)); fDelta <- function(p) file.path(p$comm, "community_meanDeltaP_unc_vsBaseline.tif")

# 1. expected richness 2005 and 2025, the change, and where the change is clear (one row per group)
png1(sprintf("richness_%d_vs_%d.png", y0, y1), 19, 4.9 * length(GP) + 1, function() {
  dl <- lapply(GP, function(p) { u <- rast(fDelta(p)); list(d = ger(p$n * lay(u, "deltaMean", 1)), l = lay(u, "deltaLwr", 3), up = lay(u, "deltaUpr", 4)) })
  lim <- max(sapply(dl, function(z) symLim(z$d)), 0.5); par(mfrow = c(length(GP), 4), oma = c(2.6, 0, 2.8, 0))
  for (i in seq_along(GP)) { p <- GP[[i]]; a <- ger(lay(rast(fRich(p, y0)), "mean", 1)); b <- ger(lay(rast(fRich(p, y1)), "mean", 1)); zl <- c(0, max(values(a, na.rm = TRUE), values(b, na.rm = TRUE)))
    drawMap(a, sprintf("%s: %d", p$label, y0), palRich, zl); drawMap(b, sprintf("%s: %d", p$label, y1), palRich, zl)
    drawMap(dl[[i]]$d, sprintf("Change in expected richness, %d vs %d (species)", y1, y0), palDiv, c(-lim, lim)); drawClear(dl[[i]]$d, ger(clearMask(dl[[i]]$l, dl[[i]]$up)), "Only where the change is clear (grey: interval includes zero)", c(-lim, lim)) }
  txt(sprintf("Expected species richness, %d and %d, by species group", y0, y1)); foot(paste0("Richness is relative (probabilities summed), so compare pattern and change, not the numbers between rows. ", grpTxt, ".")) })
rs <- do.call(rbind, lapply(GP, function(p) { m <- sapply(c(y0, y1), function(y) global(lay(rast(fRich(p, y)), "mean", 1), "mean", na.rm = TRUE)[1, 1])
  data.frame(group = p$g, label = p$label, nSpecies = p$n, meanRichnessBase = m[1], meanRichnessCurrent = m[2], change = m[2] - m[1], changePercent = 100 * (m[2] - m[1]) / m[1]) }))
write.csv(rs, file.path(out, "richness_by_group.csv"), row.names = FALSE); print(rs)

# 2. regional index (10 km): the index in the last year, the change since the base year, and where the change is clear
png1("regional_index_by_group_10km.png", 16, 4.9 * length(GP) + 1, function() {
  fRaw <- function(p) file.path(p$reg, "regional_index_10km_raw.tif"); fClr <- function(p) file.path(p$uncReg, "regional_index_10km_unc_change_vsBaseline.tif")
  zz <- lapply(GP, function(p) { r <- rast(fRaw(p)); list(idx = r[[as.character(y1)]], chg = r[[as.character(y1)]] - r[[as.character(y0)]]) })
  lim <- max(sapply(zz, function(z) symLim(z$chg)), 5); limI <- max(sapply(zz, function(z) symLim(z$idx - 100)), 5); par(mfrow = c(length(GP), 3), oma = c(2.6, 0, 2.8, 0))
  for (i in seq_along(GP)) { p <- GP[[i]]; z <- zz[[i]]
    drawMap(z$idx, sprintf("%s: regional index %d (%d = 100)", p$label, y1, y0), palDiv, 100 + c(-1, 1) * limI); drawMap(z$chg, sprintf("Change %d vs %d (index points)", y1, y0), palDiv, c(-lim, lim))
    if (file.exists(fClr(p))) { u <- rast(fClr(p)); l <- lay(u, c("deltaLwr", "slopeLwr"), 3); up <- lay(u, c("deltaUpr", "slopeUpr"), 4)
      if (!isTRUE(compareGeom(l, z$chg, stopOnError = FALSE))) { l <- resample(l, z$chg, "near"); up <- resample(up, z$chg, "near") }
      drawClear(z$chg, clearMask(l, up), "Only where the change is clear (grey: interval includes zero)", c(-lim, lim)) } else plot.new() }
  txt(sprintf("Regional index (10 km cells), %d vs %d", y1, y0)); foot("Index points: a cell at 85 in 2025 has lost 15 points relative to its own 2005 value (= 100). Relative to each cell's own 2005 level, not a count of birds.") })

# 3. national index of every group in one panel (line = main model SBI, band = 90% Monte Carlo interval of the MSI)
png1("national_index_by_group.png", 10, 6.6, function() {
  rd <- function(f) { x <- read.csv(f, check.names = FALSE, stringsAsFactors = FALSE); names(x) <- tolower(names(x)); x }
  xs <- lapply(GP, function(p) { u <- rd(file.path(p$report, "combined_index_uncertainty.csv")); u <- u[u$method == "MSI", ]; list(u = u[order(u$year), ], s = { s <- rd(file.path(p$report, "combined_index_sbi.csv")); s[order(s$year), ] }) })
  cols <- c("#1f4e79", "#c4551f", "#2d8a4e", "#6a3d9a")[seq_along(GP)]
  write.csv(do.call(rbind, lapply(seq_along(GP), function(i) data.frame(group = GP[[i]]$g, year = xs[[i]]$s$year, sbi = xs[[i]]$s$sbi))), file.path(out, "national_index_by_group.csv"), row.names = FALSE)
  rng <- range(unlist(lapply(xs, function(x) c(x$u$lwr, x$u$upr, x$s$sbi))), 100, na.rm = TRUE) + c(-0.4, 0.4)
  par(mar = c(4.2, 4.6, 3.2, 1)); plot(NA, xlim = range(unlist(lapply(xs, function(x) x$s$year))), ylim = rng, xlab = "Year", ylab = sprintf("Index (%d = 100)", y0), main = "Combined index by species group, Germany", bty = "l", las = 1); abline(h = 100, lty = 3, col = "grey40")
  for (i in seq_along(GP)) { x <- xs[[i]]; polygon(c(x$u$year, rev(x$u$year)), c(x$u$lwr, rev(x$u$upr)), col = adjustcolor(cols[i], 0.2), border = NA); lines(x$s$year, x$s$sbi, col = cols[i], lwd = 3) }
  legend("bottomleft", sapply(GP, function(p) sprintf("%s (%d species)", p$label, p$n)), col = cols, lwd = 3, bty = "n") })
message("done")
