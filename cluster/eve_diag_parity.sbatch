#!/bin/bash -l
# READ-ONLY: where do replicate 0 and the baseline meta-model diverge? (tools/diagnoseParity.R)    sbatch cluster/eve_diag_parity.sbatch -> logs/diag_parity_<jobid>.out
#SBATCH --job-name=diag-parity
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=16G
#SBATCH --time=00:30:00
#SBATCH --output=logs/diag_parity_%j.out
#SBATCH --error=logs/diag_parity_%j.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
Rscript tools/diagnoseParity.R "${BIRDMONITOR_RUNNAME:-test4}" honest2 reps_000-050
