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

echo "=== 1. copy replicate models etc. -> ${NEW}"
[ -d "${OLD}" ] || { echo "STOP: ${OLD} not found" >&2; exit 1; }
for d in "${OLD}"/*/; do
  sp=$(basename "${d}"); [ -d "${d}/models" ] || continue
  mkdir -p "${NEW}/${sp}"
  if [ -e "${NEW}/${sp}/models" ]; then echo "  ${sp}: already copied"; continue; fi
  cp -a "${d}/models" "${d}/coarse" "${d}/blocksize.rds" "${d}/replicate_log.csv" "${NEW}/${sp}/"
  echo "  ${sp}: copied"
done

echo "=== 2./3. climate predictions + meta-model (europe array), then the baseline index"
eur=$(sbatch --parsable modules/models_Monitor/cluster/eve_array_europe.sbatch); echo "europe array: ${eur}"
idx=$(sbatch --parsable --dependency=afterok:${eur} cluster/eve_index.sbatch); echo "index:        ${idx}"

echo "=== 4. uncertainty chain (run tag honest2)"
BIRDMONITOR_UNC_TAG=honest2 UNC_THROTTLE="${UNC_THROTTLE:-100}" bash cluster/submit_eve_uncertainty.sh
echo
echo "Submitted. Check later with the status block I give you; the baseline maps and index come first (about an hour), the uncertainty layers after about 10-13 h."
