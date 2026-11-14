#!/bin/bash
# Re-run ONLY the steps that combine species, after the roster changed (a species removed or added: data/speciesCanonical.csv, column `include` = X)
# or after the species GROUPS changed / a new group was added (data/speciesGroups.csv).
# Written 2026-11-11 (project lead: "we need the command to re-run when we remove a species"); 2026-11-14: one chain per species GROUP + viz2 layout.
#
# NOT recomputed (they are per species and stay as they are): models, ensemble fits, meta-model, the 672 uncertainty band tasks, the summaries, the per-species
# assemble, the regional bands -- they are done ONCE per species and shared by every group. What IS recomputed, for EACH group, in this order (all after the roster
# and group files were changed, committed and pulled on EVE):
#   1. ens-index        annual report (species table, national indices, richness and change maps) and the regional index maps of the species of the group, on the rectangle
#      ens-index (germany)  AND on the Germany-only maps (annual_report_<tag>_germany*/, regional_index_<tag>_germany*/ = what the Monitor shows as raw regional index).
#                       2026-11-14: the Germany-only run was missing here until now (it is what vizSources() reads for msi_regional): a roster change left the raw regional index of the OLD roster.
#   2. unc-community    expected richness, mean change and Bray-Curtis turnover over the species of the group (the old pieces are rebuilt by themselves: their stamp contains the species set,
#                       uncPieceStamp() in models_Monitor/R/uncSummarize.R; a group other than "all" writes community_<group>/)
#   3. unc-assembleall  combined indices with their uncertainty (whole window), community maps stitched
#   4. unc-regionindex  regional index with uncertainty (needs 1: its replicate 0 is compared with the baseline regional index; regional_<group>/)
#   5. unc-assembleall  again with the German-only area means (annual_report_<tag>_germany<group>/combined_index_uncertainty.csv = the national trend of the Monitor)
#   6. unc-maskmaps     Germany-only copy of the COMMUNITY maps only (the species maps are not touched)
# and once, after all groups:
#   7. copy-databirds   the inputs (incremental) and the new results into /data/birds/birdMonitor/outputs/<run>   (they REPLACE the files of the old roster there)
#   8. connector        the viz folder: every changed file is written again (msi_regional, msi_regional_unc, msi_regional_clear, richness, national trend).
#                       VIZ2=1: into /data/birds/viz2 in the group layout (richness_year_<group>/, msi_regional_<group>/, ..., msi_national/msi_national_<group>.csv) and NOT into viz.
#   9. postrun          checks, figures, package A (+ e-mail if NOTIFY_EMAIL is set) -- only when the group "all" is part of this run
# The viz folders are never emptied: files of a species that left the roster STAY in /data/birds/viz(2) until someone deletes them on purpose.
#
#   cd ~/projects/birdMonitor && git pull
#   DRY_RUN=1 BIRDMONITOR_RUNNAME=v3 NOTIFY_EMAIL="a@ufz.de" bash --login cluster/rerun_after_roster_change.sh     # only shows what would be submitted
#   BIRDMONITOR_RUNNAME=v3 NOTIFY_EMAIL="a@ufz.de" bash --login cluster/rerun_after_roster_change.sh
#   Only the farmland group, the Monitor layout in viz2 (viz stays untouched):
#   VIZ2=1 BIRDMONITOR_GROUPS=farmland BIRDMONITOR_RUNNAME=v3 NOTIFY_EMAIL="a@ufz.de" bash --login cluster/rerun_after_roster_change.sh
#
#   BIRDMONITOR_RUNNAME   (required) the run, e.g. v3          BIRDMONITOR_ENS_TAG (default ens_brt-glm-gam-rf-nn)
#   BIRDMONITOR_UNC_MEMBERS (default brt,glm,gam,rf,nn)        BIG5_REPS (default 0:25)        NOTIFY_EMAIL (failure watcher + post-run e-mail)
#   BIRDMONITOR_GROUPS    groups to recompute, space separated (default: every group of data/speciesGroups.csv; "all" = the general index, folders without suffix)
#   VIZ2=1                connector writes the group layout into BIRDMONITOR_VIZ_PATH (default /data/birds/viz2) with BIRDMONITOR_VIZ_GROUPS=1; default 0 = as before, into viz (group "all" only)
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
# a group set in the environment of the caller must never reach the jobs by accident: every job gets its group from this script
unset BIRDMONITOR_GROUP
if [ "${VIZ2:-0}" = "1" ]; then export BIRDMONITOR_VIZ_PATH="${BIRDMONITOR_VIZ_PATH:-/data/birds/viz2}" BIRDMONITOR_VIZ_GROUPS=1; echo "VIZ2=1: the connector writes the group layout into ${BIRDMONITOR_VIZ_PATH} (viz is not touched)"; fi

