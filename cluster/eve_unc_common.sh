# Sourced by every cluster/eve_unc_*.sbatch: modules, scratch space, run settings.
# Module list is set HERE (not forwarded from the submit script), like the other cluster scripts.
EVE_R_MODULE="${EVE_R_MODULE:-GCC/13.3.0 OpenMPI/5.0.5 R/4.5.1 GDAL/3.10.3 CMake ImageMagick/7.1.1-38 UDUNITS/2.2.28}"
module load ${EVE_R_MODULE}
if ! command -v Rscript >/dev/null 2>&1; then
  echo "ERROR on $(hostname): Rscript not found after: module load ${EVE_R_MODULE}" >&2
  module list >&2
  exit 1
fi
# $TMPDIR on EVE is a RAM disk: use /work and clean up when the job ends.
export TMPDIR="/work/${USER}/birdMonitor/tmp/${SLURM_JOB_ID}_${SLURM_ARRAY_TASK_ID:-0}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT
export BIRDMONITOR_RUNNAME="${BIRDMONITOR_RUNNAME:-test4}"
export BIRDMONITOR_SKIP_INSTALL=1
cd "${SLURM_SUBMIT_DIR}"

# Run one task command. R/terra sometimes ends with a segmentation fault (exit code 139) AFTER the task wrote all its output
# (seen 2026-10-07, band task 80: "=== done" logged, then SIGSEGV at shutdown). runUncertaintyTask.R writes a marker file as its
# very last act; if the command fails but the marker exists, the work is complete and the failure is only the exit-time crash.
unc_run() {
  local marker="${SLURM_SUBMIT_DIR}/logs/.done_${SLURM_JOB_ID}_${SLURM_ARRAY_TASK_ID:-0}_$$"
  export UNC_DONE_MARKER="${marker}"
  rm -f "${marker}"
  local rc=0
  "$@" || rc=$?
  if [ "${rc}" -ne 0 ] && [ -f "${marker}" ]; then
    echo "NOTE: '$*' exited with code ${rc} AFTER finishing its work (exit-time crash); counted as success." >&2
    rc=0
  fi
  rm -f "${marker}"
  return "${rc}"
}
