# Compact printout of the index uncertainty tables (species indices + the four combined indices), for a quick look.
#   Rscript tools/summarizeIndexUncertainty.R [run name, default test4]
# Finds species_index_uncertainty.csv / combined_index_uncertainty.csv under outputs/<run>/ (any tag) and prints, per species and
# for each combined method, the index with its 90% interval in a few years and the interval width.
args <- commandArgs(trailingOnly = TRUE)
run <- if (length(args)) args[1] else "test4"
root <- file.path("outputs", run)
find1 <- function(f) { x <- list.files(root, pattern = paste0("^", f, "$"), recursive = TRUE, full.names = TRUE); x[order(file.mtime(x), decreasing = TRUE)] }
sf <- find1("species_index_uncertainty.csv"); cf <- find1("combined_index_uncertainty.csv")
cat("files:\n ", paste(c(sf, cf), collapse = "\n  "), "\n\n")
fmt <- function(m, l, u) sprintf("%6.1f [%6.1f - %6.1f]", m, l, u)
if (length(sf)) {
  s <- read.csv(sf[1]); yrs <- intersect(c(2005, 2010, 2015, 2020, 2025), unique(s$year))
  cat("=== SPECIES index (100 = 2005), mean [90% interval], replicates:", paste(unique(s$nReplicates), collapse = ","), "\n")
  out <- do.call(rbind, lapply(split(s, s$species), function(d) {
    r <- setNames(vapply(yrs, function(y) { x <- d[d$year == y, ]; if (nrow(x)) fmt(x$indexMean, x$indexLwr, x$indexUpr) else NA_character_ }, ""), yrs)
    data.frame(species = d$species[1], t(r), check.names = FALSE) }))
  print(out, row.names = FALSE, right = FALSE)
}
if (length(cf)) {
  cc <- read.csv(cf[1]); yrs <- intersect(c(2005, 2010, 2015, 2020, 2025), unique(cc$year))
  cat("\n=== COMBINED indices, estimate [90% interval]\n")
  out <- do.call(rbind, lapply(split(cc, cc$method), function(d) {
    r <- setNames(vapply(yrs, function(y) { x <- d[d$year == y, ]; if (nrow(x)) fmt(x$estimate, x$lwr, x$upr) else NA_character_ }, ""), yrs)
    data.frame(method = d$method[1], t(r), check.names = FALSE) }))
  print(out[match(c("SBI", "Chain", "Analytical", "MSI"), out$method), ], row.names = FALSE, right = FALSE)
  w <- cc[cc$year == max(cc$year), ]; cat("\nInterval width in", max(cc$year), ":", paste(w$method, round(w$upr - w$lwr, 1), collapse = " | "), "\n")
}
pt <- file.path(root, "performance_table.csv")
if (file.exists(pt)) { cat("\n=== performance_table.csv (rerun tools/collectPerformance.R", run, "to refresh)\n") }
