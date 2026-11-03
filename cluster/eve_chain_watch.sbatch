#!/bin/bash -l
# Failure watcher of a run chain: every WATCH_EVERY seconds (default 3600 = hourly) it looks for jobs of the chain that FAILED / TIMEOUT / OUT_OF_MEMORY / NODE_FAIL and e-mails ONE digest
# (cluster/notify.sh) when there are new ones, never more than one e-mail per round. It replaces the per-task mails of Slurm (--mail-type=...,ARRAY_TASKS), which UFZ forbids,
# while plain --mail-type=FAIL reports an array only when ALL its tasks have ended. A job cancelled because a job before it failed is counted in the digest, not listed as a failure.
# It ends when the post-run job has left the queue (finished, failed or cancelled), after one last check; after 23 h it sends itself again (the time limit of the job).
# Started by cluster/submit_eve_clean_run.sh when NOTIFY_EMAIL is set. Environment: NOTIFY_EMAIL, WATCH_FIRST_JOB (first job id of the chain), WATCH_UNTIL_JOB (the post-run job),
# WATCH_SINCE (date of the submission, YYYY-MM-DDTHH:MM:SS), WATCH_EVERY. Jobs whose name contains preval, mail-test or chain-watch are not watched.
#SBATCH --job-name=chain-watch
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=500M
#SBATCH --time=23:30:00
#SBATCH --output=logs/chain-watch_%j.out
#SBATCH --error=logs/chain-watch_%j.err

set -uo pipefail
cd "${SLURM_SUBMIT_DIR}"
: "${WATCH_FIRST_JOB:?}" "${WATCH_UNTIL_JOB:?}" "${WATCH_SINCE:?}"
EVERY="${WATCH_EVERY:-3600}"
STATE="logs/.chain_watch_${WATCH_UNTIL_JOB}.reported"; touch "${STATE}"      # JobID|JobName|State already reported
LIMIT=$(( $(date +%s) + 23 * 3600 ))

rows() { sacct -u "${USER}" -S "${WATCH_SINCE}" -X -n -P -o JobID,JobName,State | awk -F'|' -v first="${WATCH_FIRST_JOB}" '
  { split($1, a, "_"); if (a[1] + 0 >= first + 0 && $2 !~ /preval|mail-test|chain-watch/) print }'; }
failed()    { rows | awk -F'|' '$3 ~ /^(FAILED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL|BOOT_FAIL)/' | grep -vxFf "${STATE}" || true; }
ncancelled() { rows | awk -F'|' '$3 ~ /^CANCELLED/' | wc -l; }

report() {      # $1 = new failures (JobID|JobName|State per line)
  local body; body=$(mktemp)
  { echo "birdMonitor chain (post-run job ${WATCH_UNTIL_JOB}): new failed jobs since the last check ($(date '+%F %T'))"; echo
    echo "$1" | awk -F'|' '{ n[$2 " " $3]++ } END { for (k in n) printf "  %4d x %s\n", n[k], k }' | sort -k3
    echo; echo "First ones (job id | name | state):"; echo "$1" | head -15
    [ "$(echo "$1" | wc -l)" -le 15 ] || echo "  ... and $(( $(echo "$1" | wc -l) - 15 )) more"
    echo; echo "Jobs cancelled so far (a failure upstream cancels what depends on it): $(ncancelled)"
    echo "Look:  sacct -u ${USER} -S ${WATCH_SINCE} -X -n -P -o JobID,JobName,State,Elapsed | grep -E 'FAILED|TIMEOUT|OUT_OF_MEMORY|NODE_FAIL'   and   logs/<jobname>_<jobid>*.err"; } > "${body}"
  bash cluster/notify.sh "birdMonitor chain: $(echo "$1" | wc -l) job(s) FAILED" "${body}" && echo "$1" >> "${STATE}"
  rm -f "${body}"
}

while true; do
  new=$(failed)
  [ -z "${new}" ] || report "${new}"
  if ! squeue -h -j "${WATCH_UNTIL_JOB}" -o %i 2>/dev/null | grep -q .; then
    new=$(failed); [ -z "${new}" ] || report "${new}"
    echo "$(date '+%F %T') post-run job ${WATCH_UNTIL_JOB} has left the queue: watcher ends."; break
  fi
  if [ "$(date +%s)" -ge "${LIMIT}" ]; then
    echo "$(date '+%F %T') 23 h reached: sending the watcher again."; sbatch --export=ALL cluster/eve_chain_watch.sbatch; break
  fi
  sleep "${EVERY}"
done
