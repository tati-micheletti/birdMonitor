#!/bin/bash -l
# READ-ONLY: counts the NA pixels (holes) inside Germany in the habitat, landscape and final maps of every species for five years, and the NA pixels of the covariate landscape_heterogeneity (tools/naHolesCheck.R).
#   sbatch cluster/eve_na_holes_check.sbatch      -> table in the log (logs/na-holes_<jobid>.out) and outputs/<run>/na_holes_check.csv
#SBATCH --job-name=na-holes
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=16G
#SBATCH --time=02:00:00
#SBATCH --output=logs/na-holes_%j.out
#SBATCH --error=logs/na-holes_%j.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
unc_run Rscript tools/naHolesCheck.R --run "${BIRDMONITOR_RUNNAME:-test4}"
