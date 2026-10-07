#!/bin/bash -l
# Uncertainty workflow (option B), step "assemble". Per species: stitch the pieces into maps; area means and index uncertainty.
# Submitted by cluster/submit_eve_uncertainty.sh -- do not submit by hand unless you know the dependencies.
#SBATCH --job-name=unc-assemble
#SBATCH --array=1-11
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=16G
#SBATCH --time=04:00:00
#SBATCH --output=logs/unc-assemble_%A_%a.out
#SBATCH --error=logs/unc-assemble_%A_%a.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
export BIRDMONITOR_UNC_CORES="${SLURM_CPUS_PER_TASK:-1}"
unc_run Rscript tools/runUncertaintyTask.R --step assemble --index "${SLURM_ARRAY_TASK_ID}"
