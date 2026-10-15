#!/bin/bash -l
# Mann-Kendall test and Sen slope at every pixel, from the yearly main-model maps (tools/pixelTrendTest.R). One task per species, both runs (BRT only and big 5).
#   sbatch cluster/eve_pixel_trend_test.sbatch        Output: outputs/<run>/pixel_trend_test_{brt,big5}/<Species>_pixel_trend_test.tif
#SBATCH --job-name=pixel-trend
#SBATCH --array=1-11
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=16G
#SBATCH --time=04:00:00
#SBATCH --output=logs/pixel-trend_%A_%a.out
#SBATCH --error=logs/pixel-trend_%A_%a.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
unc_run Rscript tools/pixelTrendTest.R --index "${SLURM_ARRAY_TASK_ID}" --run "${BIRDMONITOR_RUNNAME:-test4}"
