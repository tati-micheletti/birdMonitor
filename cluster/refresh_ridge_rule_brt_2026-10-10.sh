#!/bin/bash
# ONE-OFF (2026-10-10): redo the BRT-only uncertainty run (tag honest2) with the replicate ridge meta-models chosen by the BASELINE's penalty rule (ten random folds, lambda.1se).
# Until now the replicates used spatial block folds: penalties 2-3 x larger than the baseline's, weights shrunk (Perdix perdix to exactly zero), trends much weaker than the baseline's;
# the baseline combined index (95.6) fell outside the 90% interval of its own replicates (96.1-99.0). A bootstrap must repeat the SAME procedure on resampled data.
#
# What it does (nothing is deleted; old files are MOVED to <uncertainty folder>/_old_ridge_blockfolds_2026-10-10/ and the old interval tables are COPIED there as the
# "block-fold penalty" sensitivity analysis):
#   1. per species: moves aside ridge, pred/<label>, pieces, maps, maps_germany, regional, area means, parity file (models, coarse predictions and out-of-fold inputs are KEPT:
#      they do not depend on the ridge)
#   2. for the whole run: moves aside community, community_germany, regional; copies the interval tables of annual_report_germany/ and annual_report/
#   3. submits the standard chain (prepare recomputes the ridge with the new rule, then band, summarize, assemble, community, assembleAll) and the regional / Germany-only steps
#
#     cd ~/projects/birdMonitor && FORCE=1 bash --login cluster/refresh_ridge_rule_brt_2026-10-10.sh          (DRY_RUN=1 in front: only lists what would be moved)
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs
RUN="${BIRDMONITOR_RUNNAME:-test4}"; TAG="${REFRESH_TAG:-honest2}"; LAB="${REFRESH_LABEL:-reps_000-050}"
UNC="outputs/${RUN}/uncertainty_${TAG}"; OLD="${UNC}/_old_ridge_blockfolds_2026-10-10"; DRY="${DRY_RUN:-0}"
[ -d "${UNC}" ] || { echo "STOP: ${UNC} not found" >&2; exit 1; }
if [ "${DRY}" != "1" ] && [ "${FORCE:-0}" != "1" ] && squeue -u "${USER}" -h -o "%j" | grep -qE "^(unc-covcache|unc-prepare|unc-band|unc-summarize|unc-assemble|unc-community|unc-regionband)"; then
  echo "STOP: uncertainty jobs are in the queue (the big 5 chain?). This run uses another folder, so you may continue with FORCE=1." >&2; exit 1
fi
mv_aside() { local rel="$1"
  if [ -e "${UNC}/${rel}" ]; then
    if [ "${DRY}" = "1" ]; then echo "  would move: ${rel}"; else mkdir -p "${OLD}/$(dirname "${rel}")"; mv "${UNC}/${rel}" "${OLD}/${rel}"; echo "  moved: ${rel}"; fi
  fi
}
cp_keep() { local src="$1" rel="$2"      # copy a file (sensitivity analysis) -- the original is overwritten later by the new run
  if [ -f "${src}" ]; then if [ "${DRY}" = "1" ]; then echo "  would copy: ${src}"; else mkdir -p "${OLD}/$(dirname "${rel}")"; cp -p "${src}" "${OLD}/${rel}"; echo "  copied: ${src}"; fi; fi
}
echo "=== 1. per species: move aside what depends on the ridge weights"
for d in "${UNC}"/*/; do
  sp=$(basename "${d}"); case "${sp}" in _*|community*|regional|annual*) continue;; esac
  [ -d "${UNC}/${sp}/ridge" ] || continue
  echo " -- ${sp}"
  for x in ridge "pred/${LAB}" pieces maps maps_germany regional; do mv_aside "${sp}/${x}"; done
  for f in area_mean_replicates.csv area_mean_replicates_germany.csv parity_check.txt; do mv_aside "${sp}/${f}"; done
done
echo " -- results that combine all species"
for x in community community_germany regional; do mv_aside "${x}"; done
echo " -- the old interval tables (block-fold penalty), kept as a sensitivity analysis"
for f in species_index_uncertainty.csv combined_index_uncertainty.csv combined_index_replicates.csv; do
  cp_keep "outputs/${RUN}/annual_report_germany/${f}" "annual_report_germany/${f}"; cp_keep "outputs/${RUN}/annual_report/${f}" "annual_report/${f}"
done
[ "${DRY}" = "1" ] && { echo; echo "DRY RUN: nothing was moved, copied or submitted."; exit 0; }

if ! type module >/dev/null 2>&1; then echo "Run this script as:  bash --login cluster/refresh_ridge_rule_brt_2026-10-10.sh" >&2; exit 1; fi
module load ${EVE_R_MODULE:-GCC/13.3.0 OpenMPI/5.0.5 R/4.5.1 GDAL/3.10.3 CMake ImageMagick/7.1.1-38 UDUNITS/2.2.28}
export BIRDMONITOR_RUNNAME="${RUN}"
echo; echo "=== 2. submit the chain again (only what was moved aside is recomputed)"
uout=$(BIRDMONITOR_UNC_TAG="${TAG}" UNC_THROTTLE=100 UNC_BAND_TIME="${REFRESH_BAND_TIME:-24:00:00}" bash cluster/submit_eve_uncertainty.sh | tee /dev/stderr)
band=$(echo "${uout}" | awk '/^band:/{print $2}'); fin=$(echo "${uout}" | awk '/^assembleall:/{print $2}')
[ -n "${band}" ] && [ -n "${fin}" ] || { echo "ERROR: could not read the band / assembleall job ids" >&2; exit 1; }
echo; echo "=== 3. regional index, Germany-only intervals and maps"
FORCE=1 BIRDMONITOR_UNC_TAG="${TAG}" UNC_AFTER="${band}" UNC_FINAL="${fin}" UNC_THROTTLE=100 bash cluster/submit_eve_regional.sh
echo; echo "SUBMITTED. Monitor (read-only): cd ~/projects/birdMonitor && bash cluster/monitor_chains.sh | sed -n '/=== 4/,\$p'"
