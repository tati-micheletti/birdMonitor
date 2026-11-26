#!/bin/bash -l
# Land-use layers of ONE new year (Series 2), the three LANDSCAPE scales in PARALLEL (2026-11-26): the single preparation job computes the 14 crop categories of every scale one after the other
# (about 8 min per category and scale, ~2 h per scale; 2026: 200 m habitat + 3 landscape scales = ~8 h); here each scale is its own task (cluster/s2_landuse_task.R, the module's own computeLanduse()).
# The habitat scale (200 m) is not in this array (run it as a task of its own: cluster/s2_landuse_task.R <year> habitat 200) or by the preparation. Derived layers (heterogeneity, unmapped share, hedges,
# study-area crop) stay the preparation's job: run cluster/eve_rasters.sbatch AFTER this (it finds the land-use layers valid).
#   cd ~/projects/birdMonitor && YEAR=2026 BIRDMONITOR_INPUT_ROOT=$PWD/inputs_s2 sbatch --export=ALL cluster/eve_landuse_year.sbatch
# No other job may write the same year and scale at the same time (the task has no --main-log check here).
#SBATCH --job-name=landuse-year
#SBATCH --array=0-2
#SBATCH --cpus-per-task=3
#SBATCH --mem-per-cpu=8G
#SBATCH --time=06:00:00
#SBATCH --output=logs/landuse-year_%A_%a.out
#SBATCH --error=logs/landuse-year_%A_%a.err
set -euo pipefail
cd "${SLURM_SUBMIT_DIR}"; mkdir -p logs
: "${YEAR:?needs YEAR=<year>}"; : "${BIRDMONITOR_INPUT_ROOT:?needs BIRDMONITOR_INPUT_ROOT=<inputs_s2 folder>}"
EVE_R_MODULE="${EVE_R_MODULE:-GCC/13.3.0 OpenMPI/5.0.5 R/4.5.1 GDAL/3.10.3 CMake ImageMagick/7.1.1-38 UDUNITS/2.2.28}"; module load ${EVE_R_MODULE}
export TMPDIR="/work/${USER}/birdMonitor/tmp/${SLURM_JOB_ID}_${SLURM_ARRAY_TASK_ID}"; mkdir -p "${TMPDIR}"; trap 'rm -rf "${TMPDIR}"' EXIT
RES=(700 1000 5000); R="${RES[$SLURM_ARRAY_TASK_ID]}"
echo "task ${SLURM_ARRAY_TASK_ID}: year ${YEAR}, landscape ${R} m, inputs ${BIRDMONITOR_INPUT_ROOT}; $(date '+%F %T')"
Rscript cluster/s2_landuse_task.R "${YEAR}" landscape "${R}"
echo "done $(date '+%F %T')"
