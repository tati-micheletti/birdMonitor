#!/bin/bash
# A of the 2026 update (2026-11-26): ADD 2026 to Series 2 with the models of s2v2 as they are (nothing is refitted), in the COPY of the finished run: outputs/s2v2_2026 (cluster/eve_copy_run.sbatch).
# It is the standard Series 2 chain (cluster/submit_eve_clean_run.sh) resumed on the copy, with BIRDMONITOR_REUSE_MODELS=1: the landscape and habitat BRT predict with the STORED models (a refit is not reproducible),
# the ensemble members, the meta-model weights and the 25 replicate models are read back ("exists -- skipping"), the cached band pieces of the earlier years are kept, and only 2026 is new.
# Verified on Alauda arvensis (2026-11-26): 2017-2025 bit-identical at every level (BRT, ensemble means, meta-model maps, area means of the 25 replicates, uncertainty maps), 2026 looks like any other year.
# Prerequisites (done for 2026): the copy of the run folder, the 2026 layers in inputs_s2 (land use per scale: cluster/eve_landuse_year.sbatch, then cluster/eve_rasters.sbatch), the habitat covariate stack (covcache step of the chain).
#   cd ~/projects/birdMonitor && DRY_RUN=1 bash --login cluster/submit_s2v2_add2026.sh        # checks + chain, submits nothing
#   cd ~/projects/birdMonitor && bash --login cluster/submit_s2v2_add2026.sh                  # the real thing (no git pull while it runs)
# The climate-scale BRT (europe array) is fitted again: it reproduced the original exactly for Alauda; the maps of 2017-2025 of every species should be compared with s2v2 afterwards.
set -euo pipefail
cd "$(dirname "$0")/.."
[ -d outputs/s2v2_2026/scale_50 ] || { echo "STOP: outputs/s2v2_2026 not found (cluster/eve_copy_run.sbatch with SRC_RUN=s2v2 DST_RUN=s2v2_2026)" >&2; exit 1; }
[ -f inputs_s2/predictors/processed/scale_50/bioclim_2021-2026_scale_50.tif ] || { echo "STOP: the 2026 climate layer is not in inputs_s2 (cluster/eve_rasters.sbatch)" >&2; exit 1; }
export SERIES2=1 RESUME=1 SKIP_PREP=1 FORCE="${FORCE:-1}" BRT_SCALES="europe habitat landscape" BIRDMONITOR_RUNNAME=s2v2_2026 BIRDMONITOR_INPUT_ROOT="$PWD/inputs_s2"
export BIRDMONITOR_PREDICTION_YEARS=2017:2026 BIRDMONITOR_LANDSCAPE_YEARS=2017:2025 BIRDMONITOR_HABITAT_YEARS=2017:2025 BIRDMONITOR_REUSE_MODELS=1
exec bash --login cluster/submit_eve_clean_run.sh
