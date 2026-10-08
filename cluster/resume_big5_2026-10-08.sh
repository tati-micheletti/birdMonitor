#!/bin/bash
# ONE-OFF (2026-10-08 night): resume the big 5 after the GAM fix. The climate GAM of Alauda arvensis (array task 4) did not converge and stopped, which cancelled
# everything that depended on the climate fits (ensemble mean, meta-model, index, Germany-only copy, the big 5 uncertainty chain and its regional steps).
# The GAM is now robust (algoFitGAM tries REML / the efs optimiser / k = 3 before giving up, and fits that converged at once are unchanged).
#
# What this does:
#   1. cancels what is left of the old GAM arrays (landscape, habitat: they run the OLD code and could stop the same way) and of everything downstream;
#      the BRT-only chain and its regional steps (63196413-17), the other fit arrays (GLM, RF, NN) and all finished work are NOT touched
#   2. resubmits the GAM fits: climate task 4, landscape 1-11, habitat 1-11 (finished years are kept, so they resume)
#   3. rebuilds, with the SAME dependencies as cluster/submit_eve_tonight.sh: ensemble means -> honest meta-model -> index -> Germany-only copy + index ->
#      the big 5 uncertainty (replicates 0:25) -> regional / Germany-only intervals / maps
#
#     cd ~/projects/birdMonitor && bash --login cluster/resume_big5_2026-10-08.sh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs
if ! type module >/dev/null 2>&1; then echo "Run this script as:  bash --login cluster/resume_big5_2026-10-08.sh" >&2; exit 1; fi
module load ${EVE_R_MODULE:-GCC/13.3.0 OpenMPI/5.0.5 R/4.5.1 GDAL/3.10.3 CMake ImageMagick/7.1.1-38 UDUNITS/2.2.28}
export BIRDMONITOR_RUNNAME="${BIRDMONITOR_RUNNAME:-test4}"
TAG=ens_brt-glm-gam-rf-nn; MEM=brt,glm,gam,rf,nn; REPS="${BIG5_REPS:-0:25}"
# job ids from the submission of 2026-10-08 (cluster/submit_eve_tonight.sh output)
C_GLM=63196418; C_RF=63196420; C_NN=63196421
L_GLM=63196422; L_GAM_OLD=63196423; L_RF=63196424; L_NN=63196425
H_GLM=63196426; H_GAM_OLD=63196427; H_RF=63196428; H_NN=63196429
OLD_DOWNSTREAM="63196430 63196431 63196432 63196433 63196434 63196435 63196436 $(seq 63196530 63196541 | tr '\n' ' ')"

echo "=== 1. clean up: old GAM arrays and everything that depended on them"
scancel ${L_GAM_OLD} ${H_GAM_OLD} ${OLD_DOWNSTREAM} 2>/dev/null || true
sleep 10
squeue -u "${USER}" -h -o "%i %j" | grep -E "ens-(landscape|habitat)-gam|ens-mean|ens-meta|ens-index|unc-(prepare|covcache)" && echo "(the lines above are still shutting down; they disappear within a minute)" || echo "clean"

echo; echo "=== 2. GAM fits again (robust version)"
gc=$(ENS_SCALE=climate ENS_ALGO=gam sbatch --parsable --export=ALL --job-name=ens-climate-gam --array=4 --cpus-per-task=1 --mem-per-cpu=8G --time=03:00:00 cluster/eve_ens_algo.sbatch)
gl=$(ENS_SCALE=landscape ENS_ALGO=gam sbatch --parsable --export=ALL --job-name=ens-landscape-gam --array=1-11%11 --cpus-per-task=1 --mem-per-cpu=8G --time=06:00:00 cluster/eve_ens_algo.sbatch)
gh=$(ENS_SCALE=habitat ENS_ALGO=gam sbatch --parsable --export=ALL --job-name=ens-habitat-gam --array=1-11%11 --cpus-per-task=1 --mem-per-cpu=12G --time=12:00:00 cluster/eve_ens_algo.sbatch)
echo "fit climate/gam: ${gc} | landscape/gam: ${gl} | habitat/gam: ${gh}"

echo; echo "=== 3. big 5 baseline: ensemble means -> honest meta-model -> index"
mc=$(ENS_SCALE=climate ENS_MEMBERS="${MEM}" sbatch --parsable --export=ALL --job-name=ens-mean-climate --dependency=afterok:${C_GLM}:${gc}:${C_RF}:${C_NN} --kill-on-invalid-dep=yes cluster/eve_ens_ens.sbatch)
ml=$(ENS_SCALE=landscape ENS_MEMBERS="${MEM}" sbatch --parsable --export=ALL --job-name=ens-mean-landscape --dependency=afterok:${L_GLM}:${gl}:${L_RF}:${L_NN} --kill-on-invalid-dep=yes cluster/eve_ens_ens.sbatch)
mh=$(ENS_SCALE=habitat ENS_MEMBERS="${MEM}" sbatch --parsable --export=ALL --job-name=ens-mean-habitat --dependency=afterok:${H_GLM}:${gh}:${H_RF}:${H_NN} --kill-on-invalid-dep=yes cluster/eve_ens_ens.sbatch)
echo "ensemble means: climate ${mc} | landscape ${ml} | habitat ${mh}"
meta=$(BIRDMONITOR_META_SOURCE="${TAG}" sbatch --parsable --export=ALL --job-name="ens-meta-${TAG}" --dependency=afterok:${mc}:${ml}:${mh} --kill-on-invalid-dep=yes modules/models_Monitor/cluster/eve_array_meta.sbatch)
idx=$(BIRDMONITOR_INDEX_TAG="${TAG}" sbatch --parsable --export=ALL --job-name="ens-index-${TAG}" --dependency=afterok:${meta} --kill-on-invalid-dep=yes cluster/eve_index.sbatch)
echo "meta ${TAG}: ${meta} | index ${TAG}: ${idx}"

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
echo "RESUMED. Read-only monitor (any time):  cd ~/projects/birdMonitor && bash cluster/monitor_tonight.sh"
echo "================================================================================"
