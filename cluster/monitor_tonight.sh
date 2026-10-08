#!/bin/bash
# READ-ONLY monitor of everything queued by cluster/submit_eve_tonight.sh (and the rest of today's jobs). Changes nothing.
#     cd ~/projects/birdMonitor && bash cluster/monitor_tonight.sh
echo "=== queue now, by job name and state (count):"
squeue -u "${USER}" -h -o "%j %T" | sort | uniq -c | sed 's/^ *//' | column -t
echo
echo "=== PROBLEMS today (failed, out of memory, time limit, node failure):"
sacct -S today -X -n --format=JobID%16,JobName%24,State%14,Elapsed | grep -E "FAILED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL" | tail -25 || true
echo "(nothing above = no problems so far)"
echo
echo "=== finished today, by job name (count of COMPLETED):"
sacct -S today -X -n --format=JobName%24,State%12 | grep COMPLETED | awk '{print $1}' | sort | uniq -c | sed 's/^ *//' | column -t
