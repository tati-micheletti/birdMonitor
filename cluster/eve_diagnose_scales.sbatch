#!/bin/bash -l
# Which scale carries the time signal? READ-ONLY. For every roster species: the country mean of each scale's ensemble map (climate, landscape, habitat) and of the meta-model per year,
# the spread of the replicates, and for the most influential predictors of each scale their country mean per year (tools/diagnoseYearJump.R, sections A-C; section C reads the BRT member).
#   cd ~/projects/birdMonitor && BIRDMONITOR_RUNNAME=v2 sbatch --export=ALL cluster/eve_diagnose_scales.sbatch
#   DIAG_ENS=<ensemble name> (default ens_brt-glm-gam-rf-nn)   DIAG_YEARS=<years> (default 2005,2010,2015:2025)
# Output: outputs/<run>/diagnostics/scale_diagnostic.txt (nothing else is written).
#SBATCH --job-name=diag-scales
#SBATCH --cpus-per-task=2
#SBATCH --mem-per-cpu=12G
#SBATCH --time=06:00:00
#SBATCH --output=logs/diag-scales_%j.out
#SBATCH --error=logs/diag-scales_%j.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
RUN="${BIRDMONITOR_RUNNAME}"; ENS="${DIAG_ENS:-ens_brt-glm-gam-rf-nn}"
SPECIES=$(tr -d '\r' < data/speciesCanonical.csv | awk -F, 'NR > 1 && $5 != "" { printf "%s%s", sep, $1; sep = "," }')
mkdir -p "outputs/${RUN}/diagnostics"
unc_run Rscript tools/diagnoseYearJump.R "${SPECIES}" --ens "${ENS}" --tag "${ENS}" --years "${DIAG_YEARS:-2005,2010,2015:2025}" --top 6 > "outputs/${RUN}/diagnostics/scale_diagnostic.txt"
echo "written: outputs/${RUN}/diagnostics/scale_diagnostic.txt"
