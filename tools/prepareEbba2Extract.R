#!/usr/bin/env Rscript
# Bring a NEW EBBA2 extract (e.g. with the four candidate species) into the pipeline WITHOUT touching the file that is there. Nothing in inputs/ is overwritten: the result is a new, dated file.
#   Rscript tools/prepareEbba2Extract.R <new extract .csv> [--out <merged file>] [--dry]
# What it does
#   1. reads the new extract (';' or ',' separated; columns cell50x50, birdlife_code, birdlife_scientific_name, occurrence; any order, any case) and keeps the presences (occurrence == 1: the file on disk holds presences only)
#   2. renames BirdLife names that differ from the roster (sharedEbba2NameAliases in tools/sharedConfig.R, e.g. Sylvia communis -> Curruca communis) and reports every name that is in neither the roster nor the old file
#   3. checks that every cell is a cell of the EBBA2 grid (ebba2_grid50x50_v1.shp) and reports how many cells are NEW to the cell universe (the pipeline takes the "surveyed cells" = the cells present in the file,
#      so the absences of ALL species are drawn from that universe: new cells add absences to every species, and the Europe tables of all species are rebuilt -- fine for a clean run, say so in DECISIONS.md)
#   4. merges: the rows of the file on disk stay as they are; rows of species that are NOT in it are added; for species in both, the cell sets are compared and only differences are reported (the old rows win)
#   5. writes <inputs>/response/raw/ornitho/ebba2_data_occurrence_50km_<date>.csv (same format as the file on disk) + a <file>.merge_report.txt; refuses to overwrite anything
# Then ONE line switches the pipeline to it (the script prints it): sharedEbba2CsvSubpath in tools/sharedConfig.R. Afterwards: Rscript tools/checkSpeciesData.R, and include = X for the species in data/speciesCanonical.csv.
args <- commandArgs(trailingOnly = TRUE)
if (!length(args) || args[1] %in% c("-h", "--help")) { cat(readLines(sub("^--file=", "", grep("^--file=", commandArgs(), value = TRUE)[1]), n = 14), sep = "\n"); quit(status = 0) }
newFile <- args[1]; dry <- "--dry" %in% args; outArg <- if ("--out" %in% args) args[which(args == "--out") + 1] else NULL
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*")); if (length(libs)) .libPaths(c(libs, .libPaths()))
suppressMessages({ library(data.table); library(terra) }); source("tools/sharedConfig.R")
say <- function(...) { m <- paste0(...); cat(m, "\n"); reportLines <<- c(reportLines, m) }; reportLines <- character()
stopifnot(file.exists(newFile))
cur <- file.path("inputs", sharedEbba2CsvSubpath); stopifnot(file.exists(cur))
shp <- file.path("inputs", "response", "raw", "ornitho", "ebba2_grid50x50_v1.shp")
readExtract <- function(f) { first <- readLines(f, n = 1, warn = FALSE); sep <- if (grepl(";", first, fixed = TRUE)) ";" else if (grepl("\t", first, fixed = TRUE)) "\t" else ","
  d <- fread(f, sep = sep, colClasses = "character", encoding = "UTF-8"); names(d) <- tolower(trimws(gsub("^﻿", "", names(d)))); d }
