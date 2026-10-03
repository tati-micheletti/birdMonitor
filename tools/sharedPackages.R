# Packages the pipeline needs, read from every module's own `reqdPkgs` declaration
# (so this list cannot drift out of sync with the modules). Used by
#   - runMe.R in BIRDMONITOR_INSTALL_ONLY mode, to install anything setupProject()
#     skipped (e.g. mgcv: shipped with desktop R, but absent from EVE's bare R module)
#   - tools/smoketest.R, to verify the installation on a compute node.
modulePackages <- function(modules = c("dataPrep_Monitor", "inputs_Monitor",
                                       "models_Monitor", "runIndex_Monitor"),
                           modulesDir = "modules") {
  pkgs <- unlist(lapply(modules, function(m) {
    lines <- readLines(file.path(modulesDir, m, paste0(m, ".R")), warn = FALSE)
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
  sort(unique(pkgs))
}
