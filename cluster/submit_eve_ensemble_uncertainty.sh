#!/bin/bash
# The uncertainty workflow (spatial-block bootstrap, option B) with the ENSEMBLE inside every replicate.
#
# Every replicate refits ALL chosen members on its own block-bootstrap draw (BRT + GLM/GAM/RF/NN with their selected formula/settings fixed),
# averages them per scale, and trains its own ridge meta-model on out-of-fold inputs, exactly as the BRT-only run does. Everything lands in
# outputs/<run>/uncertainty_<ensTag>/ (default tag "ens" for brt,glm,gam,rf), so the BRT-only results are never touched.
#
# PREREQUISITES (all on EVE, in this order):
#   1. the members are fitted:      cluster/submit_eve_ensemble.sh   (model files <sp>_<algo>_<scale>.rds, out-of-fold files)
#   2. the BASELINE ensemble exists (ensemble maps + meta-model folder metamodel_<label>_<tag>), needed for the replicate-0 parity check
#   3. the habitat covariate cache exists (cluster/eve_unc_covcache.sbatch, done by the BRT-only uncertainty run)
#
#   ENS_MEMBERS=brt,glm,gam,rf   which models (default; any subset of brt glm gam rf nn)
#   ENS_BANDS=48                 number of bands (default 48: the ensemble predicts ~4-5x slower than the BRT alone, more bands = shorter tasks)
#   UNC_THROTTLE=100             max band tasks at once        UNC_AFTER=<job ids>   wait for these first
#   BIRDMONITOR_UNC_REPS=0:50    replicates (0 = the main models, the built-in parity check)
#     cd ~/projects/birdMonitor && bash --login cluster/submit_eve_ensemble_uncertainty.sh
set -euo pipefail
cd "$(dirname "$0")/.."
export BIRDMONITOR_UNC_MEMBERS="${ENS_MEMBERS:-brt,glm,gam,rf}"
export BIRDMONITOR_UNC_BANDS="${ENS_BANDS:-48}"
export UNC_THROTTLE="${UNC_THROTTLE:-100}"
export UNC_BAND_TIME="${UNC_BAND_TIME:-12:00:00}"
unset BIRDMONITOR_UNC_TAG || true      # the tag defaults to the ensemble's name
echo "Ensemble uncertainty run: members ${BIRDMONITOR_UNC_MEMBERS} | bands ${BIRDMONITOR_UNC_BANDS} | replicates ${BIRDMONITOR_UNC_REPS:-0:50}"
bash cluster/submit_eve_uncertainty.sh
