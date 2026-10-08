#!/bin/bash -l
# Regional index uncertainty, step "regionband". Per species x band: sums of the replicate predictions of the German 200 m pixels per 10/20/50 km cell.
# Submitted by cluster/submit_eve_regional.sh -- do not submit by hand unless you know the dependencies.
#SBATCH --job-name=unc-regionband
#SBATCH --array=1-176
#SBATCH --cpus-per-task=2
#SBATCH --mem-per-cpu=8G
#SBATCH --time=02:00:00
#SBATCH --output=logs/unc-regionband_%A_%a.out
#SBATCH --error=logs/unc-regionband_%A_%a.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
export BIRDMONITOR_UNC_CORES="${SLURM_CPUS_PER_TASK:-1}"
unc_run Rscript tools/runUncertaintyTask.R --step regionband --index "${SLURM_ARRAY_TASK_ID}"
