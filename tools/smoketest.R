# Called by cluster/eve_smoketest.sbatch. Fails loudly on the first problem.
ok <- TRUE
check <- function(label, expr) {
  res <- tryCatch({ force(expr); TRUE }, error = function(e) { message("FAIL ", label, ": ", conditionMessage(e)); FALSE })
  if (res) message("ok   ", label) else ok <<- FALSE
  invisible(res)
}

# Same library location runMe.R/setupProject uses on EVE.
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs)) .libPaths(c(libs, .libPaths()))
message("libPaths: ", paste(.libPaths(), collapse = " | "))

# Packages: the fixed core set plus EVERY package the four modules declare in reqdPkgs.
source("tools/sharedPackages.R")
pkgs <- sort(unique(c("terra", "sf", "SpaDES.core", "SpaDES.project", "reproducible", "Require",
                      "data.table", "gbm", "dismo", "glmnet", "blockCV", "magick", "yaml",
                      modulePackages())))
message("checking ", length(pkgs), " packages: ", paste(pkgs, collapse = ", "))
for (pkg in pkgs)
  check(paste("library", pkg), suppressPackageStartupMessages(library(pkg, character.only = TRUE)))

check("terra sees GDAL", print(terra::gdal(lib = TRUE)))
check("R tempdir() is on /work, not the RAM disk", stopifnot(grepl("^(/gpfs1)?/work", normalizePath(tempdir()))))

for (d in c("inputs", "cache", "outputs")) {
  check(paste(d, "resolves to /work"), stopifnot(startsWith(normalizePath(d), "/gpfs1/work") || startsWith(normalizePath(d), "/work")))
  check(paste(d, "is writable"), { f <- file.path(d, paste0(".smoketest_", Sys.getpid())); file.create(f) || stop("cannot write"); unlink(f) })
}
check("DEM inputs present", stopifnot(file.exists("inputs/predictors/processed/dem/dem_30m_laea.tif")))
check("tempdir() usable", { f <- tempfile(); writeLines("x", f); stopifnot(file.exists(f)) })

message(if (ok) "SMOKETEST: ALL OK" else "SMOKETEST: PROBLEMS FOUND (see FAIL lines above)")
quit(status = if (ok) 0 else 1)
