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

# Packages: the fixed core set plus EVERY package the four modules declare in reqdPkgs
# (read from the module files, so this test cannot drift out of sync with them).
modPkgs <- unlist(lapply(c("dataPrep_Monitor", "inputs_Monitor", "models_Monitor", "runIndex_Monitor"), function(m) {
  lines <- readLines(file.path("modules", m, paste0(m, ".R")), warn = FALSE)
  start <- grep("reqdPkgs *=", lines)[1]
  if (is.na(start)) return(character())
  end <- grep("parameters *=", lines)
  end <- end[end >= start][1]
  blk <- paste(lines[start:end], collapse = " ")
  q <- regmatches(blk, gregexpr('"[^"]+"', blk))[[1]]
  q <- gsub('"', "", q)
  q <- sub(" *[(].*[)]$", "", q)   # drop version constraint
  q <- sub("@.*$", "", q)          # drop @branch
  q <- sub("^.*/", "", q)          # drop GitHub owner
  q[q != "parameters"]
}))
pkgs <- sort(unique(c("terra", "sf", "SpaDES.core", "SpaDES.project", "reproducible", "Require",
                      "data.table", "gbm", "dismo", "glmnet", "blockCV", "magick", "yaml", modPkgs)))
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
