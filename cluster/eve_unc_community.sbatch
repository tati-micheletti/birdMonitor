#!/bin/bash -l
# Uncertainty workflow (option B), step "community". Per band: expected richness and mean change over all species.
# Submitted by cluster/submit_eve_uncertainty.sh -- do not submit by hand unless you know the dependencies.
#SBATCH --job-name=unc-community
#SBATCH --array=1-16
#SBATCH --cpus-per-task=2
#SBATCH --mem-per-cpu=16G
#SBATCH --time=04:00:00
#SBATCH --output=logs/unc-community_%A_%a.out
#SBATCH --error=logs/unc-community_%A_%a.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
export BIRDMONITOR_UNC_CORES="${SLURM_CPUS_PER_TASK:-1}"
Rscript tools/runUncertaintyTask.R --step community --index "${SLURM_ARRAY_TASK_ID}"
