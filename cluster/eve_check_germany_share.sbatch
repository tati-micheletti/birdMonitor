#!/bin/bash -l
# READ-ONLY check: share of the prediction window that lies outside Germany, and the area mean with and without it (tools/checkGermanyShare.R).
#   sbatch cluster/eve_check_germany_share.sbatch     -> logs/germany_share_<jobid>.out
#SBATCH --job-name=germany-share
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=16G
#SBATCH --time=00:30:00
#SBATCH --output=logs/germany_share_%j.out
#SBATCH --error=logs/germany_share_%j.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
Rscript tools/checkGermanyShare.R "${BIRDMONITOR_RUNNAME:-test4}" 2025
