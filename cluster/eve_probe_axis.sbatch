#!/bin/bash -l
# Diagnostic: tools/probeAxis.R on EVE -- which loaded package flips coordinate axis order?
#   sbatch cluster/eve_probe_axis.sbatch   ->  logs/probe5_<id>.out
#SBATCH --job-name=birdmon-probe5
#SBATCH --time=00:20:00
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=8G
#SBATCH --output=logs/probe5_%j.out
#SBATCH --error=logs/probe5_%j.err

set -euo pipefail
mkdir -p logs
EVE_R_MODULE="${EVE_R_MODULE:-GCC/13.3.0 OpenMPI/5.0.5 R/4.5.1 GDAL/3.10.3 CMake ImageMagick/7.1.1-38 UDUNITS/2.2.28}"
module load ${EVE_R_MODULE}
export TMPDIR="/work/${USER}/birdMonitor/tmp/${SLURM_JOB_ID}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT
cd "${SLURM_SUBMIT_DIR}"
echo "ENV on the compute node:"; env | grep -i -E "^(OSR|GDAL|PROJ)" || echo "(none of OSR*/GDAL*/PROJ* set)"
Rscript tools/probeAxis.R
