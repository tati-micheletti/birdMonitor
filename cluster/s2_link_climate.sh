#!/bin/bash
# SERIES 2: the climate scale does NOT depend on the crop layers, so it is not recomputed: copy (never link, never write back) what the climate scale has already made in the finished run
# into the new run folder, where the ensemble / meta-model / uncertainty steps find it. The uncertainty steps skip every replicate file that already exists ("exists -- skipping").
#   bash cluster/s2_link_climate.sh <new run> [<tag>] [<source run, default v3>]
#   copies: outputs/<src>/scale_50                                            (climate BRT + ensemble members, maps of all years; ~200 MB)
#           outputs/<src>/uncertainty_<tag>/<Species>/models/climate_*        (the 25 replicate climate fits, all members)
#           outputs/<src>/uncertainty_<tag>/<Species>/coarse/reps_*/climate_* (their coarse predictions)
set -euo pipefail
cd "$(dirname "$0")/.."
RUN="${1:?new run name}"; TAG="${2:-ens_brt-glm-gam-rf-nn}"; SRC="${3:-v3}"
[ -d "outputs/${SRC}/scale_50" ] || { echo "STOP: outputs/${SRC}/scale_50 not found" >&2; exit 1; }
[ -d "outputs/${RUN}" ] || mkdir -p "outputs/${RUN}"
[ -e "outputs/${RUN}/scale_50" ] && { echo "STOP: outputs/${RUN}/scale_50 exists already" >&2; exit 1; }
cp -r "outputs/${SRC}/scale_50" "outputs/${RUN}/scale_50"
U="uncertainty_${TAG}"; n=0; m=0
for d in outputs/${SRC}/${U}/*/; do sp=$(basename "$d")
  [ -d "${d}models" ] || continue
  mkdir -p "outputs/${RUN}/${U}/${sp}/models"
  for f in "${d}models"/climate_*; do [ -e "$f" ] && { cp -n "$f" "outputs/${RUN}/${U}/${sp}/models/"; n=$((n+1)); }; done
  for c in "${d}coarse"/reps_*/; do [ -d "$c" ] || continue; rl=$(basename "$c"); mkdir -p "outputs/${RUN}/${U}/${sp}/coarse/${rl}"
    for f in "$c"climate_*; do [ -e "$f" ] && { cp -n "$f" "outputs/${RUN}/${U}/${sp}/coarse/${rl}/"; m=$((m+1)); }; done; done
done
echo "climate pieces copied into outputs/${RUN}: scale_50, ${n} replicate model files, ${m} coarse prediction files"
