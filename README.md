# birdMonitor

Code to run the models for the UFZ bird monitor: for each species of the roster (14 since
2026-10-28), yearly probability maps 2005-2025 at three scales (climate 50 km, landscape 1 km,
habitat 200 m) combined by a meta-model, national and regional indices, and uncertainty
(spatial-block bootstrap, algorithm ensemble) on everything. This README covers how to actually
run the pipeline — locally and on the EVE cluster — which parameters/tables to check before a
run, and what each output is.

**Taking over the project? Start with [`START_HERE.md`](START_HERE.md)**: what to read, in which
order and why, what to check before the next run. The full handover (what was built, what was
found, how everything works, how to run it, what to do next) is `pdf_export/1_Handover_postdoc.html`
(source `pdf_export/1_Handover_postdoc.Rmd`). Where this README and the handover differ, the
handover is newer.

For **why** things are built the way they are, see:
- **`DECISIONS.md`** — every methodology/model decision (data sources,
  thresholds, predictor selection), dated, with rationale.
- **`improvements.md`** — methodological extensions still under discussion,
  not yet decided.
- **`TODO.md`** — engineering/completeness gaps.

## 0. Before you run anything

**Branch and modules.** Everything is on `main` (the old feature branch was merged in October 2026).
The root repository `birdMonitor` has four modules as git submodules (`dataPrep_Monitor`,
`inputs_Monitor`, `models_Monitor`, `runIndex_Monitor`) and one module that is part of the root
repository itself (`connector_Monitor`). The root repository points to ONE commit of each submodule.
`runMe.R` runs whatever is checked out on disk in each `modules/<name>/` folder (`useGit = FALSE`),
so after every pull put the modules at the commits the root points to, and do not switch branches
inside a module (the clean-run script stops if a module is not at its pinned commit):
```bash
cd ~/projects/birdMonitor && git pull && git submodule update --init --recursive
git status            # "working tree clean"
git submodule status  # no "+" or "-" in front of a commit
```
A change in a module is committed and pushed in the module FIRST, then the root repository (which
records the new module commit) is committed and pushed — see `UPDATING_THE_RUNS.md`.

**Packages.** `runMe.R` installs/manages its own R package library via
`Require`/`pak` (see its own `paths`/`packages` -- no separate manual
install step needed under normal use). If you ever see a `could not find
function` error partway through a run, that's a missing package Require
didn't catch — install it and re-run.

**Raw data.** Must already exist under `inputs/` before `dataPrep_Monitor`
runs (it never downloads survey data itself — only predictor rasters). The
default paths (relative to `inputs/`), all `defineParameter(..."Subpath")`
in `dataPrep_Monitor.R`:
- `response/raw/ornitho/ebba2_data_occurrence_50km_2026-10-28.csv` + `ebba2_grid50x50_v1.shp`. The EBBA2
  file is the one named by `sharedEbba2CsvSubpath` in `tools/sharedConfig.R` (17 species; a new
  extract is merged into a NEW dated file with `tools/prepareEbba2Extract.R`, which never
  overwrites; `tools/checkSpeciesData.R` says whether every species of the roster has records at the
  three scales)
- `response/raw/MhB/dbird_observations_CBBM.csv` (the raw MhB point-count
  CSV — used at habitat scale for everyone, AND at landscape scale for
  whichever species use `"MhB point counts"` in `speciesConfig_general.csv`)
- `response/raw/MhB/MhB_Probeflaechen_DE_S2637_epsg25832.shp` (routes —
  shared by habitat and landscape scale)
- `response/raw/territories/BirdStats_Daten2005-2024D_alle.xlsx` (DDA
  territories) + `BirdStats_Visits2005-2024D.xlsx` (DDA visited routes) —
  only actually read if at least one species still uses the default
  `"DDA territories"` data source at landscape scale.

## 1. Running locally (`runMe.R`)

```r
source("runMe.R")
```
This runs the four modules (`dataPrep_Monitor` → `inputs_Monitor` →
`models_Monitor` → `runIndex_Monitor`) end to end via `SpaDES.core::simInitAndSpades()`. Outputs
land under `outputs/<runName>/`. It does NOT run the uncertainty workflow or the ensemble (those
are separate cluster steps, see section 3) and not the connector.

Debug switches (environment variables; never for a real run — the clean-run script refuses the
first two): `BIRDMONITOR_SPECIES="A b;C d"` restricts the species, `BIRDMONITOR_YEARS=2022:2025`
restricts the years, `BIRDMONITOR_STUDY_AREA="DEU:Sachsen"` replaces the study area (the processed
layers are CROPPED IN PLACE, so a test with another area changes `inputs/predictors/processed`:
keep a copy first, see `DECISIONS.md` 2026-10-21).

