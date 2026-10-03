#!/bin/bash
# One-time setup of birdMonitor for ONE user on EVE (everyone needs their own: R packages
# and the /work folders are per user). Safe to run again -- it skips what is already done.
#
#   cd ~/projects/birdMonitor
#   bash --login cluster/setup_eve.sh
#
# What it does:
#   1. loads the EVE modules (R 4.5.1 + GDAL etc.)
#   2. makes /work/$USER/birdMonitor/{inputs,cache,outputs,tmp}
#   3. turns the repo's inputs/ cache/ outputs/ into shortcuts (symlinks) to those folders,
#      because /home is small and EVE kills jobs that work with scientific data in /home
#   4. installs every R package (30-60 min the first time)
#   5. submits a 10-minute smoke test (cluster/eve_smoketest.sbatch)
set -euo pipefail
cd "$(dirname "$0")/.."
REPO="$(pwd)"
WORK="/work/${USER}/birdMonitor"
MODULES="${EVE_R_MODULE:-GCC/13.3.0 OpenMPI/5.0.5 R/4.5.1 GDAL/3.10.3 CMake ImageMagick/7.1.1-38 UDUNITS/2.2.28}"

if ! type module >/dev/null 2>&1; then
  echo "The 'module' command is missing. Run this script as:  bash --login cluster/setup_eve.sh" >&2
  exit 1
fi

echo "== 1/5 Loading modules: ${MODULES}"
module load ${MODULES}
R --version | head -1

echo "== 2/5 Creating ${WORK}"
mkdir -p "${WORK}"/{inputs,cache,outputs,tmp}

echo "== 3/5 Linking inputs/ cache/ outputs/ to ${WORK}"
for d in inputs cache outputs; do
  if [ -L "${REPO}/${d}" ]; then
    echo "   ${d}: already a link -> $(readlink "${REPO}/${d}")"
  elif [ -d "${REPO}/${d}" ] && [ -z "$(ls -A "${REPO}/${d}")" ]; then
    rmdir "${REPO}/${d}"
    ln -s "${WORK}/${d}" "${REPO}/${d}"
    echo "   ${d}: empty folder replaced by a link"
  elif [ -e "${REPO}/${d}" ]; then
    echo "   ${d}: exists and is NOT empty -- move its contents to ${WORK}/${d}/ yourself, then run this again." >&2
    exit 1
  else
    ln -s "${WORK}/${d}" "${REPO}/${d}"
    echo "   ${d}: link created"
  fi
done

echo "== 4/5 Installing R packages (first time: 30-60 minutes; keep this window open)"
BIRDMONITOR_INSTALL_ONLY=1 Rscript runMe.R

echo "== 5/5 Submitting the smoke test"
mkdir -p logs
sbatch cluster/eve_smoketest.sbatch
echo
echo "Done. In about a minute:  cat logs/smoketest_<jobnumber>.err   -- look for: SMOKETEST: ALL OK"
