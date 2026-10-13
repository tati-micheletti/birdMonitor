#!/bin/bash -l
# Copies inputs and results to /data/birds (see cluster/copy_to_data_birds.sh; run its sizes and dry modes first).
# One cpu is enough (the copy is limited by the file system). Resumable: submit it again if it hits the time limit.
#   cd ~/projects/birdMonitor && sbatch cluster/eve_copy_data_birds.sbatch
#   with the per-replicate predictions as well:  COPY_PRED=1 sbatch --export=ALL cluster/eve_copy_data_birds.sbatch
#SBATCH --job-name=copy-databirds
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=4G
#SBATCH --time=48:00:00
#SBATCH --output=logs/copy-databirds_%j.out
#SBATCH --error=logs/copy-databirds_%j.err

set -euo pipefail
cd "${SLURM_SUBMIT_DIR}"
mkdir -p logs
MODE=copy CONFIRM=1 bash cluster/copy_to_data_birds.sh
