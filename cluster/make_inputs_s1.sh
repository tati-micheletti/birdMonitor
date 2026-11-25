#!/bin/bash
# SERIES 1 (land use = HCTM 2005-2023, no conversion): build an INPUTS folder of its own, next to inputs/ and inputs_s2/, WITHOUT touching inputs/ (v3 and its finished uncertainty/regional outputs rely on it).
# Use it with  BIRDMONITOR_INPUT_ROOT=$PWD/inputs_s1  (read by runMe.R, runClusterTask.R, runUncertaintyTask.R, runEnsembleTask.R), via  SERIES1=1  in cluster/submit_eve_clean_run.sh.
#   * raw/*                      symbolic links to inputs/predictors/raw/* (raw is never written by the pipeline), land-use maps included (HCTM 2005-2023 are the classes; v202 2017-2021 give the hedges)
#   * processed/dem, and every processed layer that does NOT depend on land use: symbolic links; the ORIGINALS are made read-only (chmod a-w, reversible: chmod u+w), so an accidental write fails loudly
#   * processed land-use layers of the years 2005-2023 (landuse_*, unmapped_other_*, landscape_heterogeneity_*, with their markers) are COPIED with their dates kept (cp -p): they were made by the v3 run with the
#     HCTM-first rule (scheme tag "hctm-first|classes=HCTM_..."), so the preparation finds them valid (cache hit) and does not recompute them; the copy keeps the original untouched even if a step rewrites a file
#   * land-use layers of 2024-2025 (converted v302) are NOT copied: the HCTM series ends in 2023
#   * response/raw               link; response/processed is COPIED (the preparation rebuilds the occurrence tables in place); model_ready starts empty (rebuilt by the preparation)
# Refuses to run if the target exists.   bash cluster/make_inputs_s1.sh       (INPUTS_S1=... to put it elsewhere)
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="$PWD/inputs"; DST="${INPUTS_S1:-$PWD/inputs_s1}"
[ -d "${SRC}/predictors/processed" ] || { echo "STOP: ${SRC}/predictors/processed not found" >&2; exit 1; }
[ ! -e "${DST}" ] || { echo "STOP: ${DST} exists; remove it by hand if you really want to rebuild it" >&2; exit 1; }
miss=""; for y in $(seq 2005 2023); do [ -f "${SRC}/predictors/raw/landuse/HCTM_GER_${y}_rst_v101_COG.tif" ] || miss="${miss} ${y}"; done
[ -z "${miss}" ] || { echo "STOP: HCTM maps missing in ${SRC}/predictors/raw/landuse for:${miss}" >&2; exit 1; }
mkdir -p "${DST}/predictors/raw" "${DST}/predictors/processed" "${DST}/response" "${DST}/model_ready"
for d in "${SRC}"/predictors/raw/*; do ln -s "$d" "${DST}/predictors/raw/$(basename "$d")"; done
nl=0; nc=0; nf=0; noyear=""
for d in "${SRC}"/predictors/processed/*; do b=$(basename "$d")
  if [ ! -d "$d" ] || [ "$b" = "dem" ]; then ln -s "$d" "${DST}/predictors/processed/$b"; find -L "$d" -type f -exec chmod a-w {} +; continue; fi
  mkdir -p "${DST}/predictors/processed/$b"
  for f in "$d"/*; do fb=$(basename "$f")
    case "$fb" in
      landuse_*|unmapped_other_*|landscape_heterogeneity_*)
        yr=$(echo "$fb" | grep -oE '_(19|20)[0-9]{2}_' | head -1 | tr -d _)
        if [ -z "$yr" ]; then noyear="${noyear} ${b}/${fb}"
        elif [ "$yr" -le 2023 ]; then cp -p "$f" "${DST}/predictors/processed/$b/$fb"; nc=$((nc+1))
        else nf=$((nf+1)); fi;;
      *) ln -s "$f" "${DST}/predictors/processed/$b/$fb"; chmod a-w "$f"; nl=$((nl+1));;
    esac
  done
done
ln -s "${SRC}/response/raw" "${DST}/response/raw"
echo "copying response/processed ($(du -sh "${SRC}/response/processed" | cut -f1)) ..."; cp -r "${SRC}/response/processed" "${DST}/response/processed"
echo "inputs_s1 ready: ${DST}"
echo "  processed layers linked (read-only originals): ${nl};  land-use layers 2005-2023 copied: ${nc};  land-use layers of 2024-2025 left out: ${nf}"
[ -z "${noyear}" ] || echo "  NOTE: land-use-named files without a year in the name were NOT copied:${noyear}"
echo "  use:  SERIES1=1 BIRDMONITOR_RUNNAME=<new run> BIRDMONITOR_INPUT_ROOT=${DST} BIRDMONITOR_PREDICTION_YEARS=2005:2023 BIRDMONITOR_LANDSCAPE_YEARS=2005:2023 bash --login cluster/submit_eve_clean_run.sh"
