#!/bin/bash -l
# Ensemble workflow, step "algo": fit + block-CV + predict ONE algorithm at ONE scale for ONE species (see tools/runEnsembleTask.R).
# Submitted by cluster/submit_eve_ensemble.sh, which sets the scale/algorithm of each array and the resources (random forest uses all cores,
# GLM/GAM one). Finished years are kept, so a task that hits the time limit simply resumes when submitted again.
#SBATCH --job-name=ens-algo
#SBATCH --array=1-11
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=8G
#SBATCH --time=12:00:00
#SBATCH --output=logs/ens-algo_%A_%a.out
#SBATCH --error=logs/ens-algo_%A_%a.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
: "${ENS_SCALE:?ENS_SCALE (climate|landscape|habitat) must be set}"
: "${ENS_ALGO:?ENS_ALGO (glm|gam|rf) must be set}"
# array task i (1..11) = species i
unc_run Rscript tools/runEnsembleTask.R --step algo --scale "${ENS_SCALE}" --algo "${ENS_ALGO}" --index "${SLURM_ARRAY_TASK_ID}" --threads "${SLURM_CPUS_PER_TASK:-1}"
