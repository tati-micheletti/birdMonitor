#!/bin/bash -l
# READ-ONLY: why does the index of the open-farmland species rise in 2022 (and fall back by 2025)? (tools/diagnoseYearJump.R)
#   sbatch cluster/eve_diag_yearjump.sbatch      -> logs/diag_yearjump_<jobid>.out
# Prints, per species and year: A. the country mean of the climate, landscape, habitat and final map (which scale carries the jump?), B. the spread over the replicates
# (BRT-only run, tag honest2: do all replicates jump?), C. the yearly mean of the most influential predictors and the share of cells outside the training range.
#SBATCH --job-name=diag-yearjump
#SBATCH --cpus-per-task=2
#SBATCH --mem-per-cpu=32G
#SBATCH --time=04:00:00
#SBATCH --output=logs/diag_yearjump_%j.out
#SBATCH --error=logs/diag_yearjump_%j.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
Rscript tools/diagnoseYearJump.R "Vanellus vanellus,Perdix perdix,Alauda arvensis" --tag honest2 --top 6
