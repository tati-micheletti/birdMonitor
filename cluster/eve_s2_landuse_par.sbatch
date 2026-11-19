#!/bin/bash -l
# SERIES 2 helper (2026-11-19): the land-use layers of the CTM v302 series computed in PARALLEL, one (year, scale) per array task (cluster/s2_landuse_task.R), while the single preparation job works through its
# years one class after the other. Years are listed in the order the preparation will reach them (it goes 2018, 2019, ...); a task refuses to start for a year the preparation has already reached (--main-log).
#   BIRDMONITOR_INPUT_ROOT=$PWD/inputs_s2 S2_MAIN_LOG=logs/prep_<id>.err sbatch --export=ALL cluster/eve_s2_landuse_par.sbatch
# Task 0 is a VALIDATION: the same code writes (2022, landscape 1 km) into a scratch folder and compares it cell by cell with the file the module itself made in the smoke test.
#SBATCH --job-name=s2-landuse
#SBATCH --array=0-22%11
#SBATCH --cpus-per-task=3
#SBATCH --mem-per-cpu=8G
#SBATCH --time=06:00:00
#SBATCH --output=logs/s2-landuse_%A_%a.out
#SBATCH --error=logs/s2-landuse_%A_%a.err
set -euo pipefail
cd "${SLURM_SUBMIT_DIR}"; mkdir -p logs
: "${BIRDMONITOR_INPUT_ROOT:?needs BIRDMONITOR_INPUT_ROOT=<inputs_s2 folder>}"; : "${S2_MAIN_LOG:?needs S2_MAIN_LOG=logs/prep_<id>.err (the running preparation)}"
EVE_R_MODULE="${EVE_R_MODULE:-GCC/13.3.0 OpenMPI/5.0.5 R/4.5.1 GDAL/3.10.3 CMake ImageMagick/7.1.1-38 UDUNITS/2.2.28}"; module load ${EVE_R_MODULE}
# year scale resolution
T=("2022 landscape 1000"
   "2019 habitat 200" "2019 landscape 700" "2019 landscape 1000" "2019 landscape 5000"
   "2020 habitat 200" "2020 landscape 700" "2020 landscape 1000" "2020 landscape 5000"
   "2021 landscape 700" "2021 landscape 5000"
   "2022 landscape 700" "2022 landscape 5000"
   "2023 landscape 700" "2023 landscape 5000"
   "2024 habitat 200" "2024 landscape 700" "2024 landscape 1000" "2024 landscape 5000"
   "2025 habitat 200" "2025 landscape 700" "2025 landscape 1000" "2025 landscape 5000")
read -r Y S R <<< "${T[$SLURM_ARRAY_TASK_ID]}"
echo "task ${SLURM_ARRAY_TASK_ID}: year ${Y}, ${S} ${R} m"
if [ "${SLURM_ARRAY_TASK_ID}" = "0" ]; then   # validation against the file the module made (smoke test)
  SC="outputs/s2_landuse_validation"; rm -rf "${SC:?}/scale_1" 2>/dev/null || true
  Rscript cluster/s2_landuse_task.R "${Y}" "${S}" "${R}" --scratch "${SC}" --compare "${BIRDMONITOR_INPUT_ROOT}/predictors/processed/scale_1/landuse_${Y}_landscape_scale_1.tif"
else
  Rscript cluster/s2_landuse_task.R "${Y}" "${S}" "${R}" --main-log "${S2_MAIN_LOG}"
fi
