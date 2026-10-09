#!/bin/bash
# ONE-OFF (2026-10-09): resume the big 5 uncertainty chain after its prepare step failed for 8 of 11 species (job 63200690).
#   tasks 3, 7, 11 (species Lullula, E. citrinella, Anthus) COMPLETED and are kept;
#   tasks 1, 6, 8, 9, 10 FAILED after 8-22 min: "<scale> / gam: N replicate fit(s) failed" -- one GAM refit error on a bootstrap resample takes the whole batch of a core with it;
#   tasks 2, 4, 5 ran out of memory (peak above the 64 GB requested; the completed tasks peaked at 51 GB).
# Fixes (models_Monitor): the GAM refit now uses the robust settings ladder of the main GAM fit; any refit error is caught per replicate (the main fit then stands in and the
# case is logged in <species>/models/refit_fallbacks.csv); and the failed tasks are rerun with 128 GB (16 GB per core). Work already saved (BRT replicates, finished member
# fits) is skipped by the code.
#
#     cd ~/projects/birdMonitor && bash --login cluster/resume_big5_prepare_2026-10-09.sh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs
if ! type module >/dev/null 2>&1; then echo "Run this script as:  bash --login cluster/resume_big5_prepare_2026-10-09.sh" >&2; exit 1; fi
if [ "${FORCE:-0}" != "1" ] && squeue -u "${USER}" -h -o "%j" | grep -qE "^unc-prepare"; then
  echo "STOP: an unc-prepare job is still queued or running (see: squeue -u ${USER}). Submitting again would make two runs write the same files. FORCE=1 overrides." >&2; exit 1
fi
module load ${EVE_R_MODULE:-GCC/13.3.0 OpenMPI/5.0.5 R/4.5.1 GDAL/3.10.3 CMake ImageMagick/7.1.1-38 UDUNITS/2.2.28}
export BIRDMONITOR_RUNNAME="${BIRDMONITOR_RUNNAME:-test4}"
TAG=ens_brt-glm-gam-rf-nn; MEM=brt,glm,gam,rf,nn; REPS="${BIG5_REPS:-0:25}"
TASKS="${BIG5_PREP_TASKS:-1,2,4,5,6,8,9,10}"

echo "=== 1. prepare again for species tasks ${TASKS} (128 GB, 24 h)"
export BIRDMONITOR_UNC_MEMBERS="${MEM}" BIRDMONITOR_UNC_REPS="${REPS}" BIRDMONITOR_UNC_BANDS=48
unset BIRDMONITOR_UNC_TAG || true      # the tag defaults to the ensemble's name
prep=$(sbatch --parsable --export=ALL --array="${TASKS}" --mem-per-cpu=16G --time=24:00:00 cluster/eve_unc_prepare.sbatch)
echo "prepare:    ${prep}"

echo; echo "=== 2. band ... assembleall behind it (band limit 24 h)"
uout=$(UNC_PREPARE_JOB="${prep}" UNC_BAND_TIME=24:00:00 ENS_MEMBERS="${MEM}" BIRDMONITOR_UNC_REPS="${REPS}" bash cluster/submit_eve_ensemble_uncertainty.sh | tee /dev/stderr)
band=$(echo "${uout}" | awk '/^band:/{print $2}'); fin=$(echo "${uout}" | awk '/^assembleall:/{print $2}')
[ -n "${band}" ] && [ -n "${fin}" ] || { echo "ERROR: could not read the band / assembleall job ids" >&2; exit 1; }

echo; echo "=== 3. regional index, Germany-only intervals, Germany-only maps"
FORCE=1 BIRDMONITOR_UNC_MEMBERS="${MEM}" BIRDMONITOR_UNC_TAG="${TAG}" BIRDMONITOR_UNC_BANDS=48 BIRDMONITOR_UNC_REPS="${REPS}" UNC_AFTER="${band}" UNC_FINAL="${fin}" UNC_THROTTLE=100 bash cluster/submit_eve_regional.sh
echo; echo "RESUMED. Monitor (read-only): cd ~/projects/birdMonitor && bash cluster/monitor_chains.sh | sed -n '/=== 4/,\$p'"
