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

**Status as of 2026-10-02: the whole workflow is wired for EVE, but has never
been submitted to the real cluster -- expect to debug the first run.** See the
`.claude/skills/eve-cluster/` skill for onboarding constraints (VPN-only
access, module system, Transfer Queue for downloads, memory/node sizing,
fair-share priority).

The whole workflow runs on EVE as one dependency chain, submitted by a single
command from an EVE login node:

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
  in `data/speciesCanonical.csv` (currently 11, Milvus milvus excluded); the
  task index maps to that species' position among the included rows. Keep the
  four `.sbatch` files in sync when the roster changes.
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

```bash
# one model task, locally, for testing:
Rscript tools/runClusterTask.R --scale habitat --index 3 --run-name test4
```
