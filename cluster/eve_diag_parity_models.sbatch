#!/bin/bash -l
# READ-ONLY, step 3 of the parity diagnostic: is replicate 0's model the baseline's current model? (tools/diagnoseParityModels.R)
#   sbatch cluster/eve_diag_parity_models.sbatch -> logs/diag_parity_models_<jobid>.out
#SBATCH --job-name=diag-parity-models
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=16G
#SBATCH --time=00:40:00
#SBATCH --output=logs/diag_parity_models_%j.out
#SBATCH --error=logs/diag_parity_models_%j.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
Rscript tools/diagnoseParityModels.R "${BIRDMONITOR_RUNNAME:-test4}" honest2 reps_000-050
