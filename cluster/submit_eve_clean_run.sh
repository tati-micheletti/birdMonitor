#!/bin/bash
# A FULL RUN (clean) = everything from the data preparation to /data/birds/viz as ONE dependency chain, in a NEW run folder. v2 was the first for the Spatio.IO / Bird Monitor;
# v3 (2026-11-03) is the same chain with the new land-use rule (HCTM for every year <= 2023, CTM 2024-2025 recoded to HCTM classes; DECISIONS.md 2026-11-03).
#
#   0. checks on the login node (a clean run folder, a clean and pushed code state, every roster species has records at the three scales, the study area can be built)
#   1. prep      dataPrep_Monitor + inputs_Monitor: land use (new rule), layers cropped/masked to the study area, hedges and heterogeneity (v2), CORINE classes, occurrence tables, model_ready tables
#                + a continuity check of the land-use layers with an e-mail (cluster/eve_landuse_check.sbatch; the chain does not wait for it, read the e-mail and scancel if it says FLAGGED)
#   2. covcache  the 200 m habitat covariate stacks of every year, written once (cluster/eve_covcache.sbatch); the habitat array reads them
#   3. BRT       europe / habitat / landscape arrays, one task per species (the meta-model of the BRT runs inside the last scale task of a species)
#   4. ensemble  GLM/GAM/RF/NN fits, ensemble means, honest meta-model, index (cluster/submit_eve_ensemble.sh), reporting-area copies of the maps and the index on them,
#                and the Mann-Kendall pixel trend test on those maps (cluster/eve_pixel_trend_test.sbatch; needed by the results page)
#   5. uncertainty  the ensemble inside 25 bootstrap replicates, regional index, intervals, reporting-area maps (cluster/submit_eve_big5_uncertainty.sh steps)
#      diagnostics  (after the meta-model, in parallel with step 5) the ensemble maps read at the survey routes and the per-scale country means (cluster/eve_model_at_routes.sbatch,
#                   cluster/eve_diagnose_scales.sbatch -> outputs/<run>/diagnostics/); the post-run job waits for them but a failure there does not block it
#   6. copy to /data/birds, then the connector (modules/connector_Monitor) puts the newest result of every species into /data/birds/viz
#   7. post-run (cluster/eve_postrun.sbatch): the end-of-run checks (cluster/post_run_checks.sh); if they pass, all figures and package A of cluster/pack_downloads.sh;
#      an e-mail with the verdict to NOTIFY_EMAIL (comma-separated addresses; cluster/notify.sh)
#
# The run folder is new ON PURPOSE: the file-based caches of a run (covariate stacks, ensemble model files, uncertainty folders, model_ready tables) live in outputs/<run>/,
# so nothing of the old runs can be reused by mistake. The persistent Cache (cache/) is content-based and safe to share. The processed layers in inputs/ are brought to the
# current definition by the preparation itself (study-area crop, heterogeneity v2 and CORINE classes by their stamps).
#
# Usage (EVE login node, VPN on; NOTIFY_EMAIL="you@ufz.de" in front of the real command: failure digest, land-use check and the post-run verdict go there):
#   cd ~/projects/birdMonitor && git pull && git submodule update --init --recursive && DRY_RUN=1 bash --login cluster/submit_eve_clean_run.sh     # checks + prints the chain, submits nothing
#   cd ~/projects/birdMonitor && bash --login cluster/submit_eve_clean_run.sh                                                                          # the real thing
# Environment: BIRDMONITOR_RUNNAME (default v3), RESUME=1 (the run folder may exist: only what is missing is recomputed), BIG5_REPS (default 0:25), FORCE=1 (skip the queue check).
# To continue a run whose prep (and perhaps two of the BRT arrays) already finished: SKIP_PREP=1 [BRT_SCALES=habitat] RESUME=1 (prep is not sent again; BRT_SCALES lists the arrays to send, default all three).
# BIRDMONITOR_SPECIES and BIRDMONITOR_YEARS must NOT be set (debug switches: the steps that combine species would see only a subset).
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs
RUN="${BIRDMONITOR_RUNNAME:-v3}"; export BIRDMONITOR_RUNNAME="${RUN}"
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

