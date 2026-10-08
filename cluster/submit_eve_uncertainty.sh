#!/bin/bash
# Submit the uncertainty workflow (option B: spatial-block bootstrap of the BRTs) to EVE as one dependency chain.
#
#   preflight (login node, here)
#     -> covcache                    habitat covariate stacks, once
#       -> prepare   [species]       replicate BRTs, coarse predictions, replicate ridge models
#         -> band    [species x band]  predict all years for all replicates (the expensive part)
#           -> summarize [species x band]  percentile maps, change maps, per-pixel trend
#             -> assemble [species] + community [band]
#               -> assembleall       combined multi-species indices per replicate
#
# Run from the repo ROOT on an EVE login node, AFTER the baseline (prep -> model arrays) has finished.
#
#   [BIRDMONITOR_RUNNAME=test4]          baseline run folder (default test4)
#   [BIRDMONITOR_UNC_REPS=0:50]          replicate ids of this run (0 = the main models, a built-in check); to ADD replicates later use e.g. 51:100
#   [BIRDMONITOR_UNC_YEARS=2005,2025]    restrict the mapped years (default: all prediction years)
#   [BIRDMONITOR_UNC_BANDS=16]           number of bands (default 16)
#   [BIRDMONITOR_UNC_BLOCKMULT=1]        multiplier on the resampling block size (sensitivity test)
#   [BIRDMONITOR_UNC_TAG=timing]         write to outputs/<run>/uncertainty_timing/ instead (timing/test run; never mixes with real replicates)
#   [UNC_THROTTLE=60]                    max band tasks running at once (default: no limit)
#   [UNC_AFTER=62887498]                 job id(s) to wait for first (e.g. the baseline habitat array), colon-separated.
#                                        The whole chain then queues unattended (e.g. overnight).
#   [UNC_BAND_TIME=12:00:00]             wall-time limit of one band task
#     bash --login cluster/submit_eve_uncertainty.sh
#
# If a step fails, jobs waiting on it are cancelled automatically (--kill-on-invalid-dep). Fix the cause and run this
# script again with the SAME settings: finished work is detected and skipped.

set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs

EVE_R_MODULE="${EVE_R_MODULE:-GCC/13.3.0 OpenMPI/5.0.5 R/4.5.1 GDAL/3.10.3 CMake ImageMagick/7.1.1-38 UDUNITS/2.2.28}"
if ! type module >/dev/null 2>&1; then
  echo "The 'module' command is missing. Run this script as:  bash --login cluster/submit_eve_uncertainty.sh" >&2
  exit 1
fi
module load ${EVE_R_MODULE}
export BIRDMONITOR_RUNNAME="${BIRDMONITOR_RUNNAME:-test4}"
export BIRDMONITOR_UNC_REPS="${BIRDMONITOR_UNC_REPS:-0:50}"
export BIRDMONITOR_UNC_BANDS="${BIRDMONITOR_UNC_BANDS:-16}"
EXPORTS="ALL"

echo "Run: ${BIRDMONITOR_RUNNAME} | replicates ${BIRDMONITOR_UNC_REPS} | bands ${BIRDMONITOR_UNC_BANDS} | years ${BIRDMONITOR_UNC_YEARS:-<all>}"

# 1. pre-flight: every input must exist. When queued behind the baseline (UNC_AFTER) the inputs do not exist yet, so the
#    check is skipped here and runs as the first thing inside the covcache job instead.
if [ -z "${UNC_AFTER:-}" ]; then
  Rscript tools/runUncertaintyTask.R --step preflight
else
  echo "UNC_AFTER is set: the input check runs inside the first job, after ${UNC_AFTER} has finished."
fi
NSP=$(Rscript -e 'source("tools/sharedConfig.R"); cat(length(sharedSpecies))' 2>/dev/null | tail -1)
NB="${BIRDMONITOR_UNC_BANDS}"
NSB=$((NSP * NB))
echo "species: ${NSP} | band tasks: ${NSB}"

AFTER=()
if [ -n "${UNC_AFTER:-}" ]; then AFTER=(--dependency=afterok:"${UNC_AFTER}"); fi
THR=""; if [ -n "${UNC_THROTTLE:-}" ]; then THR="%${UNC_THROTTLE}"; fi

cov=$(sbatch --parsable --export=${EXPORTS} "${AFTER[@]+"${AFTER[@]}"}" --kill-on-invalid-dep=yes cluster/eve_unc_covcache.sbatch)
echo "covcache:   ${cov}"
prep=$(sbatch --parsable --export=${EXPORTS} --array=1-${NSP} --dependency=afterok:${cov} --kill-on-invalid-dep=yes cluster/eve_unc_prepare.sbatch)
echo "prepare:    ${prep}"
band=$(sbatch --parsable --export=${EXPORTS} --array=1-${NSB}${THR} --time="${UNC_BAND_TIME:-12:00:00}" --dependency=afterok:${prep} --kill-on-invalid-dep=yes cluster/eve_unc_band.sbatch)
echo "band:       ${band}"
summ=$(sbatch --parsable --export=${EXPORTS} --array=1-${NSB} --dependency=afterok:${band} --kill-on-invalid-dep=yes cluster/eve_unc_summarize.sbatch)
echo "summarize:  ${summ}"
asm=$(sbatch --parsable --export=${EXPORTS} --array=1-${NSP} --dependency=afterok:${summ} --kill-on-invalid-dep=yes cluster/eve_unc_assemble.sbatch)
echo "assemble:   ${asm}"
com=$(sbatch --parsable --export=${EXPORTS} --array=1-${NB} --dependency=afterok:${summ} --kill-on-invalid-dep=yes cluster/eve_unc_community.sbatch)
echo "community:  ${com}"
fin=$(sbatch --parsable --export=${EXPORTS} --dependency=afterok:${asm}:${com} --kill-on-invalid-dep=yes cluster/eve_unc_assembleall.sbatch)
echo "assembleall: ${fin}"
echo
echo "Submitted. Logs in ./logs/unc-*"
echo "CHECK AT ANY TIME (read-only):  cd ~/projects/birdMonitor && bash cluster/status.sh ${cov} ${prep} ${band} ${summ} ${asm} ${com} ${fin}"
echo "CHECK THE PARITY when everything is COMPLETED (every species: RESULT: OK):  grep -H RESULT outputs/${BIRDMONITOR_RUNNAME}/uncertainty*/*/parity_check.txt"
