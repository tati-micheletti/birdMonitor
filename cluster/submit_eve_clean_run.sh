#!/bin/bash
# THE SECOND FULL RUN (clean) = the first one for the Spatio.IO / Bird Monitor: everything from the data preparation to /data/birds/viz as ONE dependency chain, in a NEW run folder.
#
#   0. checks on the login node (a clean run folder, a clean and pushed code state, every roster species has records at the three scales, the study area can be built)
#   1. prep      dataPrep_Monitor + inputs_Monitor: layers cropped/masked to the study area, hedges and heterogeneity (v2), CORINE classes, occurrence tables, model_ready tables
#   2. BRT       europe / habitat / landscape arrays, one task per species (the meta-model of the BRT runs inside the last scale task of a species)
#   3. ensemble  GLM/GAM/RF/NN fits, ensemble means, honest meta-model, index (cluster/submit_eve_ensemble.sh), reporting-area copies of the maps and the index on them
#   4. uncertainty  the ensemble inside 25 bootstrap replicates, regional index, intervals, reporting-area maps (cluster/submit_eve_big5_uncertainty.sh steps)
#   5. copy to /data/birds, then the connector (modules/connector_Monitor) puts the newest result of every species into /data/birds/viz
#
# The run folder is new ON PURPOSE: the file-based caches of a run (covariate stacks, ensemble model files, uncertainty folders, model_ready tables) live in outputs/<run>/,
# so nothing of the old runs can be reused by mistake. The persistent Cache (cache/) is content-based and safe to share. The processed layers in inputs/ are brought to the
# current definition by the preparation itself (study-area crop, heterogeneity v2 and CORINE classes by their stamps).
#
# Usage (EVE login node, VPN on):
#   cd ~/projects/birdMonitor && git pull && git submodule update --init --recursive && DRY_RUN=1 bash --login cluster/submit_eve_clean_run.sh     # checks + prints the chain, submits nothing
#   cd ~/projects/birdMonitor && bash --login cluster/submit_eve_clean_run.sh                                                                          # the real thing
# Environment: BIRDMONITOR_RUNNAME (default v2), RESUME=1 (the run folder may exist: only what is missing is recomputed), BIG5_REPS (default 0:25), FORCE=1 (skip the queue check).
# BIRDMONITOR_SPECIES and BIRDMONITOR_YEARS must NOT be set (debug switches: the steps that combine species would see only a subset).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs
RUN="${BIRDMONITOR_RUNNAME:-v2}"; export BIRDMONITOR_RUNNAME="${RUN}"
TAG=ens_brt-glm-gam-rf-nn; MEM=brt,glm,gam,rf,nn; REPS="${BIG5_REPS:-0:25}"
if ! type module >/dev/null 2>&1; then echo "Run this script as:  bash --login cluster/submit_eve_clean_run.sh" >&2; exit 1; fi
export EVE_R_MODULE="${EVE_R_MODULE:-GCC/13.3.0 OpenMPI/5.0.5 R/4.5.1 GDAL/3.10.3 CMake ImageMagick/7.1.1-38 UDUNITS/2.2.28}"
module load ${EVE_R_MODULE}
if [ -n "${BIRDMONITOR_SPECIES:-}" ]; then echo "STOP: BIRDMONITOR_SPECIES is set (${BIRDMONITOR_SPECIES}); unset it for a full run." >&2; exit 1; fi
if [ -n "${BIRDMONITOR_YEARS:-}" ]; then echo "STOP: BIRDMONITOR_YEARS is set (${BIRDMONITOR_YEARS}); it is a debug switch, unset it for a full run." >&2; exit 1; fi
if [ "${FORCE:-0}" != "1" ] && squeue -u "${USER}" -h -o "%j" | grep -qE "^(birdmon-prep|ens-|unc-|connector|copy-databirds)"; then
  echo "STOP: jobs of this workflow are already in the queue (squeue -u ${USER}). FORCE=1 overrides." >&2; exit 1; fi

echo "=== 0. checks (run ${RUN})"
if [ -e "outputs/${RUN}" ] && [ "${RESUME:-0}" != "1" ]; then
  echo "STOP: outputs/${RUN} already exists. A clean run needs a new name (BIRDMONITOR_RUNNAME=...); RESUME=1 continues this one." >&2; exit 1; fi
