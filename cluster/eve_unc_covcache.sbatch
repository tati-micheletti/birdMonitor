#!/bin/bash -l
# Uncertainty workflow (option B), step "covcache". Once: writes the habitat covariate stacks (about 1-2 min per year).
# Submitted by cluster/submit_eve_uncertainty.sh -- do not submit by hand unless you know the dependencies.
#SBATCH --job-name=unc-covcache
#SBATCH --cpus-per-task=1
# 16G keeps it on the 'compute' partition (a request above ~16G is routed to the small 'highmem' partition). When the cache
# files already exist (the usual case: the baseline covcache job wrote them) this job only checks inputs and skips them.
#SBATCH --mem-per-cpu=16G
#SBATCH --time=08:00:00
#SBATCH --output=logs/unc-covcache_%A_%a.out
#SBATCH --error=logs/unc-covcache_%A_%a.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
export BIRDMONITOR_UNC_CORES="${SLURM_CPUS_PER_TASK:-1}"
# Pre-flight first: when the chain is queued behind the baseline (UNC_AFTER) the inputs do not exist yet at submit time,
# so the check runs here, once they do. A failed check stops the job and, through the dependencies, the whole chain.
Rscript tools/runUncertaintyTask.R --step preflight
Rscript tools/runUncertaintyTask.R --step covcache
