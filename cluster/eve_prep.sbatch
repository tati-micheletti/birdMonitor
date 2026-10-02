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
#SBATCH --cpus-per-task=4
#SBATCH --mem=64G
#SBATCH --time=24:00:00
#SBATCH --output=logs/prep_%j.out
#SBATCH --error=logs/prep_%j.err

set -euo pipefail
mkdir -p logs

# EVE_R_MODULE is set at submit time (see cluster/submit_eve_pipeline.sh).
if [ -n "${EVE_R_MODULE:-}" ]; then module load ${EVE_R_MODULE}; fi   # may hold several names: "GCC/15.3.0 R/4.6.1" (unquoted on purpose)

export BIRDMONITOR_STAGE=prep
export BIRDMONITOR_SKIP_INSTALL=1
# No Python/CLMS token/internet on compute nodes: use what is already in inputs/.
export BIRDMONITOR_SKIP_DOWNLOAD=1
export BIRDMONITOR_RUNNAME="${BIRDMONITOR_RUNNAME:-test4}"

cd "${SLURM_SUBMIT_DIR}"
Rscript runMe.R
