#!/bin/bash
# 2026-11-21: run ONE uncertainty-prepare task of a series chain again (after it hit its time limit or failed) and re-point the band tasks of that species to it.
# The environment of the chain was saved from the running jobs in logs/env_<series>.raw (BIRDMONITOR_RUNNAME, INPUT_ROOT, years, members, replicates ...).
# fit + coarse + the climate out-of-fold step are on disk and are skipped; the out-of-fold step now keeps a checkpoint per replicate (uncOof.R, commit 136e7a5).
#   cd ~/projects/birdMonitor && bash --login cluster/resubmit_unc_prepare_task.sh <s2v2|s1v3> <task>
#   <task> = species number of the prepare array (s2v2: 1 = Vanellus vanellus;  s1v3: 13 = Motacilla flava)
# The band tasks of that species ((task-1)*48+1 .. task*48) are given the dependency afterok:<new prepare job>. Everything behind the band array keeps waiting.
set -euo pipefail
cd "$(dirname "$0")/.."
SERIES="${1:?series s2v2|s1v3}"; TASK="${2:?species task number}"
case "${SERIES}" in
  s2v2) BAND=66881130; ;;
  s1v3) BAND=66881433; ;;
  *) echo "unknown series ${SERIES}" >&2; exit 1 ;;
esac
RAW="logs/env_${SERIES}.raw"; [ -s "${RAW}" ] || { echo "missing ${RAW}" >&2; exit 1; }
if squeue -u "${USER}" -h -r -o "%j %i" | grep -E "^unc-prepare .*_${TASK}$" >/dev/null && [ "${FORCE:-0}" != "1" ]; then
  echo "STOP: a prepare task ${TASK} is still queued or running. FORCE=1 overrides." >&2; exit 1
fi
while IFS= read -r line; do
  case "${line}" in UNC_DONE_MARKER=*|BIRDMONITOR_UNC_CORES=*|pid=*|"") continue ;; esac
  export "${line?}"
done < "${RAW}"
module load ${EVE_R_MODULE} >/dev/null 2>&1 || true
NB=48; LO=$(( (TASK - 1) * NB + 1 )); HI=$(( TASK * NB ))
new=$(sbatch --parsable --export=ALL --array="${TASK}" --mem-per-cpu="${UNC_PREP_MEM:-16G}" --time="${RERUN_TIME:-96:00:00}" cluster/eve_unc_prepare.sbatch)
echo "new prepare job: ${new} (species ${TASK}, run ${BIRDMONITOR_RUNNAME})"
scontrol update JobId="${BAND}_[${LO}-${HI}]" Dependency="afterok:${new}"
echo "band tasks ${LO}-${HI} of job ${BAND} now wait for ${new}"
squeue -h -r -j "${BAND}" -o "%i %T %E" | sed -n "1,3p"
echo "${SERIES} task ${TASK}: prepare ${new}, bands ${LO}-${HI} ($(date +%F\ %H:%M))" >> logs/.resubmitted_unc_prepare