# The land-use inputs of the rule since 2026-11-03: HCTM for every year <= 2023, CTM v302 for 2024-2025 (recoded to HCTM classes with data/landuseRecodeCTMtoHCTM.csv), CTM v202 2017-2021 for the hedges.
LUDIR="inputs/predictors/raw/landuse"; miss=""
for y in $(seq 2005 2023); do [ -f "${LUDIR}/HCTM_GER_${y}_rst_v101_COG.tif" ] || miss="${miss} HCTM_${y}"; done
for y in 2017 2018 2019 2020 2021; do [ -f "${LUDIR}/CTM_GER_${y}_rst_v202_COG.tif" ] || miss="${miss} CTM_${y}(v202)"; done
[ -f "${LUDIR}/CTM_GER_2024_rst_v302_COG.tif" ] || miss="${miss} CTM_2024(v302)"
[ -f "${LUDIR}/CTM_GER_2025_rst_v302_2025_08_COG.tif" ] || miss="${miss} CTM_2025(v302)"
[ -f "data/landuseRecodeCTMtoHCTM.csv" ] || miss="${miss} data/landuseRecodeCTMtoHCTM.csv(git pull?)"
[ -z "${miss}" ] || { echo "STOP: land-use inputs missing in ${LUDIR}:${miss}" >&2; exit 1; }
echo "land-use inputs: HCTM 2005-2023, CTM v202 2017-2021, CTM v302 2024-2025 and the recode table are there"
# The water layer for the mask of the Monitor maps (sharedWaterMaskFile in tools/sharedConfig.R; "none" = no mask, on purpose). The connector is the LAST job of the chain: a missing file would only show after days, so it is checked here.
WATER=$(Rscript -e 'source("tools/sharedConfig.R"); cat(sharedWaterMaskFile)' 2>/dev/null | tail -1); WF="${BIRDMONITOR_WATER_FILE:-${WATER}}"
if [ "${WF}" = "none" ]; then
  echo "water mask: OFF on purpose (none)"
elif [ -f "${WF}" ]; then
  echo "water layer: ${WF} -> $(stat -c %s "${WF}") bytes, md5 $(md5sum "${WF}" | cut -c1-32)"
else
  echo "STOP: the water layer ${WF} for the mask of the Monitor maps is not on this machine (sharedWaterMaskFile in tools/sharedConfig.R). Put it there, or set it to \"none\" on purpose." >&2; exit 1
fi
# The EBBA2 file the pipeline will read (sharedEbba2CsvSubpath in tools/sharedConfig.R -> runMe.R -> dataPrep_Monitor, and the same variable in checkSpeciesData.R below): print its name, size and checksum so it can be compared with the local copy.
EBBA2=$(Rscript -e 'source("tools/sharedConfig.R"); cat(sharedEbba2CsvSubpath)' 2>/dev/null | tail -1)
[ -f "inputs/${EBBA2}" ] || { echo "STOP: the EBBA2 file inputs/${EBBA2} (sharedEbba2CsvSubpath) is not on this machine. Copy it to inputs/$(dirname "${EBBA2}")/ first." >&2; exit 1; }
EBBA2SUM="$(md5sum "inputs/${EBBA2}" | cut -c1-32) $(stat -c %s "inputs/${EBBA2}") bytes $(($(wc -l < "inputs/${EBBA2}") - 1)) rows $(cut -d';' -f3 "inputs/${EBBA2}" | tail -n +2 | sort -u | wc -l) species"
echo "EBBA2 file: inputs/${EBBA2} -> ${EBBA2SUM}"
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
  { echo "run ${RUN} submitted $(date -Is) by ${USER}"; echo "main $(git rev-parse HEAD)"; git submodule status; echo "species ${NSP}"; echo "EBBA2 file: inputs/${EBBA2} ${EBBA2SUM}"; echo "study area: $(grep -m1 -o 'study area:.*' "logs/species_check_${RUN}.txt" || true)"; } > "outputs/${RUN}/RUN_INFO.txt"
fi

