#!/bin/bash
# READ-ONLY: state of every stage of the running workflows (2026-10-08/09 submissions), task counts per state. Changes nothing.
#     cd ~/projects/birdMonitor && bash cluster/monitor_chains.sh
stage() {   # label, job id
  local label="$1" id="$2" st
  st=$(sacct -j "${id}" -X -n -o State 2>/dev/null | awk '{print $1}' | sed 's/+$//' | sort | uniq -c | awk '{printf "%s %s  ", $2, $1}')
  printf "  %-34s %-10s %s\n" "${label}" "${id}" "${st:-(not known to the scheduler)}"
}
echo "=== 1. BRT-only uncertainty (main chain)"
stage "band (last stage that ran)" 63119392; stage "summarize" 63119393; stage "assemble" 63119394; stage "community" 63119395; stage "assembleAll" 63119396
echo; echo "=== 2. BRT-only regional index + Germany-only intervals and maps"
stage "regionband" 63196413; stage "regionassemble" 63196414; stage "regionindex" 63196415; stage "assembleAll (Germany)" 63196416; stage "maskmaps" 63196417
echo; echo "=== 3. THE BIG 5, baseline"
stage "fit GAM climate (task 4)" 63196700; stage "fit GAM landscape" 63196701; stage "fit GAM habitat" 63196702
stage "fit GLM landscape" 63196422; stage "fit RF landscape" 63196424; stage "fit NN landscape" 63196425
stage "fit GLM habitat" 63196426; stage "fit RF habitat" 63196428; stage "fit NN habitat" 63196429
stage "ensemble mean climate" 63196758; stage "ensemble mean landscape" 63196759; stage "ensemble mean habitat" 63196760
stage "meta-model" 63196761; stage "index (whole box)" 63196762; stage "mask Germany" 63196763; stage "index (Germany only)" 63196764
echo; echo "=== 4. THE BIG 5, uncertainty (25 replicates): the LATEST chain, found by itself (from the newest covcache job onwards)"
first=$(sacct -S today -X -n --name=unc-covcache -o JobID 2>/dev/null | awk '{print $1}' | sed 's/_.*//' | sort -un | tail -1)
if [ -z "${first}" ]; then
  echo "  no covcache job found today: the big 5 uncertainty chain has not been submitted"
else
  echo "  (newest covcache job: ${first}; every line below was submitted at or after it)"
  sacct -S today -X -n -o JobID%22,JobName%22,State%14 2>/dev/null | awk -v f="${first}" '
    { split($1, a, "_"); if (a[1] + 0 >= f + 0) { st = $3; sub(/\+$/, "", st); k = a[1] "|" $2 "|" st; c[k]++; if (!(k in o)) o[k] = ++n } }
    END { for (k in c) { split(k, b, "|"); printf "%d  %-10s %-22s %-14s %d task(s)\n", o[k], b[1], b[2], b[3], c[k] } }' | sort -n | cut -d' ' -f3-
fi
echo; echo "=== problems today (failed, out of memory, time limit):"
sacct -S today -X -n --format=JobID%16,JobName%24,State%14,Elapsed | grep -E "FAILED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL" | grep -vE "preval|germany-share|63196419_4|63117587_1|63196765" || echo "none new"
