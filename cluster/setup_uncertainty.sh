#!/bin/bash
# One-time, on an EVE login node: installs the one extra R package the uncertainty workflow needs (matrixStats)
# into the same personal library the other packages live in. Safe to run again.
#
#   cd ~/projects/birdMonitor
#   bash --login cluster/setup_uncertainty.sh
set -euo pipefail
cd "$(dirname "$0")/.."
MODULES="${EVE_R_MODULE:-GCC/13.3.0 OpenMPI/5.0.5 R/4.5.1 GDAL/3.10.3 CMake ImageMagick/7.1.1-38 UDUNITS/2.2.28}"
if ! type module >/dev/null 2>&1; then
  echo "The 'module' command is missing. Run this script as:  bash --login cluster/setup_uncertainty.sh" >&2
  exit 1
fi
module load ${MODULES}
Rscript -e '
libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*"))
if (length(libs) == 0) stop("The birdMonitor R library was not found -- run cluster/setup_eve.sh first.")
.libPaths(c(libs, .libPaths()))
if (!requireNamespace("matrixStats", quietly = TRUE)) install.packages("matrixStats", lib = libs[1], repos = "https://cloud.r-project.org")
for (p in c("matrixStats", "gbm", "glmnet", "terra", "sf", "blockCV"))
  cat(sprintf("%-12s %s
", p, if (requireNamespace(p, quietly = TRUE)) as.character(packageVersion(p)) else "MISSING"))
'
