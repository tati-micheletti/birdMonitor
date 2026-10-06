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
#SBATCH --cpus-per-task=4
# 10G per CPU (40G): the first run died at 32G (change maps were all kept in memory; fixed). A guess with head-room, because the
# regional index has never run on EVE -- read the real peak afterwards: sacct -j <jobid> --format=MaxRSS, and tighten this.
#SBATCH --mem-per-cpu=10G
#SBATCH --time=12:00:00
#SBATCH --output=logs/index_%j.out
#SBATCH --error=logs/index_%j.err

set -euo pipefail
mkdir -p logs

# Module list is set HERE (not only by the submit script) so the job never depends on
# EVE forwarding environment variables. Override at submit time with EVE_R_MODULE=... if needed.
EVE_R_MODULE="${EVE_R_MODULE:-GCC/13.3.0 OpenMPI/5.0.5 R/4.5.1 GDAL/3.10.3 CMake ImageMagick/7.1.1-38 UDUNITS/2.2.28}"
module load ${EVE_R_MODULE}
if ! command -v Rscript >/dev/null 2>&1; then
  echo "ERROR on $(hostname): Rscript not found after: module load ${EVE_R_MODULE}" >&2
  module list >&2
  exit 1
fi

# $TMPDIR on EVE is a RAM disk (half of the node's RAM, shared with the job itself),
# so terra's large temporary rasters would exhaust memory. Use /work instead and
# clean up when the job ends (EVE wiki, Storage page).
export TMPDIR="/work/${USER}/birdMonitor/tmp/${SLURM_JOB_ID}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT

export BIRDMONITOR_STAGE=index
export BIRDMONITOR_SKIP_INSTALL=1
export BIRDMONITOR_RUNNAME="${BIRDMONITOR_RUNNAME:-test4}"

cd "${SLURM_SUBMIT_DIR}"
Rscript runMe.R