### Parameters to check/adjust before a run

- **`runNameBase`** (top of `runMe.R`) — bump this by hand for a run whose
  cached outputs shouldn't be reused (a real config change). A timestamp is
  always appended automatically (`test1_20260927_091500`), so every run
  gets its own `outputs/` folder regardless — see `DECISIONS.md` if you
  want the history of why it's built this way.
- **Species subset, for a test run** — do NOT hand-type a species vector
  anywhere in `runMe.R`; `sharedSpecies` (from `sharedConfig.R`) is the
  single source of truth every module and the cluster path both read, and
  a hand-typed copy is easy to forget to revert. Instead, temporarily mark
  just the species you want to test `"X"` in `data/speciesCanonical.csv`'s
  `include` column (and the rest not-included) — `sharedSpecies` is built
  from that column, so every module and the cluster path see the same
  restricted roster automatically, with nothing else to remember to revert.

### Config tables to check before a run

Both live under `data/` (not the repo root — moved there 2026-09-28), loaded
once by `runMe.R` via `sharedSpeciesConfig.R`.
Missing either file is fine — every module falls back to its own shared
defaults exactly as if these didn't exist.

**`speciesConfig_general.csv`** — exactly 3 rows per species (climate/
landscape/habitat):

| column | wired to real effect? | what it does |
|---|---|---|
| `resolution_m` | **Yes** | per-species resolution override (e.g. Milvus milvus's coarser landscape window) — `dataPrep_Monitor` generates each scale's distinct resolutions and re-keys occurrence extraction by it; `inputs_Monitor` groups spatial blocking by it; `models_Monitor` resolves each species' own model/prediction directory from it |
| `data_source` | **Yes** (landscape rows only) | `"DDA territories"` (default) or `"MhB point counts"` — routes that species' landscape-scale occurrence construction through a different raw source entirely, see `DECISIONS.md` |
| `thinning_dist_m` | **Yes** | per-species spatial thinning distance override |
| `brutzeitcode_filter` | **Yes** (habitat rows only) | ATLAS_CODE prefix filter (e.g. `"C"` = confirmed-breeding only), on top of the existing global filter |
| `spatial_term` | **Yes** | x/y coordinates as predictors for that species and scale (see `DECISIONS.md`) |
| `years_override` | **Yes** | fitting years of that species and scale instead of the shared years (habitat: `2022:2025` for all species) |

`data/speciesCanonical.csv` (17 species; column `include` = `X` for the 14 that run) is the roster;
`sharedSpecies` is built from it. A new species needs a row there, three rows in
`speciesConfig_general.csv` and its predictor rows in `speciesConfig_predictors.csv`; run
`Rscript tools/checkSpeciesData.R` before sending a run.

**`speciesConfig_predictors.csv`** — many rows per species, one per
predictor, columns `species`/`climate`/`landscape`/`habitat`. The ONLY
source of a species' candidate predictors — every species must be listed
here (a species missing here is a hard error, not a silent fallback).
Toggle a predictor off just by blanking its cell for that species+scale.
Independently, `inputs_Monitor`'s `dropCollinearPredictors` parameter
(module-level, default `FALSE`) controls whether that per-species list is
further pruned for collinearity via `select07Blockcv()` — see
`DECISIONS.md`'s 2026-09-28 entry.

### Output layout

```
outputs/<runName>/
  <climate label>/       # e.g. scale_50 -- europe/climate-scale outputs
  <habitat label>/       # e.g. scale_02 -- habitat-scale outputs
  <landscape label>/     # e.g. scale_1  -- landscape-scale outputs
  metamodel_<labels>/    # meta-model outputs (per-species/year prediction rasters) --
                         # this is what runIndex_Monitor reads as `metaDir`
  annual_report/         # runIndex_Monitor's annual report (see below)
  regional_index/        # runIndex_Monitor's regional gridded index maps (see below)
```
Suffixes keep variants side by side: `_germany` = copy cut to the reporting area (Germany today; the
suffix means "reporting area"), `_ens_brt-glm-gam-rf-nn` = the algorithm ensemble, and
`uncertainty_<tag>/` = the bootstrap uncertainty run. The full map of every folder and file is in
the handover (`pdf_export/1_Handover_postdoc.html`, tab 3, "Output file map").

## 2. The multi-species index/report (`runIndex_Monitor`)

Part of the SAME `runMe.R` run now (its own SpaDES module, chained last in
`loadOrder` -- see DECISIONS.md's 2026-09-28 "runIndex_Monitor" entry). No
separate script to run anymore; one `runMe.R` invocation produces data prep
-> inputs -> models -> index/report. Configure it via `runMe.R`'s
`params$runIndex_Monitor` block: `species` (the full roster its
`checkAllInputs` event waits on before computing anything -- matters mainly
for a cluster run, where different species' `metaModel()` tasks finish at
unpredictable times), `indexSpecies` (optional subset the report/index
actually covers -- leave unset to use all of `species`; an index/change-map
for a species with no `metaModel()` output is meaningless, not just empty),
`baselineYear`/`allYears`/`currentYear`/`restrictedYears`.

Before computing anything, it warns (never stops) about any specific
year/comparison it can't actually satisfy given which years'
`metaModel()` output exists on disk -- e.g. `"species X: vsLastYear needs
year 2024's metaModel() output, which is missing"`.

Produces, under `outputs/<runName>/annual_report/`:
- `species_index.csv` — per-species baseline-100 index series
- `combined_index_{sbi,analytical,msi,chain}.csv` — four combined-index
  methods (see `computeAnnualReport()`'s docstring for why they can legitimately disagree at the
  margins). The Analytical one is still computed but is no longer reported (decision of 13 October
  2026: same estimate as SBI and MSI)
- `combined_index_chain_restricted.csv` — Chain index restricted to
  non-hindcast years only (a robustness check)
- `SR_map_<year>.tif` — species richness map
- `change_{vsBaseline,vs5YearsAgo,vsLastYear}_{community,<species>}.tif` —
  prevalence-change/gain-loss maps

And under `outputs/<runName>/regional_index/`: `regional_index_<N>km_{raw,smoothed}.tif`
for each of `sharedRegionalCellSizesM`'s grid sizes (10/20/50km by default).

## 3. Running on the EVE cluster

**New to EVE? Follow [`EVE_GUIDE.md`](EVE_GUIDE.md)** (step by step, one-command setup via
`cluster/setup_eve.sh`). The notes below are the technical reference.

**Status as of 2026-10-29:** the baseline, the BRT-only and the algorithm-ensemble ("big 5")
uncertainty runs of 11 species have been run on EVE (run `test4`, 12-13 October). The first clean
run for the Monitor (run folder `v2`, 14 species, one script: `cluster/submit_eve_clean_run.sh`) is
written and has been tried as a dry run only; it has NOT been submitted. See the
`.claude/skills/eve-cluster/` skill for onboarding constraints (VPN-only
access, module system, Transfer Queue for downloads, memory/node sizing,
fair-share priority).

**For a full run use `cluster/submit_eve_clean_run.sh` (section 4).** The chain below is the
baseline part only (the first stage of that script), kept as the technical reference of how the
stages depend on each other. The whole baseline workflow runs on EVE as one dependency chain,
submitted by a single command from an EVE login node:

```text
prep   (dataPrep_Monitor + inputs_Monitor)      cluster/eve_prep.sbatch
  -> model arrays: europe, habitat, landscape    modules/models_Monitor/cluster/eve_array_*.sbatch
     (one task per included species; each species' meta-model
      runs inside whichever of its scale tasks finishes last)
    -> index (runIndex_Monitor)                  cluster/eve_index.sbatch
```

```bash
# on an EVE login node, from the repo root, after VPN + clone + rsync of
# inputs/ and cache/ + R packages installed (compute nodes have throttled internet):
EVE_R_MODULE=<name from `module spider R`> \
EVE_PARTITION=<partition from `sinfo -s`> \
BIRDMONITOR_RUNNAME=test4 \
  bash cluster/submit_eve_pipeline.sh
```

- The array size is `--array=1-N` where N is the number of `include = "X"` rows
  in `data/speciesCanonical.csv` (currently 14); the task index maps to that
  species' position among the included rows. The scripts of the clean-run chain read the
  roster size themselves; older one-off scripts (`cluster/*2026-10-0*.sh`) and some `.sbatch`
  headers still say `--array=1-11` (`grep -rn "array=1-" cluster modules/models_Monitor/cluster`).
- `runMe.R` runs a single stage when `BIRDMONITOR_STAGE` is set (`prep` or
  `index`; default `all` = everything in one session, the local behaviour --
  see `tools/sharedStageConfig.R`). `BIRDMONITOR_RUNNAME` pins the run folder
  so every stage and the model arrays write to the same `outputs/<runName>/`.
  `BIRDMONITOR_SKIP_INSTALL=1` skips the package-install block at the top of
  `runMe.R` (set automatically in the cluster jobs).
- `tools/runClusterTask.R` is the standalone entry point for one species x
  scale/meta task. It reads the `_inputs.rds`/`_predictors.rds` files that
  `inputs_Monitor` writes, which is why the prep stage must finish first.
  It builds its own `resolutionConfig`/per-species fitting years from
  `sharedConfig.R`/`speciesConfig_general.csv` (same as `runMe.R`), so a
  cluster task can never silently disagree with a full run.
- Resource requests in `eve_prep.sbatch`/`eve_index.sbatch` are unmeasured
  starting guesses; tighten them from `sacct` after the first run.
- Nothing in these jobs downloads data: put `inputs/` and `cache/` on EVE first.

### First-time setup on EVE (once)

1. Connect the UFZ VPN, then `ssh -l <your UFZ user name> frontend1.eve.ufz.de` (a "login node").
2. `git clone --recurse-submodules https://github.com/tati-micheletti/birdMonitor.git`
   (HTTPS, not SSH), then `cd birdMonitor`.
3. Load R and the geo libraries. `module avail R` shows nothing (R is hidden until a
   compiler is loaded; use `module spider`). R 4.6.1 exists but cannot be combined with
   GDAL: GDAL 3.10.3 (needed by `terra`) was built with GCC/13.3.0 + OpenMPI/5.0.5, which
   matches R 4.5.1. As of 2026-10-02:
   `module load GCC/13.3.0 OpenMPI/5.0.5 R/4.5.1 GDAL/3.10.3 CMake ImageMagick/7.1.1-38 UDUNITS/2.2.28`, then `R --version`.
   The submit script loads the same set by default (`EVE_R_MODULE`).
4. Install every R package once, on the login node (compute nodes have throttled
   internet): `BIRDMONITOR_INSTALL_ONLY=1 Rscript runMe.R`. It installs and quits
   without running the pipeline. Re-run it if it stops on an error; it resumes.
5. Optional: `sinfo -s` lists partitions (the first column is the name). Leave
   `EVE_PARTITION` unset to use EVE's default.
6. Put `inputs/` and `cache/` on EVE, then submit with `cluster/submit_eve_pipeline.sh`.

```bash
# one model task, locally, for testing:
Rscript tools/runClusterTask.R --scale habitat --index 3 --run-name test4
```

## 4. The clean run, updating a run, and what the Monitor reads

**A full run for a new run folder** (first version of the Monitor, a new study area, a new species
set, changed layers): one command on an EVE login node. It chains the checks, the preparation, the
BRT arrays at three scales, the ensemble, the reporting-area copies and the index, the uncertainty
(25 replicates), the regional steps, the copy to `/data/birds` and the connector. About two days.
```bash
cd ~/projects/birdMonitor && git pull && git submodule update --init --recursive
DRY_RUN=1 bash --login cluster/submit_eve_clean_run.sh      # runs the checks, prints the chain, submits nothing
bash --login cluster/submit_eve_clean_run.sh                # sends it (run folder v2; BIRDMONITOR_RUNNAME=<name> for another)
```
It stops, and says why, if the run folder exists (`RESUME=1` continues it), if the code on EVE has
uncommitted changes or a module is not at its pinned commit, if a species of the roster has no
records at one scale, if the EBBA2 file is missing, or if `/data/birds/birdMonitor/inputs` has no
complete safety copy of `inputs/predictors/processed` and `inputs/response/processed` (the
preparation changes those in place; make the copy with `sbatch cluster/eve_copy_data_birds.sbatch`).

**Updating part of a run** (one species, one scale, only the index): `UPDATING_THE_RUNS.md`, and
the table "Which command for which job" in the handover (tab 5).

**What the Monitor reads:** the folder `/data/birds/viz`, filled by `connector_Monitor`
(`sbatch cluster/eve_connector.sbatch`, after the results are copied to `/data/birds`): one raster
per metric and year (probability, uncertainty layers, richness, regional index) and a national
trend table with a `preliminary` flag; `_manifest.csv` and `_missing.csv` say what is there and
what is not. Details: `modules/connector_Monitor/README.md`.

**Where things are and are not stored** (GitHub, `/data/birds`, only on one PC): handover, tab 1,
"What lives where, and what does not". `inputs/`, `outputs/`, `cache/` and `logs/` are not in git.
