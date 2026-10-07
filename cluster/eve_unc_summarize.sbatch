#!/bin/bash -l
# Uncertainty workflow (option B), step "summarize". Per species x band: percentile maps, change maps, per-pixel trend.
# Submitted by cluster/submit_eve_uncertainty.sh -- do not submit by hand unless you know the dependencies.
#SBATCH --job-name=unc-summarize
#SBATCH --array=1-176
#SBATCH --cpus-per-task=2
#SBATCH --mem-per-cpu=12G
#SBATCH --time=04:00:00
#SBATCH --output=logs/unc-summarize_%A_%a.out
#SBATCH --error=logs/unc-summarize_%A_%a.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
export BIRDMONITOR_UNC_CORES="${SLURM_CPUS_PER_TASK:-1}"
unc_run Rscript tools/runUncertaintyTask.R --step summarize --index "${SLURM_ARRAY_TASK_ID}"
