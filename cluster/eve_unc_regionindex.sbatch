#!/bin/bash -l
# Regional index uncertainty, step "regionindex". Once: regional index per replicate, intervals, change, trend, coverage, parity with the baseline.
# Submitted by cluster/submit_eve_regional.sh -- do not submit by hand unless you know the dependencies.
#SBATCH --job-name=unc-regionindex
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=24G
#SBATCH --time=01:00:00
#SBATCH --output=logs/unc-regionindex_%j.out
#SBATCH --error=logs/unc-regionindex_%j.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
unc_run Rscript tools/runUncertaintyTask.R --step regionindex
