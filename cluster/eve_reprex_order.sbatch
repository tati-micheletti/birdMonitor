#!/bin/bash -l
# Does the order of first use (terra vs sf) change EPSG:3035 axis order?  sbatch cluster/eve_reprex_order.sbatch
#SBATCH --job-name=birdmon-reprexorder
#SBATCH --time=00:20:00
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=8G
#SBATCH --output=logs/reprexorder_%j.out
#SBATCH --error=logs/reprexorder_%j.err

set -euo pipefail
mkdir -p logs
EVE_R_MODULE="${EVE_R_MODULE:-GCC/13.3.0 OpenMPI/5.0.5 R/4.5.1 GDAL/3.10.3 CMake ImageMagick/7.1.1-38 UDUNITS/2.2.28}"
module load ${EVE_R_MODULE}
export TMPDIR="/work/${USER}/birdMonitor/tmp/${SLURM_JOB_ID}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT
cd "${SLURM_SUBMIT_DIR}"
# two SEPARATE R processes, so each starts with a fresh GDAL/PROJ state
Rscript tools/reprexOrder.R terraFirst
Rscript tools/reprexOrder.R sfFirst
