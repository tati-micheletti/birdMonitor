#!/bin/bash -l
# The end of a full run: (1) the end-of-run checks (cluster/post_run_checks.sh); only if they PASS: (2) all figures (tools/makeResultFigures.R, section list of the script),
# (3) package A of cluster/pack_downloads.sh (the zip/tar for the people who check the results), (4) an e-mail to NOTIFY_EMAIL with the verdict.
# If the checks FAIL, no figures and no package are made and the e-mail says so. The text of the e-mail is also kept in outputs/<run>/POSTRUN_SUMMARY.txt.
# Sent at the end of cluster/submit_eve_clean_run.sh (after the connector); can also be sent by hand:
#   cd ~/projects/birdMonitor && BIRDMONITOR_RUNNAME=v2 NOTIFY_EMAIL="a@ufz.de,b@ufz.de" sbatch --export=ALL cluster/eve_postrun.sbatch
#   POSTRUN_SKIP_FIGURES=1 (figures already made)   FIG_ARGS="--sections S6" (options of tools/makeResultFigures.R)
# The results page (pdf_export/5_Figure_reference.Rmd) is made on the PC afterwards, from the figures in the package: BIRDMONITOR_RUNNAME=<run> Rscript R/render_figure_reference.R
#SBATCH --job-name=postrun
#SBATCH --cpus-per-task=2
#SBATCH --mem-per-cpu=12G
#SBATCH --time=08:00:00
#SBATCH --output=logs/postrun_%j.out
#SBATCH --error=logs/postrun_%j.err

set -uo pipefail
mkdir -p logs
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
RUN="${BIRDMONITOR_RUNNAME}"; O="outputs/${RUN}"; SUMMARY="${O}/POSTRUN_SUMMARY.txt"
DL="${PACK_OUT:-/work/${USER}/birdMonitor/download}"
verdict=PASS; detail=""

bash cluster/post_run_checks.sh || verdict=FAIL

if [ "${verdict}" = PASS ]; then
  if [ "${POSTRUN_SKIP_FIGURES:-0}" = "1" ]; then detail="${detail}Figures: not made in this job (POSTRUN_SKIP_FIGURES=1).
"
  else
    # shellcheck disable=SC2086
    if unc_run Rscript tools/makeResultFigures.R --run "${RUN}" --variants big5 ${FIG_ARGS:-}; then
      nskip=$(( $(wc -l < "${O}/figures_fullreport/skipped.csv" 2>/dev/null || echo 1) - 1 ))
      detail="${detail}Figures: ${O}/figures_fullreport (figures that could not be made: ${nskip}, see skipped.csv).
"
    else verdict=FAIL; detail="${detail}Figures: makeResultFigures.R FAILED (see logs/postrun_${SLURM_JOB_ID}.err).
"; fi
  fi
fi
if [ "${verdict}" = PASS ]; then
  if bash cluster/pack_downloads.sh A; then
    detail="${detail}Package A (tables, figures, indices, regional rasters, accuracy files): ${DL}/figures_A_${RUN}.tar ($(du -h "${DL}/figures_A_${RUN}.tar" | cut -f1))
Sizes of all packages: $(bash cluster/pack_downloads.sh sizes 2>/dev/null | grep '^package' | tr '\n' ';')
Download with WinSCP, unpack, then on the PC:  BIRDMONITOR_RUNNAME=${RUN} Rscript R/render_figure_reference.R
"
  else verdict=FAIL; detail="${detail}Package A: pack_downloads.sh FAILED (see logs/postrun_${SLURM_JOB_ID}.err).
"; fi
fi

{ echo "birdMonitor run ${RUN}: post-run ${verdict} ($(date '+%F %T'), job ${SLURM_JOB_ID}, ${USER})"; echo; cat "${O}/POSTRUN_CHECKS.txt" 2>/dev/null; echo; printf '%s' "${detail}"
  [ "${verdict}" = PASS ] || echo "Nothing was packed. Read logs/postrun_${SLURM_JOB_ID}.out and ${O}/POSTRUN_CHECKS.txt."; } > "${SUMMARY}"
cat "${SUMMARY}"
bash cluster/notify.sh "birdMonitor ${RUN}: post-run ${verdict}" "${SUMMARY}" || echo "NOTE: no e-mail was sent; the summary is in ${SUMMARY}"
[ "${verdict}" = PASS ]
