#!/bin/bash -l
# Copies a finished run folder to a NEW run folder (2026-11-26), e.g. to add predictions of a new year without touching the original (the "never edit originals" rule).
# One cpu is enough (the copy is limited by the file system). Resumable: with RESUME=1 it can be submitted again into the same target (rsync only adds or updates). Never deletes in the target.
#   cd ~/projects/birdMonitor && SRC_RUN=s2v2 DST_RUN=s2v2_2026 sbatch --export=ALL cluster/eve_copy_run.sbatch
# Not copied: case_studies/ and _diag_* (side products of the source). The source's RUN_INFO.txt is kept in the target as RUN_INFO_of_<source>.txt (the target's own RUN_INFO.txt is written by the run that uses it).
#SBATCH --job-name=copy-run
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=4G
#SBATCH --time=48:00:00
#SBATCH --output=logs/copy-run_%j.out
#SBATCH --error=logs/copy-run_%j.err
set -euo pipefail
cd "${SLURM_SUBMIT_DIR}"; mkdir -p logs
: "${SRC_RUN:?needs SRC_RUN=<finished run folder name>}"; : "${DST_RUN:?needs DST_RUN=<new run folder name>}"
[ -d "outputs/${SRC_RUN}" ] || { echo "STOP: outputs/${SRC_RUN} not found" >&2; exit 1; }
[ "${SRC_RUN}" != "${DST_RUN}" ] || { echo "STOP: source and target are the same" >&2; exit 1; }
if [ -e "outputs/${DST_RUN}" ] && [ "${RESUME:-0}" != "1" ]; then echo "STOP: outputs/${DST_RUN} exists (RESUME=1 to continue a copy that was interrupted)" >&2; exit 1; fi
echo "copy outputs/${SRC_RUN} -> outputs/${DST_RUN}: $(date '+%F %T'); source size: $(du -sh "outputs/${SRC_RUN}" | cut -f1)"
mkdir -p "outputs/${DST_RUN}"
rsync -a --exclude=case_studies --exclude='_diag_*' --exclude=RUN_INFO.txt "outputs/${SRC_RUN}/" "outputs/${DST_RUN}/"
[ -f "outputs/${SRC_RUN}/RUN_INFO.txt" ] && cp -p "outputs/${SRC_RUN}/RUN_INFO.txt" "outputs/${DST_RUN}/RUN_INFO_of_${SRC_RUN}.txt"
printf 'Copy of outputs/%s made by cluster/eve_copy_run.sbatch, job %s, %s. The original is untouched.\n' "${SRC_RUN}" "${SLURM_JOB_ID}" "$(date '+%F %T')" > "outputs/${DST_RUN}/COPIED_FROM.txt"
echo "done: $(date '+%F %T'); target size: $(du -sh "outputs/${DST_RUN}" | cut -f1); files source/target: $(find "outputs/${SRC_RUN}" -type f | wc -l) / $(find "outputs/${DST_RUN}" -type f | wc -l) (the target has 2-3 files fewer or more: excluded folders, RUN_INFO, COPIED_FROM)"
