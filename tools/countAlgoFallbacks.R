# Counts the species-scale fits of the GLM and GAM ensemble members that did NOT use the first, default setting (READ-ONLY; audit table S3-26, S3-37; set 2026-11-04 for the v3 results).
#   Rscript tools/countAlgoFallbacks.R --run v3                       (from the repository root, on EVE after the ensemble fits: module load R first)
# Each fit written by algoFitGAM()/algoFitGLM() (modules/models_Monitor/R/algoModels.R) carries a `note`: empty = the first attempt worked; otherwise what had to be changed
# ("REML 500 iterations; ", "REML + efs optimiser; ", "k = 3; ", "dropped <predictor>; "). A GAM that fell back is a simpler or differently estimated model than the documented default:
# the results are valid, but the fit is not the plain s(x, k = 4) GAM of the method description.
# Output: a table on screen and outputs/<run>/diagnostics/algo_fallbacks.csv (one row per fit) and algo_fallbacks_summary.csv (counts per algorithm and scale).
args <- commandArgs(trailingOnly = TRUE); getArg <- function(k, d) { i <- match(k, args); if (is.na(i) || i == length(args)) d else args[i + 1] }
run <- getArg("--run", Sys.getenv("BIRDMONITOR_RUNNAME", "v3")); out <- getArg("--out-root", "outputs"); root <- file.path(out, run)
stopifnot(dir.exists(root))
files <- list.files(root, pattern = "_(glm|gam)_(climate|landscape|habitat)\\.rds$", recursive = TRUE, full.names = TRUE)
files <- files[!grepl("/(uncertainty|figures|diagnostics)", gsub("\\\\", "/", files))]          # main fits only, not the replicate fits
if (!length(files)) stop("No GLM/GAM fit files found under ", root)
rows <- lapply(files, function(f) {
  b <- basename(f); m <- regmatches(b, regexec("^(.*)_(glm|gam)_(climate|landscape|habitat)\\.rds$", b))[[1]]
  fit <- tryCatch(readRDS(f), error = function(e) NULL)
  note <- if (is.list(fit) && !is.null(fit$note)) as.character(fit$note)[1] else NA_character_
  data.frame(species = gsub("_", " ", m[2]), algorithm = m[3], scale = m[4], note = note, nPredictors = if (is.list(fit)) length(fit$predSel) else NA_integer_,
             what = if (is.na(note)) "could not be read" else if (!nzchar(note)) "first attempt" else if (grepl("dropped", note)) "predictor(s) dropped"
                    else if (grepl("k = 3", note)) "k = 3" else if (grepl("efs", note)) "REML + efs optimiser" else if (grepl("REML", note)) "REML, more iterations" else "other", stringsAsFactors = FALSE)
})
d <- do.call(rbind, rows); d <- d[order(d$algorithm, d$scale, d$species), ]
dir.create(file.path(root, "diagnostics"), showWarnings = FALSE, recursive = TRUE)
write.csv(d, file.path(root, "diagnostics", "algo_fallbacks.csv"), row.names = FALSE)
s <- as.data.frame(table(algorithm = d$algorithm, scale = d$scale, what = d$what)); s <- s[s$Freq > 0, ]
write.csv(s, file.path(root, "diagnostics", "algo_fallbacks_summary.csv"), row.names = FALSE)
cat("fits read:", nrow(d), "\n\n"); print(s, row.names = FALSE)
fb <- d[!d$what %in% c("first attempt"), ]
cat("\nfits that did not use the first attempt:", nrow(fb), "of", nrow(d), "\n"); if (nrow(fb)) print(fb[, c("species", "algorithm", "scale", "what", "note")], row.names = FALSE)
