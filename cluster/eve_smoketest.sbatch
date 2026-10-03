#!/bin/bash -l
# 10-minute smoke test on EVE's `testing` partition. Run BEFORE the real pipeline:
#   sbatch cluster/eve_smoketest.sbatch      (from the repo root, on a login node)
# Checks, on a real compute node: modules load, R starts, the key R packages load,
# terra finds GDAL, inputs/cache/outputs resolve (to /work), TMPDIR works.
# Result: logs/smoketest_<jobid>.out -- look for "SMOKETEST: ALL OK".

#SBATCH --job-name=birdmon-smoke
#SBATCH --partition=testing
#SBATCH --time=00:10:00
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=4G
#SBATCH --output=logs/smoketest_%j.out
#SBATCH --error=logs/smoketest_%j.err

set -euo pipefail
mkdir -p logs

EVE_R_MODULE="${EVE_R_MODULE:-GCC/13.3.0 OpenMPI/5.0.5 R/4.5.1 GDAL/3.10.3 CMake ImageMagick/7.1.1-38 UDUNITS/2.2.28}"
module load ${EVE_R_MODULE}

export TMPDIR="/work/${USER}/birdMonitor/tmp/${SLURM_JOB_ID}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT

cd "${SLURM_SUBMIT_DIR}"
echo "node: $(hostname)  tmpdir: ${TMPDIR}"
R --version | head -1

Rscript tools/smoketest.R
