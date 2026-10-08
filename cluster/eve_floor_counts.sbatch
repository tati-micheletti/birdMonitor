#!/bin/bash -l
# READ-ONLY: counts of regional cells affected by the baseline floor, and what candidate floors would change (tools/floorCounts.R), on the Germany-only maps.
#   sbatch cluster/eve_floor_counts.sbatch     -> logs/floor_counts_<jobid>.out
#SBATCH --job-name=floor-counts
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=16G
#SBATCH --time=01:00:00
#SBATCH --output=logs/floor_counts_%j.out
#SBATCH --error=logs/floor_counts_%j.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
Rscript tools/floorCounts.R "${BIRDMONITOR_RUNNAME:-test4}" 2005 2025
