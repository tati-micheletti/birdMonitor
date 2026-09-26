# birdMonitor

Code to run the models for the UFZ bird monitor. This README covers how to
actually run the pipeline — locally and on the EVE cluster —
which parameters/tables to check before a run, and what each output is.

For **why** things are built the way they are, see:
- **`DECISIONS.md`** — every methodology/model decision (data sources,
  thresholds, predictor selection), dated, with rationale.
- **`improvements.md`** — methodological extensions still under discussion,
  not yet decided.
- **`TODO.md`** — engineering/completeness gaps.

## 0. Before you run anything

**Branch.** As of 2026-09-25, everything described here (the two config
CSVs, the per-species wiring, the Buteo/Star landscape routing) lives on
`feature/reconcile-with-v2-flexible-config` in **all four repos** — root
`birdMonitor` plus the `dataPrep_Monitor`/`inputs_Monitor`/`models_Monitor`
submodules — not yet merged to `main`. `runMe.R` runs whatever is checked
out on disk in each `modules/<name>/` folder (`useGit = FALSE`), so before
running, confirm each of the 4 repos is actually on that branch:
```bash
cd birdMonitor && git branch --show-current
cd modules/dataPrep_Monitor && git branch --show-current
cd ../inputs_Monitor && git branch --show-current
cd ../models_Monitor && git branch --show-current
```
All four should print `feature/reconcile-with-v2-flexible-config`.

**Packages.** `runMe.R` installs/manages its own R package library via
`Require`/`pak` (see its own `paths`/`packages` -- no separate manual
install step needed under normal use). If you ever see a `could not find
function` error partway through a run, that's a missing package Require
didn't catch — install it and re-run.

**Raw data.** Must already exist under `inputs/` before `dataPrep_Monitor`
runs (it never downloads survey data itself — only predictor rasters). The
default paths (relative to `inputs/`), all `defineParameter(..."Subpath")`
in `dataPrep_Monitor.R`:
- `response/raw/ornitho/ebba2_data_occurrence_50km.csv` + `ebba2_grid50x50_v1.shp`
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
This runs all three modules (`dataPrep_Monitor` → `inputs_Monitor` →
`models_Monitor`) end to end via `SpaDES.core::simInitAndSpades()`. Outputs
land under `outputs/<runName>/`.

### Parameters to check/adjust before a run

- **`runNameBase`** (top of `runMe.R`) — bump this by hand for a run whose
  cached outputs shouldn't be reused (a real config change). A timestamp is
  always appended automatically (`test1_20260927_091500`), so every run
  gets its own `outputs/` folder regardless — see `DECISIONS.md` if you
  want the history of why it's built this way.
- **Species subset, for a test run** — do NOT edit `sharedConfig.R`'s
  `sharedSpecies` for a one-off test; that file is the single source of
  truth the CLUSTER path reads too, and it's easy to forget to revert it.
  Instead, temporarily override `species` directly in `runMe.R`'s
  `params$dataPrep_Monitor` and `params$inputs_Monitor` lists, e.g.:
  ```r
  testSpecies <- c("Vanellus vanellus", "Alauda arvensis",
                    "Anthus pratensis", "Saxicola rubetra")
  # then in params$dataPrep_Monitor and params$inputs_Monitor, replace
  # `species = sharedSpecies` with `species = testSpecies`
  ```
  `models_Monitor` needs no change — it takes its species list from
  whatever `inputs_Monitor` actually produced, not a separate parameter.
- **`hedgesTreatment`** (`inputs_Monitor` params, currently defaults to
  `"drop"` in the module itself, not overridden in `runMe.R`) — a single
  code-level toggle, not per-species. Must be `"backfill"` for ANY species
  to be able to list `"hedges"` as a candidate in
  `speciesConfig_predictors.csv` at all (see `DECISIONS.md`).

### Config tables to check before a run

Both live at the repo root, loaded once by `runMe.R` via `sharedSpeciesConfig.R`.
Missing either file is fine — every module falls back to its own shared
defaults exactly as if these didn't exist.

**`speciesConfig_general.csv`** — exactly 3 rows per species (climate/
landscape/habitat):

| column | wired to real effect? | what it does |
|---|---|---|
| `resolution_m` | **No** | captured for a human to read; per-species covariate resolution needs the `Cache()` redesign in `improvements.md` item 4 |
| `data_source` | **Yes** (landscape rows only) | `"DDA territories"` (default) or `"MhB point counts"` — routes that species' landscape-scale occurrence construction through a different raw source entirely, see `DECISIONS.md` |
| `thinning_dist_m` | **Yes** | per-species spatial thinning distance override |
| `brt_start_lr` | **Yes** | per-species BRT starting learning rate |
| `brutzeitcode_filter` | **Yes** (habitat rows only) | ATLAS_CODE prefix filter (e.g. `"C"` = confirmed-breeding only), on top of the existing global filter |
| `predictor_mode` | **Yes** | `"table"` / `"all"` / `"auto"` — see below |

