#!/bin/bash
# ONE-OFF (2026-10-12): resume the big 5 uncertainty chain. The first chain (prepare 63257254) died because task 6 (Emberiza calandra) ran into its 24 h limit
# in the out-of-fold step (the other 7 reruns completed); everything behind it (band ... maskmaps) was cancelled.
#   - species 6 : prepare again (128 GB, 48 h). fit + coarse are on disk and skipped; the out-of-fold step now keeps a checkpoint per scale (uncOof.R).
#   - the other 10 species do NOT wait for it: ridge redo (baseline penalty rule, fast) -> band (24 h) for their 480 band tasks start at once.
#   - species 6 : band (48 tasks) behind its own prepare.
#   - summarize, assemble, community, assembleall and the regional / Germany-only steps wait for BOTH band arrays.
# Species 6's prepare also fits its ridge (current code = baseline rule), so it needs no ridge redo.
#
#     cd ~/projects/birdMonitor && bash --login cluster/resume_big5_2026-10-12.sh        (the second run is refused; FORCE=1 overrides)
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs
MARK="logs/.resume_big5_2026-10-12.submitted"
if [ "${FORCE:-0}" != "1" ] && [ -e "${MARK}" ]; then
  echo "STOP: this script already submitted its jobs ($(cat "${MARK}")). A second run would make two runs write the same files. FORCE=1 overrides." >&2; exit 1
fi
if ! type module >/dev/null 2>&1; then echo "Run this script as:  bash --login cluster/resume_big5_2026-10-12.sh" >&2; exit 1; fi
module load ${EVE_R_MODULE:-GCC/13.3.0 OpenMPI/5.0.5 R/4.5.1 GDAL/3.10.3 CMake ImageMagick/7.1.1-38 UDUNITS/2.2.28}
export BIRDMONITOR_RUNNAME="${BIRDMONITOR_RUNNAME:-test4}"
TAG=ens_brt-glm-gam-rf-nn; MEM=brt,glm,gam,rf,nn; REPS="${BIG5_REPS:-0:25}"; NB=48; NSP=11
LATE="${BIG5_LATE_TASK:-6}"                                  # the species whose prepare must run again
PREP_TIME="${PREP_TIME:-48:00:00}"; BAND_TIME="${UNC_BAND_TIME:-24:00:00}"; THR="${UNC_THROTTLE:-100}"
export BIRDMONITOR_UNC_MEMBERS="${MEM}" BIRDMONITOR_UNC_REPS="${REPS}" BIRDMONITOR_UNC_BANDS="${NB}"
unset BIRDMONITOR_UNC_TAG || true      # the tag defaults to the ensemble's name
EARLY=$(seq -s, 1 "${NSP}" | tr ',' '\n' | grep -vx "${LATE}" | paste -sd, -)              # 1,2,3,4,5,7,...
LO=$(( (LATE - 1) * NB + 1 )); HI=$(( LATE * NB ))
BANDEARLY="1-$((LO - 1))"; [ "${HI}" -lt $((NSP * NB)) ] && BANDEARLY="${BANDEARLY},$((HI + 1))-$((NSP * NB))"; [ "${LO}" -eq 1 ] && BANDEARLY="$((HI + 1))-$((NSP * NB))"

echo "=== 1. prepare, species task ${LATE} only (128 GB, ${PREP_TIME})   [first, so a refused time limit stops everything before anything else is submitted]"
prep=$(sbatch --parsable --export=ALL --array="${LATE}" --mem-per-cpu=16G --time="${PREP_TIME}" cluster/eve_unc_prepare.sbatch)
echo "prepare:       ${prep}"
echo "=== 2. ridge redo for the other species (${EARLY}), then their band tasks (${BANDEARLY})"
ridge=$(sbatch --parsable --export=ALL --array="${EARLY}" --kill-on-invalid-dep=yes cluster/eve_unc_ridgeredo.sbatch)
echo "ridgeredo:     ${ridge}"
bandA=$(sbatch --parsable --export=ALL --array="${BANDEARLY}%${THR}" --time="${BAND_TIME}" --dependency=afterok:${ridge} --kill-on-invalid-dep=yes cluster/eve_unc_band.sbatch)
echo "band (early):  ${bandA}"
bandB=$(sbatch --parsable --export=ALL --array="${LO}-${HI}" --time="${BAND_TIME}" --dependency=afterok:${prep} --kill-on-invalid-dep=yes cluster/eve_unc_band.sbatch)
echo "band (late):   ${bandB}"
BANDS="${bandA}:${bandB}"
echo "=== 3. summarize, assemble, community, assembleall behind both band arrays"
summ=$(sbatch --parsable --export=ALL --array=1-$((NSP * NB)) --dependency=afterok:${BANDS} --kill-on-invalid-dep=yes cluster/eve_unc_summarize.sbatch)
asm=$(sbatch --parsable --export=ALL --array=1-${NSP} --dependency=afterok:${summ} --kill-on-invalid-dep=yes cluster/eve_unc_assemble.sbatch)
com=$(sbatch --parsable --export=ALL --array=1-${NB} --dependency=afterok:${summ} --kill-on-invalid-dep=yes cluster/eve_unc_community.sbatch)
fin=$(sbatch --parsable --export=ALL --dependency=afterok:${asm}:${com} --kill-on-invalid-dep=yes cluster/eve_unc_assembleall.sbatch)
echo "summarize:     ${summ}"; echo "assemble:      ${asm}"; echo "community:     ${com}"; echo "assembleall:   ${fin}"
echo "=== 4. regional index, Germany-only intervals, Germany-only maps"
FORCE=1 BIRDMONITOR_UNC_MEMBERS="${MEM}" BIRDMONITOR_UNC_TAG="${TAG}" BIRDMONITOR_UNC_BANDS="${NB}" BIRDMONITOR_UNC_REPS="${REPS}" UNC_AFTER="${BANDS}" UNC_FINAL="${fin}" UNC_THROTTLE="${THR}" bash cluster/submit_eve_regional.sh
echo "prepare ${prep} ridgeredo ${ridge} band ${bandA}+${bandB} summarize ${summ} assemble ${asm} community ${com} assembleall ${fin} ($(date +%F\ %H:%M))" > "${MARK}"
echo; echo "SUBMITTED. Monitor (read-only): cd ~/projects/birdMonitor && bash cluster/monitor_chains.sh | sed -n '/=== 4/,\$p'"
