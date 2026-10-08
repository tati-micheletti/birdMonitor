#!/bin/bash
# EVERYTHING that can run unattended, queued in one go (2026-10-08, deadline for all results: Tuesday 13 Oct, midday). Dependencies are by job id, so nothing
# starts before its inputs exist; a failed step cancels what depends on it (--kill-on-invalid-dep) and is fixed the next morning.
#
#   A. BRT-only: the regional index with uncertainty, the Germany-only national intervals and the Germany-only maps, behind the running band stage
#      (BRT_BAND_JOB = 63119392, BRT_FINAL_JOB = 63119396; override with the environment if the ids differ)
#   B. THE BIG 5 (brt, glm, gam, rf, nn), baseline: fit GLM/GAM/RF/NN at the three scales -> ensemble means -> honest meta-model -> index (rectangle)
#      -> Germany-only copies of the maps -> index on them (annual_report_ens_brt-glm-gam-rf-nn_germany/)
#   C. THE BIG 5, uncertainty: the ensemble inside every replicate (spatial-block bootstrap), first BIG5_REPS (default 0:25, i.e. replicate 0 = the
#      main models + 25), then the same regional / Germany-only / map-masking steps for it. Replicates 26-50 can be added later (BIRDMONITOR_UNC_REPS=26:50).
#
#     cd ~/projects/birdMonitor && bash --login cluster/submit_eve_tonight.sh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs
if [ "${FORCE:-0}" != "1" ] && squeue -u "${USER}" -h -o "%j" | grep -qE "^(ens-|unc-region|unc-maskmaps)"; then
  echo "STOP: jobs of this workflow are already in the queue (see: squeue -u ${USER}). Submitting again would make two runs write the same files." >&2
  echo "      If you are sure, run it again with FORCE=1 in front of the command." >&2
  exit 1
fi
if ! type module >/dev/null 2>&1; then echo "Run this script as:  bash --login cluster/submit_eve_tonight.sh" >&2; exit 1; fi
module load ${EVE_R_MODULE:-GCC/13.3.0 OpenMPI/5.0.5 R/4.5.1 GDAL/3.10.3 CMake ImageMagick/7.1.1-38 UDUNITS/2.2.28}
export BIRDMONITOR_RUNNAME="${BIRDMONITOR_RUNNAME:-test4}"

echo "=== 0. packages the ensemble needs"
Rscript -e 'libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*")); if (length(libs)) .libPaths(c(libs, .libPaths())); need <- c("ranger", "mgcv", "nnet", "matrixStats", "geodata", "terra"); miss <- need[!vapply(need, requireNamespace, logical(1), quietly = TRUE)]; if (length(miss)) { cat("MISSING PACKAGES:", miss, "\n"); quit(status = 1) } else cat("all present:", need, "\n")' 2>&1 | tail -2

echo; echo "=== A. BRT-only: regional index, Germany-only intervals and maps (behind the running band stage)"
BIRDMONITOR_UNC_TAG="${BRT_TAG:-honest2}" UNC_AFTER="${BRT_BAND_JOB:-63119392}" UNC_FINAL="${BRT_FINAL_JOB:-63119396}" UNC_THROTTLE=100 bash cluster/submit_eve_regional.sh

TAG=ens_brt-glm-gam-rf-nn; MEM=brt,glm,gam,rf,nn; REPS="${BIG5_REPS:-0:25}"
echo; echo "=== B. big 5 baseline: fits -> ensemble means -> honest meta-model -> index"
out=$(ENS_ALGOS="glm gam rf nn" ENS_VARIANTS="${MEM}" ENS_THROTTLE=11 bash cluster/submit_eve_ensemble.sh | tee /dev/stderr)
meta=$(echo "${out}" | awk '/^meta /{print $NF}')
[ -n "${meta}" ] || { echo "ERROR: could not read the meta-model job id of the big 5 baseline" >&2; exit 1; }
echo; echo "=== B2. big 5 baseline on Germany-only maps"
mk=$(MASK_META_TAG="${TAG}" sbatch --parsable --export=ALL --dependency=afterok:${meta} --kill-on-invalid-dep=yes cluster/eve_mask_meta.sbatch); echo "mask-meta (big 5): ${mk}"
gi=$(BIRDMONITOR_INDEX_TAG="${TAG}_germany" sbatch --parsable --export=ALL --dependency=afterok:${mk} --kill-on-invalid-dep=yes cluster/eve_index.sbatch); echo "index (big 5, Germany only): ${gi}"

echo; echo "=== C. big 5 uncertainty: the ensemble inside the replicates (${REPS})"
uout=$(ENS_MEMBERS="${MEM}" BIRDMONITOR_UNC_REPS="${REPS}" UNC_AFTER="${meta}" UNC_PREP_TIME="${BIG5_PREP_TIME:-24:00:00}" bash cluster/submit_eve_ensemble_uncertainty.sh | tee /dev/stderr)
band=$(echo "${uout}" | awk '/^band:/{print $2}'); fin=$(echo "${uout}" | awk '/^assembleall:/{print $2}')
[ -n "${band}" ] && [ -n "${fin}" ] || { echo "ERROR: could not read the band / assembleall job ids of the big 5 uncertainty chain" >&2; exit 1; }
echo; echo "=== C2. big 5 uncertainty: regional index, Germany-only intervals, Germany-only maps"
FORCE=1 BIRDMONITOR_UNC_MEMBERS="${MEM}" BIRDMONITOR_UNC_TAG="${TAG}" BIRDMONITOR_UNC_BANDS=48 BIRDMONITOR_UNC_REPS="${REPS}" UNC_AFTER="${band}" UNC_FINAL="${fin}" UNC_THROTTLE=100 bash cluster/submit_eve_regional.sh

echo
echo "================================================================================"
echo "ALL QUEUED. Logs in ./logs/ . Read-only monitor (any time):  cd ~/projects/birdMonitor && bash cluster/monitor_tonight.sh"
echo "================================================================================"
