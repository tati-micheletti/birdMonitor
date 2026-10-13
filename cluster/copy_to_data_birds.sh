#!/bin/bash
# Copy the inputs and the results of birdMonitor to /data/birds (the project folder on /work has no backup; files untouched for 60 days are deleted there).
# Safe by design: rsync only ADDS or UPDATES files in the destination, it never deletes anything (no --delete), and it can be run again to resume.
#
#   cd ~/projects/birdMonitor && git pull -q
#   1. MODE=dry   bash cluster/copy_to_data_birds.sh     (read-only: where each item really is, how many files and bytes would be copied)
#   2. sbatch cluster/eve_copy_data_birds.sbatch          (the real copy as a job; it sets MODE=copy CONFIRM=1)
#   3. MODE=verify bash cluster/copy_to_data_birds.sh    (read-only: anything still different between source and destination? the list must be empty)
#   (MODE=sizes bash cluster/copy_to_data_birds.sh shows quota, free space and the size of every item)
#
# What is copied (each item is a folder under the repo root; a folder that is a symbolic link is followed to its real place):
#   inputs/                  the master copy of all inputs. COPY_INPUTS=0 skips it.
#   outputs/<run>/           baseline, BRT-only and big 5 results (default run: test4)
#   logs/                    the job logs
# What is NOT copied by default (large and rebuildable, or only intermediate):
#   pred/        the per-replicate predictions, in outputs/<run>/uncertainty*/<Species>/pred/ . COPY_PRED=1 copies them too.
#   pieces/      band pieces of the summaries, in outputs/<run>/uncertainty*/<Species>/pieces/ and .../community/pieces/
#   covcache/    the 200 m habitat covariate stacks, in outputs/<run>/uncertainty/covcache/
#
# Result in the destination: /data/birds/birdMonitor/inputs, /data/birds/birdMonitor/outputs/<run>, /data/birds/birdMonitor/logs
# Permissions: files get the group of /data/birds (eve_birds, setgid directory) and group read/write; no access for others. Owner and group of the source are not kept.
# Symbolic links inside a folder: links that point outside the folder are replaced by a copy of what they point to (--copy-unsafe-links); the dry run shows the effect on the size.
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
DUEXC=(--exclude=pieces --exclude=covcache)
if [ "${COPY_PRED}" != "1" ]; then EXC+=(--exclude='pred/'); DUEXC+=(--exclude=pred); fi
RSYNC=(rsync -rltp --copy-unsafe-links --no-owner --no-group --chmod=Dug+rwx,Fug+rw,o-rwx "${EXC[@]}")

declare -A SRC
for it in "${ITEMS[@]}"; do
  [ -e "${it}" ] || { echo "STOP: ${it} not found (run this from the repo root on EVE)" >&2; exit 1; }
  SRC[${it}]="$(readlink -f "${it}")"
  [ -d "${SRC[${it}]}" ] || { echo "STOP: ${it} does not lead to a folder (${SRC[${it}]})" >&2; exit 1; }
done
echo "Run: ${RUN} | destination: ${DEST} | mode: ${MODE} | per-replicate predictions: $([ "${COPY_PRED}" = "1" ] && echo copied || echo "NOT copied") | inputs: $([ "${COPY_INPUTS}" = "1" ] && echo copied || echo "NOT copied")"
echo "Where each item really is:"; for it in "${ITEMS[@]}"; do echo "  ${it}  ->  ${SRC[${it}]}"; done

case "${MODE}" in
  sizes)
    echo; echo "== quota and free space of /data/birds"
    cat /data/birds/quota.txt 2>/dev/null || echo "(no /data/birds/quota.txt)"
    df -h /data/birds | tail -1
    echo; echo "== size of what would be copied with the current settings (this can take a few minutes)"
    for it in "${ITEMS[@]}"; do echo "  $(du -sh "${DUEXC[@]}" "${SRC[${it}]}" 2>/dev/null | cut -f1)  ${it}"; done
    echo; echo "== size of the per-replicate predictions (pred/), per uncertainty folder"
    for u in outputs/${RUN}/uncertainty*/; do echo "  $(du -sch "${u}"*/pred 2>/dev/null | tail -1 | cut -f1)  ${u}"; done
    echo; echo "== number of files (the quota counts files too)"
    for it in "${ITEMS[@]}"; do echo "  $(find "${SRC[${it}]}" -type f 2>/dev/null | wc -l)  ${it}"; done
    ;;
  dry)
    TMPD="$(mktemp -d "${TMPDIR:-/tmp}/copy_dry_XXXXXX")"
    for it in "${ITEMS[@]}"; do
      echo; echo "== ${it}: symbolic links inside: $(find "${SRC[${it}]}" -type l 2>/dev/null | wc -l)"
      echo "== would copy ${SRC[${it}]}/ -> ${DEST}/${it}/ (compared with an empty folder, so these are the totals)"
      "${RSYNC[@]}" -n --stats --human-readable "${SRC[${it}]}/" "${TMPD}/${it##*/}/" | grep -E "Number of (regular )?files|Total file size|Total transferred file size" || true
    done
    rm -rf "${TMPD}"
    ;;
  copy)
    if [ "${CONFIRM:-0}" != "1" ]; then echo "STOP: the real copy needs CONFIRM=1 (the sbatch file sets it). Do a dry run first." >&2; exit 1; fi
    for it in "${ITEMS[@]}"; do
      mkdir -p "${DEST}/${it}"
      [ -w "${DEST}/${it}" ] || { echo "STOP: ${DEST}/${it} is not writable for ${USER}" >&2; exit 1; }
      echo; echo "== $(date '+%F %T') copying ${SRC[${it}]}/ -> ${DEST}/${it}/"
      "${RSYNC[@]}" --partial --human-readable --info=stats2,progress2 "${SRC[${it}]}/" "${DEST}/${it}/"
    done
    echo; echo "== $(date '+%F %T') finished. Check with: MODE=verify bash cluster/copy_to_data_birds.sh"
    ;;
  verify)
    bad=0
    for it in "${ITEMS[@]}"; do
      echo; echo "== differences (size or time) between ${it} and ${DEST}/${it} (the list must be empty)"
      [ -d "${DEST}/${it}" ] || { echo "MISSING: ${DEST}/${it}"; bad=1; continue; }
      out=$("${RSYNC[@]}" -n --itemize-changes "${SRC[${it}]}/" "${DEST}/${it}/" | grep -v '^\.d' | head -50 || true)
      if [ -n "${out}" ]; then echo "${out}"; bad=1; else echo "none"; fi
    done
    if [ "${bad}" = "0" ]; then echo; echo "VERIFY: everything that should be copied is there."; else echo; echo "VERIFY: differences found; run the copy job again (it resumes)."; fi
    ;;
  *) echo "MODE must be sizes, dry, copy or verify" >&2; exit 1;;
esac
