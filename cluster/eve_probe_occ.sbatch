#!/bin/bash -l
# Diagnostic: tools/probeOccurrence.R on EVE (real occurrence builders, one species/year, temp folders).
#   sbatch cluster/eve_probe_occ.sbatch   ->  logs/probe4_<id>.out / .err
#SBATCH --job-name=birdmon-probe4
#SBATCH --time=01:00:00
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=32G
#SBATCH --output=logs/probe4_%j.out
#SBATCH --error=logs/probe4_%j.err

set -euo pipefail
mkdir -p logs
EVE_R_MODULE="${EVE_R_MODULE:-GCC/13.3.0 OpenMPI/5.0.5 R/4.5.1 GDAL/3.10.3 CMake ImageMagick/7.1.1-38 UDUNITS/2.2.28}"
module load ${EVE_R_MODULE}
export TMPDIR="/work/${USER}/birdMonitor/tmp/${SLURM_JOB_ID}"
mkdir -p "${TMPDIR}"
trap 'rm -rf "${TMPDIR}"' EXIT
cd "${SLURM_SUBMIT_DIR}"
Rscript tools/probeOccurrence.R "Emberiza citrinella" 2022 2020
