#!/bin/bash
# READ-ONLY (creates one .tar file, changes nothing else): packs what you need on your own computer to (1) have a second copy of the results and
# (2) regenerate every figure and number of the Steering Consortium material.
#   bash --login cluster/pack_downloads.sh sizes      how big is each package (nothing is written)
#   bash --login cluster/pack_downloads.sh A          small package: all tables, figures, indices, regional rasters, accuracy files (download this first)
#   bash --login cluster/pack_downloads.sh B          maps: final probability maps (Germany), per-pixel change/trend/uncertainty maps, community and change maps
#   bash --login cluster/pack_downloads.sh C          the fitted models (.rds) of every scale and algorithm, to be able to re-predict
# Not packed on purpose (huge, regenerable, and already in /data/birds/birdMonitor if you copied it): pred/, coarse/, oof/, pieces/, covcache/.
# The .tar files go to /work/$USER/birdMonitor/download/ (override: PACK_OUT=...). Download them with WinSCP, then unpack on your computer
# (7-Zip, or `tar -xf <file>` in a folder of your choice); the folder structure inside is the same as in the repository (outputs/<run>/...).
set -euo pipefail
MODE="${1:-sizes}"
RUN="${BIRDMONITOR_RUNNAME:-test4}"
ENS="${BIRDMONITOR_ENS_TAG:-ens_brt-glm-gam-rf-nn}"
UNC_BRT="${BIRDMONITOR_UNC_TAG:-honest2}"
ROOT="${PACK_ROOT:-$(cd "$(dirname "$0")/.." && pwd)}"
OUT="${PACK_OUT:-/work/${USER}/birdMonitor/download}"
cd "$ROOT"
shopt -s nullglob
O="outputs/${RUN}"

emit() { for p in "$@"; do [ -e "$p" ] && echo "$p"; done; return 0; }      # print the paths that exist

listA() {
  emit "$O/figures_fullreport" "$O/performance_table.csv" "$O/meta_check"
  emit data/speciesCanonical.csv inputs/predictors/raw/gadm logs/meta_*.err
  for tag in "" "_${ENS}"; do
    emit "$O/annual_report${tag}_germany"/*.csv "$O/annual_report${tag}_germany"/*.txt
    emit "$O/regional_index${tag}_germany"/*.tif
    emit "$O/metamodel_02_1_50${tag}"/*_perf_meta.rds "$O/metamodel_02_1_50${tag}"/*_varimp_meta.rds "$O/metamodel_02_1_50${tag}"/*_ridge_meta.rds "$O/metamodel_02_1_50${tag}"/*_meta_ridgeid.txt
  done
  for sd in $(cd "$O" 2>/dev/null && ls -d scale_* 2>/dev/null); do emit "$O/$sd"/*_perf_*.rds "$O/$sd"/*_expl_dev_*.rds; done
  for u in "uncertainty_${UNC_BRT}" "uncertainty_${ENS}"; do
    emit "$O/$u"/*.csv "$O/$u"/regional "$O/$u"/*.txt
    for d in "$O/$u"/*/; do emit "$d"area_mean_replicates*.csv "$d"species_index_uncertainty.csv "$d"replicate_log.csv "$d"parity_check.txt "$d"blocksize.rds "$d"run_info_*.txt "$d"ridge "$d"refit_fallbacks.csv "$d"models/refit_fallbacks.csv; done
  done
}
listB() {
  for tag in "" "_${ENS}"; do
    emit "$O/metamodel_02_1_50${tag}_germany" "$O/pixel_trend_test_brt" "$O/pixel_trend_test_big5"
    emit "$O/annual_report${tag}_germany"/*.tif
  done
  for u in "uncertainty_${UNC_BRT}" "uncertainty_${ENS}"; do
    emit "$O/$u/community_germany"
    for d in "$O/$u"/*/; do emit "${d}maps_germany"; done
  done
  for sd in $(cd "$O" 2>/dev/null && ls -d scale_* 2>/dev/null); do emit "$O/$sd"/*_pred_*_2025.tif "$O/$sd"/*_sd_*_2025.tif; done
}
listC() {
  for sd in $(cd "$O" 2>/dev/null && ls -d scale_* 2>/dev/null); do emit "$O/$sd"/*.rds; done
  for tag in "" "_${ENS}"; do emit "$O/metamodel_02_1_50${tag}"/*.rds; done
}

list() { case "$1" in A) listA ;; B) listB ;; C) listC ;; *) echo "unknown package $1" >&2; exit 1 ;; esac | sort -u; }

case "$MODE" in
  sizes)
    for k in A B C; do
      n=$(list "$k" | wc -l); s=$(list "$k" | tr '\n' '\0' | du -ch --files0-from=- 2>/dev/null | tail -1 | cut -f1)
      echo "package $k: $n items, about $s"
    done
    echo "(sizes are before packing; the .tar has the same size. Package A first, then B if you have room.)" ;;
  A|B|C)
    mkdir -p "$OUT"; f="$OUT/figures_${MODE}_${RUN}.tar"; list "$MODE" > "$OUT/figures_${MODE}_${RUN}.list.txt"
    [ -s "$OUT/figures_${MODE}_${RUN}.list.txt" ] || { echo "nothing found for package $MODE" >&2; exit 1; }
    tar -cf "$f" -T "$OUT/figures_${MODE}_${RUN}.list.txt"
    echo "wrote $f ($(du -h "$f" | cut -f1)); contents listed in $OUT/figures_${MODE}_${RUN}.list.txt" ;;
  *) echo "usage: bash cluster/pack_downloads.sh sizes|A|B|C" >&2; exit 1 ;;
esac
