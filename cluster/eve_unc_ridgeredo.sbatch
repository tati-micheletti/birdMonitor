#!/bin/bash -l
# Recompute the replicate ridge meta-models of one species with the CURRENT penalty rule (tools/runUncertaintyTask.R --step ridgeredo). The old file is moved aside.
# Submitted by cluster/ridge_rule_big5_2026-10-10.sh -- do not submit by hand unless you know the dependencies.
#SBATCH --job-name=unc-ridgeredo
#SBATCH --array=1-11
#SBATCH --cpus-per-task=2
#SBATCH --mem-per-cpu=16G
#SBATCH --time=02:00:00
#SBATCH --output=logs/unc-ridgeredo_%A_%a.out
#SBATCH --error=logs/unc-ridgeredo_%A_%a.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
export BIRDMONITOR_UNC_CORES="${SLURM_CPUS_PER_TASK:-1}"
unc_run Rscript tools/runUncertaintyTask.R --step ridgeredo --index "${SLURM_ARRAY_TASK_ID}"
