#!/bin/bash
# READ-ONLY end-of-run checks of a finished run: the checks that were made by hand after the first clean run (v2, 3 Nov 2026), now one script.
#   bash cluster/post_run_checks.sh                       (BIRDMONITOR_RUNNAME=<run>, default v2)
# Exit code 0 = PASS, 1 = FAIL. The report is printed and also written to outputs/<run>/POSTRUN_CHECKS.txt.
# FAIL: products missing in the viz folder; a species without "RESULT: OK" in its parity check (or the wrong number of species); a regional parity that is not OK;
#       the block-CV or meta-model line of a species/scale missing in the logs of this run.
# NOTE (not a failure, for a person to read): models with a block-CV AUC below 0.70, and the lowest meta-model AUC.
# The logs of THIS run are the ones newer than outputs/<run>/RUN_INFO.txt (logs/ also holds the logs of older runs).
set -uo pipefail
cd "$(dirname "$0")/.."
RUN="${BIRDMONITOR_RUNNAME:-v2}"
TAG="${BIRDMONITOR_ENS_TAG:-ens_brt-glm-gam-rf-nn}"
VIZ="${DATA_BIRDS_VIZ:-/data/birds/viz}"
O="outputs/${RUN}"
REPORT="${O}/POSTRUN_CHECKS.txt"
[ -d "${O}" ] || { echo "STOP: ${O} does not exist (BIRDMONITOR_RUNNAME=${RUN})." >&2; exit 1; }
NSP=$(tr -d '\r' < data/speciesCanonical.csv | awk -F, 'NR > 1 && $5 != ""' | wc -l)         # species of the roster (include is not blank)
newer=(); [ -f "${O}/RUN_INFO.txt" ] && newer=(-newer "${O}/RUN_INFO.txt")
fails=0
ok()   { echo "  ok    $*"; }
bad()  { echo "  FAIL  $*"; fails=$((fails + 1)); }
note() { echo "  note  $*"; }
logsOf() { find logs -name "$1" ${newer[@]+"${newer[@]}"} -print0 | xargs -0 -r grep -h "$2" || true; }     # lines of this run's logs

{
echo "=== post-run checks | run ${RUN} | ${NSP} species | $(date '+%F %T') ==="

echo "1. products in ${VIZ}"
if [ -f "${VIZ}/_missing.csv" ]; then
  nm=$(( $(wc -l < "${VIZ}/_missing.csv") - 1 ))
  if [ "${nm}" -le 0 ]; then ok "_missing.csv is empty"; else bad "${nm} products missing (see ${VIZ}/_missing.csv)"; fi
else bad "${VIZ}/_missing.csv not found (the connector did not run)"; fi

echo "2. replicate 0 reproduces the baseline map, per species (${O}/uncertainty_${TAG})"
np=0; nok=0
for f in "${O}/uncertainty_${TAG}"/*/parity_check.txt; do
  [ -e "${f}" ] || continue
  np=$((np + 1))
  if grep -q 'RESULT: OK' "${f}"; then nok=$((nok + 1)); else bad "$(basename "$(dirname "${f}")"): $(grep RESULT "${f}" | head -1)"; fi
done
if [ "${np}" -eq "${NSP}" ] && [ "${nok}" -eq "${np}" ]; then ok "${nok} of ${NSP} species: RESULT: OK"; else bad "${nok} species OK, ${np} parity files, ${NSP} species expected"; fi

echo "3. regional index (10/20/50 km): replicate 0 against the baseline"
nr=0
for f in "${O}/uncertainty_${TAG}/regional"/regional_parity_*km.txt; do
  [ -e "${f}" ] || continue
  nr=$((nr + 1))
  if grep -q 'RESULT: OK' "${f}"; then ok "$(basename "${f}")"; else bad "$(basename "${f}") is not OK"; fi
done
[ "${nr}" -gt 0 ] || bad "no regional parity files found"

echo "4. ensemble block-CV (accuracy of the ensemble, per species and scale; logs of this run)"
cv=$(logsOf 'ens-mean_*.err' 'ensemble block-CV' | awk -F' [|] ' '
  { sp = $1; sc = $2; if (match($3, /AUC [0-9.]+/)) v[sp "|" sc] = substr($3, RSTART + 4, RLENGTH - 4) }
  END { n = 0; weak = ""; for (k in v) { n++; if (v[k] + 0 < 0.70) { split(k, p, "|"); weak = weak p[1] " " p[2] " (AUC " v[k] "); " } } print n; print weak }')
ncv=$(echo "${cv}" | sed -n 1p); weak=$(echo "${cv}" | sed -n 2p)
if [ "${ncv:-0}" -eq $((NSP * 3)) ]; then ok "${ncv} species x scale results (${NSP} species x 3 scales)"; else bad "${ncv:-0} species x scale results found, ${NSP} x 3 expected"; fi
[ -z "${weak}" ] || note "block-CV AUC below 0.70: ${weak}"

echo "5. meta-model (out-of-fold accuracy, one per species; logs of this run)"
meta=$(logsOf 'meta_*.err' 'Performance (')
nmeta=$(echo "${meta}" | grep -c 'AUC' || true)
if [ "${nmeta}" -ge "${NSP}" ]; then ok "${nmeta} meta-model results for ${NSP} species"; else bad "${nmeta} meta-model results, ${NSP} expected"; fi
minauc=$(echo "${meta}" | sed -n -E 's/.*AUC = ([0-9.]+).*/\1/p' | sort -n | head -1)
[ -z "${minauc}" ] || note "lowest meta-model AUC: ${minauc}"

echo
if [ "${fails}" -eq 0 ]; then echo "RESULT: PASS"; else echo "RESULT: FAIL (${fails} problems)"; fi
} > "${REPORT}"

cat "${REPORT}"
[ "${fails}" -eq 0 ]
