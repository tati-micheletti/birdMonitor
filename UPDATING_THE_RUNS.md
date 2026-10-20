# How to update the runs (short version)

Rule of the house: **never delete results, move them aside; never edit raw inputs.** Everything below is run on an EVE login node (VPN on) unless it says PC.

## 1. Get the latest version (PC and EVE)
```bash
cd ~/projects/birdMonitor && git pull && git submodule update --init --recursive
```
Without this you change an old version. On the PC use the same command in the repo folder.

## 2. Change what has to change (PC), then commit and push
| You want to... | Change this |
|---|---|
| add or remove a species | `data/speciesCanonical.csv` (column `include`), `data/speciesConfig_general.csv`, `data/speciesConfig_predictors.csv`. The species count is read from the roster by the submit scripts; the sbatch files with a fixed `--array=1-11` in their header (`grep -rn "array=1-" cluster modules/models_Monitor/cluster`) need the new number |
| change years | `tools/sharedConfig.R` (`predictionYears`, `sharedHabitatYears`, `sharedLandscapeYears`); one species only: `years_override` in `data/speciesConfig_general.csv` |
| change predictors or models of a species | `data/speciesConfig_predictors.csv`, `data/speciesConfig_general.csv` |
| change code | in the module: `modules/<module>/R/...` |
| run only the 10 km map of the regional index (all the Monitor shows) | `export BIRDMONITOR_REGIONAL_KM=10` before submitting (default: 10, 20, 50 km) |
| use another run folder | `export BIRDMONITOR_RUNNAME=<name>` before every step (default `test4`) |

Commit and push **the module first, then the main repo** (a module is its own repository):
```bash
cd modules/<module> && git add -A && git commit -m "..." && git push && cd ../.. && git add modules/<module> <other changed files> && git commit -m "..." && git push
```
Never change the data on EVE by hand. New input files go to `inputs/` (WinSCP) and are recorded in `DECISIONS.md`.

## 3. Send it to EVE
`git push` on the PC, then the command of step 1 on EVE. Nothing else has to be copied.

## 4. Re-run only what changed
1. Find what the change touches and **move it aside** (to `outputs/<run>/_old_<date>/`, never delete). Examples of how this is done, with `DRY_RUN=1` to list the moves first:
   `cluster/refresh_climate_3species_2026-10-09.sh` (some species), `cluster/rerun_after_climate_fix.sh` (everything that depends on a layer).
2. Submit the standard chain for **all** species. Finished results are skipped, only what was moved aside is recomputed:
```bash
cd ~/projects/birdMonitor && bash --login cluster/submit_eve_ensemble.sh                # fits, ensemble means, meta-model, index (see its header for ENS_ALGOS / ENS_VARIANTS)
cd ~/projects/birdMonitor && bash --login cluster/submit_eve_big5_uncertainty.sh        # 25 replicates, intervals, regional index, Germany-only maps
```
   **Do not set `BIRDMONITOR_SPECIES` for this**: it is a debug switch, and the steps that combine species (index, expected richness, MSI) would see only that subset.
3. Check: `bash cluster/status.sh <job ids>` (no problems), and `grep -H RESULT outputs/<run>/uncertainty*/*/parity_check.txt` (every species `RESULT: OK`).

## 5. Bring the results to the Monitor
```bash
cd ~/projects/birdMonitor && cp=$(COPY_INPUTS=0 sbatch --parsable --export=ALL cluster/eve_copy_data_birds.sbatch) && sbatch --dependency=afterok:${cp} cluster/eve_connector.sbatch
```
The first job copies the new results to `/data/birds` (permanent); the second starts when the copy has finished and puts the newest result of every species into `/data/birds/viz`.
`/data/birds/viz` is what the Monitor reads. Whatever is not there is not shown. When the connector job is done, `/data/birds/viz/_missing.csv` must be empty (otherwise a species or a layer is missing); `_manifest.csv` says which run every file came from.
The upload from `/data/birds/viz` to the bucket is not part of this repository.
