#!/bin/bash -l
# DEBUG: the real prep stage (SpaDES) restricted to two species, to see quickly what the real session does.
#   sbatch cluster/eve_prep_debug.sbatch    -> logs/prepdbg_<id>.err   (look for lines starting "!!")
# Uses a SEPARATE run name, so nothing of the main run is touched.
#SBATCH --job-name=birdmon-prepdbg
#SBATCH --time=03:00:00
#SBATCH --cpus-per-task=4
#SBATCH --mem-per-cpu=8G
#SBATCH --output=logs/prepdbg_%j.out
#SBATCH --error=logs/prepdbg_%j.err

set -euo pipefail
mkdir -p logs
EVE_R_MODULE="${EVE_R_MODULE:-GCC/13.3.0 OpenMPI/5.0.5 R/4.5.1 GDAL/3.10.3 CMake ImageMagick/7.1.1-38 UDUNITS/2.2.28}"
module load ${EVE_R_MODULE}
export TMPDIR="/work/${USER}/birdMonitor/tmp/${SLURM_JOB_ID}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT

export BIRDMONITOR_STAGE=prep
export BIRDMONITOR_SKIP_INSTALL=1
export BIRDMONITOR_SKIP_DOWNLOAD=1
export BIRDMONITOR_RUNNAME=debug_prep
export BIRDMONITOR_SPECIES="Emberiza citrinella;Emberiza calandra"
cd "${SLURM_SUBMIT_DIR}"
Rscript runMe.R
