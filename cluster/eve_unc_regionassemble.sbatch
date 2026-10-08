#!/bin/bash -l
# Regional index uncertainty, step "regionassemble". Per species: add the band pieces up -> regional_means_<km>km.rds.
# Submitted by cluster/submit_eve_regional.sh -- do not submit by hand unless you know the dependencies.
#SBATCH --job-name=unc-regionassemble
#SBATCH --array=1-11
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=16G
#SBATCH --time=01:00:00
#SBATCH --output=logs/unc-regionassemble_%A_%a.out
#SBATCH --error=logs/unc-regionassemble_%A_%a.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
unc_run Rscript tools/runUncertaintyTask.R --step regionassemble --index "${SLURM_ARRAY_TASK_ID}"