**`speciesConfig_predictors.csv`** — many rows per species, one per
predictor, columns `species`/`climate`/`landscape`/`habitat`. Only consulted
for a species+scale whose `predictor_mode` is `"table"`. Lists every
candidate predictor for every species by design, so you can toggle one off
just by blanking its cell for that species+scale — see `DECISIONS.md`'s
"Predictor selection" entry for the full `"table"`/`"all"`/`"auto"` design.

### Output layout

```
outputs/<runName>/
  <climate label>/       # e.g. scale_50 -- europe/climate-scale outputs
  <habitat label>/       # e.g. scale_02 -- habitat-scale outputs
  <landscape label>/     # e.g. scale_1  -- landscape-scale outputs
  metamodel_<labels>/    # meta-model outputs (per-species/year prediction rasters) --
                         # this is what runIndex.R reads as `metaDir`
```

## 2. Running the multi-species index/report (`runIndex.R`)

Not part of `runMe.R`'s own event flow — the index/report functions
(`computeAnnualReport()`, `computeRegionalIndex()`, and their dependencies,
all in `modules/models_Monitor/R/`) are auto-sourced when `models_Monitor`
loads, but nothing calls them automatically. Run this AFTER `runMe.R`
finishes:

```r
source("runIndex.R")
```

Edit the top of that script first: `runName` (must match the `runMe.R` run
you just did — check its console output or `ls outputs/`) and
`indexSpecies` (must be a subset of whatever species that run actually
covered — an index/change-map for a species with no `metaModel()` output is
meaningless, not just empty).

Produces, under `outputs/<runName>/annual_report/`:
- `species_index.csv` — per-species baseline-100 index series
- `combined_index_{sbi,analytical,msi,chain}.csv` — four combined-index
  methods (report all four together, not just one — see `computeAnnualReport()`'s
  docstring for why they can legitimately disagree at the margins)
- `combined_index_chain_restricted.csv` — Chain index restricted to
  non-hindcast years only (a robustness check)
- `SR_map_<year>.tif` — species richness map
- `change_{vsBaseline,vs5YearsAgo,vsLastYear}_{community,<species>}.tif` —
  prevalence-change/gain-loss maps

And under `outputs/<runName>/regional_index/`: `regional_index_<N>km_{raw,smoothed}.tif`
for each of `sharedRegionalCellSizesM`'s grid sizes (10/20/50km by default).

## 3. Running on the EVE cluster

**Status as of 2026-09-25: designed, never actually submitted to real EVE,
and NOT yet updated for today's per-species config CSVs — see the gap
below before relying on it for a real cluster run.** See
[[project_eve_cluster_parallelization]] memory / `.claude/skills/eve-cluster/`
for onboarding constraints (VPN-only access, module system, transfer-queue
downloads).

The design: `tools/runClusterTask.R` is a standalone entry point for one
species × scale/meta task, run as a SLURM array (`--array=1-12`, one index
per `sharedSpecies` entry) via
`modules/models_Monitor/cluster/eve_array_{europe,habitat,landscape,meta}.sbatch`.
It requires `inputs_Monitor`'s `collinearityCheck` event to have already
run locally for that `runName` (reads the `_inputs.rds`/`_predictors.rds`
files that step writes) — i.e. run `dataPrep_Monitor` + `inputs_Monitor`
locally/beforehand, then submit `models_Monitor`'s per-species fitting as
the cluster array job.

```bash
# one task, locally, for testing:
Rscript tools/runClusterTask.R --scale habitat --index 3 --run-name test1
# real submission: sbatch modules/models_Monitor/cluster/eve_array_habitat.sbatch
# (partition name and R module-load line inside are still explicit
# placeholders -- genuinely unknown until submitted for real)
```

**Known gap: `runClusterTask.R` does not yet forward
`speciesConfig_general.csv`'s per-species settings** (`brt_start_lr`,
`thinning_dist_m`, etc.) to `models_Monitor` — it only sets
`runScale`/`runSpecies`/the shared year/resolution values. A species with a
tuned starting learning rate in the CSV would silently get the plain shared
default on the cluster instead. This needs fixing before the CSVs' values
are relied on for a real cluster run — flag this before next week if it
hasn't been addressed yet.
