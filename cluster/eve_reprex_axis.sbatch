#!/bin/bash -l
# Reprex / bisection on EVE: does a coordinate transform flip x/y inside a SpaDES simulation?
#   sbatch cluster/eve_reprex_axis.sbatch  ->  logs/reprex_<id>.out  (look for "<<< FLIPPED")
#SBATCH --job-name=birdmon-reprex
#SBATCH --time=00:20:00
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=8G
#SBATCH --output=logs/reprex_%j.out
#SBATCH --error=logs/reprex_%j.err

set -euo pipefail
mkdir -p logs
EVE_R_MODULE="${EVE_R_MODULE:-GCC/13.3.0 OpenMPI/5.0.5 R/4.5.1 GDAL/3.10.3 CMake ImageMagick/7.1.1-38 UDUNITS/2.2.28}"
module load ${EVE_R_MODULE}
export TMPDIR="/work/${USER}/birdMonitor/tmp/${SLURM_JOB_ID}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT
cd "${SLURM_SUBMIT_DIR}"
Rscript tools/reprexAxis.R
