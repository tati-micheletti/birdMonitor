#!/bin/bash
# ONE command to redo everything that depends on the climate layers after the 2026-10-07 climate fix (DECISIONS.md).
# Run on an EVE login node, from the repo root, AFTER the 4 rebuilt window files (bioclim_2017-2022_scale_50.tif ... bioclim_2020-2025_scale_50.tif)
# have been uploaded to inputs/predictors/processed/scale_50/ (overwriting the old ones; WinSCP: Preserve timestamp OFF) :
#
#   cd ~/projects/birdMonitor && git pull && git submodule update --init --recursive && bash --login cluster/rerun_after_climate_fix.sh
#
# What it does:
#   0. checks that all climate windows are sane (stops otherwise)
#   1. copies the replicate models, landscape/climate coarse predictions, block sizes and the replicate log of the previous uncertainty run
#      (outputs/<run>/uncertainty_honest) into a NEW run folder uncertainty_honest2 (copy only; nothing old is touched or deleted).
#      The coarse CLIMATE predictions are recomputed anyway (older than the rebuilt windows).
#   2. europe array: climate predictions with the corrected windows, then (self-triggered inside each task) the meta-model of that species
#   3. baseline index after step 2
#   4. the uncertainty chain (covcache -> prepare[coarse, oof, ridge] -> band -> summarize -> assemble -> community -> assembleall) as run
#      "honest2", NOT waiting for the europe array (it does not need the new baseline until the final parity check)
#   [UNC_THROTTLE=100]  max band tasks at once
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs
EVE_R_MODULE="${EVE_R_MODULE:-GCC/13.3.0 OpenMPI/5.0.5 R/4.5.1 GDAL/3.10.3 CMake ImageMagick/7.1.1-38 UDUNITS/2.2.28}"
if ! type module >/dev/null 2>&1; then echo "Run as:  bash --login cluster/rerun_after_climate_fix.sh" >&2; exit 1; fi
module load ${EVE_R_MODULE}
export BIRDMONITOR_RUNNAME="${BIRDMONITOR_RUNNAME:-test4}"
RUN="${BIRDMONITOR_RUNNAME}"
OLD="outputs/${RUN}/uncertainty_honest"; NEW="outputs/${RUN}/uncertainty_honest2"

echo "=== 0a. R packages (ranger for the ensemble; matrixStats for the uncertainty; already installed ones are skipped)"
bash cluster/setup_uncertainty.sh || echo "WARNING: package setup failed -- the BRT-only rerun below does not need it, the ensemble does"

echo "=== 0. climate windows"
Rscript tools/checkClimateWindows.R || { echo "STOP: a climate window looks broken (see above). Nothing was submitted." >&2; exit 1; }

STALE="outputs/${RUN}/_old_before_climate_fix_2026-10-07"
mkdir -p "${STALE}"
echo "=== 0c. move aside (never delete) everything made with the buggy 2022-2025 climate"
# (a) the climate-scale predictions of the target years 2022-2025 (all species)
mkdir -p "${STALE}/scale_50"
for f in outputs/${RUN}/scale_50/*_pred_EU_202[2-5].tif; do if [ -e "${f}" ]; then mv "${f}" "${STALE}/scale_50/"; fi; done
# (b) the meta-models (their weights were trained on the buggy climate) and everything built from them: maps, indices, performance tables
for d in outputs/${RUN}/metamodel_* outputs/${RUN}/annual_report outputs/${RUN}/regional_index outputs/${RUN}/meta_check outputs/${RUN}/performance_table.csv; do
  if [ -e "${d}" ]; then mv "${d}" "${STALE}/"; echo "  moved ${d}"; fi
done
echo "  (the climate MODEL itself and its training table are NOT affected: trained on the atlas window 2012-2017)"

echo "=== 1. copy replicate models etc. -> ${NEW}"
if [ -d "${OLD}" ]; then
  for d in "${OLD}"/*/; do
    sp=$(basename "${d}"); [ -d "${d}/models" ] || continue
    mkdir -p "${NEW}/${sp}"
    if [ -e "${NEW}/${sp}/models" ]; then echo "  ${sp}: already copied"; continue; fi
    cp -a "${d}/models" "${d}/coarse" "${d}/blocksize.rds" "${d}/replicate_log.csv" "${NEW}/${sp}/"
    # the copied coarse CLIMATE predictions of 2022-2025 came from the buggy windows: move the COPIES aside (the step would also recompute them)
    mkdir -p "${NEW}/${sp}/_old_climate_bug"
    for f in "${NEW}/${sp}"/coarse/*/climate_202[2-5].tif; do if [ -e "${f}" ]; then mv "${f}" "${NEW}/${sp}/_old_climate_bug/"; fi; done
    echo "  ${sp}: copied"
  done
  # the previous uncertainty run is contaminated as a whole (climate inputs, out-of-fold inputs, ridge weights, maps): put it aside
  if [ -d "${NEW}" ] && [ "$(ls -d ${NEW}/*/ 2>/dev/null | wc -l)" -ge 1 ]; then
    mv "${OLD}" "${STALE}/uncertainty_honest" && echo "  previous run ${OLD} moved to ${STALE}/"
  fi