if [ -n "$(git status --porcelain --untracked-files=no)" ]; then echo "STOP: the main repo has uncommitted changes on this machine (git status)." >&2; exit 1; fi
if [ -n "$(git submodule foreach --quiet 'git status --porcelain --untracked-files=no' 2>/dev/null)" ]; then echo "STOP: a module has uncommitted changes on this machine (git submodule foreach git status)." >&2; exit 1; fi
if git submodule status | grep -q '^[+-U]'; then echo "STOP: the modules are not at the commits the main repo points to. Run: git submodule update --init --recursive" >&2; exit 1; fi
# The preparation changes inputs/predictors/processed and inputs/response/processed IN PLACE (crop to the study area, hedges filled, heterogeneity v2, new CORINE classes, rebuilt occurrence tables); raw/ is never touched.
# Before that, a copy of the CURRENT state must exist in /data/birds (cluster/eve_copy_data_birds.sbatch adds/updates, never deletes). The check compares the number of processed files; SKIP_BACKUP_CHECK=1 overrides.
BK="${DATA_BIRDS_INPUTS:-/data/birds/birdMonitor/inputs}"
if [ "${SKIP_BACKUP_CHECK:-0}" != "1" ]; then
  for sub in predictors/processed response/processed; do
    nSrc=$(find "inputs/${sub}" -type f | wc -l); nBk=$(find "${BK}/${sub}" -type f 2>/dev/null | wc -l || true)
    if [ "${nBk}" -lt "${nSrc}" ]; then
      echo "STOP: no complete safety copy of inputs/${sub} in ${BK}/${sub} (${nBk} files there, ${nSrc} here). The preparation overwrites these files in place." >&2
      echo "      Make it first (adds only, deletes nothing; a job, takes a while):   cd ~/projects/birdMonitor && sbatch cluster/eve_copy_data_birds.sbatch     then run this script again when the job has finished." >&2
      exit 1
    fi
  done
  echo "safety copy of the processed inputs: found in ${BK}"
fi
echo "code: main $(git rev-parse --short HEAD); modules: $(git submodule status | awk '{print $2 " " substr($1,1,7)}' | tr '\n' ';')"
Rscript tools/check_duplicated_functions.R | tail -1
Rscript tools/checkSpeciesData.R 2>&1 | tee "logs/species_check_${RUN}.txt" | tail -25
if grep -q "WARNING: species that are ON but not READY" "logs/species_check_${RUN}.txt"; then
  echo "STOP: at least one species of the roster has no records at one scale (list above). Fix the data or set include blank in data/speciesCanonical.csv." >&2; exit 1; fi
Rscript -e 'libs <- Sys.glob(file.path(path.expand("~"), ".local", "share", "R", "birdMonitor", "packages", "*", "*")); if (length(libs)) .libPaths(c(libs, .libPaths())); suppressMessages(library(terra))
  source("tools/sharedConfig.R"); for (f in c("laeaAnalytic.R", "studyArea.R")) source(file.path("modules/dataPrep_Monitor/R", f))
  a <- buildStudyArea(sharedStudyArea, file.path("inputs", "predictors", "raw", "gadm")); cat("study area:", a$label, "| ", round(expanse(a) / 1e6), "km2 | species:", length(sharedSpecies), "\n")'
NSP=$(Rscript -e 'source("tools/sharedConfig.R"); cat(length(sharedSpecies))' 2>/dev/null | tail -1)
[ -n "${NSP}" ] || { echo "ERROR: could not read the number of species" >&2; exit 1; }

if [ "${DRY_RUN:-0}" = "1" ]; then                # every sbatch (also inside the scripts called below) only prints and returns a fake job id
  sbatch() { echo "DRY sbatch $*" >&2; echo $((900000 + RANDOM)); }; export -f sbatch
  echo "DRY_RUN=1: nothing is submitted; the lines 'DRY sbatch ...' are what would be."
else
  mkdir -p "outputs/${RUN}"
  { echo "run ${RUN} submitted $(date -Is) by ${USER}"; echo "main $(git rev-parse HEAD)"; git submodule status; echo "species ${NSP}"; echo "study area: $(grep -m1 -o 'study area:.*' "logs/species_check_${RUN}.txt" || true)"; } > "outputs/${RUN}/RUN_INFO.txt"
fi

