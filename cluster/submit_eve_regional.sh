#!/bin/bash
# Submit the regional-index uncertainty chain (10/20/50 km grids) to EVE.
#
#   regionband [species x band]  -> regionassemble [species]  -> regionindex (once)
#                                                             -> assembleAll again, with the GERMAN-only area means (annual_report_germany/)
#                                                                -> maskmaps: Germany-only copies of the finished maps (maps_germany/, community_germany/)
#
# It reads the stored per-replicate predictions of the uncertainty run, so the band stage (cluster/submit_eve_uncertainty.sh) must have
# finished, or be named in UNC_AFTER. Nothing is refitted and nothing of the running chain is touched.
#
#   BIRDMONITOR_UNC_TAG=honest2   the uncertainty run folder (outputs/<run>/uncertainty_<tag>); same value as for the main chain
#   [UNC_AFTER=63119392]          job id(s) to wait for first (the band job), colon-separated
#   [UNC_FINAL=63119396]          the main chain's last job (assembleall): the Germany-only re-run of assembleAll waits for it, so they never write at once
#   [UNC_THROTTLE=100]            max band tasks running at once
#   [BIRDMONITOR_RUNNAME=test4] [BIRDMONITOR_UNC_REPS=0:50] [BIRDMONITOR_UNC_YEARS=...] [BIRDMONITOR_UNC_BANDS=16]   as in submit_eve_uncertainty.sh
#     BIRDMONITOR_UNC_TAG=honest2 UNC_AFTER=<band job id> bash --login cluster/submit_eve_regional.sh
#
# Check afterwards: outputs/<run>/uncertainty_<tag>/regional/regional_parity_<km>km.txt (every grid: RESULT: OK).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs
# refuse to run twice: a second submission writes the same files at the same time (happened 2026-10-08)
if [ "${FORCE:-0}" != "1" ] && squeue -u "${USER}" -h -o "%j" | grep -qE "^unc-regionband|unc-regionassemble|unc-regionindex|unc-maskmaps$"; then
  echo "STOP: jobs of this workflow are already in the queue (see: squeue -u ${USER}). Submitting again would make two runs write the same files." >&2
  echo "      If you are sure, run it again with FORCE=1 in front of the command." >&2
  exit 1
fi
EVE_R_MODULE="${EVE_R_MODULE:-GCC/13.3.0 OpenMPI/5.0.5 R/4.5.1 GDAL/3.10.3 CMake ImageMagick/7.1.1-38 UDUNITS/2.2.28}"
if ! type module >/dev/null 2>&1; then echo "The 'module' command is missing. Run this script as:  bash --login cluster/submit_eve_regional.sh" >&2; exit 1; fi
module load ${EVE_R_MODULE}
export BIRDMONITOR_RUNNAME="${BIRDMONITOR_RUNNAME:-test4}"
export BIRDMONITOR_UNC_REPS="${BIRDMONITOR_UNC_REPS:-0:50}"
export BIRDMONITOR_UNC_BANDS="${BIRDMONITOR_UNC_BANDS:-16}"
EXPORTS="ALL"
NSP=$(Rscript -e 'source("tools/sharedConfig.R"); cat(length(sharedSpecies))' 2>/dev/null | tail -1)
NB="${BIRDMONITOR_UNC_BANDS}"; NSB=$((NSP * NB))
echo "Run: ${BIRDMONITOR_RUNNAME} | tag: ${BIRDMONITOR_UNC_TAG:-<none>} | species ${NSP} | band tasks ${NSB}"
AFTER=(); if [ -n "${UNC_AFTER:-}" ]; then AFTER=(--dependency=afterok:"${UNC_AFTER}"); fi
THR=""; if [ -n "${UNC_THROTTLE:-}" ]; then THR="%${UNC_THROTTLE}"; fi
rb=$(sbatch --parsable --export=${EXPORTS} --array=1-${NSB}${THR} "${AFTER[@]+"${AFTER[@]}"}" --kill-on-invalid-dep=yes cluster/eve_unc_regionband.sbatch)
echo "regionband:     ${rb}"
ra=$(sbatch --parsable --export=${EXPORTS} --array=1-${NSP} --dependency=afterok:${rb} --kill-on-invalid-dep=yes cluster/eve_unc_regionassemble.sbatch)
echo "regionassemble: ${ra}"
ri=$(sbatch --parsable --export=${EXPORTS} --dependency=afterok:${ra} --kill-on-invalid-dep=yes cluster/eve_unc_regionindex.sbatch)
echo "regionindex:    ${ri}"
asm2=$(sbatch --parsable --export=ALL,BIRDMONITOR_UNC_AREAMEAN=area_mean_replicates_germany.csv,BIRDMONITOR_INDEX_TAG=germany --dependency=afterok:${ra}${UNC_FINAL:+:${UNC_FINAL}} --kill-on-invalid-dep=yes cluster/eve_unc_assembleall.sbatch)
echo "assembleAll (Germany-only area means): ${asm2}"
mm=$(sbatch --parsable --export=ALL --array=1-$((NSP + 1)) --dependency=afterok:${asm2} --kill-on-invalid-dep=yes cluster/eve_unc_maskmaps.sbatch)
echo "maskmaps:       ${mm}"
echo
echo "Submitted. Logs in ./logs/unc-region*"
echo "CHECK AT ANY TIME (read-only):  cd ~/projects/birdMonitor && bash cluster/status.sh ${rb} ${ra} ${ri} ${asm2} ${mm}"
echo "CHECK THE PARITY when everything is COMPLETED (every grid: RESULT: OK):  cat outputs/${BIRDMONITOR_RUNNAME}/uncertainty${BIRDMONITOR_UNC_TAG:+_${BIRDMONITOR_UNC_TAG}}/regional/regional_parity_*km.txt"
