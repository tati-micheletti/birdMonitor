#!/bin/bash -l
# Baseline step BEFORE the habitat model array: writes the 200 m habitat covariate stack of every year as a GeoTIFF
# (outputs/<run>/uncertainty/covcache/scale_02/habitat_<year>.tif). The habitat array then READS these files instead of
# building each year in memory with loadHabitatCovariates(), which peaks at ~11.6 GB per year (measured) and killed the
# habitat tasks twice. The files hold exactly the layers loadHabitatCovariates() returns. About 1-2 minutes per year.
#
#   sbatch cluster/eve_covcache.sbatch                          (from the repo root)
# The uncertainty workflow re-uses the same files.

#SBATCH --job-name=birdmon-covcache
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=24G
#SBATCH --time=04:00:00
#SBATCH --output=logs/covcache_%j.out
#SBATCH --error=logs/covcache_%j.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
Rscript tools/runUncertaintyTask.R --step covcache