elif [ -d "${NEW}" ]; then echo "  ${OLD} already moved aside; ${NEW} exists"; else echo "STOP: neither ${OLD} nor ${NEW} found" >&2; exit 1; fi

echo "=== 2./3. climate predictions + meta-model (europe array), then the baseline index"
eur=$(sbatch --parsable modules/models_Monitor/cluster/eve_array_europe.sbatch); echo "europe array: ${eur}"
# the meta-model does NOT start by itself after a rerun of the europe array (found 2026-10-08): submit its array explicitly
meta=$(sbatch --parsable --dependency=afterok:${eur} --array=1-11 modules/models_Monitor/cluster/eve_array_meta.sbatch); echo "meta-models:  ${meta}"
idx=$(sbatch --parsable --dependency=afterok:${meta} cluster/eve_index.sbatch); echo "index:        ${idx}"

echo "=== 4. uncertainty chain (run tag honest2)"
UNCOUT=$(BIRDMONITOR_UNC_TAG=honest2 UNC_THROTTLE="${UNC_THROTTLE:-100}" bash cluster/submit_eve_uncertainty.sh | tee /dev/stderr)
UNCIDS=$(echo "${UNCOUT}" | grep -E "^(covcache|prepare|band|summarize|assemble|community|assembleall):" | awk '{print $2}' | tr '\n' ' ')
echo
echo "================================================================================"
echo "SUBMITTED. What happens, in order:"
echo "  1. europe array ${eur}: corrected climate predictions (~10 min)"
echo "  2. meta-models ${meta}: honest weights per species (~15 min after 1)"
echo "  3. index ${idx}: baseline index on the corrected maps (~35 min after 2)"
echo "  4. uncertainty chain (${UNCIDS}): prepare (~1 h), then the band stage (the long part, ~10-13 h), then summaries"
echo
echo "CHECK AT ANY TIME (read-only; paste the output to me):"
echo "  cd ~/projects/birdMonitor && bash cluster/status.sh ${eur} ${meta} ${idx} ${UNCIDS}"
echo
echo "CHECK THE META-MODELS ~30 min from now (weights must be >= 0, 'out-of-fold inputs', honest AUC):"
echo "  for f in logs/meta_${meta}_*.err; do echo \"== \$f\"; grep -E 'Coefficients|Performance \\(' \"\$f\" | tail -2; done"
echo "CHECK THE INDEX when it is COMPLETED (peak memory):"
echo "  sacct -j ${idx} --format=JobID,State,Elapsed,MaxRSS,ReqMem | head -5"
echo "CHECK THE REPLICATE-0 PARITY when the whole chain is COMPLETED (every species must say RESULT: OK):"
echo "  grep -H RESULT outputs/${RUN}/uncertainty_honest2/*/parity_check.txt"
echo "================================================================================"
