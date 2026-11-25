# Chain-link the two land-use series into ONE 2005-2025 line, AFTER prediction (2026-11-19; reference and checks 2026-11-20).
#   HCTM series      (run s1v3): HCTM crop maps, 2005-2023, models refitted on rows <= 2023
#   CTM v302 series  (run s2v2): CTM v302 crop maps, 2017-2025, models refitted on 2017-2025 rows
# For every species and replicate the scale factor is k = mean(HCTM) / mean(CTM) over the overlap years (2017-2023, the whole overlap by default).
#   --reference ctm  (DEFAULT, decision of the project lead 2026-11-20: CTM is the modern product): the joined series is the HCTM series divided by k BEFORE the first CTM year (2005-2016, on the CTM level) and the
#                    CTM v302 series for ALL its years (2017-2025). The index is a ratio to the baseline year, so this equals HCTM 2005-2016 and 100 x k x CTM / HCTM(2005) from 2017 on.
#   --reference hctm (sensitivity): the joined series is the HCTM series up to its last year (2023) and k x CTM v302 after it.
# The species index (100 x area mean / area mean of the baseline year) and the combined index (SBI = geometric mean over species = the Bird Index Farmland, Chain) are then computed per replicate EXACTLY as
# runIndex_Monitor/R/computeIndexUncertainty.R does (90% interval = 5th-95th percentile over the replicates). The MAIN model (replicate 0) is joined the same way and written to combined_index_main_model.csv
# (the line the figures and the Monitor draw). Replicate r of one series is paired with replicate r of the other (by replicate id). The climate-scale replicate fits are the same files in both series (the climate model
# was fitted once); the landscape and habitat replicates are fitted on other years and land-use layers. Both series are read from  <run>/uncertainty_<tag>/<Species>/<areamean file>.
#
#   Rscript tools/joinSeries.R --hctm outputs/s1v3 --ctm outputs/s2v2 --out outputs/joined_ctmref
#       [--reference ctm|hctm] [--group farmland|all] [--groups-file data/speciesGroups.csv] [--tag ens_brt-glm-gam-rf-nn] [--areamean area_mean_replicates_germany.csv] [--baseline 2005]
#       [--hctm-years 2005:2023] [--ctm-years 2017:2025] [--overlap 2017:2023] [--scale-years 2017:2023]
#   --group        the species of the index (default farmland = the 12 species of the first version, no raptors; all = every species present in both runs)
#   --scale-years  the overlap years the scale factor is calibrated on (default = --overlap). Sensitivity: run once with the whole overlap and once with the last years (2021:2023), and once with --reference hctm;
#                  compare the runs with tools/joinSensitivity.R.
# PRE-SPECIFIED CHECKS (2026-11-20, project lead) per species over the overlap; yellow / red limits:
#   scale factor k (median)                         yellow: < 0.67 or > 1.5      red: < 0.5 or > 2
#   drift of the ratio CTM/HCTM, % per decade       yellow: |x| > 5              red: |x| > 10
#   junction misfit, %                              yellow: |x| > 5              red: |x| > 10      (last HCTM year with --reference hctm; first CTM year with --reference ctm)
#   RMSE of the log after scaling                   yellow: > 0.10               red: > 0.20
#   overlap years inside the HCTM 90% band          yellow: fewer than 5 of 7    red: fewer than 3 of 7
#   correlation of the yearly changes (6 values)    yellow: < 0.5                red: < 0          (descriptive)
# RULE: a species with a RED check means we revisit the method (no automatic exclusion). The comparison with the observed DDA series and the official statistics is reported in any case.
# Writes (all in --out):
#   joined_area_means.csv            species, replicate, year, areaMean (joined), source (HCTM_scaled | CTM | HCTM | CTM_scaled), k
#   scale_factors.csv                species, replicate, k  (= mean HCTM / mean CTM over the calibration years)
#   combined_index_replicates.csv    replicate, year, SBI, Chain  (same layout as the pipeline's file)
#   combined_index_summary.csv       method, year, nReplicates, estimate (= mean over the replicates), median, lwr, upr
#   combined_index_main_model.csv    year, SBI, Chain of the main model (replicate 0), joined and scaled like the replicates
#   species_index_summary.csv        species, year, indexMedian, indexLwr, indexUpr, source
#   overlap_agreement_species.csv    the checks above per species, with a flag per check (ok | yellow | red), nYellow, nRed, overall
#   flag_summary.txt                 species with a red or yellow check, and the rule
#   overlap_combined.csv             combined index (SBI) of each series alone over the overlap years, both rebased to 100 at the first overlap year
#   join_info.txt                    the settings and counts of this run
# NOT in this script (later step): the regional (10/20/50 km) cell index needs the same scaling per cell; see the note at the end.
args <- commandArgs(trailingOnly = TRUE)
getArg <- function(f, d = NULL) { i <- which(args == f); if (length(i)) args[i + 1] else d }
years <- function(s) { p <- as.integer(strsplit(s, ":")[[1]]); if (length(p) == 1) p else p[1]:p[2] }
hctmRun <- getArg("--hctm"); ctmRun <- getArg("--ctm"); out <- getArg("--out")
if (is.null(hctmRun) || is.null(ctmRun) || is.null(out)) stop("usage: Rscript tools/joinSeries.R --hctm <run> --ctm <run> --out <folder>   (see the header of this file)")
tag <- getArg("--tag", "ens_brt-glm-gam-rf-nn"); amFile <- getArg("--areamean", "area_mean_replicates_germany.csv"); base <- as.integer(getArg("--baseline", 2005))
reference <- tolower(getArg("--reference", "ctm")); stopifnot(reference %in% c("ctm", "hctm"))
group <- getArg("--group", "farmland"); groupsFile <- getArg("--groups-file", "data/speciesGroups.csv")
hy <- years(getArg("--hctm-years", "2005:2023")); cy <- years(getArg("--ctm-years", "2017:2025")); ov <- years(getArg("--overlap", "2017:2023"))
sy <- years(getArg("--scale-years", getArg("--overlap", "2017:2023")))      # the years the scale factor is calibrated on (default: the whole overlap; e.g. 2021:2023 = the last years only)
stopifnot(all(ov %in% hy), all(ov %in% cy), all(sy %in% ov), base %in% hy, max(cy) > max(hy))
if (reference == "ctm") stopifnot(base < min(cy))
if (file.exists(out) && length(list.files(out))) stop("STOP: ", out, " exists and is not empty; choose a new --out (nothing is overwritten)")
dir.create(out, recursive = TRUE, showWarnings = FALSE)
readAM <- function(run) {
  u <- file.path(run, paste0("uncertainty_", tag)); fs <- list.files(u, pattern = paste0("^", gsub("[.]", "[.]", amFile), "$"), recursive = TRUE, full.names = TRUE)
  fs <- fs[dirname(dirname(fs)) == u]; if (!length(fs)) stop("no ", amFile, " under ", u)
  d <- do.call(rbind, lapply(fs, function(f) read.csv(f, stringsAsFactors = FALSE)[, c("species", "replicate", "year", "areaMean")]))
  d$species <- gsub(" ", "_", d$species)               # the pipeline files carry "Vanellus vanellus"; the group file and the outputs here use "Vanellus_vanellus" (found on EVE 2026-11-23, the synthetic test used underscores)
  d
}
H <- readAM(hctmRun); C <- readAM(ctmRun)
H <- H[H$year %in% hy, ]; C <- C[C$year %in% cy, ]
spp <- sort(intersect(unique(H$species), unique(C$species)))
if (length(setdiff(union(H$species, C$species), spp))) stop("species differ between the runs: ", paste(setdiff(union(H$species, C$species), spp), collapse = ", "))
if (group != "all") {                                  # the species of the index: the group of data/speciesGroups.csv (farmland = 12 species, no raptors)
  g <- read.csv(groupsFile, stringsAsFactors = FALSE); gs <- gsub(" ", "_", g$latin_name[g$group == group]); if (!length(gs)) stop("group '", group, "' not found in ", groupsFile)
  miss <- setdiff(gs, spp); if (length(miss)) stop("species of the group missing in the runs: ", paste(miss, collapse = ", "))
  spp <- sort(intersect(spp, gs))
}
reps <- sort(intersect(unique(H$replicate), unique(C$replicate)))
H <- H[H$species %in% spp & H$replicate %in% reps, ]; C <- C[C$species %in% spp & C$replicate %in% reps, ]
chk <- function(d, yrs, nm) { n <- table(d$species[d$year %in% yrs], d$replicate[d$year %in% yrs]); if (any(n != length(yrs))) stop(nm, ": some species x replicate lack years of ", min(yrs), "-", max(yrs)) }
chk(H, hy, "HCTM series"); chk(C, cy, "CTM v302 series")
if (any(H$areaMean <= 0 | is.na(H$areaMean)) || any(C$areaMean <= 0 | is.na(C$areaMean))) stop("non-positive or missing area means: the ratio of the means is not defined")
# 1. scale factors over the calibration years -----------------------------------------------------------------------------------------------------------------------
mh <- aggregate(areaMean ~ species + replicate, H[H$year %in% sy, ], mean); names(mh)[3] <- "meanH"
mc <- aggregate(areaMean ~ species + replicate, C[C$year %in% sy, ], mean); names(mc)[3] <- "meanC"
K <- merge(mh, mc, by = c("species", "replicate")); K$k <- K$meanH / K$meanC
write.csv(K[order(K$species, K$replicate), c("species", "replicate", "k")], file.path(out, "scale_factors.csv"), row.names = FALSE)
# 2. the joined area means --------------------------------------------------------------------------------------------------------------------------------------------
cols <- c("species", "replicate", "year", "areaMean", "source", "k")
if (reference == "ctm") {                              # HCTM before the first CTM year, divided by k (CTM level); CTM v302 for all its years
  Hp <- merge(H[H$year < min(cy), ], K[, c("species", "replicate", "k")], by = c("species", "replicate")); Hp$areaMean <- Hp$areaMean / Hp$k; Hp$source <- "HCTM_scaled"
  Cp <- C; Cp$source <- "CTM"; Cp$k <- NA_real_
} else {                                               # HCTM up to its last year; CTM v302 times k after it
  Hp <- H; Hp$source <- "HCTM"; Hp$k <- NA_real_
  Cp <- merge(C[C$year > max(hy), ], K[, c("species", "replicate", "k")], by = c("species", "replicate")); Cp$areaMean <- Cp$areaMean * Cp$k; Cp$source <- "CTM_scaled"
}
J <- rbind(Hp[, cols], Cp[, cols]); J <- J[order(J$species, J$replicate, J$year), ]; write.csv(J, file.path(out, "joined_area_means.csv"), row.names = FALSE)
# 3. indices exactly as computeIndexUncertainty() --------------------------------------------------------------------------------------------------------------
indexOf <- function(d, baseYear) { b <- d[d$year == baseYear, c("species", "replicate", "areaMean")]; names(b)[3] <- "baseMean"; d <- merge(d, b, by = c("species", "replicate")); d$index <- 100 * d$areaMean / d$baseMean; d }
combine <- function(idx, yrs, rr = sort(setdiff(unique(idx$replicate), 0))) {
  sp <- sort(unique(idx$species))
  do.call(rbind, lapply(rr, function(r) {
    im <- matrix(NA_real_, length(sp), length(yrs), dimnames = list(sp, yrs))
    for (s in sp) { d <- idx[idx$species == s & idx$replicate == r, ]; im[s, ] <- d$index[match(yrs, d$year)] }
    sbi <- apply(im, 2, function(v) { v <- v[!is.na(v) & v > 0]; if (length(v)) exp(mean(log(v))) else NA_real_ })
    lam <- log(im[, -1, drop = FALSE] / im[, -ncol(im), drop = FALSE]); chain <- c(100, 100 * exp(cumsum(colMeans(lam, na.rm = TRUE))))
    data.frame(replicate = r, year = yrs, SBI = sbi, Chain = chain)
  }))
}
q <- function(x, p) unname(quantile(x, p))
yrsAll <- sort(unique(J$year)); idx <- indexOf(J, base); idx <- idx[order(idx$species, idx$replicate, idx$year), ]
rep <- combine(idx, yrsAll); write.csv(rep, file.path(out, "combined_index_replicates.csv"), row.names = FALSE)
summ <- do.call(rbind, lapply(c("SBI", "Chain"), function(m) do.call(rbind, lapply(split(rep, rep$year), function(d)
  data.frame(method = m, year = d$year[1], nReplicates = nrow(d), estimate = mean(d[[m]]), median = median(d[[m]]), lwr = q(d[[m]], 0.05), upr = q(d[[m]], 0.95))))))
