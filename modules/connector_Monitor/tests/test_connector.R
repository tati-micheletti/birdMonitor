# Local test of connector_Monitor on a small synthetic fixture (no real data needed):
#   Rscript modules/connector_Monitor/tests/test_connector.R        (from the repo root)
# Two run folders: runA (older, two species) and runB (newer, only Perdix perdix); utest is a folder that must be ignored.
suppressMessages(library(terra))
for (f in list.files("modules/connector_Monitor/R", full.names = TRUE)) source(f)
ok <- 0L; fail <- 0L
check <- function(what, cond) { if (isTRUE(cond)) { ok <<- ok + 1L; message("ok   ", what) } else { fail <<- fail + 1L; message("FAIL ", what) } }
tag <- "ens_brt-glm-gam-rf-nn"; root <- file.path(tempdir(), paste0("conn_", Sys.getpid())); runs <- file.path(root, "outputs"); viz <- file.path(root, "viz")
mk <- function(n, v, nm) { r <- rast(nrows = 20, ncols = 20, xmin = 4e6, xmax = 4.02e6, ymin = 3e6, ymax = 3.02e6, crs = "EPSG:3035", nlyrs = n); values(r) <- v; names(r) <- nm; r }
w <- function(r, f) { dir.create(dirname(f), recursive = TRUE, showWarnings = FALSE); writeRaster(r, f, overwrite = TRUE) }
fiveNm <- c("mean", "sd", "lwr", "upr", "width")
build <- function(run, spp, yrs, val, withCommon) {
  rd <- file.path(runs, run)
  for (sp in spp) for (yr in yrs) {
    s <- gsub(" ", "_", sp)
    w(mk(2, val, c("meta_prob", "binary")), file.path(rd, paste0("metamodel_02_1_50_", tag, "_germany"), paste0(s, "_meta_suitability_", yr, ".tif")))
    w(mk(5, val, fiveNm), file.path(rd, paste0("uncertainty_", tag), s, "maps_germany", paste0(s, "_unc_", yr, ".tif")))
  }
  if (withCommon) {
    for (yr in yrs) w(mk(5, val, fiveNm), file.path(rd, paste0("uncertainty_", tag), "community_germany", paste0("richness_expected_unc_", yr, ".tif")))
    nd <- file.path(rd, paste0("annual_report_", tag, "_germany")); dir.create(nd, recursive = TRUE, showWarnings = FALSE)
    utils::write.csv(data.frame(method = "MSI", year = 2005:2025, nReplicates = 25, estimate = 100, median = 100, lwr = 95, upr = 105), file.path(nd, "combined_index_uncertainty.csv"), row.names = FALSE)
    w(mk(2, val, c("2005", "2006")), file.path(rd, paste0("regional_index_", tag, "_germany"), "regional_index_10km_raw.tif"))
    for (yr in yrs) w(mk(5, val, fiveNm), file.path(rd, paste0("uncertainty_", tag), "regional", paste0("regional_index_10km_unc_", yr, ".tif")))
  }
}
sp2 <- c("Alauda arvensis", "Perdix perdix"); yrs <- 2005:2006
build("runA", sp2, yrs, 1, TRUE); build("utest", sp2, yrs, 99, TRUE)
Sys.setFileTime(list.files(file.path(runs, "runA"), recursive = TRUE, full.names = TRUE), Sys.time() - 3600)
run <- function(species = sp2, ...) connectViz(runs, viz, tag, species, yrs, runs = NULL, linkMode = "copy", ...)

