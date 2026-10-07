#!/bin/bash -l
# Uncertainty workflow (option B), step "bandpredict". Per species x band: predict all years for all replicates (the expensive part).
# Submitted by cluster/submit_eve_uncertainty.sh -- do not submit by hand unless you know the dependencies.
#SBATCH --job-name=unc-band
#SBATCH --array=1-176
#SBATCH --cpus-per-task=4
#SBATCH --mem-per-cpu=13G
#SBATCH --time=12:00:00
#SBATCH --output=logs/unc-band_%A_%a.out
#SBATCH --error=logs/unc-band_%A_%a.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
export BIRDMONITOR_UNC_CORES="${SLURM_CPUS_PER_TASK:-1}"
unc_run Rscript tools/runUncertaintyTask.R --step bandpredict --index "${SLURM_ARRAY_TASK_ID}"
