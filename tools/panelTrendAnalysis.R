#!/usr/bin/env Rscript
# Same-plot panel: observed occupancy and abundance against our predictions at the SAME plots and years (input: outputs/<run>/panel_trend_check/<Species>.csv from tools/panelTrendCheck.R).
# Rules of the DDA / Kamp et al. 2021 as in section S9 of tools/makeResultFigures.R: only plots surveyed in at least two years, the first year of each plot series dropped, reference year 2006;
# the same plot-and-year model (expected value = plot effect x year effect, iterative scaling) is applied to every series, so they differ only in the data (observed presence, observed territories,
# predicted probability of the climate, landscape, habitat scale and of the final map).
#   Rscript tools/panelTrendAnalysis.R [--run test4] [--ref-year 2006] [--out outputs/test4/panel_trend_check]
# Output: panel_series.csv (species, series, year, index), panel_species_last_year.csv, and the figures panel_combined.png and panel_species.png in --out.
args <- commandArgs(trailingOnly = TRUE)
getArg <- function(flag, default = NULL) { i <- which(args == flag); if (length(i) == 0) default else args[i + 1] }
run <- getArg("--run", "test4"); refYear <- as.integer(getArg("--ref-year", 2006)); inDir <- file.path("outputs", run, "panel_trend_check"); out <- getArg("--out", inDir)
fs <- list.files(inDir, pattern = "\\.csv$", full.names = TRUE); fs <- fs[!grepl("^panel_", basename(fs))]
d <- do.call(rbind, lapply(fs, read.csv, stringsAsFactors = FALSE))
english <- c("Alauda arvensis" = "Skylark", "Anthus pratensis" = "Meadow Pipit", "Buteo buteo" = "Common Buzzard", "Emberiza calandra" = "Corn Bunting", "Emberiza citrinella" = "Yellowhammer",
             "Lanius collurio" = "Red-backed Shrike", "Lullula arborea" = "Woodlark", "Perdix perdix" = "Grey Partridge", "Saxicola rubetra" = "Whinchat", "Sturnus vulgaris" = "Common Starling", "Vanellus vanellus" = "Lapwing")
ipf <- function(M, S, bi) {                                                # expected value a_plot * b_year over the surveyed plot-years; index 100 * b_year / b_reference
  M0 <- M; M0[!S] <- 0; b <- rep(1, ncol(M)); keep <- rowSums(M0) > 0; M0 <- M0[keep, , drop = FALSE]; Sk <- S[keep, , drop = FALSE] * 1
  for (it in 1:3000) { a <- rowSums(M0) / as.vector(Sk %*% b); b2 <- colSums(M0) / as.vector(t(Sk) %*% a); b2 <- b2 / b2[bi]; if (max(abs(b2 - b)) < 1e-9) { b <- b2; break }; b <- b2 }
  100 * b }
