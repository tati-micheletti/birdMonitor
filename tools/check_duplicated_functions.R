# ============================================================
# check_duplicated_functions.R
#
# Some small utility functions are deliberately duplicated across
# dataPrep_Monitor / inputs_Monitor / models_Monitor rather than shared
# via a package or cross-module sim$.mods$ calls, so each module can be
# loaded and tested independently (see the "module independence"
# discussion in the project chat/memory).
#
# The tradeoff of duplication is silent drift: if you fix a bug or
# change behaviour in one module's copy and forget the others, the
# modules quietly diverge with no error -- exactly what happened in the
# original (pre-SpaDES) pipeline scripts, which is why this check
# exists. Run it after touching any file that also exists (by the same
# name) in another module's R/ folder, or periodically as a sanity
# check.
#
# Usage:
#   Rscript tools/check_duplicated_functions.R
# Exit code 0 = all duplicated files match across modules; 1 = at least
# one has drifted (details printed to console).
# ============================================================

getScriptPath <- function() {
  cmdArgs <- commandArgs(trailingOnly = FALSE)
  fileArgMatch <- grep("^--file=", cmdArgs)
  if (length(fileArgMatch) > 0) {
    return(normalizePath(sub("^--file=", "", cmdArgs[fileArgMatch[1]])))
  }
  normalizePath(sys.frame(1)$ofile)  # fallback when source()'d interactively
}

birdMonitorRoot <- normalizePath(file.path(dirname(getScriptPath()), ".."))
moduleDirs <- list.dirs(file.path(birdMonitorRoot, "modules"), recursive = FALSE)

# Collect every R/*.R file across all modules, keyed by basename
allFiles <- list()
for (modDir in moduleDirs) {
  modName <- basename(modDir)
  rFiles <- list.files(file.path(modDir, "R"), pattern = "\\.R$", full.names = TRUE)
  for (f in rFiles) {
    fname <- basename(f)
    allFiles[[fname]] <- c(allFiles[[fname]], stats::setNames(f, modName))
  }
}

# Only basenames appearing in 2+ modules are "duplicated" functions
duplicated <- Filter(function(x) length(x) > 1, allFiles)

if (length(duplicated) == 0) {
  cat("No same-named R files shared across modules -- nothing to check.\n")
  quit(status = 0)
}

cat("Checking", length(duplicated), "function file(s) duplicated across modules...\n\n")

drifted <- character(0)

for (fname in names(duplicated)) {
  paths <- duplicated[[fname]]
  contents <- lapply(paths, function(p) paste(readLines(p, warn = FALSE), collapse = "\n"))

  allMatch <- length(unique(contents)) == 1

  cat(sprintf("%-32s across [%s] : %s\n", fname, paste(names(paths), collapse = ", "),
              if (allMatch) "MATCH" else "*** DIFFERS ***"))

  if (!allMatch) {
    drifted <- c(drifted, fname)
    for (i in seq_along(paths)) {
      cat(sprintf("    %-18s %s\n", names(paths)[i], paths[i]))
    }
  }
}

cat("\n")
if (length(drifted) == 0) {
  cat("All duplicated functions are identical across modules.\n")
  quit(status = 0)
} else {
  cat("DRIFT DETECTED in:", paste(drifted, collapse = ", "), "\n")
  cat("Diff the files above and decide which version is correct, then sync them.\n")
  quit(status = 1)
}
