#!/bin/bash
# Status of a set of SLURM jobs (arrays included): how many tasks are in which state, any problem, and what is still queued.
#   bash cluster/status.sh <jobid> [<jobid> ...]
# Read-only. States: COMPLETED = done, RUNNING, PENDING = waiting; FAILED / OUT_OF_MEMORY / TIMEOUT / CANCELLED need a look.
if [ "$#" -eq 0 ]; then echo "usage: bash cluster/status.sh <jobid> [<jobid> ...]"; exit 1; fi
echo "=== state of each job (number of tasks per state)"
for j in "$@"; do
  name=$(sacct -j "$j" -X -n --format=JobName%18 2>/dev/null | head -1 | xargs)
  states=$(sacct -j "$j" -X -n --format=State%14 2>/dev/null | sort | uniq -c | awk '{printf "%s %s | ", $1, $2}')
  printf "%-10s %-18s %s\n" "$j" "${name:-?}" "${states:-not started (waiting for its dependency)}"
done
echo "=== problems"
ids=$(IFS=,; echo "$*")
sacct -j "$ids" -X -n --format=JobID%16,JobName%16,State%14,Elapsed,ExitCode 2>/dev/null | grep -E "FAILED|OUT_OF_MEMORY|TIMEOUT|CANCELLED|NODE_FAIL" || echo "none"
echo "=== in the queue now"
squeue -u "$USER" -o "%.14i %.16j %.8T %.10M %R" | head -12