SINCE=$(date +%FT%T)                                  # for the failure watcher (step 7): jobs of this chain are submitted from now on
echo; echo "=== 1. prep"
if [ "${SKIP_PREP:-0}" = "1" ]; then prep=""; echo "prep: skipped (SKIP_PREP=1: it finished earlier in this run folder)"
else prep=$(sbatch --parsable --export=ALL cluster/eve_prep.sbatch); echo "prep: ${prep}"; fi
LCDEP=(); if [ -n "${prep}" ]; then LCDEP=(--dependency=afterok:"${prep}" --kill-on-invalid-dep=yes); fi
lc=$(sbatch --parsable --export=ALL "${LCDEP[@]+"${LCDEP[@]}"}" cluster/eve_landuse_check.sbatch); echo "land-use continuity check (e-mail when it is done; nothing waits for it): ${lc}"

# The habitat array READS the 200 m covariate stacks of every year from outputs/<run>/uncertainty/covcache (written once by this job). Without them each task builds the stacks in memory
# and is killed at 12 GB (all 14 habitat tasks of the first v2 chain, 31 Oct 2026). So the habitat array waits for this job.
echo; echo "=== 2. habitat covariate stacks (once; the habitat array waits for it)"
PREPDEP=(); if [ -n "${prep}" ]; then PREPDEP=(--dependency=afterok:"${prep}" --kill-on-invalid-dep=yes); fi
cc=$(sbatch --parsable --export=ALL "${PREPDEP[@]+"${PREPDEP[@]}"}" cluster/eve_covcache.sbatch); echo "covcache: ${cc}"

echo; echo "=== 3. BRT at the scales ${BRT_SCALES:-europe habitat landscape} (${NSP} species each)"
ids=()
for scale in ${BRT_SCALES:-europe habitat landscape}; do        # BRT_SCALES=habitat re-sends only the habitat array when the other two have finished
  dep="${prep}"; if [ "${scale}" = "habitat" ]; then dep="${dep:+${dep}:}${cc}"; fi
  DEPARG=(); if [ -n "${dep}" ]; then DEPARG=(--dependency=afterok:"${dep}" --kill-on-invalid-dep=yes); fi
  id=$(sbatch --parsable --export=ALL --array="1-${NSP}" "${DEPARG[@]+"${DEPARG[@]}"}" modules/models_Monitor/cluster/eve_array_${scale}.sbatch)
  echo "BRT ${scale}: ${id}"; ids+=("${id}")
done
brt=$(IFS=:; echo "${ids[*]}")

echo; echo "=== 4. ensemble: fits -> ensemble means -> honest meta-model -> index"
out=$(ENS_AFTER="${brt}" ENS_ALGOS="glm gam rf nn" ENS_VARIANTS="${MEM}" ENS_THROTTLE=15 bash cluster/submit_eve_ensemble.sh | tee /dev/stderr)
meta=$(echo "${out}" | awk '/^meta /{print $NF}')
[ -n "${meta}" ] || { echo "ERROR: could not read the meta-model job id of the ensemble" >&2; exit 1; }
# Diagnostics (read-only): the ensemble maps at the survey routes, the per-scale country means and predictors. The post-run job waits for them (afterany: a failure here does not block the figures).
mr=$(sbatch --parsable --export=ALL --dependency=afterok:${meta} --kill-on-invalid-dep=yes cluster/eve_model_at_routes.sbatch); echo "diagnostics, model at the survey routes: ${mr}"
ds=$(sbatch --parsable --export=ALL --dependency=afterok:${meta} --kill-on-invalid-dep=yes cluster/eve_diagnose_scales.sbatch); echo "diagnostics, per-scale country means: ${ds}"
mk=$(MASK_META_TAG="${TAG}" sbatch --parsable --export=ALL --array="1-${NSP}" --dependency=afterok:${meta} --kill-on-invalid-dep=yes cluster/eve_mask_meta.sbatch); echo "reporting-area copies of the maps: ${mk}"
gi=$(BIRDMONITOR_INDEX_TAG="${TAG}_germany" sbatch --parsable --export=ALL --dependency=afterok:${mk} --kill-on-invalid-dep=yes cluster/eve_index.sbatch); echo "index on the reporting-area maps: ${gi}"
# Mann-Kendall test and Sen slope at every pixel of the main-model maps (the second opinion on the trend maps; the results page and its species list need it). One task per roster species.
pt=$(BIRDMONITOR_RUNNAME="${RUN}" sbatch --parsable --export=ALL --array="1-${NSP}" --dependency=afterok:${mk} --kill-on-invalid-dep=yes cluster/eve_pixel_trend_test.sbatch); echo "pixel trend test (Mann-Kendall): ${pt}"