r1 <- run()
check("first run: no result missing", nrow(r1$missing) == 0)
check("first run: probability file of each species and year", all(file.exists(file.path(viz, "meta_prob_year", rep(gsub(" ", "_", sp2), each = 2), paste0(rep(gsub(" ", "_", sp2), each = 2), "_", yrs, ".tif")))))
check("uncertainty split into 5 single-layer files", all(file.exists(file.path(viz, "meta_unc_year", "Perdix_perdix", paste0("Perdix_perdix_2005_", fiveNm, ".tif")))))
check("every file has one layer", all(sapply(list.files(viz, pattern = "[.]tif$", recursive = TRUE, full.names = TRUE), function(f) nlyr(rast(f))) == 1))
check("probability file is the probability layer (value 1), not the binary", global(rast(file.path(viz, "meta_prob_year", "Perdix_perdix", "Perdix_perdix_2005.tif")), "mean")[1, 1] == 1)
check("richness: mean and uncertainty layers, for EVERY year", all(file.exists(file.path(viz, "richness_year", paste0("richness_", rep(yrs, each = 5), "_", fiveNm, ".tif")))))
nt <- read.csv(file.path(viz, "msi_national", "msi_national.csv"))
check("national trend: written with the preliminary flag (none: no year given)", nrow(nt) == 21 && !any(nt$preliminary))
r1b <- run(nationalLastPublishedYear = 2023L); nt <- read.csv(file.path(viz, "msi_national", "msi_national.csv"))
check("national trend: only the years after the last published year are preliminary (2024, 2025), the rest untouched", identical(nt$year[nt$preliminary], 2024:2025) && nrow(nt) == 21 && r1b$done == 1L)
check("national trend: a table, not a raster, and nothing else is marked", !any(grepl("preliminary", list.files(viz, recursive = TRUE))) && nrow(r1b$missing) == 0)
check("regional index: one file per year, uncertainty split", file.exists(file.path(viz, "msi_regional", "msi_10km_2005.tif")) && file.exists(file.path(viz, "msi_regional_unc", "msi_10km_2006_width.tif")))
check("ignored folder (utest) not used", !any(grepl("utest", r1$manifest$run)))
check("manifest written", file.exists(file.path(viz, "_manifest.csv")) && file.exists(file.path(viz, "_missing.csv")))
r2 <- run(nationalLastPublishedYear = 2023L)
check("second run (same settings) changes nothing", r2$done == 0L)

# a later run of ONE species: only that species is replaced, the other keeps its earlier file
build("runB", "Perdix perdix", yrs, 2, FALSE)
r3 <- run()
check("later run: Perdix replaced", global(rast(file.path(viz, "meta_prob_year", "Perdix_perdix", "Perdix_perdix_2005.tif")), "mean")[1, 1] == 2)
check("later run: Alauda untouched (still from runA)", global(rast(file.path(viz, "meta_prob_year", "Alauda_arvensis", "Alauda_arvensis_2005.tif")), "mean")[1, 1] == 1 && all(r3$manifest$run[r3$manifest$species == "Alauda_arvensis"] == "runA"))
check("later run: the viz folder is still complete", nrow(r3$missing) == 0)
check("later run: regional index still from runA (runB has none)", all(r3$manifest$run[r3$manifest$product == "msi_regional"] == "runA"))
r4 <- run()
check("after that nothing to do", r4$done == 0L)

# an old, deleted run folder must not make the viz folder regress, and a species without any result is reported
r5 <- suppressWarnings(run(species = c(sp2, "Vanellus vanellus")))
check("missing species reported", any(r5$missing$species == "Vanellus_vanellus") && nrow(r5$missing) > 0)
res <- tryCatch(run(species = c(sp2, "Vanellus vanellus"), failIfIncomplete = TRUE), error = function(e) "error")
check("failIfIncomplete stops", identical(res, "error"))
d <- run(dryRun = TRUE); check("dry run writes nothing", is.null(d$missing))

