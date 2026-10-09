#!/bin/bash
# READ-ONLY: how long did the tasks of finished jobs take? Per job id: number of tasks, shortest, average and longest task, and the wall time from the first
# task's start to the last task's end. Changes nothing.
#     cd ~/projects/birdMonitor && bash cluster/job_timings.sh <jobid> [<jobid> ...]
to_hours() {   # [D-]HH:MM:SS -> hours
  awk -v t="$1" 'BEGIN { d = 0; if (index(t, "-")) { split(t, p, "-"); d = p[1]; t = p[2] } n = split(t, a, ":"); h = (n == 3) ? a[1] + a[2] / 60 + a[3] / 3600 : (n == 2 ? a[1] / 60 + a[2] / 3600 : 0); printf "%.2f", d * 24 + h }'
}
printf "%-10s %-22s %6s %9s %9s %9s %14s\n" "job" "name" "tasks" "min (h)" "mean (h)" "max (h)" "wall (h)"
for id in "$@"; do
  rows=$(sacct -j "${id}" -X -n -P -o JobName,Elapsed,Start,End,State 2>/dev/null | grep -v "^$")
  [ -z "${rows}" ] && { printf "%-10s (not known to the scheduler)\n" "${id}"; continue; }
  name=$(echo "${rows}" | head -1 | cut -d'|' -f1)
  hrs=$(echo "${rows}" | cut -d'|' -f2 | while read -r e; do to_hours "${e}"; echo; done | grep -v "^$")
  n=$(echo "${hrs}" | wc -l)
  mn=$(echo "${hrs}" | sort -n | head -1); mx=$(echo "${hrs}" | sort -n | tail -1)
  mean=$(echo "${hrs}" | awk '{s += $1} END { printf "%.2f", s / NR }')
  first=$(echo "${rows}" | cut -d'|' -f3 | grep -v "Unknown" | sort | head -1); last=$(echo "${rows}" | cut -d'|' -f4 | grep -v "Unknown" | sort | tail -1)
  wall="n/a"
  if [ -n "${first}" ] && [ -n "${last}" ]; then wall=$(awk -v a="$(date -d "${first}" +%s)" -v b="$(date -d "${last}" +%s)" 'BEGIN { printf "%.1f", (b - a) / 3600 }'); fi
  printf "%-10s %-22s %6s %9s %9s %9s %14s\n" "${id}" "${name}" "${n}" "${mn}" "${mean}" "${mx}" "${wall}"
done