series <- c(observedOccupancy = "occurrence", observedAbundance = "Reviere", climate = "climate", landscape = "landscape", habitat = "habitat", final = "final")
rows <- list(); info <- list()
for (sp in unique(d$species)) {
  x <- d[d$species == sp, ]; x <- x[!duplicated(x[, c("ROUTENCODE", "year")]), ]
  n <- tapply(x$year, x$ROUTENCODE, function(v) length(unique(v))); x <- x[x$ROUTENCODE %in% names(n)[n >= 2], ]                  # plots surveyed in at least two years
  first <- tapply(x$year, x$ROUTENCODE, min); x <- x[x$year > first[x$ROUTENCODE], ]                                               # first year of each plot series dropped
  yrs <- sort(unique(x$year)); plots <- sort(unique(x$ROUTENCODE)); bi <- match(refYear, yrs)
  if (is.na(bi)) { message(sp, ": reference year ", refYear, " has no data after the rules -- skipped"); next }
  S <- matrix(FALSE, length(plots), length(yrs), dimnames = list(plots, yrs)); S[cbind(match(x$ROUTENCODE, plots), match(x$year, yrs))] <- TRUE
  for (sn in names(series)) {
    M <- matrix(NA_real_, length(plots), length(yrs)); M[cbind(match(x$ROUTENCODE, plots), match(x$year, yrs))] <- x[[series[[sn]]]]
    ok <- S & !is.na(M); Mz <- M; Mz[!ok] <- NA
    if (sn == "observedOccupancy") Mz <- (Mz > 0) * 1
    if (all(is.na(Mz[ok])) || sum(ok) == 0) next
    rows[[length(rows) + 1]] <- data.frame(species = sp, series = sn, year = yrs, index = ipf(replace(Mz, is.na(Mz), 0), ok, bi))
  }
  info[[sp]] <- data.frame(species = sp, plots = length(plots), plotYears = sum(S), years = paste(range(yrs), collapse = "-"), prevalence = round(mean(x$occurrence > 0), 3))
}
ser <- do.call(rbind, rows); ser$english <- english[ser$species]; write.csv(ser, file.path(out, "panel_series.csv"), row.names = FALSE)
write.csv(do.call(rbind, info), file.path(out, "panel_plots.csv"), row.names = FALSE)
geo <- function(v) exp(mean(log(pmax(v, 1e-3))))
comb <- do.call(rbind, lapply(split(ser, list(ser$series, ser$year), drop = TRUE), function(z) data.frame(series = z$series[1], year = z$year[1], index = geo(z$index), nSpecies = nrow(z))))
comb <- comb[comb$nSpecies >= 9, ]; comb <- comb[order(comb$series, comb$year), ]; write.csv(comb, file.path(out, "panel_combined.csv"), row.names = FALSE)
lastY <- max(ser$year[ser$series == "final"]); w <- reshape(ser[ser$year == lastY, c("species", "series", "index")], idvar = "species", timevar = "series", direction = "wide"); names(w) <- sub("index\\.", "", names(w))
w <- w[, c("species", intersect(names(series), names(w)))]; w[, -1] <- round(w[, -1], 1); write.csv(w, file.path(out, "panel_species_last_year.csv"), row.names = FALSE)
cat("Same-plot panel, index", lastY, "(", refYear, "= 100)\n"); print(w, row.names = FALSE)
cat("\nCombined (geometric mean over species), index", lastY, ":\n"); print(round(setNames(comb$index[comb$year == lastY], comb$series[comb$year == lastY]), 1))
cat("\nPlots:\n"); print(do.call(rbind, info), row.names = FALSE)
col <- c(observedOccupancy = "#2d8a4e", observedAbundance = "black", climate = "#b3b3b3", landscape = "#1f78b4", habitat = "#a6761d", final = "#c8501a")
lab <- c(observedOccupancy = "observed occupancy (presence)", observedAbundance = "observed abundance (territories)", climate = "climate scale", landscape = "landscape scale", habitat = "habitat scale", final = "final map (meta-model)")
lw <- c(observedOccupancy = 3, observedAbundance = 3, climate = 1.6, landscape = 1.6, habitat = 1.6, final = 3.5); lt <- c(observedOccupancy = 1, observedAbundance = 2, climate = 1, landscape = 1, habitat = 1, final = 1)
png(file.path(out, "panel_combined.png"), width = 2300, height = 1400, res = 200); par(mar = c(4.2, 4.6, 3, 1), oma = c(4, 0, 0, 0))
yl <- c(40, max(110, comb$index) + 3); plot(NA, xlim = range(comb$year), ylim = yl, xlab = "Year", ylab = sprintf("Index (%d = 100)", refYear), bty = "l", las = 1, main = "Observed and predicted at the same plots, same plot rules"); abline(h = 100, lty = 3, col = "grey40")
for (s in rev(names(series))) { z <- comb[comb$series == s, ]; if (nrow(z)) lines(z$year, z$index, col = col[[s]], lwd = lw[[s]], lty = lt[[s]]) }
legend("bottomleft", lab, col = col, lwd = lw, lty = lt, bty = "n", cex = 0.85)
mtext(sprintf("DDA plots surveyed in at least two years, first year of each plot dropped, reference year %d; plot-and-year model applied to every series; geometric mean over the species.\nPredictions extracted at the plot centroids (1 km landscape cell; final map 200 m cell). The landscape scale is fitted on part of these data: not an independent test.", refYear), outer = TRUE, side = 1, line = 1.2, cex = 0.55, col = "grey30"); invisible(dev.off())
png(file.path(out, "panel_species.png"), width = 2800, height = 1800, res = 200); par(mfrow = c(3, 4), mar = c(3, 3.6, 2.4, 0.6), oma = c(1.5, 0, 1, 0), mgp = c(2.2, 0.7, 0))
for (sp in intersect(names(english), unique(ser$species))) { z <- ser[ser$species == sp, ]; yl <- range(c(z$index, 100)); yl <- yl + c(-1, 1) * 0.04 * diff(yl)
  plot(NA, xlim = range(z$year), ylim = yl, xlab = "", ylab = sprintf("Index (%d = 100)", refYear), main = english[[sp]], cex.main = 1.1, bty = "l", las = 1); abline(h = 100, lty = 3, col = "grey40")
  for (s in rev(names(series))) { q <- z[z$series == s, ]; if (nrow(q)) lines(q$year, q$index, col = col[[s]], lwd = lw[[s]], lty = lt[[s]]) } }
plot.new(); legend("center", lab, col = col, lwd = lw, lty = lt, bty = "n", cex = 1); invisible(dev.off())
