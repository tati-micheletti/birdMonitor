#!/bin/bash
# Submit the WHOLE birdMonitor workflow to EVE as one dependency chain:
#
#   prep (dataPrep_Monitor + inputs_Monitor)
#     -> model arrays: europe, habitat, landscape  (one task per species; the
#        meta-model runs inside whichever scale task finishes last for a species)
#       -> index (runIndex_Monitor)
#
# Run from anywhere inside the repo, ON an EVE login node, after:
#   - VPN + SSH to EVE, repo cloned, inputs/ and cache/ rsync'd up
#   - R packages installed (login node -- compute nodes have throttled internet)
#
# Usage:
#   [EVE_R_MODULE="GCC/13.3.0 OpenMPI/5.0.5 R/4.5.1 GDAL/3.10.3 CMake ImageMagick/7.1.1-38"] \
#   [EVE_PARTITION=<partition from `sinfo -s`>] \
#   [BIRDMONITOR_RUNNAME=test4] \
#     bash cluster/submit_eve_pipeline.sh
#
# BIRDMONITOR_RUNNAME is the run folder every stage writes to
# (outputs/<runName>/), so it MUST be the same across stages -- this script
# exports it once for all of them. Default test4.
#
# If the prep job fails, SLURM cancels every job waiting on it automatically
# (--kill-on-invalid-dep=yes below), so nothing is left stuck in the queue.
# Read the prep log (logs/prep_<jobid>.err), fix the cause, and run this
# script again -- Cache() resumes, so nothing already computed is redone.

set -euo pipefail
cd "$(dirname "$0")/.."

# Modules to load, in order. R 4.5.1 (not 4.6.1) on purpose: EVE's GDAL 3.10.3 (needed
# by terra) was built with GCC/13.3.0 + OpenMPI/5.0.5, which matches R 4.5.1 but not 4.6.1.
# Found with `module spider R/4.5.1` and `module spider GDAL/3.10.3`. Override at submit time if EVE's modules change.
EVE_R_MODULE="${EVE_R_MODULE:-GCC/13.3.0 OpenMPI/5.0.5 R/4.5.1 GDAL/3.10.3 CMake ImageMagick/7.1.1-38}"

export EVE_R_MODULE
export BIRDMONITOR_RUNNAME="${BIRDMONITOR_RUNNAME:-test4}"

# SLURM does not create the directory for --output/--error files, so it has
# to exist before submission, not just inside the job script.
mkdir -p logs

PART=()
if [ -n "${EVE_PARTITION:-}" ]; then PART=(--partition="${EVE_PARTITION}"); fi

echo "Run name: ${BIRDMONITOR_RUNNAME} | R module: ${EVE_R_MODULE} | partition: ${EVE_PARTITION:-<EVE default>}"

prep=$(sbatch --parsable "${PART[@]+"${PART[@]}"}" cluster/eve_prep.sbatch)
echo "prep:      ${prep}"

arrayIds=()
for scale in europe habitat landscape; do
  id=$(sbatch --parsable "${PART[@]+"${PART[@]}"}" --dependency=afterok:"${prep}" \
         --kill-on-invalid-dep=yes \
         modules/models_Monitor/cluster/eve_array_${scale}.sbatch)
  echo "${scale}: ${id}"
  arrayIds+=("${id}")
done

dep=$(IFS=:; echo "${arrayIds[*]}")
# The index needs BOTH: prep succeeded (afterok -- otherwise it would start after
# the arrays were auto-cancelled and have nothing to index) AND every array task
# has ended (afterany -- so one failed species doesn't block the rest).
idx=$(sbatch --parsable "${PART[@]+"${PART[@]}"}" \
        --dependency=afterok:"${prep}",afterany:"${dep}" --kill-on-invalid-dep=yes \
        cluster/eve_index.sbatch)
echo "index:     ${idx}"

echo
echo "Submitted. Monitor with: squeue -u \$USER   |   logs in ./logs/"
