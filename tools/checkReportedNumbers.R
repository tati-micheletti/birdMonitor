#!/usr/bin/env Rscript
# READ-ONLY independent check of the reported numbers (2026-10-13). Changes nothing; prints OK / DIFFERENCE for each comparison.
#
# It re-derives the reported numbers from the files that sit closest to the maps and compares them with the tables that are reported:
#   1. maps  -> area means : the mean of `meta_prob` over all non-empty pixels of the Germany-only map of a species and year, recomputed with terra,
#                            against the area mean of replicate 0 (the main model) in <uncertainty folder>/<Species>/area_mean_replicates_germany.csv
#   2. area means -> species index : 100 x area mean (year) / area mean (2005), against species_index.csv of the annual report (best estimate)
#   3. species index -> combined index : geometric mean of the species indices, against combined_index_sbi.csv (best estimate)
#   4. replicates -> intervals : combined SBI per replicate from all area_mean_replicates_germany.csv files, mean and 5th/95th percentile,
#                                against combined_index_uncertainty.csv (small differences in the percentile definition are tolerated)
#
#   Rscript tools/checkReportedNumbers.R [run test4] [tag honest2] [species "Alauda arvensis;Saxicola rubetra"] [years 2005,2015,2025]
#   big 5:  Rscript tools/checkReportedNumbers.R test4 ens_brt-glm-gam-rf-nn
# Needs R with terra (the personal library of the cluster is added to .libPaths()). Takes a few minutes (it reads a few 200 m maps).
args <- commandArgs(trailingOnly = TRUE)
run  <- if (length(args) >= 1) args[1] else "test4"
tag  <- if (length(args) >= 2) args[2] else "honest2"
spp  <- if (length(args) >= 3) strsplit(args[3], ";")[[1]] else c("Alauda arvensis", "Saxicola rubetra")
yrs  <- if (length(args) >= 4) as.integer(strsplit(args[4], ",")[[1]]) else c(2005L, 2015L, 2025L)
lib  <- Sys.glob(path.expand("~/.local/share/R/birdMonitor/packages/*/*")); if (length(lib)) .libPaths(c(lib, .libPaths()))
suppressMessages(library(terra))

big5   <- grepl("ens_", tag)
out    <- file.path("outputs", run)
uncDir <- file.path(out, paste0("uncertainty_", tag))
repDir <- file.path(out, if (big5) paste0("annual_report_", tag, "_germany") else "annual_report_germany")
mapDir <- file.path(out, if (big5) paste0("metamodel_02_1_50_", tag, "_germany") else "metamodel_02_1_50_germany")
for (d in c(uncDir, repDir, mapDir)) if (!dir.exists(d)) stop("not found: ", d, " (run from the repo root; check the tag)")
cat("Run:", run, "| tag:", tag, "\n  maps: ", mapDir, "\n  area means: ", uncDir, "\n  reports: ", repDir, "\n", sep = "")

nbad <- 0L; nok <- 0L
report <- function(label, a, b, tol, rel = TRUE) {
  d <- if (rel) abs(a - b) / max(abs(b), 1e-12) else abs(a - b)
  ok <- is.finite(d) && d <= tol
  if (ok) nok <<- nok + 1L else nbad <<- nbad + 1L
  cat(sprintf("  %-10s %-58s recomputed %-12.6g reported %-12.6g %s\n", if (ok) "OK" else "DIFFERENCE", label, a, b, if (ok) "" else sprintf("(difference %.3g)", d)))
}
readTbl <- function(f) { if (!file.exists(f)) { cat("  MISSING FILE:", f, "\n"); nbad <<- nbad + 1L; return(NULL) }; read.csv(f, check.names = FALSE, stringsAsFactors = FALSE) }

## species index from species_index.csv, whatever the orientation (long: species/year/index; wide: species rows, year columns)
idxTbl <- readTbl(file.path(repDir, "species_index.csv"))
getIdx <- function(sp, yr) {
  if (is.null(idxTbl)) return(NA_real_)
  nm <- tolower(names(idxTbl))
  if (all(c("species", "year") %in% nm)) {
    r <- idxTbl[idxTbl[[which(nm == "species")]] == sp & idxTbl[[which(nm == "year")]] == yr, , drop = FALSE]
    col <- setdiff(names(idxTbl)[sapply(idxTbl, is.numeric)], names(idxTbl)[nm %in% c("year", "nreplicates")])
    return(if (nrow(r) == 1 && length(col)) as.numeric(r[[col[length(col)]]]) else NA_real_)
  }
  rn <- idxTbl[[1]]; colyr <- suppressWarnings(as.integer(gsub("\\D", "", names(idxTbl))))
  i <- which(rn == sp | gsub("_", " ", rn) == sp); j <- which(colyr == yr)
  if (length(i) == 1 && length(j) == 1) as.numeric(idxTbl[i, j]) else NA_real_
}

