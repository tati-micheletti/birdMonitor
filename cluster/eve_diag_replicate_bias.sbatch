#!/bin/bash -l
# READ-ONLY: why do the bootstrap replicates show less decline than the baseline? (tools/diagnoseReplicateBias.R)   sbatch cluster/eve_diag_replicate_bias.sbatch -> logs/diag_replicate_bias_<jobid>.out
#SBATCH --job-name=diag-bias
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=8G
#SBATCH --time=00:20:00
#SBATCH --output=logs/diag_replicate_bias_%j.out
#SBATCH --error=logs/diag_replicate_bias_%j.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
Rscript tools/diagnoseReplicateBias.R "${BIRDMONITOR_RUNNAME:-test4}" honest2 reps_000-050 2025
