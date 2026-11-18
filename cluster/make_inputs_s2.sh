#!/bin/bash
# SERIES 2 (land use = CTM v302 from ThEO, 2017-2025, no recode): build an INPUTS folder of its own, next to inputs/, WITHOUT copying the big data.
# Use it with  BIRDMONITOR_INPUT_ROOT=$PWD/inputs_s2  (read by runMe.R, runClusterTask.R, runUncertaintyTask.R, runEnsembleTask.R).
#   * raw/*                      symbolic links to inputs/predictors/raw/* (raw is never written by the pipeline); raw/landuse -> the nine ThEO v302 files
#   * processed/dem, and every processed layer that does NOT depend on land use (landcover, dist_to_woodland, slope, elevation, solar radiation, with their markers)
#                                symbolic links; the ORIGINALS are made read-only (chmod a-w, reversible: chmod u+w), so an accidental write fails loudly instead of changing inputs/
#   * processed land-use layers (landuse_*, unmapped_other_*, landscape_heterogeneity_*, with their markers) are NOT linked: Series 2 makes its own
#   * response/raw               link; response/processed is COPIED (the preparation rebuilds the occurrence tables in place); model_ready starts empty (rebuilt by the preparation)
# Nothing in inputs/ is changed except the read-only flag on the linked files. Refuses to run if the target exists.
#   bash cluster/make_inputs_s2.sh            (INPUTS_S2=... to put it elsewhere; LU_DIR=... for another land-use folder)
set -euo pipefail
cd "$(dirname "$0")/.."
SRC="$PWD/inputs"; DST="${INPUTS_S2:-$PWD/inputs_s2}"; LU="${LU_DIR:-$SRC/predictors/raw/landuse_theo_v302}"
[ -d "${SRC}/predictors/processed" ] || { echo "STOP: ${SRC}/predictors/processed not found" >&2; exit 1; }
[ ! -e "${DST}" ] || { echo "STOP: ${DST} exists; remove it by hand if you really want to rebuild it" >&2; exit 1; }
n=$(ls "${LU}"/CTM_GER_20{17,18,19,20,21,22,23,24,25}_rst_v302_COG.tif 2>/dev/null | wc -l); [ "${n}" = "9" ] || { echo "STOP: ${LU} does not hold the nine v302 files (found ${n})" >&2; exit 1; }
mkdir -p "${DST}/predictors/raw" "${DST}/predictors/processed" "${DST}/response" "${DST}/model_ready"
for d in "${SRC}"/predictors/raw/*; do b=$(basename "$d"); case "$b" in landuse|landuse_theo_v302) ;; *) ln -s "$d" "${DST}/predictors/raw/$b";; esac; done
ln -s "${LU}" "${DST}/predictors/raw/landuse"
nl=0; nf=0
for d in "${SRC}"/predictors/processed/*; do b=$(basename "$d")
  if [ ! -d "$d" ] || [ "$b" = "dem" ]; then ln -s "$d" "${DST}/predictors/processed/$b"; find -L "$d" -type f -exec chmod a-w {} +; continue; fi
  mkdir -p "${DST}/predictors/processed/$b"
  for f in "$d"/*; do fb=$(basename "$f")
    case "$fb" in landuse_*|unmapped_other_*|landscape_heterogeneity_*) nf=$((nf+1));; *) ln -s "$f" "${DST}/predictors/processed/$b/$fb"; chmod a-w "$f"; nl=$((nl+1));; esac
  done
done
mkdir -p "${DST}/response"; ln -s "${SRC}/response/raw" "${DST}/response/raw"
echo "copying response/processed ($(du -sh "${SRC}/response/processed" | cut -f1)) ..."; cp -r "${SRC}/response/processed" "${DST}/response/processed"
echo "inputs_s2 ready: ${DST}"; echo "  processed layers linked (read-only originals): ${nl}; land-use-derived files left out (Series 2 makes them): ${nf}"
echo "  use:  export BIRDMONITOR_INPUT_ROOT=${DST}"
