#!/bin/bash -l
# Final stage of the full EVE workflow: runIndex_Monitor.
#
# Builds the per-species/combined trend index from the finished metaModel()
# outputs of every model-array task. Submitted by cluster/submit_eve_pipeline.sh
# with --dependency=afterok:<prep>,afterany:<the three scale arrays>: it starts
# once prep succeeded AND every model task has ended (meta runs inside
# whichever scale task finishes last for a species -- see
# checkAllScalesReady() in models_Monitor.R). afterany (not afterok) for the
# arrays: if one species' task failed, you still get an index for the rest,
# plus a warning naming the missing species, instead of the job waiting forever.
#
# NOTE: runIndex_Monitor's own checkAllInputs event polls for missing species
# before proceeding (pollIntervalSeconds/pollTimeoutHours, default 5 min / 6 h).
# If a species' meta output genuinely never appears, this job will sit in that
# poll for up to pollTimeoutHours before warning and continuing without it.
#
# RESOURCES ARE UNMEASURED STARTING GUESSES -- see the note in eve_prep.sbatch
# and tighten after the first run.

#SBATCH --job-name=birdmon-index
#SBATCH --cpus-per-task=2
#SBATCH --mem=64G
#SBATCH --time=12:00:00
#SBATCH --output=logs/index_%j.out
#SBATCH --error=logs/index_%j.err

set -euo pipefail
mkdir -p logs

if [ -n "${EVE_R_MODULE:-}" ]; then module load "${EVE_R_MODULE}"; fi

export BIRDMONITOR_STAGE=index
export BIRDMONITOR_SKIP_INSTALL=1
export BIRDMONITOR_RUNNAME="${BIRDMONITOR_RUNNAME:-test4}"

cd "${SLURM_SUBMIT_DIR}"
Rscript runMe.R
