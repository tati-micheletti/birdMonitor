#!/bin/bash -l
# DIAGNOSTIC (2026-11-22): time every GAM fold refit of the slow landscape out-of-fold replicates (tools/diagGamFolds.R). Writes only to outputs/s2v2/_diag_gam_folds_<date>/.
#   cd ~/projects/birdMonitor && sbatch cluster/eve_diag_gam_folds.sbatch
#SBATCH --job-name=diag-gam
#SBATCH --cpus-per-task=8
#SBATCH --mem-per-cpu=8G
#SBATCH --time=04:00:00
#SBATCH --output=logs/diag-gam_%j.out
#SBATCH --error=logs/diag-gam_%j.err
set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
while IFS= read -r line; do case "${line}" in UNC_DONE_MARKER=*|BIRDMONITOR_UNC_CORES=*|pid=*|"") continue ;; esac; export "${line?}"; done < "${SLURM_SUBMIT_DIR}/logs/env_s2v2.raw"
export BIRDMONITOR_UNC_CORES="${SLURM_CPUS_PER_TASK:-1}"
Rscript tools/diagGamFolds.R --step diag --index 1 --diagreps 4,5,1 --diagspecies "Vanellus vanellus" --diagscale landscape
