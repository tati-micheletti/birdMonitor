#!/usr/bin/env Rscript
# READ-ONLY plot of the combined indices (SBI, MSI, Chain) with their 90% intervals, for the BRT-only run and the big 5 (2026-10-15).
# Base R only. Reads  outputs/<run>/annual_report_germany/combined_index_uncertainty.csv  and the same for the big 5 (annual_report_<tag>_germany),
# plus combined_index_sbi.csv (the main model, dashed black line). Writes outputs/<run>/figures/combined_indices.png and .pdf.
#   Rscript tools/plotCombinedIndices.R [run test4] [big5 tag ens_brt-glm-gam-rf-nn]
args <- commandArgs(trailingOnly = TRUE)
run <- if (length(args) >= 1) args[1] else "test4"
tag <- if (length(args) >= 2) args[2] else "ens_brt-glm-gam-rf-nn"
out <- file.path("outputs", run, "figures"); dir.create(out, recursive = TRUE, showWarnings = FALSE)
dirs <- c("BRT only (50 replicates)" = file.path("outputs", run, "annual_report_germany"),
          "Big 5 ensemble (25 replicates)" = file.path("outputs", run, paste0("annual_report_", tag, "_germany")))
cols <- c(SBI = "#1f4e79", MSI = "#2d8a4e", Chain = "#d9822b")
lty  <- c(SBI = 1, MSI = 3, Chain = 2)
read <- function(f) { if (!file.exists(f)) stop("not found: ", f); read.csv(f, check.names = FALSE, stringsAsFactors = FALSE) }

draw <- function() {
  dat <- lapply(dirs, function(d) read(file.path(d, "combined_index_uncertainty.csv")))
  main <- lapply(dirs, function(d) { x <- read(file.path(d, "combined_index_sbi.csv")); names(x) <- tolower(names(x)); x })
  rng <- range(unlist(lapply(dat, function(x) c(x$lwr, x$upr))), unlist(lapply(main, function(x) x$sbi)), na.rm = TRUE) + c(-.4, .4)
  par(mfrow = c(1, 2), mar = c(4.2, 4.6, 3.2, 1), oma = c(3.2, 0, 2.6, 0), family = "sans")
  for (k in seq_along(dirs)) {
    x <- dat[[k]]; yrs <- sort(unique(x$year))
    plot(NA, xlim = range(yrs), ylim = rng, xlab = "Year", ylab = "Index (2005 = 100)", main = names(dirs)[k], cex.main = 1.3, bty = "l", las = 1)
    rect(min(yrs) - .5, rng[1] - 5, 2021.5, rng[2] + 5, col = "#ececec", border = NA)
    text(mean(c(min(yrs), 2021.5)), rng[2] - .05, "hindcast 2005-2021", col = "grey45", cex = .95, adj = c(.5, 1))
    abline(h = 100, lty = 3, col = "grey40")
    for (m in c("SBI", "MSI", "Chain")) {
      d <- x[x$method == m, ]; d <- d[order(d$year), ]
      if (m == "SBI") polygon(c(d$year, rev(d$year)), c(d$lwr, rev(d$upr)), col = adjustcolor(cols[m], .20), border = NA)
      else { lines(d$year, d$lwr, col = cols[m], lty = lty[m], lwd = 1.6); lines(d$year, d$upr, col = cols[m], lty = lty[m], lwd = 1.6) }
    }
    for (m in c("SBI", "MSI", "Chain")) { d <- x[x$method == m, ]; d <- d[order(d$year), ]; lines(d$year, d$estimate, col = cols[m], lty = lty[m], lwd = if (m == "SBI") 3 else 2.2) }
    mm <- main[[k]]; lines(mm$year, mm$sbi, col = "black", lty = 5, lwd = 1.8)
    if (k == 1) legend("bottomleft", c("SBI (band = 90% interval)", "MSI (lines = 90% interval)", "Chain / LPI-style (lines = 90% interval)", "main model (SBI)"),
                       col = c(cols["SBI"], cols["MSI"], cols["Chain"], "black"), lty = c(lty["SBI"], lty["MSI"], lty["Chain"], 5), lwd = c(3, 2.2, 2.2, 1.8), bty = "n", cex = .95)
  }
  mtext("Combined multi-species indices, 11 species, Germany only", outer = TRUE, side = 3, line = .6, font = 2, cex = 1.5)
  mtext("The lines are the mean over the replicates; intervals are the 5th to 95th percentile (SBI, Chain) or Monte Carlo (MSI). SBI and Chain coincide as long as no species is missing in any year.",
        outer = TRUE, side = 1, line = 1.8, cex = .85, col = "grey30")
}
png(file.path(out, "combined_indices.png"), width = 15, height = 6.6, units = "in", res = 200, type = "cairo"); draw(); invisible(dev.off())
cairo_pdf(file.path(out, "combined_indices.pdf"), width = 15, height = 6.6); draw(); invisible(dev.off())
cat("written:", file.path(out, "combined_indices.png"), "and .pdf\n")
