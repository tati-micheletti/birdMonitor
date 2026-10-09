#!/bin/bash
# ONE-OFF (2026-10-09): give the big 5 uncertainty chain a 24 h limit for the band tasks. The BRT-only band tasks took up to 11 h (limit 12 h); the big 5 tasks are
# one third of the area each but 4-5 times slower, so the heaviest would need about 16 h and would be killed at 12 h (which would stop the whole chain).
#
# The running prepare job (63200690) is NOT touched. This cancels the waiting stages behind it (band, summarize, assemble, community, assembleall, the regional
# steps and the map masking: jobs 63200691-63200701) and submits them again with UNC_BAND_TIME = 24:00:00, depending on the same prepare job.
#
#     cd ~/projects/birdMonitor && bash --login cluster/resubmit_big5_downstream.sh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs
if ! type module >/dev/null 2>&1; then echo "Run this script as:  bash --login cluster/resubmit_big5_downstream.sh" >&2; exit 1; fi
module load ${EVE_R_MODULE:-GCC/13.3.0 OpenMPI/5.0.5 R/4.5.1 GDAL/3.10.3 CMake ImageMagick/7.1.1-38 UDUNITS/2.2.28}
export BIRDMONITOR_RUNNAME="${BIRDMONITOR_RUNNAME:-test4}"
PREP="${PREP_JOB:-63200690}"; TAG=ens_brt-glm-gam-rf-nn; MEM=brt,glm,gam,rf,nn; REPS="${BIG5_REPS:-0:25}"
OLD=$(seq 63200691 63200701 | tr '\n' ' ')

# the prepare job must still be alive (queued or running), otherwise this script would depend on a job the scheduler has forgotten
if [ -z "$(squeue -h -j "${PREP}" 2>/dev/null)" ]; then echo "STOP: prepare job ${PREP} is not in the queue any more. Do not continue: check it with  sacct -j ${PREP} -X" >&2; exit 1; fi
echo "=== 1. cancel the waiting stages behind prepare (${OLD% })"
scancel ${OLD} 2>/dev/null || true
sleep 8
left=$(squeue -u "${USER}" -h -o "%A %j %T" | awk '$1 >= 63200691 && $1 <= 63200701' | wc -l)
echo "still listed: ${left} (they disappear within a minute)"

echo; echo "=== 2. band ... assembleall again, band limit 24 h, behind the same prepare job ${PREP}"
uout=$(UNC_PREPARE_JOB="${PREP}" UNC_BAND_TIME="${BIG5_BAND_TIME:-24:00:00}" ENS_MEMBERS="${MEM}" BIRDMONITOR_UNC_REPS="${REPS}" bash cluster/submit_eve_ensemble_uncertainty.sh | tee /dev/stderr)
band=$(echo "${uout}" | awk '/^band:/{print $2}'); fin=$(echo "${uout}" | awk '/^assembleall:/{print $2}')
[ -n "${band}" ] && [ -n "${fin}" ] || { echo "ERROR: could not read the band / assembleall job ids" >&2; exit 1; }

echo; echo "=== 3. regional index, Germany-only intervals, Germany-only maps"
FORCE=1 BIRDMONITOR_UNC_MEMBERS="${MEM}" BIRDMONITOR_UNC_TAG="${TAG}" BIRDMONITOR_UNC_BANDS=48 BIRDMONITOR_UNC_REPS="${REPS}" UNC_AFTER="${band}" UNC_FINAL="${fin}" UNC_THROTTLE=100 bash cluster/submit_eve_regional.sh
echo; echo "RESUBMITTED. Monitor (read-only): cd ~/projects/birdMonitor && bash cluster/monitor_chains.sh | sed -n '/=== 4/,\$p'"
