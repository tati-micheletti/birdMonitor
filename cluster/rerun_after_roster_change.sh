#!/bin/bash
# Re-run ONLY the steps that combine species, after the roster changed (a species removed or added: data/speciesCanonical.csv, column `include` = X).
# Written 2026-11-11 (project lead: "we need the command to re-run when we remove a species").
#
# NOT recomputed (they are per species and stay as they are): models, ensemble fits, meta-model, the 672 uncertainty band tasks, the summaries, the per-species
# assemble, the regional bands. What IS recomputed, in this order (all after the roster file was changed, committed and pulled on EVE):
#   1. ens-index        annual report (species table, national indices, richness and change maps) and the regional index maps of the NEW roster
#   2. unc-community    expected richness, mean change and Bray-Curtis turnover over the species of the new roster (the old pieces are rebuilt by themselves:
#                       their stamp contains the species set, uncPieceStamp() in models_Monitor/R/uncSummarize.R)
#   3. unc-assembleall  combined indices with their uncertainty (whole window), community maps stitched
#   4. unc-regionindex  regional index with uncertainty (needs 1: its replicate 0 is compared with the baseline regional index)
#   5. unc-assembleall  again with the German-only area means (annual_report_<tag>_germany/combined_index_uncertainty.csv = the national trend of the Monitor)
#   6. unc-maskmaps     Germany-only copy of the COMMUNITY maps only (the species maps are not touched)
#   7. copy-databirds   the new results into /data/birds/birdMonitor/outputs/<run>   (they REPLACE the files of the old roster there)
#   8. connector        the viz folder: every changed file is written again (msi_regional, msi_regional_unc, msi_regional_clear, richness, national trend)
#   9. postrun          checks, figures, package A (+ e-mail if NOTIFY_EMAIL is set)
# The viz folder is never emptied: files of a species that left the roster STAY in /data/birds/viz until someone deletes them on purpose.
#
#   cd ~/projects/birdMonitor && git pull
#   DRY_RUN=1 BIRDMONITOR_RUNNAME=v3 NOTIFY_EMAIL="a@ufz.de" bash --login cluster/rerun_after_roster_change.sh     # only shows what would be submitted
#   BIRDMONITOR_RUNNAME=v3 NOTIFY_EMAIL="a@ufz.de" bash --login cluster/rerun_after_roster_change.sh
#
#   BIRDMONITOR_RUNNAME   (required) the run, e.g. v3          BIRDMONITOR_ENS_TAG (default ens_brt-glm-gam-rf-nn)
#   BIRDMONITOR_UNC_MEMBERS (default brt,glm,gam,rf,nn)        BIG5_REPS (default 0:25)        NOTIFY_EMAIL (failure watcher + post-run e-mail)
#   KEEP_OLD=0 skips the small backup of the old tables (default: outputs/<run>_before_roster_change_<date>/ gets annual_report_*, regional_index_* and the csv/txt files
#   of uncertainty_<tag>; the old MAPS of the community and regional index are not kept, the permanent copy in /data/birds is replaced in step 7)
#   FORCE=1 submits although jobs of these steps are already in the queue        DRY_RUN=1 prints the commands, submits nothing
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs
RUN="${BIRDMONITOR_RUNNAME:?Set BIRDMONITOR_RUNNAME (for example v3): the run whose results are combined again.}"
TAG="${BIRDMONITOR_ENS_TAG:-ens_brt-glm-gam-rf-nn}"; MEM="${BIRDMONITOR_UNC_MEMBERS:-brt,glm,gam,rf,nn}"; REPS="${BIG5_REPS:-0:25}"; NB=48
DRY="${DRY_RUN:-0}"; N=9000
sb() { if [ "${DRY}" = "1" ]; then echo "  [dry run] sbatch $*" >&2; echo "$((9000 + RANDOM % 1000))"; else sbatch --parsable "$@"; fi; }

[ -d "outputs/${RUN}/uncertainty_${TAG}" ] || { echo "STOP: outputs/${RUN}/uncertainty_${TAG} does not exist: there is nothing to combine." >&2; exit 1; }
if [ "${DRY}" != "1" ] && [ "${FORCE:-0}" != "1" ] && squeue -u "${USER}" -h -o "%j" | grep -qE "^(ens-index|unc-community|unc-assembleall|unc-regionindex|unc-maskmaps|copy-databirds|connector|postrun)"; then
  echo "STOP: jobs of these steps are already in the queue (squeue -u ${USER}). A second submission would make two runs write the same files. FORCE=1 overrides." >&2; exit 1; fi
if [ "${DRY}" != "1" ]; then
  EVE_R_MODULE="${EVE_R_MODULE:-GCC/13.3.0 OpenMPI/5.0.5 R/4.5.1 GDAL/3.10.3 CMake ImageMagick/7.1.1-38 UDUNITS/2.2.28}"
  type module >/dev/null 2>&1 || { echo "Run this script as:  bash --login cluster/rerun_after_roster_change.sh" >&2; exit 1; }
  module load ${EVE_R_MODULE}
