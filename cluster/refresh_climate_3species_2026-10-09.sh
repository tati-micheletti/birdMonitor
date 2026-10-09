#!/bin/bash
# ONE-OFF (2026-10-09): bring the BRT-only uncertainty run (tag honest2) back in line with the CURRENT baseline climate models of three species.
#
# Why: the europe array refitted the climate BRTs on 2026-10-08 10:39. For three species (Anthus pratensis, Vanellus vanellus, Sturnus vulgaris) the refit chose a slightly different
# number of trees (the internal cross-validation of gbm.step is random), while replicate 0 and the bootstrap replicates still use the copy of 2026-10-06 (parity check: 2 species MISMATCH;
# diagnostics tools/diagnoseParity*.R). Everything that depends on those climate models is recomputed: the climate replicate models, their coarse predictions, the out-of-fold inputs,
# the ridge weights, all band predictions, the summaries, the community maps, the index intervals, and the regional / Germany-only steps.
#
# What it does (nothing is deleted, old files are MOVED to <uncertainty folder>/_old_climate_refit_2026-10-09/):
#   1. per species: moves aside models/climate_*, coarse/*/climate_*.tif, oof, ridge, pred, pieces, maps, maps_germany, regional, area means, parity file
#   2. for the whole run: moves aside community/pieces, community, community_germany and the regional index outputs (they combine all species)
#   3. submits the standard chain (covcache, prepare, band, summarize, assemble, community, assembleAll) and the regional / Germany-only steps behind it. Steps whose
#      results still exist (the other eight species, the landscape and habitat scales) are SKIPPED by the code, so only what was moved aside is recomputed.
#
#     cd ~/projects/birdMonitor && bash --login cluster/refresh_climate_3species_2026-10-09.sh          (DRY_RUN=1 in front: only lists what would be moved, submits nothing)
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs
RUN="${BIRDMONITOR_RUNNAME:-test4}"; TAG="${REFRESH_TAG:-honest2}"
SPECIES=(${REFRESH_SPECIES:-Anthus_pratensis Vanellus_vanellus Sturnus_vulgaris})
LAB="${REFRESH_LABEL:-reps_000-050}"
UNC="outputs/${RUN}/uncertainty_${TAG}"; OLD="${UNC}/_old_climate_refit_2026-10-09"
DRY="${DRY_RUN:-0}"
[ -d "${UNC}" ] || { echo "STOP: ${UNC} not found" >&2; exit 1; }
if [ "${DRY}" != "1" ] && [ "${FORCE:-0}" != "1" ] && squeue -u "${USER}" -h -o "%j" | grep -qE "^(unc-covcache|unc-prepare|unc-band|unc-summarize|unc-assemble|unc-community|unc-regionband)"; then
  echo "STOP: uncertainty jobs are still in the queue (the big 5 chain?). This script may only run when nothing of THIS run is queued; the big 5 uses another folder, so you may continue with FORCE=1." >&2; exit 1
fi
mv_aside() {   # path (relative to ${UNC}) -> ${OLD}/<same path>
  local rel="$1"
  if [ -e "${UNC}/${rel}" ]; then
    if [ "${DRY}" = "1" ]; then echo "  would move: ${rel}"; else mkdir -p "${OLD}/$(dirname "${rel}")"; mv "${UNC}/${rel}" "${OLD}/${rel}"; echo "  moved: ${rel}"; fi
  fi
}
echo "=== 1. move aside what depends on the climate models (${SPECIES[*]})"
for sp in "${SPECIES[@]}"; do
  echo " -- ${sp}"
  mv_aside "${sp}/models/climate_${LAB}.rds"
  for f in "${UNC}/${sp}/coarse/${LAB}"/climate_*.tif; do [ -e "${f}" ] && mv_aside "${f#${UNC}/}"; done
  for d in oof ridge "pred/${LAB}" pieces maps maps_germany regional; do mv_aside "${sp}/${d}"; done
  for f in area_mean_replicates.csv area_mean_replicates_germany.csv parity_check.txt; do mv_aside "${sp}/${f}"; done
done
echo " -- results that combine all species"
for d in community community_germany regional; do mv_aside "${d}"; done      # (community/ holds the pieces too)
[ "${DRY}" = "1" ] && { echo; echo "DRY RUN: nothing was moved or submitted."; exit 0; }

if ! type module >/dev/null 2>&1; then echo "Run this script as:  bash --login cluster/refresh_climate_3species_2026-10-09.sh" >&2; exit 1; fi
module load ${EVE_R_MODULE:-GCC/13.3.0 OpenMPI/5.0.5 R/4.5.1 GDAL/3.10.3 CMake ImageMagick/7.1.1-38 UDUNITS/2.2.28}
export BIRDMONITOR_RUNNAME="${RUN}"
echo; echo "=== 2. submit the chain again (only the moved-aside results are recomputed)"
uout=$(BIRDMONITOR_UNC_TAG="${TAG}" UNC_THROTTLE=100 UNC_BAND_TIME="${REFRESH_BAND_TIME:-24:00:00}" bash cluster/submit_eve_uncertainty.sh | tee /dev/stderr)
band=$(echo "${uout}" | awk '/^band:/{print $2}'); fin=$(echo "${uout}" | awk '/^assembleall:/{print $2}')
[ -n "${band}" ] && [ -n "${fin}" ] || { echo "ERROR: could not read the band / assembleall job ids" >&2; exit 1; }
echo; echo "=== 3. regional index, Germany-only intervals and maps"
FORCE=1 BIRDMONITOR_UNC_TAG="${TAG}" UNC_AFTER="${band}" UNC_FINAL="${fin}" UNC_THROTTLE=100 bash cluster/submit_eve_regional.sh
echo; echo "SUBMITTED. Monitor (read-only): cd ~/projects/birdMonitor && bash cluster/monitor_chains.sh | sed -n '/=== 4/,\$p'   (newest chain = this refresh until the big 5 chain is resubmitted)"
