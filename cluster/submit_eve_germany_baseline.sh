#!/bin/bash
# Baseline index on Germany-only maps: (1) Germany-only copies of the meta-model maps (array over the species), then (2) the index run on them
# with BIRDMONITOR_INDEX_TAG=germany -> outputs/<run>/annual_report_germany/ and regional_index_germany/ (the rectangle versions stay as they are,
# so the two can be compared). See DECISIONS.md 2026-10-08.
#     bash --login cluster/submit_eve_germany_baseline.sh
set -euo pipefail
cd "$(dirname "$0")/.."
mkdir -p logs
mk=$(sbatch --parsable cluster/eve_mask_meta.sbatch); echo "mask-meta: ${mk}"
idx=$(BIRDMONITOR_INDEX_TAG=germany sbatch --parsable --export=ALL --dependency=afterok:${mk} --kill-on-invalid-dep=yes cluster/eve_index.sbatch); echo "index (germany): ${idx}"
echo
echo "CHECK AT ANY TIME (read-only):  cd ~/projects/birdMonitor && bash cluster/status.sh ${mk} ${idx}"
echo "Results: outputs/${BIRDMONITOR_RUNNAME:-test4}/annual_report_germany/  and  regional_index_germany/"