# the roster, read from the file (include = X); the same list is what every R step reads through tools/sharedConfig.R
ROSTER=$(tr -d '\r' < data/speciesCanonical.csv | awk -F, 'NR > 1 && $5 ~ /^X/ {print $1}')
NSP=$(echo "${ROSTER}" | grep -c .)
echo "Run ${RUN} | tag ${TAG} | roster of ${NSP} species (data/speciesCanonical.csv):"; echo "${ROSTER}" | sed 's/^/  /'
[ "${DRY}" = "1" ] || echo "${ROSTER}" > "logs/roster_${RUN}_$(date +%F_%H%M).txt"

# the groups: data/speciesGroups.csv (group,label,latin_name), read with awk (no commas in labels: checked by tests/test_speciesGroups.R); the R steps check every group against the roster
GRP_FILE=$(tr -d '\r' < data/speciesGroups.csv)
GRP_ALL=$(echo "${GRP_FILE}" | awk -F, 'NR > 1 && !seen[$1]++ {print $1}')
GRP_RUN="${BIRDMONITOR_GROUPS:-$(echo ${GRP_ALL})}"
for g in ${GRP_RUN}; do echo "${GRP_ALL}" | grep -qx "${g}" || { echo "STOP: group '${g}' is not in data/speciesGroups.csv (groups: $(echo ${GRP_ALL})). Check BIRDMONITOR_GROUPS." >&2; exit 1; }; done
echo "Groups of this run: ${GRP_RUN}"
for g in ${GRP_RUN}; do
  n=$(echo "${GRP_FILE}" | awk -F, -v g="${g}" 'NR > 1 && $1 == g' | wc -l); echo "  ${g}: $(echo "${GRP_FILE}" | awk -F, -v g="${g}" 'NR > 1 && $1 == g {print $2; exit}') -- ${n} species"
done