old <- readExtract(cur); new <- readExtract(newFile)
need <- c("cell50x50", "birdlife_code", "birdlife_scientific_name", "occurrence")
if (!all(need %in% names(new))) stop("The new extract lacks column(s): ", paste(setdiff(need, names(new)), collapse = ", "), " (has: ", paste(names(new), collapse = ", "), "). Rename them or tell me the layout.")
new <- new[, ..need]; new[, `:=`(birdlife_scientific_name = trimws(birdlife_scientific_name), cell50x50 = trimws(cell50x50), occurrence = suppressWarnings(as.numeric(occurrence)))]
say("file on disk: ", cur, " (", nrow(old), " rows, ", uniqueN(old$birdlife_scientific_name), " species, ", uniqueN(old$cell50x50), " cells)")
say("new extract:  ", newFile, " (", nrow(new), " rows, ", uniqueN(new$birdlife_scientific_name), " species, ", uniqueN(new$cell50x50), " cells)")
if (anyNA(new$occurrence)) { say("WARNING: ", sum(is.na(new$occurrence)), " rows without a numeric occurrence dropped"); new <- new[!is.na(occurrence)] }
if (any(new$occurrence == 0)) say("note: ", sum(new$occurrence == 0), " rows with occurrence = 0 are not kept (the file on disk holds presences only)")
new <- new[occurrence == 1]
al <- sharedEbba2NameAliases; hit <- new$birdlife_scientific_name %in% names(al)
if (any(hit)) { say("renamed to the roster name: ", paste(sprintf("%s -> %s (%d rows)", names(al), al, sapply(names(al), function(n) sum(new$birdlife_scientific_name == n))), collapse = "; ")); new[hit, birdlife_scientific_name := al[birdlife_scientific_name]] }
canon <- read.csv("data/speciesCanonical.csv", stringsAsFactors = FALSE); roster <- canon$latin_name
say("\nroster species (data/speciesCanonical.csv) in the NEW extract:")
for (sp in roster) say(sprintf("  %-22s new: %6d cells | old file: %6d cells %s", sp, new[birdlife_scientific_name == sp, uniqueN(cell50x50)], old[birdlife_scientific_name == sp, uniqueN(cell50x50)],
                              if (new[birdlife_scientific_name == sp, .N] == 0 && old[birdlife_scientific_name == sp, .N] == 0) "  <-- MISSING in both" else ""))
other <- setdiff(unique(new$birdlife_scientific_name), roster); if (length(other)) say("\nnames in the new extract that are not in the roster (ignored): ", paste(head(other, 15), collapse = ", "), if (length(other) > 15) paste0(" ... (", length(other), ")"))
new <- new[birdlife_scientific_name %in% roster]
grid <- vect(shp); gc <- as.character(values(grid)[["cell50x50"]]); bad <- setdiff(unique(new$cell50x50), gc)
say("\ncells of the new extract that are not cells of the EBBA2 grid: ", length(bad), if (length(bad)) paste0(" (e.g. ", paste(head(bad, 5), collapse = ", "), ") -> those rows are dropped") else "")
new <- new[cell50x50 %in% gc]
inOld <- unique(old$birdlife_scientific_name); both <- intersect(unique(new$birdlife_scientific_name), inOld); add <- setdiff(unique(new$birdlife_scientific_name), inOld)
for (sp in both) { a <- unique(old[birdlife_scientific_name == sp, cell50x50]); b <- unique(new[birdlife_scientific_name == sp, cell50x50])
  if (!setequal(a, b)) say(sprintf("DIFFERENT cell sets for %s (kept the OLD rows): only in old %d, only in new %d", sp, length(setdiff(a, b)), length(setdiff(b, a)))) }
say("\nspecies added to the file: ", if (length(add)) paste(add, collapse = ", ") else "NONE (nothing to add)")
added <- new[birdlife_scientific_name %in% add]; added <- added[!duplicated(added[, .(cell50x50, birdlife_scientific_name)])]
newCells <- setdiff(unique(added$cell50x50), unique(old$cell50x50))
say("cells the added species bring to the 'surveyed cells' universe: ", length(newCells), " (universe now ", uniqueN(old$cell50x50), " -> ", uniqueN(old$cell50x50) + length(newCells), "): the absences of every species are drawn from it.")
merged <- rbind(old[, ..need], added[, ..need], fill = TRUE)
out <- if (!is.null(outArg)) outArg else file.path(dirname(cur), paste0("ebba2_data_occurrence_50km_", format(Sys.Date(), "%Y-%m-%d"), ".csv"))
say("\nmerged file: ", nrow(merged), " rows, ", uniqueN(merged$birdlife_scientific_name), " species -> ", out)
if (file.exists(out)) stop("Refusing to overwrite ", out)
if (!length(add)) { say("Nothing to add: no file written."); dry <- TRUE }
if (!dry) {
  fwrite(merged, out, sep = ";", quote = FALSE, row.names = FALSE); writeLines(reportLines, paste0(out, ".merge_report.txt"))
  chk <- readExtract(out); stopifnot(nrow(chk) == nrow(merged), all(need %in% names(chk)))
  cat("\nWritten and read back (", nrow(chk), " rows). TO USE IT, in tools/sharedConfig.R set:\n  sharedEbba2CsvSubpath <- \"", sub("^inputs/", "", gsub("\\\\", "/", out)), "\"\nthen: Rscript tools/checkSpeciesData.R   and set include = X for the species in data/speciesCanonical.csv\n", sep = "")
} else cat("\n(dry: nothing written)\n")