echo; echo "=== 1. prep"
prep=$(sbatch --parsable --export=ALL cluster/eve_prep.sbatch); echo "prep: ${prep}"

echo; echo "=== 2. BRT at the three scales (${NSP} species each)"
ids=()
for scale in europe habitat landscape; do
  id=$(sbatch --parsable --export=ALL --array="1-${NSP}" --dependency=afterok:"${prep}" --kill-on-invalid-dep=yes modules/models_Monitor/cluster/eve_array_${scale}.sbatch)
  echo "BRT ${scale}: ${id}"; ids+=("${id}")
done
brt=$(IFS=:; echo "${ids[*]}")

echo; echo "=== 3. ensemble: fits -> ensemble means -> honest meta-model -> index"
out=$(ENS_AFTER="${brt}" ENS_ALGOS="glm gam rf nn" ENS_VARIANTS="${MEM}" ENS_THROTTLE=15 bash cluster/submit_eve_ensemble.sh | tee /dev/stderr)
meta=$(echo "${out}" | awk '/^meta /{print $NF}')
[ -n "${meta}" ] || { echo "ERROR: could not read the meta-model job id of the ensemble" >&2; exit 1; }
mk=$(MASK_META_TAG="${TAG}" sbatch --parsable --export=ALL --array="1-${NSP}" --dependency=afterok:${meta} --kill-on-invalid-dep=yes cluster/eve_mask_meta.sbatch); echo "reporting-area copies of the maps: ${mk}"
gi=$(BIRDMONITOR_INDEX_TAG="${TAG}_germany" sbatch --parsable --export=ALL --dependency=afterok:${mk} --kill-on-invalid-dep=yes cluster/eve_index.sbatch); echo "index on the reporting-area maps: ${gi}"

echo; echo "=== 4. uncertainty: the ensemble inside the replicates (${REPS})"
uout=$(ENS_MEMBERS="${MEM}" BIRDMONITOR_UNC_REPS="${REPS}" UNC_AFTER="${meta}" UNC_PREP_TIME="${BIG5_PREP_TIME:-24:00:00}" bash cluster/submit_eve_ensemble_uncertainty.sh | tee /dev/stderr)
band=$(echo "${uout}" | awk '/^band:/{print $2}'); fin=$(echo "${uout}" | awk '/^assembleall:/{print $2}')
[ -n "${band}" ] && [ -n "${fin}" ] || { echo "ERROR: could not read the band / assembleall job ids of the uncertainty chain" >&2; exit 1; }
rout=$(FORCE=1 BIRDMONITOR_UNC_MEMBERS="${MEM}" BIRDMONITOR_UNC_TAG="${TAG}" BIRDMONITOR_UNC_BANDS=48 BIRDMONITOR_UNC_REPS="${REPS}" UNC_AFTER="${band}" UNC_FINAL="${fin}" UNC_THROTTLE=100 bash cluster/submit_eve_regional.sh | tee /dev/stderr)
mm=$(echo "${rout}" | awk '/^maskmaps:/{print $2}'); ri=$(echo "${rout}" | awk '/^regionindex:/{print $2}')
[ -n "${mm}" ] && [ -n "${ri}" ] || { echo "ERROR: could not read the maskmaps / regionindex job ids" >&2; exit 1; }

echo; echo "=== 5. /data/birds and /data/birds/viz"
cp=$(COPY_INPUTS=0 sbatch --parsable --export=ALL --dependency=afterok:${mm}:${gi}:${ri} --kill-on-invalid-dep=yes cluster/eve_copy_data_birds.sbatch); echo "copy to /data/birds: ${cp}"
cn=$(sbatch --parsable --export=ALL --dependency=afterok:${cp} --kill-on-invalid-dep=yes cluster/eve_connector.sbatch); echo "connector: ${cn}"

echo
echo "================================================================================"
echo "ALL QUEUED (run ${RUN}, ${NSP} species). Expect about 2 days. Read-only monitor:  cd ~/projects/birdMonitor && bash cluster/monitor_tonight.sh"
echo "WHEN THE CONNECTOR IS DONE:  cat /data/birds/viz/_missing.csv   (must be empty)   |   grep -H RESULT outputs/${RUN}/uncertainty*/*/parity_check.txt   (every species RESULT: OK)"
echo "================================================================================"