rownames(summ) <- NULL; write.csv(summ, file.path(out, "combined_index_summary.csv"), row.names = FALSE)
if (0 %in% idx$replicate) write.csv(combine(idx, yrsAll, rr = 0)[, c("year", "SBI", "Chain")], file.path(out, "combined_index_main_model.csv"), row.names = FALSE)   # main model (replicate 0): the line of the figures and the Monitor
srcOf <- unique(J[, c("year", "source")]); i2 <- idx[idx$replicate != 0, ]
sp <- do.call(rbind, lapply(split(i2, list(i2$species, i2$year), drop = TRUE), function(d) data.frame(species = d$species[1], year = d$year[1], indexMedian = median(d$index), indexLwr = q(d$index, 0.05), indexUpr = q(d$index, 0.95))))
sp <- merge(sp, srcOf, by = "year"); sp <- sp[order(sp$species, sp$year), c("species", "year", "indexMedian", "indexLwr", "indexUpr", "source")]; rownames(sp) <- NULL
write.csv(sp, file.path(out, "species_index_summary.csv"), row.names = FALSE)
# 4. how well do the two series agree over the overlap? ---------------------------------------------------------------------------------------------------
rr <- sort(setdiff(reps, 0)); Hm <- aggregate(areaMean ~ species + year, H[H$replicate %in% rr & H$year %in% ov, ], mean); Cm <- aggregate(areaMean ~ species + year, C[C$replicate %in% rr & C$year %in% ov, ], mean)
Hq <- aggregate(areaMean ~ species + year, H[H$replicate %in% rr & H$year %in% ov, ], function(v) c(lo = q(v, 0.05), hi = q(v, 0.95)))
jYear <- if (reference == "ctm") min(cy) else max(hy)   # the year of the junction check: first CTM year (CTM reference) or last HCTM year (HCTM reference); both lie in the overlap
agree <- do.call(rbind, lapply(spp, function(s) {
  h <- Hm[Hm$species == s, ]; h <- h[order(h$year), ]; c0 <- Cm[Cm$species == s, ]; c0 <- c0[order(c0$year), ]; hq <- Hq[Hq$species == s, ]; hq <- hq[order(hq$year), ]
  ks <- K$k[K$species == s & K$replicate %in% rr]; kmed <- median(ks); lr <- log(c0$areaMean / h$areaMean); drift <- coef(lm(lr ~ h$year))[2] * 10
  dh <- diff(log(h$areaMean)); dc <- diff(log(c0$areaMean)); sc <- c0$areaMean * mean(ks); inside <- mean(sc >= hq$areaMean[, "lo"] & sc <= hq$areaMean[, "hi"])
  jm <- 100 * (kmed * c0$areaMean[c0$year == jYear] / h$areaMean[h$year == jYear] - 1)       # JUNCTION: scaled CTM v302 level vs the HCTM level in the year where the two series meet; carried into the joined series
  data.frame(species = s, kMedian = kmed, kQ25 = q(ks, 0.25), kQ75 = q(ks, 0.75), junctionMisfitPct = jm, driftRatioPctPerDecade = 100 * (exp(drift) - 1), corrYearlyChanges = suppressWarnings(cor(dh, dc)),
             spearmanYearlyChanges = suppressWarnings(cor(dh, dc, method = "spearman")), rmseLogAfterScaling = sqrt(mean((log(sc) - log(h$areaMean))^2)), shareInsideHCTM90 = inside, nOverlapYears = length(ov))
}))
# the pre-specified yellow / red limits (see the header) --------------------------------------------------------------------------------------------------
lev <- function(red, yellow) ifelse(is.na(red) | is.na(yellow), NA_character_, ifelse(red, "red", ifelse(yellow, "yellow", "ok")))
nIn <- agree$shareInsideHCTM90 * agree$nOverlapYears
agree$flagK <- lev(agree$kMedian < 0.5 | agree$kMedian > 2, agree$kMedian < 0.67 | agree$kMedian > 1.5)
agree$flagDrift <- lev(abs(agree$driftRatioPctPerDecade) > 10, abs(agree$driftRatioPctPerDecade) > 5)
agree$flagJunction <- lev(abs(agree$junctionMisfitPct) > 10, abs(agree$junctionMisfitPct) > 5)
agree$flagRMSE <- lev(agree$rmseLogAfterScaling > 0.20, agree$rmseLogAfterScaling > 0.10)
agree$flagInside <- lev(nIn < 3 - 1e-9, nIn < 5 - 1e-9)
agree$flagCorr <- lev(agree$corrYearlyChanges < 0, agree$corrYearlyChanges < 0.5)
fl <- agree[, grep("^flag", names(agree))]; agree$nRed <- rowSums(fl == "red", na.rm = TRUE); agree$nYellow <- rowSums(fl == "yellow", na.rm = TRUE)
agree$overall <- ifelse(agree$nRed > 0, "red", ifelse(agree$nYellow > 0, "yellow", "ok"))
write.csv(agree, file.path(out, "overlap_agreement_species.csv"), row.names = FALSE, na = "")
fs <- c(sprintf("Join checks (%s), reference %s, group %s, calibration years %d-%d", format(Sys.time(), "%Y-%m-%d %H:%M"), toupper(reference), group, min(sy), max(sy)),
        sprintf("species: %d | ok %d | yellow %d | red %d", nrow(agree), sum(agree$overall == "ok"), sum(agree$overall == "yellow"), sum(agree$overall == "red")), "RULE: a species with a red check means we revisit the method (no automatic exclusion).", "")
