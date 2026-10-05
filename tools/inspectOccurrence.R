# Diagnostic: per-species occurrence tables on disk -- date, rows, presences, columns.
# Usage (repo root):  Rscript tools/inspectOccurrence.R "Emberiza_citrinella"
args <- commandArgs(trailingOnly = TRUE)
pat <- if (length(args)) args[1] else "Emberiza_citrinella"
files <- list.files("inputs/response/processed", pattern = pat, recursive = TRUE, full.names = TRUE)
files <- files[grepl("[.]rds$", files)]
cat("files matching '", pat, "': ", length(files), "\n\n", sep = "")
for (f in files) {
  x <- tryCatch(readRDS(f), error = function(e) NULL)
  if (!is.data.frame(x)) { cat(sprintf("%-95s (not a data.frame / unreadable)\n", sub("inputs/response/processed/", "", f))); next }
  cat(sprintf("%-95s %s rows=%-6d pres=%-6d hetero=%-5s hedges=%-5s dist2wood=%-5s\n",
              sub("inputs/response/processed/", "", f),
              format(file.mtime(f), "%m-%d %H:%M"), nrow(x),
              if ("occurrence" %in% names(x)) sum(x$occurrence == 1, na.rm = TRUE) else NA,
              "landscape_heterogeneity" %in% names(x), "hedges" %in% names(x), "dist_to_woodland" %in% names(x)))
}
