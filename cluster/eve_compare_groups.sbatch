#!/bin/bash -l
# ONE-OFF (2026-11-14), delete when done: the species groups side by side (tools/compareGroupsOnce.R). READ-ONLY; writes outputs/<run>/figures_groups_compare/.
#   BIRDMONITOR_RUNNAME=v3 sbatch --export=ALL cluster/eve_compare_groups.sbatch
#SBATCH --job-name=compare-groups
#SBATCH --cpus-per-task=2
#SBATCH --mem-per-cpu=12G
#SBATCH --time=01:00:00
#SBATCH --output=logs/compare-groups_%j.out
#SBATCH --error=logs/compare-groups_%j.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
unc_run Rscript tools/compareGroupsOnce.R --run "${BIRDMONITOR_RUNNAME:-v3}"
