#!/bin/bash
# ONE-OFF (2026-10-10): the replicate ridge meta-models of the BIG 5 run use the baseline's penalty rule (ten random folds) instead of spatial block folds (which shrank the
# weights 2-3 x and made the replicates show much less decline than the baseline; see DECISIONS.md). The band job of the big 5 chain (63257289) is HELD and has not started, so only
# the (fast) ridge step has to be redone. This submits it for all 11 species behind the prepare job (63257254; the running prepare tasks may still write old-rule ridge files:
# the redo moves them aside), re-points the band job's dependency to it and releases the band job.
#
#     cd ~/projects/birdMonitor && bash --login cluster/ridge_rule_big5_2026-10-10.sh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs
PREP="${PREP_JOB:-63257254}"; BAND="${BAND_JOB:-63257289}"; TAG=ens_brt-glm-gam-rf-nn; MEM=brt,glm,gam,rf,nn; REPS="${BIG5_REPS:-0:25}"
st=$(squeue -h -j "${BAND}" -o "%T" 2>/dev/null | sort -u | tr '\n' ' ')
case "${st}" in *PENDING*) ;; *) echo "STOP: band job ${BAND} is not PENDING (state: '${st}'): it may already have started with the old rule. Do not continue; paste this line." >&2; exit 1;; esac
if ! type module >/dev/null 2>&1; then echo "Run this script as:  bash --login cluster/ridge_rule_big5_2026-10-10.sh" >&2; exit 1; fi
module load ${EVE_R_MODULE:-GCC/13.3.0 OpenMPI/5.0.5 R/4.5.1 GDAL/3.10.3 CMake ImageMagick/7.1.1-38 UDUNITS/2.2.28}
export BIRDMONITOR_RUNNAME="${BIRDMONITOR_RUNNAME:-test4}" BIRDMONITOR_UNC_MEMBERS="${MEM}" BIRDMONITOR_UNC_REPS="${REPS}" BIRDMONITOR_UNC_BANDS=48
unset BIRDMONITOR_UNC_TAG || true
dep=(); if [ -n "$(squeue -h -j "${PREP}" 2>/dev/null)" ]; then dep=(--dependency=afterok:"${PREP}"); fi
ridge=$(sbatch --parsable --export=ALL "${dep[@]+"${dep[@]}"}" --kill-on-invalid-dep=yes cluster/eve_unc_ridgeredo.sbatch)
echo "ridge redo (11 species): ${ridge}  ${dep[*]:-(prepare already finished)}"
scontrol update JobId="${BAND}" Dependency=afterok:"${ridge}"
scontrol release "${BAND}"
echo "band ${BAND}: now waits for ${ridge}; released."
squeue -h -j "${BAND}" -o "%i %T %E" | head -2
