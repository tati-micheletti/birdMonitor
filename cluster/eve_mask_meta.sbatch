#!/bin/bash -l
# Germany-only copies of the meta-model maps (tools/maskMetaModels.R). One task per species.
#   Submitted by cluster/submit_eve_germany_baseline.sh. Output: outputs/<run>/metamodel_<resolutions>_germany/
#SBATCH --job-name=mask-meta
#SBATCH --array=1-11
#SBATCH --cpus-per-task=2
#SBATCH --mem-per-cpu=8G
#SBATCH --time=02:00:00
#SBATCH --output=logs/mask-meta_%A_%a.out
#SBATCH --error=logs/mask-meta_%A_%a.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
unc_run Rscript tools/maskMetaModels.R --index "${SLURM_ARRAY_TASK_ID}"
