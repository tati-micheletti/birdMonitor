#!/bin/bash
# The big 5 UNCERTAINTY chain only (the baseline is finished): the ensemble (brt, glm, gam, rf, nn) inside every bootstrap replicate, first BIG5_REPS
# (default 0:25), then its regional index / Germany-only intervals / Germany-only maps. Same steps as parts C and C2 of cluster/submit_eve_tonight.sh.
#
#     cd ~/projects/birdMonitor && bash --login cluster/submit_eve_big5_uncertainty.sh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs
if [ "${FORCE:-0}" != "1" ] && squeue -u "${USER}" -h -o "%j" | grep -qE "^(unc-covcache|unc-prepare|unc-band|unc-summarize|unc-assemble|unc-community|unc-regionband|unc-maskmaps)"; then
  echo "STOP: uncertainty jobs are already in the queue (see: squeue -u ${USER}). Submitting again would make two runs write the same files. FORCE=1 overrides." >&2; exit 1
fi
if ! type module >/dev/null 2>&1; then echo "Run this script as:  bash --login cluster/submit_eve_big5_uncertainty.sh" >&2; exit 1; fi
module load ${EVE_R_MODULE:-GCC/13.3.0 OpenMPI/5.0.5 R/4.5.1 GDAL/3.10.3 CMake ImageMagick/7.1.1-38 UDUNITS/2.2.28}
export BIRDMONITOR_RUNNAME="${BIRDMONITOR_RUNNAME:-test4}"
TAG=ens_brt-glm-gam-rf-nn; MEM=brt,glm,gam,rf,nn; REPS="${BIG5_REPS:-0:25}"
echo "=== C. big 5 uncertainty: the ensemble inside the replicates (${REPS})"
uout=$(ENS_MEMBERS="${MEM}" BIRDMONITOR_UNC_REPS="${REPS}" UNC_PREP_TIME="${BIG5_PREP_TIME:-24:00:00}" bash cluster/submit_eve_ensemble_uncertainty.sh | tee /dev/stderr)
band=$(echo "${uout}" | awk '/^band:/{print $2}'); fin=$(echo "${uout}" | awk '/^assembleall:/{print $2}')
[ -n "${band}" ] && [ -n "${fin}" ] || { echo "ERROR: could not read the band / assembleall job ids of the big 5 uncertainty chain" >&2; exit 1; }
echo; echo "=== C2. regional index, Germany-only intervals, Germany-only maps"
FORCE=1 BIRDMONITOR_UNC_MEMBERS="${MEM}" BIRDMONITOR_UNC_TAG="${TAG}" BIRDMONITOR_UNC_BANDS=48 BIRDMONITOR_UNC_REPS="${REPS}" UNC_AFTER="${band}" UNC_FINAL="${fin}" UNC_THROTTLE=100 bash cluster/submit_eve_regional.sh
echo; echo "SUBMITTED. Monitor (read-only): cd ~/projects/birdMonitor && bash cluster/monitor_tonight.sh"