fi
export BIRDMONITOR_RUNNAME="${RUN}" BIRDMONITOR_UNC_MEMBERS="${MEM}" BIRDMONITOR_UNC_TAG="${TAG}" BIRDMONITOR_UNC_BANDS="${NB}" BIRDMONITOR_UNC_REPS="${REPS}"

# the roster, read from the file (include = X); the same list is what every R step reads through tools/sharedConfig.R
ROSTER=$(awk -F, 'NR > 1 && $5 ~ /^X/ {print $1}' data/speciesCanonical.csv)
NSP=$(echo "${ROSTER}" | grep -c .)
echo "Run ${RUN} | tag ${TAG} | roster of ${NSP} species (data/speciesCanonical.csv):"; echo "${ROSTER}" | sed 's/^/  /'
[ "${DRY}" = "1" ] || echo "${ROSTER}" > "logs/roster_${RUN}_$(date +%F_%H%M).txt"

if [ "${DRY}" != "1" ] && [ "${KEEP_OLD:-1}" != "0" ]; then
  B="outputs/${RUN}_before_roster_change_$(date +%F)"; mkdir -p "${B}"
  for d in "outputs/${RUN}/annual_report_${TAG}" "outputs/${RUN}/annual_report_${TAG}_germany" "outputs/${RUN}/regional_index_${TAG}_germany"; do [ -d "${d}" ] && cp -a "${d}" "${B}/"; done
  mkdir -p "${B}/uncertainty_${TAG}"; cp -a "outputs/${RUN}/uncertainty_${TAG}"/*.csv "${B}/uncertainty_${TAG}/" 2>/dev/null || true
  echo "Old tables kept in ${B} (small files only)."
fi
SINCE=$(date +%FT%T)

echo "=== 1. annual report + regional index of the new roster (ens-index)"
idx=$(BIRDMONITOR_INDEX_TAG="${TAG}" sb --export=ALL --job-name="ens-index-${TAG}" cluster/eve_index.sbatch); echo "ens-index:       ${idx}"
echo "=== 2-5. uncertainty: community, combined indices, regional index"
com=$(sb --export=ALL --array=1-${NB} cluster/eve_unc_community.sbatch); echo "unc-community:   ${com}"
fin=$(sb --export=ALL --dependency=afterok:${com} --kill-on-invalid-dep=yes cluster/eve_unc_assembleall.sbatch); echo "unc-assembleall: ${fin}"
ri=$(sb --export=ALL --dependency=afterok:${idx} --kill-on-invalid-dep=yes cluster/eve_unc_regionindex.sbatch); echo "unc-regionindex: ${ri}"
asm2=$(sb --export=ALL,BIRDMONITOR_UNC_AREAMEAN=area_mean_replicates_germany.csv,BIRDMONITOR_INDEX_TAG="${TAG}_germany" --dependency=afterok:${idx}:${fin}:${ri} --kill-on-invalid-dep=yes cluster/eve_unc_assembleall.sbatch); echo "assembleall (Germany-only area means): ${asm2}"
echo "=== 6. Germany-only copy of the community maps (task $((NSP + 1)) of the maskmaps array = the community)"
mm=$(sb --export=ALL --array=$((NSP + 1)) --dependency=afterok:${asm2} --kill-on-invalid-dep=yes cluster/eve_unc_maskmaps.sbatch); echo "unc-maskmaps:    ${mm}"
echo "=== 7-9. /data/birds, viz folder, post-run"
cp=$(COPY_INPUTS=0 sb --export=ALL --dependency=afterok:${mm}:${idx}:${ri} --kill-on-invalid-dep=yes cluster/eve_copy_data_birds.sbatch); echo "copy-databirds:  ${cp}"
cn=$(sb --export=ALL --dependency=afterok:${cp} --kill-on-invalid-dep=yes cluster/eve_connector.sbatch); echo "connector:       ${cn}"
[ -n "${NOTIFY_EMAIL:-}" ] || echo "NOTE: NOTIFY_EMAIL is not set: no e-mail from the post-run job or the failure watcher."
pr=$(sb --export=ALL --dependency=afterok:${cn} --kill-on-invalid-dep=yes cluster/eve_postrun.sbatch); echo "postrun:         ${pr}"
if [ -n "${NOTIFY_EMAIL:-}" ]; then
  wd=$(WATCH_FIRST_JOB="${idx}" WATCH_UNTIL_JOB="${pr}" WATCH_SINCE="${SINCE}" sb --export=ALL cluster/eve_chain_watch.sbatch); echo "failure watcher: ${wd} (e-mail to ${NOTIFY_EMAIL})"
fi
echo
echo "Submitted. CHECK AT ANY TIME (read-only):  cd ~/projects/birdMonitor && bash cluster/status.sh ${idx} ${com} ${fin} ${ri} ${asm2} ${mm} ${cp} ${cn} ${pr}"
echo "When it is done: outputs/${RUN}/POSTRUN_SUMMARY.txt; files of a species that left the roster are still in /data/birds/viz (delete them on purpose)."
