#!/bin/bash -l
# Honest accuracy of the combined map (meta-model refit on OUT-OF-FOLD inputs), one task per species.
# See modules/models_Monitor/R/metaOutOfFoldCheck.R and improvements.md item 16.
#
#   sbatch cluster/eve_meta_check.sbatch                      (from the repo root; needs the fold models of the model arrays)
#   Rscript tools/runMetaCheck.R --collect                    (afterwards, one table of all species)
#
# Predicts only around the habitat records, so it is light (minutes per species).

#SBATCH --job-name=birdmon-metacheck
#SBATCH --array=1-11
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=12G
#SBATCH --time=03:00:00
#SBATCH --output=logs/metacheck_%A_%a.out
#SBATCH --error=logs/metacheck_%A_%a.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
Rscript tools/runMetaCheck.R --index "${SLURM_ARRAY_TASK_ID}"
