#!/bin/bash -l
# CASE STUDIES (not part of the workflow): regional index change to an end year the pipeline did not use (case_studies/regional_change_to_year.R). READ-ONLY; writes outputs/<run>/case_studies/change_<year>_<group>/.
#   BIRDMONITOR_RUNNAME=v3 sbatch --export=ALL case_studies/eve_regional_change_to_year.sbatch
#SBATCH --job-name=change-to-year
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=12G
#SBATCH --time=01:00:00
#SBATCH --output=logs/change-to-year_%j.out
#SBATCH --error=logs/change-to-year_%j.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
unc_run Rscript case_studies/regional_change_to_year.R --run "${BIRDMONITOR_RUNNAME:-v3}" --year "${CHANGE_YEAR:-2023}"
