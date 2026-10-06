# One table of the block-CV performance of every species and scale (+ the meta-model, flagged), from the saved perf files.
#   Rscript tools/collectPerformance.R [run name, default test4]
# Writes outputs/<run>/performance_table.csv and prints it.
#
# How to read it:
#  * climate / landscape / habitat rows: block cross-validation of that scale's BRT = held-out blocks, honest.
#  * meta rows: the ridge combiner's own block-CV. Its INPUTS (the three scale predictions at the training records) come
#    from BRTs fitted on all records, so it is optimistic (improvements.md item 16): do NOT quote it as the final map's accuracy.
args <- commandArgs(trailingOnly = TRUE)
run <- if (length(args)) args[1] else "test4"
root <- file.path("outputs", run)
rows <- list()
read1 <- function(f, species, scale, honest) {
  if (!file.exists(f)) return(NULL)
  p <- readRDS(f)
  data.frame(species = species, scale = scale, honest = honest, p[, intersect(c("AUC", "TSS", "Kappa", "Sens", "Spec", "PCC", "D2", "thresh"), names(p)), drop = FALSE])
}
sp <- unique(sub("_perf_.*[.]rds$", "", list.files(root, pattern = "_perf_.*[.]rds$", recursive = TRUE)))
sp <- unique(sub("^.*/", "", sp))
for (s in sp) {
  sc <- gsub("_", " ", s)
  for (d in list.dirs(root, recursive = FALSE)) {
    for (suffix in c("EU", "landscape", "habitat")) {
      f <- file.path(d, paste0(s, "_perf_", suffix, ".rds"))
      scale <- c(EU = "climate", landscape = "landscape", habitat = "habitat")[[suffix]]
      rows[[length(rows) + 1]] <- read1(f, sc, scale, TRUE)
    }
    rows[[length(rows) + 1]] <- read1(file.path(d, paste0(s, "_perf_meta.rds")), sc, "meta (optimistic)", FALSE)
  }
}
tab <- do.call(rbind, rows)
if (is.null(tab)) stop("No perf files found under ", root)
tab <- tab[order(tab$species, match(sub(" .*", "", tab$scale), c("climate", "landscape", "habitat", "meta"))), ]
num <- vapply(tab, is.numeric, logical(1)); tab[num] <- lapply(tab[num], round, 3)
out <- file.path(root, "performance_table.csv"); utils::write.csv(tab, out, row.names = FALSE)
print(tab, row.names = FALSE); cat("\n->", out, "\n")
