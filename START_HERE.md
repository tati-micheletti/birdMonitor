# Start here: taking over birdMonitor and setting the next run

Written on 29 October 2026 for whoever takes over the project. Everything below is in this GitHub
repository (`tati-micheletti/birdMonitor`) unless it says otherwise. The state described is the one of
29 October: 14 species in the roster, the first clean run (run folder `v2`) submitted on 29 October (first prep killed for memory, fixed and resubmitted; running on 30 October), **not yet
finished**, the Bird Monitor reads `/data/birds/viz`.

## 1. Read, in this order

| # | File | Why you read it | Time |
|---|---|---|---|
| 1 | `pdf_export/1_Handover_postdoc.html` (source: `pdf_export/1_Handover_postdoc.Rmd`) | **This is the full handover document.** It is the only place that says what exists, what has been checked and what has not, how the code works, how to run each part, and what to do next. It is long, so read first tab 1 (what lives where, the state of the work, the ten things to know), tab 5 (Step 0 = the clean run, and the table "Which command for which job") and tab 6 (block P0 = what is needed before the next run). Tabs 2 to 4 and 7 (chronology, how the modules work, glossary of scripts and functions, checks and results) are reference: look things up there when you need them. | about 1 hour for the three parts; the whole document is several hours |
| 2 | `EVE_GUIDE.md`, part A | You cannot run anything without an EVE account, the UFZ VPN, the ssh settings for Windows, the clone of the repository with its submodules and the setup script. It is written for someone who has never used a cluster. | 30 min, plus the one-off setup run (30-60 min) |
| 3 | `UPDATING_THE_RUNS.md` | The routine you will use after the first run: pull, change, commit the module first and the main repository second, move results aside instead of deleting, re-run only what changed. It also holds the house rule: never delete results, never edit raw inputs. | 10 min |
| 4 | `DECISIONS.md` | Every method choice, dated, with its reason. Read the entries of 2026-10-20, 2026-10-21 and 2026-10-28 for the new pipeline (study area, complete layers, roster, viz files); the handover names the earlier ones, from 5 October on. Read this before you change anything, so that you do not undo a decision. | 1 hour |
| 5 | `pdf_export/4_Methods_indices_uncertainty.html` | What the models, the indices and the intervals are. You need it to explain a result to someone else. | 45 min |
| 6 | The header comments of `cluster/submit_eve_clean_run.sh` | What the one command for a full run checks, in which order, and what it chains. | 10 min |

Afterwards, as a to-do list and not as reading: `improvements.md` (methodological extensions under
discussion) and `TODO.md` (engineering gaps). `README.md` describes the code and the config tables;
where it and the handover differ, the handover is newer.

## 2. Config files to check before sending the run

| File | What to check, and why |
|---|---|
| `data/speciesCanonical.csv` | Column `include`: the 14 species marked `X` are the ones that run (the table holds 17). Off: Perdix perdix, Streptopelia turtur, Milvus milvus. The submit scripts read the number of species from here. |
| `data/speciesConfig_general.csv` | Three rows per species (climate, landscape, habitat): data source, resolution, thinning, `years_override`. Habitat uses `2022:2025` for all species. The Falco tinnunculus rows were copied from Passer montanus. |
| `data/speciesConfig_predictors.csv` | The candidate predictors of each species and scale. A species missing here is a hard error. Falco tinnunculus has a provisional full set; the layer guidance for the four new species is in `DECISIONS.md` of 2026-10-28. |
| `tools/sharedConfig.R` | `sharedStudyArea` (Germany); `predictionYears` (2005:2025); `sharedHabitatYears` and `sharedLandscapeYears`; the three resolutions; `sharedEbba2CsvSubpath` (the 28 October file) and the two name-alias tables; the buffers; `sharedRegionalCellSizesM` (10, 20, 50 km); `sharedNationalIndicatorLastYear` (2023, still to be confirmed with the DDA contact; only the connector uses it). `sharedClmsTokenJSONPath` is a path on the PC of the previous maintainer and only matters if the CORINE land cover has to be rebuilt. |

## 3. Environment checks in the EVE session

- These must be empty: `echo $BIRDMONITOR_SPECIES $BIRDMONITOR_YEARS $BIRDMONITOR_STUDY_AREA`. The script refuses the first two;
  the third is the study-area test switch (a test with another area crops the processed layers in place).
- The run folder is `v2` by default (`BIRDMONITOR_RUNNAME`); `outputs/v2` must not exist yet.

## 4. Checks to run, in this order (one step at a time on EVE)

1. **Get the code safely.** `cd ~/projects/birdMonitor && git status --short` and `git submodule status`. If tracked files are modified, do not pull before you know why (`git stash` keeps them without deleting). Then `git pull && git submodule update --init --recursive`. Check: `git status` says "working tree clean" and `git submodule status` shows no `+` or `-` in front of a commit.
2. **Compare `inputs/` with the `/data/birds` copy:** `COPY_INPUTS=1 MODE=verify bash cluster/copy_to_data_birds.sh`. If it lists differences, run `sbatch cluster/eve_copy_data_birds.sbatch` (adds and updates, never deletes).
3. **Check the EBBA2 file** in `inputs/response/raw/ornitho/`: `md5sum ebba2_data_occurrence_50km_2026-10-28.csv` must give `58ad0369ec0cbeb7cf17d1dc1b66a0c0` (1,913,376 bytes, 53,447 rows, 17 species).
4. **Dry run:** `DRY_RUN=1 bash --login cluster/submit_eve_clean_run.sh`. It runs all the checks (including that every species has records at the three scales) and prints the chain without submitting.
5. **Send it** (about 5 to 6 days in total; estimated from the October timings and the first prep of v2: prep ~22 h, ensemble fits ~7 h, uncertainty prepare up to ~24 h, bands ~38 h, the rest ~7 h, plus queue waits): `bash --login cluster/submit_eve_clean_run.sh`. Afterwards `cat /data/birds/viz/_missing.csv` must be empty and `grep -H RESULT outputs/v2/uncertainty*/*/parity_check.txt` must say `RESULT: OK` for every species.

## 5. What is not settled or not verified (so that you do not assume it is)

- The clean-run script was used for the first time on 29 October (run v2, still running on 30 October): until it has finished, its end-to-end result is not verified; the pieces ran separately in October.
- The connector (`modules/connector_Monitor`) has been tested on synthetic files only, never on real results.
- Richness with uncertainty for every year is a change in the community step that has not run on real replicate data.
- The cut-off year of the preliminary national trend (2023) is a placeholder; the figure code for the dashed line is not written.
- Falco tinnunculus is on trial and may not stay in the Monitor.
- The upload from `/data/birds/viz` to the bucket is not in this repository.
- The wording of the acknowledgement of the DDA data in the public Monitor is not agreed.
- What is in `/data/birds` depends on what the copy script was run for: check it (step 2 above).
