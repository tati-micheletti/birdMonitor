#!/bin/bash -l
# Diagnostic: tools/probeCovStack.R on EVE (re-gridding behaviour of terra/GDAL/PROJ).
#   sbatch cluster/eve_probe_covstack.sbatch   ->  logs/probe_<id>.out
#SBATCH --job-name=birdmon-probe3
#SBATCH --partition=testing
#SBATCH --time=00:14:00
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=32G
#SBATCH --output=logs/probe3_%j.out
#SBATCH --error=logs/probe3_%j.err

set -euo pipefail
mkdir -p logs
EVE_R_MODULE="${EVE_R_MODULE:-GCC/13.3.0 OpenMPI/5.0.5 R/4.5.1 GDAL/3.10.3 CMake ImageMagick/7.1.1-38 UDUNITS/2.2.28}"
module load ${EVE_R_MODULE}
export TMPDIR="/work/${USER}/birdMonitor/tmp/${SLURM_JOB_ID}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT
cd "${SLURM_SUBMIT_DIR}"
Rscript tools/probeCovStack.R
