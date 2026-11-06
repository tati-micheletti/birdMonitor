#!/bin/bash -l
# TEST of the CTM -> HCTM recode for 2024-2025 (DECISIONS 2026-11-06): refits the matrix INSIDE Germany (CTM "other" split into mapped-but-unclassified and no data) and applies it to CTM v302 2024 the way
# computeLanduse() does, against HCTM 2023 and the matrix in use now. READ-ONLY on the raw maps and on data/; writes to outputs/recode_test/ only. Memory is a first guess (peak unknown): read it with mem_history.py afterwards and put it in the ledger.
#   cd ~/projects/birdMonitor && sbatch cluster/eve_recode_test.sbatch        then:   tail -n 32 outputs/recode_test/recode_test.txt
#SBATCH --job-name=recode-test
#SBATCH --cpus-per-task=1
#SBATCH --mem-per-cpu=12G
#SBATCH --time=03:00:00
#SBATCH --output=logs/recode-test_%j.out
#SBATCH --error=logs/recode-test_%j.err

set -uo pipefail
mkdir -p logs outputs/recode_test
source "${SLURM_SUBMIT_DIR}/cluster/eve_unc_common.sh"
unc_run Rscript tools/buildLanduseRecode.R --points 1.5e6 --out-dir outputs/recode_test > outputs/recode_test/recode_test.txt 2>&1
