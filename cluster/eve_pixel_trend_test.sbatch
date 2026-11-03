#!/bin/bash -l
# Mann-Kendall test and Sen slope at every pixel, from the yearly main-model maps (tools/pixelTrendTest.R). One task per species, both runs (BRT only and big 5).
#   BIRDMONITOR_RUNNAME=<run> sbatch --export=ALL --array=1-<number of roster species> cluster/eve_pixel_trend_test.sbatch
#     Output: outputs/<run>/pixel_trend_test_{brt,big5}/<Species>_pixel_trend_test.tif  (the array line below is only the default of the 11-species roster: always pass --array)
#   Sent by cluster/submit_eve_clean_run.sh with --array=1-<roster size>.
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
