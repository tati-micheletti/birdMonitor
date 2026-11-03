#!/bin/bash -l
# The ensemble maps read at the survey routes (DDA territory-mapping plots), every year (tools/modelAtRoutes.R). READ-ONLY: writes one CSV.
#   cd ~/projects/birdMonitor && BIRDMONITOR_RUNNAME=v2 sbatch --export=ALL cluster/eve_model_at_routes.sbatch
#   DIAG_ENS=<ensemble name> (default ens_brt-glm-gam-rf-nn)
# Output: outputs/<run>/diagnostics/model_at_routes.csv (download it, then the comparison with the observed series is made on the PC).
#SBATCH --job-name=model-at-routes
#SBATCH --cpus-per-task=2
#SBATCH --mem-per-cpu=12G
#SBATCH --time=06:00:00
#SBATCH --output=logs/model-at-routes_%j.out
#SBATCH --error=logs/model-at-routes_%j.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
RUN="${BIRDMONITOR_RUNNAME}"
unc_run Rscript tools/modelAtRoutes.R --ens "${DIAG_ENS:-ens_brt-glm-gam-rf-nn}"
