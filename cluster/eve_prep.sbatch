#!/bin/bash -l
# Stage 1 of the full EVE workflow: dataPrep_Monitor + inputs_Monitor.
#
# Builds covariates, occurrence tables, spatial blocks and the
# inputs/model_ready/ tables that the model-fitting arrays
# (modules/models_Monitor/cluster/eve_array_*.sbatch) read. One job, because
# these steps are inherently sequential and share one SpaDES session.
#
# Submit via cluster/submit_eve_pipeline.sh (which chains this -> model
# arrays -> index), not directly.
#
# EVE rejects --mem; it requires --mem-per-cpu (total = cpus x mem-per-cpu: here 8 x 8G = 64G).
# RESOURCES BELOW ARE UNMEASURED STARTING GUESSES -- nothing has been timed
# for this stage on EVE yet. After the first run, check
#   sacct -j <jobid> --format=JobID,Elapsed,MaxRSS,State
# and tighten --mem/--time to what it actually needed (the eve-cluster skill:
# right-size, don't pad -- over ~8GB/core routes to the smaller big-memory
# node pool and lengthens the queue wait).
#
# NO DOWNLOADS IN THIS JOB: compute nodes have throttled internet on EVE.
# Everything this stage needs (inputs/raw, inputs/predictors, cache/) must
# already be on EVE -- rsync'd up, or fetched beforehand on a login/transfer
# node. reproducible::Cache() resumes after an interruption, so a re-run
# picks up where a killed/timed-out run stopped.

#SBATCH --job-name=birdmon-prep
#SBATCH --cpus-per-task=8
#SBATCH --mem-per-cpu=8G
#SBATCH --time=72:00:00
#SBATCH --output=logs/prep_%j.out
#SBATCH --error=logs/prep_%j.err

set -euo pipefail
mkdir -p logs

# EVE_R_MODULE is set at submit time (see cluster/submit_eve_pipeline.sh).
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

export BIRDMONITOR_STAGE=prep
export BIRDMONITOR_SKIP_INSTALL=1
# No Python/CLMS token/internet on compute nodes: use what is already in inputs/.
export BIRDMONITOR_SKIP_DOWNLOAD=1
export BIRDMONITOR_RUNNAME="${BIRDMONITOR_RUNNAME:-test4}"

cd "${SLURM_SUBMIT_DIR}"
Rscript runMe.R
