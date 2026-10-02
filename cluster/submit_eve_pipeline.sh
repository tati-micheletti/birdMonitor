#!/bin/bash
# Submit the WHOLE birdMonitor workflow to EVE as one dependency chain:
#
#   prep (dataPrep_Monitor + inputs_Monitor)
#     -> model arrays: europe, habitat, landscape  (one task per species; the
#        meta-model runs inside whichever scale task finishes last for a species)
#       -> index (runIndex_Monitor)
#
# Run from anywhere inside the repo, ON an EVE login node, after:
#   - VPN + SSH to EVE, repo cloned, inputs/ and cache/ rsync'd up
#   - R packages installed (login node -- compute nodes have throttled internet)
#
# Usage:
#   EVE_R_MODULE=<name from `module spider R`> \
#   [EVE_PARTITION=<partition from `sinfo -s`>] \
#   [BIRDMONITOR_RUNNAME=test4] \
#     bash cluster/submit_eve_pipeline.sh
#
# BIRDMONITOR_RUNNAME is the run folder every stage writes to
# (outputs/<runName>/), so it MUST be the same across stages -- this script
# exports it once for all of them. Default test4.
#
# If the prep job fails, the three model arrays stay pending as
# "DependencyNeverSatisfied" -- cancel them with scancel and re-submit once
# the cause is fixed (Cache() resumes, so nothing already computed is redone).

set -euo pipefail
cd "$(dirname "$0")/.."

if [ -z "${EVE_R_MODULE:-}" ]; then
  echo "EVE_R_MODULE is not set. Find the module name with \`module spider R\`," >&2
  echo "then re-run:  EVE_R_MODULE=<name> bash cluster/submit_eve_pipeline.sh" >&2
  exit 1
fi

export EVE_R_MODULE
export BIRDMONITOR_RUNNAME="${BIRDMONITOR_RUNNAME:-test4}"

# SLURM does not create the directory for --output/--error files, so it has
# to exist before submission, not just inside the job script.
mkdir -p logs

PART=()
if [ -n "${EVE_PARTITION:-}" ]; then PART=(--partition="${EVE_PARTITION}"); fi

echo "Run name: ${BIRDMONITOR_RUNNAME} | R module: ${EVE_R_MODULE} | partition: ${EVE_PARTITION:-<EVE default>}"

prep=$(sbatch --parsable "${PART[@]+"${PART[@]}"}" cluster/eve_prep.sbatch)
echo "prep:      ${prep}"

arrayIds=()
for scale in europe habitat landscape; do
  id=$(sbatch --parsable "${PART[@]+"${PART[@]}"}" --dependency=afterok:"${prep}" \
         modules/models_Monitor/cluster/eve_array_${scale}.sbatch)
  echo "${scale}: ${id}"
  arrayIds+=("${id}")
done

dep=$(IFS=:; echo "${arrayIds[*]}")
idx=$(sbatch --parsable "${PART[@]+"${PART[@]}"}" --dependency=afterany:"${dep}" cluster/eve_index.sbatch)
echo "index:     ${idx}"

echo
echo "Submitted. Monitor with: squeue -u \$USER   |   logs in ./logs/"
