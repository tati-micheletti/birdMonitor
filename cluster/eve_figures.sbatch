#!/bin/bash -l
# READ-ONLY: all figures for the Steering Consortium meeting (tools/makeResultFigures.R). Reads existing outputs, writes only to outputs/<run>/figures_fullreport/.
#   sbatch cluster/eve_figures.sbatch                                   -> everything (both runs, all sections)
#   FIG_ARGS="--sections S6 --variants big5" sbatch --export=ALL cluster/eve_figures.sbatch     -> only part of it (same options as the R script)
#SBATCH --job-name=result-figures
#SBATCH --cpus-per-task=2
#SBATCH --mem-per-cpu=12G
#SBATCH --time=06:00:00
#SBATCH --output=logs/result-figures_%j.out
#SBATCH --error=logs/result-figures_%j.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
# shellcheck disable=SC2086
unc_run Rscript tools/makeResultFigures.R --run "${BIRDMONITOR_RUNNAME:-test4}" ${FIG_ARGS:-}
