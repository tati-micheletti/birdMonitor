#!/bin/bash
# B of the 2026 update (2026-11-26): the REFIT of Series 2 (ThEO CTM v302) with the new bird data, predicting 2017-2026, as a new run folder s2v3. One command; DRY_RUN=1 checks and prints the chain only.
#   cd ~/projects/birdMonitor && DRY_RUN=1 bash --login cluster/submit_s2v3_refit.sh        # checks + chain, submits nothing
#   cd ~/projects/birdMonitor && bash --login cluster/submit_s2v3_refit.sh                  # the real thing (about 4 days; no git pull while it runs)
# What differs from the s2v2 settings (everything else is the Series 2 chain of cluster/submit_eve_clean_run.sh):
#   inputs_s2b            own inputs folder (the preparation rewrites the training tables in place; A relies on the unchanged ones of inputs_s2)  [cluster/make_inputs_s2.sh with S2_COPY_LANDUSE_FROM=inputs_s2]
#   years                 prediction, landscape and habitat fitting years 2017:2026
#   BIRDMONITOR_MHB_FILE  the cleaned MhB export of 13 Nov 2026 (habitat scale, and Buteo/Sturnus at the landscape scale)
#   BIRDMONITOR_DDA_NEW   the validated 2025-2026 DDA territories of 10 species, appended to the two xlsx tables (the surveyed route-years of 2025-2026 are a proxy, see DECISIONS.md 2026-11-26)
#   BIRDMONITOR_YEARS_OVERLAY  data/yearsOverlay_update2026.csv: MhB years to 2026, species without new territories end at 2024 at the landscape scale
#   BRT_SCALES            europe habitat landscape: the climate-scale BRT is in the chain (the Series 2 default skips it, but the 2026 climate map must be made)
# 2026 climate = the flagged copy of the 2025 layer (sharedClimateLastYear); 2026 land use = the in-season map to September 2026 (findCtmFile).
set -euo pipefail
cd "$(dirname "$0")/.."
[ -d inputs_s2b/predictors/processed ] || { echo "STOP: inputs_s2b not found: INPUTS_S2=\$PWD/inputs_s2b S2_COPY_LANDUSE_FROM=\$PWD/inputs_s2 bash cluster/make_inputs_s2.sh" >&2; exit 1; }
for f in response/raw/MhB/dbird/observations_cbbm_flat.csv response/raw/MhB/dbird/territories_cbbm.csv; do [ -f "inputs/${f}" ] || { echo "STOP: inputs/${f} not found (DDA export of 13 Nov 2026)" >&2; exit 1; }; done
export SERIES2=1 FORCE="${FORCE:-1}" BRT_SCALES="europe habitat landscape" BIRDMONITOR_RUNNAME="${BIRDMONITOR_RUNNAME:-s2v3}" BIRDMONITOR_INPUT_ROOT="$PWD/inputs_s2b"
export BIRDMONITOR_PREDICTION_YEARS=2017:2026 BIRDMONITOR_LANDSCAPE_YEARS=2017:2026 BIRDMONITOR_HABITAT_YEARS=2017:2026
export BIRDMONITOR_MHB_FILE=response/raw/MhB/dbird/observations_cbbm_flat.csv BIRDMONITOR_DDA_NEW=response/raw/MhB/dbird/territories_cbbm.csv BIRDMONITOR_YEARS_OVERLAY=data/yearsOverlay_update2026.csv
exec bash --login cluster/submit_eve_clean_run.sh
