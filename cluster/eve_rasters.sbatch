#!/bin/bash -l
# Predictor RASTERS only (BIRDMONITOR_STAGE=rasters: dataPrep_Monitor, no occurrence tables), for NEW years of an existing series (2026-11-26).
# Used to add 2026 to Series 2: land use of the new year from the newest CTM v302 map (findCtmFile), climate = flagged copy of the last year with CHELSA data (sharedClimateLastYear),
# CORINE snapshot by rule, hedges = the existing fixed layer (completeHedges adopts it), heterogeneity, unmapped share, study-area crop. Years that exist are cache hits.
#   cd ~/projects/birdMonitor && BIRDMONITOR_INPUT_ROOT=$PWD/inputs_s2 BIRDMONITOR_PREDICTION_YEARS=2026:2026 sbatch --export=ALL cluster/eve_rasters.sbatch
# BIRDMONITOR_LANDSCAPE_YEARS / BIRDMONITOR_HABITAT_YEARS default to 2017:2025 (the Series 2 fitting years, so the layers of those years are asked for and found); the land-use rule is CTM first, no recode.
# Series 2 only: the inputs folder must be inputs_s2, never inputs/.
#SBATCH --job-name=birdmon-rasters
#SBATCH --cpus-per-task=8
#SBATCH --mem-per-cpu=8G
#SBATCH --time=24:00:00
#SBATCH --output=logs/rasters_%j.out
#SBATCH --error=logs/rasters_%j.err
set -euo pipefail
mkdir -p logs
: "${BIRDMONITOR_INPUT_ROOT:?needs BIRDMONITOR_INPUT_ROOT=<inputs_s2 folder>}"; : "${BIRDMONITOR_PREDICTION_YEARS:?needs BIRDMONITOR_PREDICTION_YEARS (e.g. 2026:2026)}"
cd "${SLURM_SUBMIT_DIR}"
[ "$(readlink -f "${BIRDMONITOR_INPUT_ROOT}")" != "$(readlink -f inputs)" ] || { echo "STOP: this job must NOT use inputs/ itself (Series 2: inputs_s2)" >&2; exit 1; }
EVE_R_MODULE="${EVE_R_MODULE:-GCC/13.3.0 OpenMPI/5.0.5 R/4.5.1 GDAL/3.10.3 CMake ImageMagick/7.1.1-38 UDUNITS/2.2.28}"
module load ${EVE_R_MODULE}
command -v Rscript >/dev/null 2>&1 || { echo "ERROR on $(hostname): Rscript not found after: module load ${EVE_R_MODULE}" >&2; exit 1; }
export TMPDIR="/work/${USER}/birdMonitor/tmp/${SLURM_JOB_ID}"; mkdir -p "${TMPDIR}"; trap 'rm -rf "${TMPDIR}"' EXIT   # $TMPDIR is a RAM disk on EVE
export BIRDMONITOR_STAGE=rasters BIRDMONITOR_SKIP_INSTALL=1 BIRDMONITOR_SKIP_DOWNLOAD=1        # no internet on compute nodes
export BIRDMONITOR_RUNNAME="${BIRDMONITOR_RUNNAME:-s2v2_2026}"
export BIRDMONITOR_LANDSCAPE_YEARS="${BIRDMONITOR_LANDSCAPE_YEARS:-2017:2025}" BIRDMONITOR_HABITAT_YEARS="${BIRDMONITOR_HABITAT_YEARS:-2017:2025}"
export BIRDMONITOR_LANDUSE_PREFER_HCTM=FALSE
export BIRDMONITOR_INPUT_ROOT BIRDMONITOR_PREDICTION_YEARS
echo "rasters: inputs ${BIRDMONITOR_INPUT_ROOT}, prediction years ${BIRDMONITOR_PREDICTION_YEARS}, landscape ${BIRDMONITOR_LANDSCAPE_YEARS}, habitat ${BIRDMONITOR_HABITAT_YEARS}; $(date '+%F %T')"
Rscript runMe.R
echo "done $(date '+%F %T')"