echo; echo "=== 5. uncertainty: the ensemble inside the replicates (${REPS})"
uout=$(ENS_MEMBERS="${MEM}" BIRDMONITOR_UNC_REPS="${REPS}" UNC_AFTER="${meta}" UNC_PREP_TIME="${BIG5_PREP_TIME:-48:00:00}" UNC_PREP_MEM="${BIG5_PREP_MEM:-16G}" bash cluster/submit_eve_ensemble_uncertainty.sh | tee /dev/stderr)
band=$(echo "${uout}" | awk '/^band:/{print $2}'); fin=$(echo "${uout}" | awk '/^assembleall:/{print $2}')
[ -n "${band}" ] && [ -n "${fin}" ] || { echo "ERROR: could not read the band / assembleall job ids of the uncertainty chain" >&2; exit 1; }
rout=$(FORCE=1 BIRDMONITOR_UNC_MEMBERS="${MEM}" BIRDMONITOR_UNC_TAG="${TAG}" BIRDMONITOR_UNC_BANDS=48 BIRDMONITOR_UNC_REPS="${REPS}" UNC_AFTER="${band}" UNC_FINAL="${fin}" UNC_THROTTLE=100 bash cluster/submit_eve_regional.sh | tee /dev/stderr)
mm=$(echo "${rout}" | awk '/^maskmaps:/{print $2}'); ri=$(echo "${rout}" | awk '/^regionindex:/{print $2}')
[ -n "${mm}" ] && [ -n "${ri}" ] || { echo "ERROR: could not read the maskmaps / regionindex job ids" >&2; exit 1; }

echo; echo "=== 6. /data/birds and /data/birds/viz"
cp=$(COPY_INPUTS=0 sbatch --parsable --export=ALL --dependency=afterok:${mm}:${gi}:${ri} --kill-on-invalid-dep=yes cluster/eve_copy_data_birds.sbatch); echo "copy to /data/birds: ${cp}"
cn=$(sbatch --parsable --export=ALL --dependency=afterok:${cp} --kill-on-invalid-dep=yes cluster/eve_connector.sbatch); echo "connector: ${cn}"

echo; echo "=== 7. post-run: checks, then (if they pass) figures + zip, then an e-mail"
[ -n "${NOTIFY_EMAIL:-}" ] || echo "NOTE: NOTIFY_EMAIL is not set: the post-run job will run but no e-mail is sent (NOTIFY_EMAIL=\"a@ufz.de,b@ufz.de\" bash --login cluster/submit_eve_clean_run.sh)."
pr=$(sbatch --parsable --export=ALL --dependency=afterok:${cn}:${pt},afterany:${mr}:${ds} --kill-on-invalid-dep=yes cluster/eve_postrun.sbatch); echo "post-run: ${pr}"
# Failure watcher: one digest e-mail within the hour (WATCH_EVERY, seconds) of new failures anywhere in the chain (UFZ forbids Slurm's per-array-task mails; cluster/eve_chain_watch.sbatch).
if [ -n "${NOTIFY_EMAIL:-}" ]; then
  wd=$(WATCH_FIRST_JOB="${prep:-${cc}}" WATCH_UNTIL_JOB="${pr}" WATCH_SINCE="${SINCE}" sbatch --parsable --export=ALL cluster/eve_chain_watch.sbatch); echo "failure watcher: ${wd} (e-mail to ${NOTIFY_EMAIL})"
fi

echo
echo "================================================================================"
echo "ALL QUEUED (run ${RUN}, ${NSP} species). Expect about 4 days from the start of prep (v2 took about 4 days; stage times: prep ~22 h, ensemble fits ~7 h, uncertainty prepare up to ~24 h, bands ~38 h, the rest ~7 h; longer if the queue is slow). Read-only monitor:  cd ~/projects/birdMonitor && bash cluster/monitor_tonight.sh"
echo "WHEN THE POST-RUN JOB (${pr}) IS DONE:  cat outputs/${RUN}/POSTRUN_SUMMARY.txt   (the same text as the e-mail; by hand: bash cluster/post_run_checks.sh)"
echo "================================================================================"
