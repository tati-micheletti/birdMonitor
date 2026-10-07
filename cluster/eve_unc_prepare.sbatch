#!/bin/bash -l
# Uncertainty workflow (option B), step "prepare". Per species: fit the replicate BRTs, predict the coarse scales, out-of-fold inputs, fit the replicate ridge models.
# Submitted by cluster/submit_eve_uncertainty.sh -- do not submit by hand unless you know the dependencies.
#SBATCH --job-name=unc-prepare
#SBATCH --array=1-11
#SBATCH --cpus-per-task=8
#SBATCH --mem-per-cpu=8G
#SBATCH --time=10:00:00
#SBATCH --output=logs/unc-prepare_%A_%a.out
#SBATCH --error=logs/unc-prepare_%A_%a.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
export BIRDMONITOR_UNC_CORES="${SLURM_CPUS_PER_TASK:-1}"
for step in fit coarse oof ridge; do
  unc_run Rscript tools/runUncertaintyTask.R --step ${step} --index "${SLURM_ARRAY_TASK_ID}"
done
