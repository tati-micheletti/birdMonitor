#!/bin/bash -l
# READ-ONLY on the model outputs. Builds on EVE what was built on the PC for the Steering Consortium (2026-10-16):
#   1. the csv copies of the two DDA territory workbooks (tools/convertDdaTerritories.py, python standard library only; the raw xlsx files are not touched),
#   2. section S9 of tools/makeStCoFigures.R: S9_closest_comparison(.png, _german.png), S9_observed_vs_modelled_combined/_species and the tables,
#      with our MSI from the main model and the Monte Carlo band (needs outputs/<run>/uncertainty_*/<Species>/area_mean_replicates_germany.csv),
#   3. the same-plot panel (tools/panelTrendAnalysis.R) from outputs/<run>/panel_trend_check/*.csv (written by cluster/eve_panel_trend_check.sbatch).
#   sbatch cluster/eve_closest_comparison.sbatch        -> outputs/<run>/figures_fullreport/ (S9) and outputs/<run>/panel_trend_check/ (panel_*.png, panel_*.csv)
#SBATCH --job-name=closest-cmp
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=16G
#SBATCH --time=01:00:00
#SBATCH --output=logs/closest-cmp_%j.out
#SBATCH --error=logs/closest-cmp_%j.err

set -euo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
RUN="${BIRDMONITOR_RUNNAME:-test4}"

echo "=== 0. checks"
Rscript -e 'if (!requireNamespace("data.table", quietly = TRUE)) { cat("ERROR: the R package data.table is not installed for this R\n"); quit(status = 1) }'
PY="$(command -v python3 || true)"
if [ -z "${PY}" ]; then module load Python >/dev/null 2>&1 || true; PY="$(command -v python3 || true)"; fi
[ -n "${PY}" ] || { echo "ERROR: python3 not found on $(hostname)" >&2; exit 1; }
echo "python: ${PY} ($(${PY} --version 2>&1))"

echo "=== 1. csv copies of the DDA workbooks"
"${PY}" tools/convertDdaTerritories.py
check() { got="$(sha256sum "inputs/response/processed/territories_csv/$1" | cut -d' ' -f1)"
  if [ "${got}" = "$2" ]; then echo "$1: identical to the copy used on the PC (2026-10-16)"; else echo "WARNING: $1 differs from the copy used on the PC: ${got}" >&2; fi; }
check dda_data.csv 566e07d4cf5dbca37d63858fd2ed601dc34d72b8c991d6ed6356cdaf6fc1dc2b
check dda_visits.csv 3fee3f754e79b2563b121f1063380c6b0fbfe8457a5d382a46585fc7645f557a

echo "=== 2. figures S9 (run ${RUN})"
unc_run Rscript tools/makeStCoFigures.R --run "${RUN}" --variants big5 --sections S9

echo "=== 3. same-plot panel"
Rscript tools/panelTrendAnalysis.R --run "${RUN}"
echo "=== done: outputs/${RUN}/figures_fullreport/S3_indices/S9_closest_comparison*.png, outputs/${RUN}/panel_trend_check/panel_*.png"
