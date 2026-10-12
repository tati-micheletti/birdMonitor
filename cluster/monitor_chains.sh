#!/bin/bash
# READ-ONLY: state of every stage of the running workflows (2026-10-08..12 submissions), task counts per state. Looks back 7 days. Changes nothing.
#     cd ~/projects/birdMonitor && bash cluster/monitor_chains.sh
SINCE=$(date -d '7 days ago' +%Y-%m-%d)
stage() {   # label, job id
  local label="$1" id="$2" st
  st=$(sacct -j "${id}" -X -n -o State 2>/dev/null | awk '{print $1}' | sed 's/+$//' | sort | uniq -c | awk '{printf "%s %s  ", $2, $1}')
  printf "  %-34s %-10s %s\n" "${label}" "${id}" "${st:-(not known to the scheduler)}"
}
echo "=== 1. BRT-only uncertainty (first chain, block-fold penalty = sensitivity version)"
stage "band" 63119392; stage "summarize" 63119393; stage "assemble" 63119394; stage "community" 63119395; stage "assembleAll" 63119396
echo; echo "=== 2. BRT-only climate refresh of 3 species (9 Oct) -- the chain that is currently on disk in uncertainty_honest2"
stage "prepare" 63249725; stage "band" 63249726; stage "summarize" 63249727; stage "assemble" 63249728; stage "community" 63249729; stage "assembleAll" 63249730
stage "regionband" 63249731; stage "regionassemble" 63249732; stage "regionindex" 63249733; stage "assembleAll (Germany)" 63249734; stage "maskmaps" 63249735
echo; echo "=== 3. THE BIG 5, baseline (finished 9 Oct)"
stage "ensemble means (climate)" 63196758; stage "ensemble mean landscape" 63196759; stage "ensemble mean habitat" 63196760
stage "meta-model" 63196761; stage "index (whole box)" 63196762; stage "mask Germany" 63196763; stage "index (Germany only)" 63196764
echo; echo "=== 4. THE BIG 5, uncertainty (25 replicates): prepare rerun -> ridge redo -> band -> ... (submitted 9-10 Oct)"
stage "prepare (rerun, 8 species)" 63257254
for id in $(sacct -S "${SINCE}" -X -n --name=unc-ridgeredo -o JobID 2>/dev/null | awk '{print $1}' | sed 's/_.*//' | sort -un | tail -1); do stage "ridge redo (all 11 species)" "${id}"; done
stage "band (528 tasks)" 63257289; stage "summarize" 63257290; stage "assemble" 63257291; stage "community" 63257292; stage "assembleAll" 63257293
stage "regionband" 63257306; stage "regionassemble" 63257307; stage "regionindex" 63257308; stage "assembleAll (Germany)" 63257309; stage "maskmaps" 63257310
echo; echo "=== 5. NEWEST chain started with a covcache job in the last 7 days (e.g. the BRT-only ridge-rule redo), found by itself"
first=$(sacct -S "${SINCE}" -X -n --name=unc-covcache -o JobID 2>/dev/null | awk '{print $1}' | sed 's/_.*//' | sort -un | tail -1)
if [ -z "${first}" ]; then
  echo "  no covcache job found"
else
  echo "  (newest covcache job: ${first}; every line below was submitted at or after it)"
  sacct -S "${SINCE}" -X -n -o JobID%22,JobName%22,State%14 2>/dev/null | awk -v f="${first}" '
    { split($1, a, "_"); if (a[1] + 0 >= f + 0) { st = $3; sub(/\+$/, "", st); k = a[1] "|" $2 "|" st; c[k]++; if (!(k in o)) o[k] = ++n } }
    END { for (k in c) { split(k, b, "|"); printf "%d  %-10s %-22s %-14s %d task(s)\n", o[k], b[1], b[2], b[3], c[k] } }' | sort -n | cut -d' ' -f3- | grep -vE "preval|germany-share|floor|diag"
  echo "  --- still waiting in the queue (a waiting job array is listed once, not per task):"
  squeue -u "${USER}" -h -o "%A %j %T" | awk -v f="${first}" '$1 + 0 >= f + 0 && $3 == "PENDING" { printf "  %-10s %-22s %s\n", $1, $2, $3 }' | sort -u
fi
echo; echo "=== problems since ${SINCE} that are NOT the known, fixed ones:"
sacct -S "${SINCE}" -X -n --format=JobID%16,JobName%24,State%14,Elapsed | grep -E "FAILED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL" | grep -vE "preval|germany-share|63196419_4|63117587_1|63196765|63200690_|63124757" || echo "none"
