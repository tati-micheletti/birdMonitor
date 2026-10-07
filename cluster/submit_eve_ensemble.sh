#!/bin/bash
# Submit the ENSEMBLE workflow to EVE as one dependency chain. Which models are fitted and which ensembles are built is chosen by names:
#
#   FIT      one array per (scale, model): fit + block CV + maps for GLM / GAM / random forest / neural network (ENS_ALGOS)
#            (the BRT is not refitted: it is the existing BRT workflow, and joins the ensembles by name)
#   ENSEMBLE for every member set in ENS_VARIANTS and every scale: the mean of the members' maps, the ensemble's block-CV performance and
#            the honest meta-model inputs (cheap: maps are averaged, nothing is refitted)
#   META     one meta-model per member set (folder metamodel_<label>_<name>), honest weights
#   INDEX    one index per member set (annual_report_<name>, regional_index_<name>)
#
# Everything is by name, so a model is turned on or off by listing it, and "one out, two out" experiments are just more member sets:
#   ENS_ALGOS="glm gam rf"                       the models to FIT (default; add nn to include the neural network)
#   ENS_VARIANTS="brt,glm,gam,rf"                member sets of the ensembles, ';'-separated (default: the Wiedenroth set, called "ens").
#                                                 Examples: "brt,glm,gam,rf;brt;brt,gam;glm,gam,rf;brt,glm,gam,rf,nn"
#                                                 (a single member = that model alone; names: brt glm gam rf nn; see ensTag() for the folder names)
#   ENS_SCALES="climate landscape habitat"       which scales (default all three)
#   ENS_AFTER=<job id(s), colon-separated>       wait for these first (e.g. the europe array of cluster/rerun_after_climate_fix.sh)
#   ENS_THROTTLE=40                              max tasks of one array running at once
# To add ensembles later WITHOUT refitting, run with ENS_ALGOS="" (nothing is refitted; the member maps already exist) and the new ENS_VARIANTS.
#
#     cd ~/projects/birdMonitor && bash --login cluster/submit_eve_ensemble.sh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs
export BIRDMONITOR_RUNNAME="${BIRDMONITOR_RUNNAME:-test4}"
read -r -a SCALES <<< "${ENS_SCALES:-climate landscape habitat}"
read -r -a ALGOS <<< "${ENS_ALGOS-glm gam rf}"
IFS=';' read -r -a VARIANTS <<< "${ENS_VARIANTS:-brt,glm,gam,rf}"
THR="%${ENS_THROTTLE:-40}"
AFTER=()
if [ -n "${ENS_AFTER:-}" ]; then AFTER=(--dependency=afterok:"${ENS_AFTER}"); fi

declare -A fitIds     # scale -> colon-separated job ids of the fits of that scale
for scale in "${SCALES[@]}"; do
  fitIds[${scale}]=""
  for algo in "${ALGOS[@]}"; do
    [ -z "${algo}" ] && continue
    # resources: ranger (rf) uses all cores of the task; GLM/GAM/NN are single-threaded. The habitat maps are the slow part.
    case "${scale}:${algo}" in
      habitat:rf)    RES=(--cpus-per-task=4 --mem-per-cpu=8G --time=12:00:00);;
      habitat:*)     RES=(--cpus-per-task=1 --mem-per-cpu=12G --time=12:00:00);;
      landscape:rf)  RES=(--cpus-per-task=4 --mem-per-cpu=4G --time=06:00:00);;
      landscape:*)   RES=(--cpus-per-task=1 --mem-per-cpu=8G --time=06:00:00);;
      climate:rf)    RES=(--cpus-per-task=2 --mem-per-cpu=4G --time=03:00:00);;
      *)             RES=(--cpus-per-task=1 --mem-per-cpu=8G --time=03:00:00);;
    esac
    id=$(ENS_SCALE="${scale}" ENS_ALGO="${algo}" sbatch --parsable --export=ALL --job-name="ens-${scale}-${algo}" --array="1-11${THR}" "${RES[@]}" \
         "${AFTER[@]+"${AFTER[@]}"}" cluster/eve_ens_algo.sbatch)
    echo "fit ${scale}/${algo}: ${id}"
    fitIds[${scale}]="${fitIds[${scale}]:+${fitIds[${scale}]}:}${id}"
  done
done

for members in "${VARIANTS[@]}"; do
  # the name of the ensemble = ensTag() in R: the default set brt+glm+gam+rf is "ens", any other set "ens_<members in canonical order>"
  sel=(); for m in brt glm gam rf nn; do if [[ ",${members}," == *",${m},"* ]]; then sel+=("${m}"); fi; done
  joined=$(IFS=-; echo "${sel[*]}")
  if [ "${joined}" = "brt-glm-gam-rf" ]; then tag="ens"; else tag="ens_${joined}"; fi
  ensIds=()
  for scale in "${SCALES[@]}"; do
    DEP=()
    if [ -n "${fitIds[${scale}]}" ]; then DEP=(--dependency=afterok:"${fitIds[${scale}]}" --kill-on-invalid-dep=yes);
    elif [ -n "${ENS_AFTER:-}" ]; then DEP=(--dependency=afterok:"${ENS_AFTER}"); fi
    id=$(ENS_SCALE="${scale}" ENS_MEMBERS="${members}" sbatch --parsable --export=ALL --job-name="ens-mean-${scale}" "${DEP[@]+"${DEP[@]}"}" cluster/eve_ens_ens.sbatch)
    echo "ensemble ${tag} / ${scale}: ${id}"; ensIds+=("${id}")
  done
  depE=$(IFS=:; echo "${ensIds[*]}")
  meta=$(BIRDMONITOR_META_SOURCE="${tag}" sbatch --parsable --export=ALL --job-name="ens-meta-${tag}" --dependency=afterok:"${depE}" --kill-on-invalid-dep=yes modules/models_Monitor/cluster/eve_array_meta.sbatch)
  echo "meta ${tag}: ${meta}"
  idx=$(BIRDMONITOR_INDEX_TAG="${tag}" sbatch --parsable --export=ALL --job-name="ens-index-${tag}" --dependency=afterok:"${meta}" --kill-on-invalid-dep=yes cluster/eve_index.sbatch)
  echo "index ${tag}: ${idx}"
done
echo
echo "Submitted. Monitor with: squeue -u \$USER   |   logs in ./logs/ens-*"
