#!/bin/bash -l
# READ-ONLY: mean probability over Germany of each scale's prediction and of the final map, 2005-2025, per species (tools/scaleTrendCheck.R). One task per species.
#   sbatch cluster/eve_scale_trend_check.sbatch      -> outputs/<run>/scale_trend_check/<Species>.csv  (small files; download them)
#SBATCH --job-name=scale-trend
#SBATCH --array=1-11
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=16G
#SBATCH --time=03:00:00
#SBATCH --output=logs/scale-trend_%A_%a.out
#SBATCH --error=logs/scale-trend_%A_%a.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
unc_run Rscript tools/scaleTrendCheck.R --index "${SLURM_ARRAY_TASK_ID}" --run "${BIRDMONITOR_RUNNAME:-test4}"
