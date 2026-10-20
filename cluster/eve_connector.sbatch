#!/bin/bash -l
# Brings the newest results of every species into the viz folder the Bird Monitor reads (modules/connector_Monitor, tools/runConnector.R).
# Reads the run folders in /data/birds/birdMonitor/outputs (the permanent copy, made by cluster/copy_to_data_birds.sh), adds to /data/birds/viz, deletes nothing.
#   cd ~/projects/birdMonitor && git pull && sbatch cluster/eve_connector.sbatch
#   BIRDMONITOR_VIZ_DRY=1 sbatch --export=ALL cluster/eve_connector.sbatch      -> only reports what would be written
#SBATCH --job-name=connector
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=8G
#SBATCH --time=06:00:00
#SBATCH --output=logs/connector_%j.out
#SBATCH --error=logs/connector_%j.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
unc_run Rscript tools/runConnector.R