for (i in which(agree$overall != "ok")) { v <- unlist(fl[i, ]); w <- which(v %in% c("red", "yellow")); fs <- c(fs, sprintf("%-26s %-6s %s", agree$species[i], toupper(agree$overall[i]), paste(sub("^flag", "", names(v))[w], v[w], collapse = ", "))) }
writeLines(fs, file.path(out, "flag_summary.txt"))
ov1 <- ov[1]; comb1 <- function(d) combine(indexOf(d[d$year %in% ov, ], ov1), ov)
ch <- comb1(H[H$species %in% spp, ]); cc <- comb1(C[C$species %in% spp, ])
oc <- merge(aggregate(SBI ~ year, ch, median), aggregate(SBI ~ year, cc, median), by = "year", suffixes = c("_HCTM", "_CTMv302")); oc$difference <- oc$SBI_CTMv302 - oc$SBI_HCTM
write.csv(oc, file.path(out, "overlap_combined.csv"), row.names = FALSE)
writeLines(c(sprintf("joinSeries.R, %s", format(Sys.time(), "%Y-%m-%d %H:%M")), sprintf("HCTM series : %s  years %d-%d", hctmRun, min(hy), max(hy)), sprintf("CTM v302    : %s  years %d-%d", ctmRun, min(cy), max(cy)),
             sprintf("reference: %s | group: %s (%d species) | overlap: %d-%d | scale factor calibrated on %d-%d | baseline year %d | tag %s | area-mean file %s", toupper(reference), group, length(spp), min(ov), max(ov), min(sy), max(sy), base, tag, amFile),
             sprintf("replicates (incl. 0): %d", length(reps)),
             if (reference == "ctm") sprintf("joined series: HCTM %d-%d divided by k, CTM v302 %d-%d", min(hy), min(cy) - 1, min(cy), max(cy)) else sprintf("joined series: HCTM up to %d, scaled CTM v302 %d-%d", max(hy), max(hy) + 1, max(cy)),
             "replicate r of one series is paired with replicate r of the other (by replicate id; the climate-scale replicates are shared by both series)"), file.path(out, "join_info.txt"))
cat("joined", length(spp), "species x", length(reps), "replicates, years", min(yrsAll), "-", max(yrsAll), "| reference", toupper(reference), "->", out, "\n")
shown <- agree[, c("species", "kMedian", "junctionMisfitPct", "driftRatioPctPerDecade", "corrYearlyChanges", "rmseLogAfterScaling", "shareInsideHCTM90", "overall")]; shown[2:7] <- round(shown[2:7], 3); print(shown, row.names = FALSE)
cat(paste(readLines(file.path(out, "flag_summary.txt")), collapse = "\n"), "\n")
# Regional (10/20/50 km) index: not joined here. The cell index of every year/replicate is in <run>/uncertainty_<tag>/regional/regional_index_<km>km_replicates.rds; the same scaling (per species and replicate, from the area means above)
# would have to be applied to the cell values of the series before the cells are combined across species. To be done once the national join has been checked on the real runs.