# water mask (2026-11-05): only the COPIES in the viz folder are masked; the cell is NA when at least half of it is water
wf <- file.path(root, "water.gpkg")                                                      # the fixture has 1 km cells (x 4.00e6 to 4.02e6): water over columns 1-3 completely, 20% of column 5, 80% of column 7, all rows
rect <- function(x0, x1) terra::vect(sprintf("POLYGON ((%f 3000000, %f 3000000, %f 3020000, %f 3020000, %f 3000000))", x0, x1, x1, x0, x0), crs = "EPSG:3035")
terra::writeVector(rbind(rect(4.000e6, 4.003e6), rect(4.004e6, 4.0042e6), rect(4.006e6, 4.0068e6)), wf, overwrite = TRUE)
srcFiles <- list.files(runs, recursive = TRUE, full.names = TRUE); md5Before <- tools::md5sum(srcFiles)
mat <- function(f) as.matrix(rast(f), wide = TRUE)
rw <- run(waterFile = wf)
mp <- mat(file.path(viz, "meta_prob_year", "Perdix_perdix", "Perdix_perdix_2005.tif")); mu <- mat(file.path(viz, "meta_unc_year", "Perdix_perdix", "Perdix_perdix_2005_width.tif")); mr <- mat(file.path(viz, "richness_year", "richness_2005_mean.tif"))
okMask <- function(m) all(is.na(m[, 1:3])) && !anyNA(m[, 4]) && !anyNA(m[, 5]) && !anyNA(m[, 6]) && all(is.na(m[, 7])) && !anyNA(m[, 8:20])
check("water mask: probability map: columns 1-3 and 7 (>= half water) are NA; 4, 5 (20% water), 6, 8-20 keep their value", okMask(mp))
check("water mask: the uncertainty layers and the richness layers are masked the same way", okMask(mu) && okMask(mr))
check("water mask: the regional index (MSI) is not masked", !anyNA(mat(file.path(viz, "msi_regional", "msi_10km_2005.tif"))) && !anyNA(mat(file.path(viz, "msi_regional_unc", "msi_10km_2006_width.tif"))))
check("water mask: the source files are untouched (same checksums)", identical(unname(tools::md5sum(srcFiles)), unname(md5Before)))
check("water mask: probability files are written, not linked, and the manifest says so", all(grepl("^written; water mask", rw$manifest$mode[rw$manifest$product %in% c("meta_prob_year", "meta_unc_year", "richness_year")])) && !any(nzchar(Sys.readlink(list.files(viz, "[.]tif$", recursive = TRUE, full.names = TRUE)))))
check("water mask: second run (same settings) changes nothing", run(waterFile = wf)$done == 0L)
check("water mask: a different share threshold makes the files again (0.1: column 5 with 20% water is now NA)", { run(waterFile = wf, waterMinShare = 0.1); is.na(mat(file.path(viz, "meta_prob_year", "Perdix_perdix", "Perdix_perdix_2005.tif"))[1, 5]) })
rOff <- run(); check("water mask: switched off, the files are made again without it", rOff$done > 0L && !anyNA(mat(file.path(viz, "meta_prob_year", "Perdix_perdix", "Perdix_perdix_2005.tif"))) && !any(grepl("water", rOff$manifest$mode)))
resW <- tryCatch(run(waterFile = file.path(root, "does_not_exist.gpkg")), error = function(e) conditionMessage(e)); check("water mask: a missing file stops at once", is.character(resW) && grepl("does not exist", resW))
check("water mask: a dry run with the mask writes nothing", is.null(run(waterFile = wf, dryRun = TRUE)$missing))

# as a SpaDES module
if (requireNamespace("SpaDES.core", quietly = TRUE)) {
  unlink(viz, recursive = TRUE)
  s <- SpaDES.core::simInitAndSpades(times = list(start = 2005, end = 2005), modules = "connector_Monitor", paths = list(modulePath = "modules", outputPath = file.path(runs, "runB")),
                                    params = list(connector_Monitor = list(vizPath = viz, runsRoot = runs, tag = tag, species = sp2, years = yrs, linkMode = "copy")))
  check("module run: viz folder filled and complete", file.exists(file.path(viz, "meta_prob_year", "Perdix_perdix", "Perdix_perdix_2006.tif")) && nrow(s$vizManifest) > 0 && nrow(read.csv(file.path(viz, "_missing.csv"))) == 0)
}
message("\n", ok, " passed, ", fail, " failed"); unlink(root, recursive = TRUE); if (fail) quit(status = 1)