cat("\n== 1 and 2: maps -> area means -> species index\n")
for (sp in spp) {
  f <- file.path(uncDir, gsub(" ", "_", sp), "area_mean_replicates_germany.csv"); am <- readTbl(f); if (is.null(am)) next
  am0 <- am[am$replicate == 0, ]
  for (yr in yrs) {
    tif <- file.path(mapDir, paste0(gsub(" ", "_", sp), "_meta_suitability_", yr, ".tif"))
    if (!file.exists(tif)) { cat("  MISSING FILE:", tif, "\n"); nbad <- nbad + 1L; next }
    r <- rast(tif); r <- if ("meta_prob" %in% names(r)) r[["meta_prob"]] else r[[1]]
    fromMap <- as.numeric(global(r, "mean", na.rm = TRUE)[1, 1])
    report(paste(sp, yr, "area mean from the map"), fromMap, am0$areaMean[am0$year == yr], 1e-3)
  }
  for (yr in setdiff(yrs, 2005L)) {
    ix <- 100 * am0$areaMean[am0$year == yr] / am0$areaMean[am0$year == 2005]
    report(paste(sp, yr, "species index from the area means"), ix, getIdx(sp, yr), 1e-3)
  }
}

cat("\n== 3: species index -> combined index (geometric mean of all species, best estimate)\n")
allF <- Sys.glob(file.path(uncDir, "*", "area_mean_replicates_germany.csv"))
am <- do.call(rbind, lapply(allF, function(f) read.csv(f, stringsAsFactors = FALSE)[, c("species", "replicate", "year", "areaMean")]))
base <- am[am$year == 2005, ]; am$index <- 100 * am$areaMean / base$areaMean[match(paste(am$species, am$replicate), paste(base$species, base$replicate))]
sbiTbl <- readTbl(file.path(repDir, "combined_index_sbi.csv"))
if (!is.null(sbiTbl)) {
  nm <- tolower(names(sbiTbl)); yc <- which(nm == "year"); sc <- which(nm == "sbi")
  if (length(yc) == 1 && length(sc) == 1) {
    for (yr in setdiff(yrs, 2005L)) {
      a0 <- am[am$replicate == 0 & am$year == yr, ]
      gm <- exp(mean(log(a0$index)))
      report(paste("combined index", yr, "(", nrow(a0), "species )"), gm, sbiTbl[[sc]][sbiTbl[[yc]] == yr], 1e-3)
    }
  } else { cat("  format of combined_index_sbi.csv not recognised; first lines:\n"); print(utils::head(sbiTbl, 3)); nbad <- nbad + 1L }
}

cat("\n== 4: replicates -> interval of the combined index (SBI; mean and 5th / 95th percentile over replicates)\n")
rp <- am[am$replicate != 0, ]
yrsAll <- sort(unique(rp$year)); reps <- sort(unique(rp$replicate))
sbiRep <- sapply(yrsAll, function(y) sapply(reps, function(r) { v <- rp$index[rp$year == y & rp$replicate == r]; exp(mean(log(v[v > 0]))) }))
unc <- readTbl(file.path(repDir, "combined_index_uncertainty.csv"))
if (!is.null(unc)) {
  u <- unc[unc$method == "SBI", ]
  for (yr in setdiff(yrs, 2005L)) {
    k <- which(yrsAll == yr); x <- sbiRep[, k]; ur <- u[u$year == yr, ]
    report(paste("SBI", yr, "mean over", length(x), "replicates"), mean(x), ur$estimate, 1e-3)
    report(paste("SBI", yr, "5th percentile"), unname(quantile(x, .05)), ur$lwr, 0.05, rel = FALSE)
    report(paste("SBI", yr, "95th percentile"), unname(quantile(x, .95)), ur$upr, 0.05, rel = FALSE)
  }
}
cat(sprintf("\nSUMMARY: %d comparisons OK, %d differences or missing files.%s\n", nok, nbad, if (nbad == 0) "  All reported numbers could be re-derived." else "  Read the DIFFERENCE lines above."))
