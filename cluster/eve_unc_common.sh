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
