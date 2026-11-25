# Compare two joins (tools/joinSeries.R output folders) on the main-model Bird Index Farmland (combined_index_main_model.csv, column SBI) - the two sensitivity checks of the pre-specified rule (2026-11-20):
#   (a) calibration on the whole overlap vs on 2021-2023:  Rscript tools/joinSensitivity.R --a outputs/joined_ctmref --b outputs/joined_ctmref_2021_23 --years 2025
#   (b) CTM reference vs HCTM reference:                   Rscript tools/joinSensitivity.R --a outputs/joined_ctmref --b outputs/joined_hctmref --years 2017:2023
# Reports the largest absolute difference in index points over --years and flags it:  yellow > 5 points, red > 10 points.  A red means we revisit the method.
args <- commandArgs(trailingOnly = TRUE)
getArg <- function(f, d = NULL) { i <- which(args == f); if (length(i)) args[i + 1] else d }
years <- function(s) { p <- as.integer(strsplit(s, ":")[[1]]); if (length(p) == 1) p else p[1]:p[2] }
a <- getArg("--a"); b <- getArg("--b"); yrs <- years(getArg("--years", "2025"))
if (is.null(a) || is.null(b)) stop("usage: Rscript tools/joinSensitivity.R --a <join folder> --b <join folder> --years 2025")
A <- read.csv(file.path(a, "combined_index_main_model.csv")); B <- read.csv(file.path(b, "combined_index_main_model.csv"))
m <- merge(A[A$year %in% yrs, c("year", "SBI")], B[B$year %in% yrs, c("year", "SBI")], by = "year", suffixes = c("_a", "_b")); m$difference <- m$SBI_a - m$SBI_b
mx <- max(abs(m$difference)); flag <- if (mx > 10) "RED" else if (mx > 5) "YELLOW" else "ok"
print(m, row.names = FALSE); cat(sprintf("largest absolute difference over %s: %.2f index points -> %s\n", paste(range(yrs), collapse = "-"), mx, flag))
if (flag == "RED") cat("RULE: a red means we revisit the method.\n")