if [ "${DRY}" != "1" ] && [ "${KEEP_OLD:-1}" != "0" ]; then
  B="outputs/${RUN}_before_roster_change_$(date +%F)"; mkdir -p "${B}"
  for g in ${GRP_RUN}; do
    S=""; [ "${g}" = "all" ] || S="_${g}"
    for d in "outputs/${RUN}/annual_report_${TAG}${S}" "outputs/${RUN}/annual_report_${TAG}_germany${S}" "outputs/${RUN}/regional_index_${TAG}_germany${S}"; do [ -d "${d}" ] && cp -a "${d}" "${B}/"; done
  done
  mkdir -p "${B}/uncertainty_${TAG}"; cp -a "outputs/${RUN}/uncertainty_${TAG}"/*.csv "${B}/uncertainty_${TAG}/" 2>/dev/null || true
  echo "Old tables kept in ${B} (small files only)."
fi
SINCE=$(date +%FT%T)

ALL_DEP=""; ALL_MM=""; FIRST_IDX=""; LASTIDS=""
for g in ${GRP_RUN}; do
  S=""; [ "${g}" = "all" ] || S="_${g}"
  GN=$(echo "${GRP_FILE}" | awk -F, -v g="${g}" 'NR > 1 && $1 == g' | wc -l)
  GX="ALL,BIRDMONITOR_GROUP=${g}"
  echo; echo "################ group '${g}' (${GN} species)"
  echo "=== 1. annual report + regional index of the species of the group (ens-index): rectangle and Germany-only"
  idx=$(BIRDMONITOR_INDEX_TAG="${TAG}" sb --export="${GX}" --job-name="ens-index-${TAG}${S}" cluster/eve_index.sbatch); echo "ens-index:       ${idx}"
  gidx=$(BIRDMONITOR_INDEX_TAG="${TAG}_germany" sb --export="${GX}" --job-name="ens-index-${TAG}_germany${S}" cluster/eve_index.sbatch); echo "ens-index (Germany only): ${gidx}"
  [ -n "${FIRST_IDX}" ] || FIRST_IDX="${idx}"
  echo "=== 2-5. uncertainty: community, combined indices, regional index"
  com=$(sb --export="${GX}" --array=1-${NB} cluster/eve_unc_community.sbatch); echo "unc-community:   ${com}"
  fin=$(sb --export="${GX}" --dependency=afterok:${com} --kill-on-invalid-dep=yes cluster/eve_unc_assembleall.sbatch); echo "unc-assembleall: ${fin}"
  ri=$(sb --export="${GX}" --dependency=afterok:${idx} --kill-on-invalid-dep=yes cluster/eve_unc_regionindex.sbatch); echo "unc-regionindex: ${ri}"
  asm2=$(sb --export="${GX},BIRDMONITOR_UNC_AREAMEAN=area_mean_replicates_germany.csv,BIRDMONITOR_INDEX_TAG=${TAG}_germany" --dependency=afterok:${idx}:${gidx}:${fin}:${ri} --kill-on-invalid-dep=yes cluster/eve_unc_assembleall.sbatch); echo "assembleall (Germany-only area means): ${asm2}"
  echo "=== 6. Germany-only copy of the community maps (task $((GN + 1)) of the maskmaps array = the community)"
  mm=$(sb --export="${GX}" --array=$((GN + 1)) --dependency=afterok:${asm2} --kill-on-invalid-dep=yes cluster/eve_unc_maskmaps.sbatch); echo "unc-maskmaps:    ${mm}"
  ALL_MM="${ALL_MM}:${mm}"; ALL_DEP="${ALL_DEP}:${idx}:${gidx}:${ri}"; LASTIDS="${LASTIDS} ${idx} ${gidx} ${com} ${fin} ${ri} ${asm2} ${mm}"
done
echo; echo "################ all groups: /data/birds, viz folder, post-run"
echo "=== 7-9. /data/birds, viz folder, post-run"
cp=$(sb --export=ALL --dependency=afterok${ALL_MM}${ALL_DEP} --kill-on-invalid-dep=yes cluster/eve_copy_data_birds.sbatch); echo "copy-databirds:  ${cp}"
cn=$(sb --export=ALL --dependency=afterok:${cp} --kill-on-invalid-dep=yes cluster/eve_connector.sbatch); echo "connector:       ${cn}"
[ -n "${NOTIFY_EMAIL:-}" ] || echo "NOTE: NOTIFY_EMAIL is not set: no e-mail from the post-run job or the failure watcher."
LAST="${cn}"; pr=""
if echo " ${GRP_RUN} " | grep -q " all "; then
  pr=$(sb --export=ALL --dependency=afterok:${cn} --kill-on-invalid-dep=yes cluster/eve_postrun.sbatch); echo "postrun:         ${pr}"; LAST="${pr}"
else echo "postrun:         skipped (it checks the whole roster and the group 'all' is not part of this run)"; fi
if [ -n "${NOTIFY_EMAIL:-}" ]; then
  wd=$(WATCH_FIRST_JOB="${FIRST_IDX}" WATCH_UNTIL_JOB="${LAST}" WATCH_SINCE="${SINCE}" sb --export=ALL cluster/eve_chain_watch.sbatch); echo "failure watcher: ${wd} (e-mail to ${NOTIFY_EMAIL})"
fi
echo
echo "Submitted. CHECK AT ANY TIME (read-only):  cd ~/projects/birdMonitor && bash cluster/status.sh${LASTIDS} ${cp} ${cn} ${pr}"
echo "When it is done: outputs/${RUN}/POSTRUN_SUMMARY.txt (group 'all'); files of a species that left the roster are still in /data/birds/viz (delete them on purpose)."
[ "${VIZ2:-0}" != "1" ] || echo "viz2 layout: ${BIRDMONITOR_VIZ_PATH}/_groups.csv lists the groups, _missing.csv / _missing_<group>.csv what is not there yet."
