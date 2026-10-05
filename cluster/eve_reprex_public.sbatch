#!/bin/bash -l
# Public minimal reprex (terra before sf -> EPSG:3035 axis order).  sbatch cluster/eve_reprex_public.sbatch
#SBATCH --job-name=birdmon-reprexpublic
#SBATCH --time=00:10:00
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=4G
#SBATCH --output=logs/reprexpublic_%j.out
#SBATCH --error=logs/reprexpublic_%j.err

set -euo pipefail
mkdir -p logs
EVE_R_MODULE="${EVE_R_MODULE:-GCC/13.3.0 OpenMPI/5.0.5 R/4.5.1 GDAL/3.10.3 CMake ImageMagick/7.1.1-38 UDUNITS/2.2.28}"
module load ${EVE_R_MODULE}
export TMPDIR="/work/${USER}/birdMonitor/tmp/${SLURM_JOB_ID}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT
cd "${SLURM_SUBMIT_DIR}"
Rscript --vanilla tools/reprexTerraSfAxis.R
