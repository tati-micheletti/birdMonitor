#!/usr/bin/env Rscript
# READ-ONLY pre-flight: does every species of data/speciesCanonical.csv (included or candidate) have the records the three scales need?
#   climate   EBBA2 atlas cells with the species (inputs/response/raw/ornitho/ebba2_data_occurrence_50km.csv, name in the BirdLife column = latin_name)
#   landscape DDA territory data (the csv copies of tools/convertDdaTerritories.py; matched by EURING code): plots and territories
#   habitat   point counts (MhB / dbird, inputs/response/raw/MhB/dbird_observations_CBBM.csv): presences April-June with an accepted breeding code in the habitat years, names via sharedDbirdNameAliases
# A species can only be switched on (include = X in speciesCanonical.csv) when all three say READY: the meta-model needs the three scales, and a species with no EBBA2 rows stops the data preparation.
#   Rscript tools/checkSpeciesData.R [--min-presences 10]
args <- commandArgs(trailingOnly = TRUE); minP <- if ("--min-presences" %in% args) as.integer(args[which(args == "--min-presences") + 1]) else 10L
repoRoot <- getwd(); libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*")); if (length(libs)) .libPaths(c(libs, .libPaths()))
suppressMessages(library(data.table)); source("tools/sharedConfig.R")
canon <- read.csv("data/speciesCanonical.csv", stringsAsFactors = FALSE); canon$candidate <- !nzchar(trimws(canon$include))
eb <- fread("inputs/response/raw/ornitho/ebba2_data_occurrence_50km.csv", sep = ";"); ebN <- eb[, .(ebba2Cells = sum(occurrence > 0)), by = .(latin_name = birdlife_scientific_name)]
dd <- fread("inputs/response/processed/territories_csv/dda_data.csv"); ddN <- dd[, .(ddaPlots = uniqueN(ROUTENCODE[Reviere > 0]), ddaTerritories = sum(Reviere)), by = .(euring_code = EURING)]
d <- fread("inputs/response/raw/MhB/dbird_observations_CBBM.csv", select = c("SPECIES_NAME_SCIENTIFIC", "DATE_TIME", "TOTAL_COUNT", "ATLAS_CODE"))
d[, year := as.integer(substr(DATE_TIME, 1, 4))]; d[, month := substr(DATE_TIME, 6, 7)]
al <- sharedDbirdNameAliases; d[SPECIES_NAME_SCIENTIFIC %in% names(al), SPECIES_NAME_SCIENTIFIC := al[SPECIES_NAME_SCIENTIFIC]]
ok <- c("A1", "A2", paste0("B", 3:9), "C10", "C11a", "C11b", "C12", "C13a", "C13b", "C14a", "C14b", "C15", "C16")
mh <- d[year >= 2022 & year <= 2025 & TOTAL_COUNT > 0 & month %in% c("04", "05", "06") & ATLAS_CODE %in% ok, .(pointCountPresences2022_25 = .N), by = .(latin_name = SPECIES_NAME_SCIENTIFIC)]
out <- merge(merge(merge(as.data.table(canon), ebN, by = "latin_name", all.x = TRUE), ddN, by = "euring_code", all.x = TRUE), mh, by = "latin_name", all.x = TRUE)
for (cc in c("ebba2Cells", "ddaPlots", "ddaTerritories", "pointCountPresences2022_25")) out[is.na(get(cc)), (cc) := 0L]
out[, status := ifelse(ebba2Cells < minP, "MISSING climate (EBBA2 rows)", ifelse(ddaTerritories < minP, "MISSING landscape (DDA)", ifelse(pointCountPresences2022_25 < minP, "MISSING habitat (point counts)", "READY")))]
print(out[order(-include, latin_name), .(latin_name, german_name, include = ifelse(candidate, "candidate", "ON"), ebba2Cells, ddaPlots, ddaTerritories, pointCountPresences2022_25, status)], row.names = FALSE)
bad <- out[candidate == FALSE & status != "READY"]; if (nrow(bad)) cat("\nWARNING: species that are ON but not READY:", paste(bad$latin_name, collapse = ", "), "\n")
cat("\nCandidates that could be switched on now:", paste(out[candidate == TRUE & status == "READY", latin_name], collapse = ", "), "\n")
