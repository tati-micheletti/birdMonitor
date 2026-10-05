#!/bin/bash -l
# Uncertainty workflow (option B), step "covcache". Once: writes the habitat covariate stacks (about 1-2 min per year).
# Submitted by cluster/submit_eve_uncertainty.sh -- do not submit by hand unless you know the dependencies.
#SBATCH --job-name=unc-covcache
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=24G
#SBATCH --time=08:00:00
#SBATCH --output=logs/unc-covcache_%A_%a.out
#SBATCH --error=logs/unc-covcache_%A_%a.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
export BIRDMONITOR_UNC_CORES="${SLURM_CPUS_PER_TASK:-1}"
Rscript tools/runUncertaintyTask.R --step covcache
