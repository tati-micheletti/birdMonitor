#!/bin/bash -l
# Continuity check of the land-use layers right after the preparation (tools/checkLanduseContinuity.R), with an e-mail: OK, or FLAGGED when the share of grassland or winter cereals
# jumps by more than 10% from one year to the next (the 2017 / 2022 / 2024 "humps" of the old patchwork of two crop type products). READ-ONLY; nothing in the chain waits for it.
# Sent by cluster/submit_eve_clean_run.sh after the prep job; by hand:   cd ~/projects/birdMonitor && BIRDMONITOR_RUNNAME=v3 NOTIFY_EMAIL=a@ufz.de sbatch --export=ALL cluster/eve_landuse_check.sbatch
# Output: outputs/<run>/diagnostics/landuse_continuity.{txt,csv} (and _flags.csv).
#SBATCH --job-name=landuse-check
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=8G
#SBATCH --time=02:00:00
#SBATCH --output=logs/landuse-check_%j.out
#SBATCH --error=logs/landuse-check_%j.err

set -uo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
RUN="${BIRDMONITOR_RUNNAME}"; D="outputs/${RUN}/diagnostics"; mkdir -p "${D}"
verdict=OK
unc_run Rscript tools/checkLanduseContinuity.R --out "${D}/landuse_continuity.csv" > "${D}/landuse_continuity.txt" || verdict="FAILED TO RUN"
if [ "${verdict}" = OK ] && [ -f "${D}/landuse_continuity_flags.csv" ] && grep -qE '^"(grassland|winter_cereals)"' "${D}/landuse_continuity_flags.csv"; then verdict=FLAGGED; fi
{ echo "birdMonitor run ${RUN}: land-use continuity ${verdict} ($(date '+%F %T'))"; echo
  case "${verdict}" in
    OK) echo "Grassland and winter cereals do not jump by more than 10% from one year to the next in any year: the land-use layers are one consistent series." ;;
    FLAGGED) echo "Grassland and/or winter cereals jump by more than 10% in a year (list below). If the years are 2017, 2022 or 2024 the patchwork is still there: STOP the chain (scancel) and look at ${D}/landuse_continuity.txt."; echo; grep -E '^"(grassland|winter_cereals)"' "${D}/landuse_continuity_flags.csv" ;;
    *) echo "The check could not be made: see logs/landuse-check_${SLURM_JOB_ID}.err" ;;
  esac
  echo; echo "Full table: ${D}/landuse_continuity.txt"; } > "${D}/landuse_continuity_summary.txt"
cat "${D}/landuse_continuity_summary.txt"
bash cluster/notify.sh "birdMonitor ${RUN}: land-use continuity ${verdict}" "${D}/landuse_continuity_summary.txt" || echo "NOTE: no e-mail was sent"
[ "${verdict}" != "FAILED TO RUN" ]
