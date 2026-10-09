#!/bin/bash -l
# READ-ONLY, step 2 of the parity diagnostic: compare the three scale prediction maps of replicate 0 and the baseline at random German pixels (tools/diagnoseParityMaps.R)
#   sbatch cluster/eve_diag_parity_maps.sbatch -> logs/diag_parity_maps_<jobid>.out
#SBATCH --job-name=diag-parity-maps
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=24G
#SBATCH --time=01:30:00
#SBATCH --output=logs/diag_parity_maps_%j.out
#SBATCH --error=logs/diag_parity_maps_%j.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
Rscript tools/diagnoseParityMaps.R "${BIRDMONITOR_RUNNAME:-test4}" honest2 reps_000-050 "2025,2015" "Alauda arvensis;Anthus pratensis;Sturnus vulgaris" 3000
