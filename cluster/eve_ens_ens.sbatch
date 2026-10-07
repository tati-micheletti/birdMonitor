#!/bin/bash -l
# Ensemble workflow, step "ens": average the BRT and the algorithms of ONE scale for ONE species (see tools/runEnsembleTask.R).
#SBATCH --job-name=ens-mean
#SBATCH --array=1-11
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=12G
#SBATCH --time=04:00:00
#SBATCH --output=logs/ens-mean_%A_%a.out
#SBATCH --error=logs/ens-mean_%A_%a.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
: "${ENS_SCALE:?ENS_SCALE (climate|landscape|habitat) must be set}"
: "${ENS_MEMBERS:?ENS_MEMBERS (e.g. brt,glm,gam,rf) must be set}"
unc_run Rscript tools/runEnsembleTask.R --step ens --scale "${ENS_SCALE}" --members "${ENS_MEMBERS}" --index "${SLURM_ARRAY_TASK_ID}"
