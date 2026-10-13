#!/bin/bash
# Copy the inputs and the results of birdMonitor from /work-style project folder to /data/birds (no backup on /work, files untouched for 60 days are deleted there).
# Safe by design: rsync only ADDS or UPDATES files in the destination, it never deletes anything (no --delete), and it can be run again to resume.
#
#   cd ~/projects/birdMonitor && git pull -q
#   1. MODE=sizes bash cluster/copy_to_data_birds.sh     (default; read-only: sizes, quota, free space)
#   2. MODE=dry   bash cluster/copy_to_data_birds.sh     (read-only: what would be copied, how many files and bytes)
#   3. sbatch cluster/eve_copy_data_birds.sbatch          (the real copy as a job; it sets MODE=copy CONFIRM=1)
#   4. MODE=verify bash cluster/copy_to_data_birds.sh    (read-only: anything still different between source and destination? the list must be empty)
#
# What is copied (each item is a folder under the repo root):
#   inputs/                  the master copy of all inputs (raw and processed rasters, response data, model-ready tables). COPY_INPUTS=0 skips it.
#   outputs/<run>/           baseline, BRT-only and big 5 results, models, out-of-fold inputs, ridge files, final maps, interval tables, the old
#                            block-fold sensitivity analysis (default run: test4)
#   logs/                    the job logs (the diagnostics refer to them)
# What is NOT copied by default (large and rebuildable, or only intermediate):
#   pred/        the per-replicate predictions (int16, about 8-12 GB per species and run): needed to ADD replicates or to build new summaries without
#                refitting. COPY_PRED=1 copies them too (decide after checking the sizes and the quota).
#   pieces/      band pieces of the summaries (intermediate)
#   covcache/    the 200 m habitat covariate stacks (rebuilt by the covcache job)
#
# Permissions: files get the group of /data/birds (eve_birds, setgid directory) and group read/write; no access for others. Owner and group of the source are not kept.
set -euo pipefail
cd "$(dirname "$0")/.."
RUN="${BIRDMONITOR_RUNNAME:-test4}"
DEST="${DEST:-/data/birds/birdMonitor}"
MODE="${MODE:-sizes}"
COPY_PRED="${COPY_PRED:-0}"
COPY_INPUTS="${COPY_INPUTS:-1}"

ITEMS=("outputs/${RUN}" "logs")
if [ "${COPY_INPUTS}" = "1" ]; then ITEMS=("inputs" "${ITEMS[@]}"); fi
EXC=(--exclude='pieces/' --exclude='covcache/' --exclude='*.part')
if [ "${COPY_PRED}" != "1" ]; then EXC+=(--exclude='pred/'); fi
RSYNC=(rsync -rltp --no-owner --no-group --chmod=Dug+rwx,Fug+rw,o-rwx "${EXC[@]}")

for it in "${ITEMS[@]}"; do [ -d "${it}" ] || { echo "STOP: ${it} not found (run this from the repo root on EVE)" >&2; exit 1; }; done
echo "Run: ${RUN} | destination: ${DEST} | mode: ${MODE} | per-replicate predictions: $([ "${COPY_PRED}" = "1" ] && echo copied || echo "NOT copied") | inputs: $([ "${COPY_INPUTS}" = "1" ] && echo copied || echo "NOT copied")"

case "${MODE}" in
  sizes)
    echo; echo "== quota and free space of /data/birds"
    cat /data/birds/quota.txt 2>/dev/null || echo "(no /data/birds/quota.txt)"
    df -h /data/birds | tail -1
    echo; echo "== size of each item, everything (this can take a few minutes)"
    for it in "${ITEMS[@]}"; do du -sh "${it}" 2>/dev/null || true; done
    echo; echo "== size of what would be copied with the current settings (without pred/, pieces/, covcache/ unless COPY_PRED=1)"
    for it in "${ITEMS[@]}"; do
      if [ "${COPY_PRED}" = "1" ]; then du -sh --exclude=pieces --exclude=covcache "${it}" 2>/dev/null || true
      else du -sh --exclude=pred --exclude=pieces --exclude=covcache "${it}" 2>/dev/null || true; fi
    done
    echo; echo "== the per-replicate predictions (pred/), per run folder"
    du -sch outputs/${RUN}/uncertainty*/*/pred 2>/dev/null | tail -1 || true
    for u in outputs/${RUN}/uncertainty*/; do echo "  $(du -sch "${u}"*/pred 2>/dev/null | tail -1 | cut -f1)  ${u}"; done
    echo; echo "== number of files (the quota counts files too)"
    for it in "${ITEMS[@]}"; do echo "  $(find "${it}" -type f 2>/dev/null | wc -l)  ${it}"; done
    ;;
  dry)
    for it in "${ITEMS[@]}"; do
      echo; echo "== would copy: ${it} -> ${DEST}/"
      "${RSYNC[@]}" -n --stats --human-readable "${it}" "${DEST}/" | grep -E "Number of (regular )?files|Total file size|Total transferred file size" || true
    done
    ;;
  copy)
    if [ "${CONFIRM:-0}" != "1" ]; then echo "STOP: the real copy needs CONFIRM=1 (the sbatch file sets it). Do a dry run first." >&2; exit 1; fi
    mkdir -p "${DEST}"
    [ -w "${DEST}" ] || { echo "STOP: ${DEST} is not writable for ${USER}" >&2; exit 1; }
    for it in "${ITEMS[@]}"; do
      echo; echo "== $(date '+%F %T') copying ${it} -> ${DEST}/"
      "${RSYNC[@]}" --partial --human-readable --info=stats2,progress2 "${it}" "${DEST}/"
    done
    echo; echo "== $(date '+%F %T') finished. Check with: MODE=verify bash cluster/copy_to_data_birds.sh"
    ;;
  verify)
    bad=0
    for it in "${ITEMS[@]}"; do
      echo; echo "== differences (size or time) between ${it} and ${DEST}/${it} (the list must be empty)"
      out=$("${RSYNC[@]}" -n --itemize-changes "${it}" "${DEST}/" | grep -v '^\.d' | head -50 || true)
      if [ -n "${out}" ]; then echo "${out}"; bad=1; else echo "none"; fi
      echo "  files: source $(find "${it}" -type f ! -path '*/pred/*' ! -path '*/pieces/*' ! -path '*/covcache/*' 2>/dev/null | wc -l) | destination $(find "${DEST}/${it}" -type f 2>/dev/null | wc -l)  (equal when the pred/ setting matches)"
    done
    [ "${bad}" = "0" ] && echo && echo "VERIFY: everything that should be copied is there." || echo && echo "VERIFY: differences found; run the copy job again (it resumes)."
    ;;
  *) echo "MODE must be sizes, dry, copy or verify" >&2; exit 1;;
esac
