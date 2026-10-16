#!/bin/bash -l
# READ-ONLY: our predictions at the survey plots of the landscape-scale records, every plot and year (tools/panelTrendCheck.R). One task per species.
#   sbatch cluster/eve_panel_trend_check.sbatch      -> outputs/<run>/panel_trend_check/<Species>.csv  (small files; download them)
#SBATCH --job-name=panel-trend
#SBATCH --array=1-11
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=16G
#SBATCH --time=03:00:00
#SBATCH --output=logs/panel-trend_%A_%a.out
#SBATCH --error=logs/panel-trend_%A_%a.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
unc_run Rscript tools/panelTrendCheck.R --index "${SLURM_ARRAY_TASK_ID}" --run "${BIRDMONITOR_RUNNAME:-test4}"
