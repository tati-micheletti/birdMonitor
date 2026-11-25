#!/bin/bash -l
# DIAGNOSTIC (2026-11-22): run tools/diagGamAlt.R INSIDE the allocation of the running diag-gam job (srun --overlap), using its free cores:
#   srun --jobid=<diag-gam job> --overlap -N1 -n1 -c 6 bash ~/projects/birdMonitor/cluster/diag_alt_launch.sh
cd ~/projects/birdMonitor
module load GCC/13.3.0 OpenMPI/5.0.5 R/4.5.1 GDAL/3.10.3 CMake ImageMagick/7.1.1-38 UDUNITS/2.2.28
export BIRDMONITOR_SKIP_INSTALL=1
while IFS= read -r line; do case "${line}" in UNC_DONE_MARKER=*|BIRDMONITOR_UNC_CORES=*|pid=*|"") continue ;; esac; export "${line?}"; done < logs/env_s2v2.raw
export BIRDMONITOR_UNC_CORES=6
export TMPDIR=/work/${USER}/birdMonitor/tmp/diagalt_$$; mkdir -p "${TMPDIR}"
Rscript tools/diagGamAlt.R --step diag --index 1 --diagpairs 4:2,5:1 --diagcap 25
