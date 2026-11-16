#!/bin/bash -l
# CASE STUDIES (not part of the workflow): numbers for the two case studies (case_studies/extract_case_study_numbers.R). READ-ONLY; writes outputs/<run>/case_studies/.
#   BIRDMONITOR_RUNNAME=v3 sbatch --export=ALL case_studies/eve_case_study.sbatch
#   Needs outputs/<run>/case_studies/areas_3035.gpkg (case_studies/build_areas.R, run locally, then copied to EVE).
#SBATCH --job-name=case-study
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=8G
#SBATCH --time=02:00:00
#SBATCH --output=logs/case-study_%j.out
#SBATCH --error=logs/case-study_%j.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
unc_run Rscript case_studies/extract_case_study_numbers.R --run "${BIRDMONITOR_RUNNAME:-v3}" ${CASE_ARGS:-}
