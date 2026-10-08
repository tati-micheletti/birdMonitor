#!/bin/bash -l
# Germany-only COPIES of the finished uncertainty maps (tools/runUncertaintyTask.R --step maskmaps): tasks 1..11 = the species' maps, 12 = the community maps.
# Submitted by cluster/submit_eve_regional.sh -- do not submit by hand unless you know the dependencies.
#SBATCH --job-name=unc-maskmaps
#SBATCH --array=1-12
#SBATCH --cpus-per-task=2
#SBATCH --mem-per-cpu=8G
#SBATCH --time=02:00:00
#SBATCH --output=logs/unc-maskmaps_%A_%a.out
#SBATCH --error=logs/unc-maskmaps_%A_%a.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
unc_run Rscript tools/runUncertaintyTask.R --step maskmaps --index "${SLURM_ARRAY_TASK_ID}"
