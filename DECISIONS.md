# birdMonitor — Methodology & Model Decisions Log

Every decision here changes what the model estimates, what data it uses, or
how a result should be interpreted -- as distinct from `TODO.md` (engineering
gaps) and `improvements.md` (methodological extensions still under
discussion, not yet decided). An entry here is a DECISION: made, dated, with
a rationale and a pointer to the code that implements it. If a decision is
later reversed, add a new dated entry noting the reversal and why -- don't
edit history, append to it.

Each entry: **What** (the decision) · **Why** (the reasoning) · **Status**
(verified against a primary source / inherited-but-unverified / etc.) ·
**Where** (implementing code, on which branch).

---

## 2026-09 — Hedges dropped as a candidate predictor (default), backfill toggle added

**What:** By default, `hedges` is excluded from every model's candidate
predictor set. A code-level toggle (`hedgesTreatment`, `"drop"`/`"backfill"`)
can re-enable it; per-species inclusion once enabled goes through the
predictors table (`speciesConfig_predictors.csv`), not a separate per-species
setting.

**Why:** Team methodology decision (2026-09, confirmed against the primary
Confluence source: page 1299251201, Action Item #36, "Drop hedges as a
covariate for the MVP", Katrin Böhning-Gaese consulted). `hedges` data only
genuinely exists for 2017-2022/2024-2025 in the Thünen dataset; other years
are backfilled from the nearest real year, which the team judged too weak a
basis to model on by default.

**Status:** Verified against primary Confluence source (see
[[project_birdmonitor_confluence_decisions]] memory for the full citation
trail, including a prior subagent error that was caught and corrected).

**Where:** `covariatePredictorColumns()` (inputs_Monitor), `hedgesTreatment`
parameter (inputs_Monitor.R). Branch `feature/reconcile-with-v2-flexible-config`.

---

## 2026-09-25 — Spatial-block-size floor: 2x covariate resolution (configurable multiplier)

**What:** A species' spatial CV block size is floored at
`blockSizeFloorMultiplier x covariate resolution` (default multiplier 2),
never allowed to go below that regardless of what the autocorrelation-range
estimate (`cv_spatial_autocor()`) suggests.

**Why:** Below this floor, adjacent occurrence points can share a covariate
cell across train/test folds, leaking information between them and inflating
apparent model performance. This function was previously missing the floor
entirely (always passing 0), a real bug -- verified empirically for Milvus
milvus at 30km landscape resolution: 69.4% of occupied cells had points split
across more than one fold before the fix.

**Why the multiplier is configurable, not hardcoded "2":** Lisa Hildebrand's
v2 config applies 2x at every landscape/habitat variant EXCEPT her own 30km
landscape variant, which uses exactly 1x -- i.e. even the source methodology
treats this as scale-dependent, not a universal constant.

**Status:** Bug fix, confirmed by direct comparison against Lisa's v2 code
and her own empirical note.

**Where:** `spatialBlockingGerHabitat.R`/`GerLandscape.R`, `blockSizeFloorMultiplier`
parameter (inputs_Monitor.R). Branch `feature/reconcile-with-v2-flexible-config`.

---

## 2026-09-25 — Spatial thinning distance: per-species/scale configurable, default 2x resolution

**What:** Thinning distance (the minimum spacing enforced between kept
occurrence points) defaults to 2x each scale's covariate resolution
(Europe 100km, landscape 2km, habitat 400m), but can be overridden per
species+scale via `speciesConfig_general.csv`'s `thinning_dist_m` column.

**Why:** Previously a single hardcoded value per scale, shared by every
species, with no override path -- a real gap given species-specific home
range sizes vary by orders of magnitude (see `improvements.md` item 4's
territory-size literature table).

**Status:** Mechanism implemented and tested; actual per-species VALUES in
`speciesConfig_general.csv` are still the shared defaults for every species
as of this writing (no species-specific tuning has been decided yet -- the
column exists and is wired, ready for real values once tuning starts).

**Where:** `occurrencePrepEurope()`/`GerHabitat()`/`GerLandscape()`'s
`perSpeciesThinDist` argument (dataPrep_Monitor). Branch
`feature/reconcile-with-v2-flexible-config`.

---

## 2026-09-25 — Predictor selection: per-species/scale mode (table / all / auto)

**What:** Each species+scale independently chooses one of three predictor
resolution strategies (`speciesConfig_general.csv`'s `predictor_mode`
column): `"table"` (use the exact, manually curated list in
`speciesConfig_predictors.csv`), `"all"` (every available covariate,
unfiltered, no collinearity check), or `"auto"` (real block-CV collinearity
selection via `select07Blockcv()`, Wiedenroth et al. methodology, capped at 1
predictor per 10 occurrences).

**Why:** Enables direct manual "with vs. without a specific predictor"
experimentation per species (the stated purpose of the predictors table)
without losing the option to fall back to fully automatic selection, or to
use every covariate unfiltered, per species+scale as needed.

**Status:** Design decided directly by the user after two rounds of
correction to an initial narrower proposal (an "additive extras on top of
auto-selection" design, then a two-parameter table+boolean design) --
settled on this single clean 3-mode parameter, replacing the old
`runCollinearityCheck` boolean entirely.

**Note for later (not yet applicable):** once alternative model families
(GLM/RF/NN, see `improvements.md` item 7) exist, an NN model should probably
always use `"all"` regardless of this per-species setting, since
collinearity matters less for NN training than for e.g. GLM coefficient
interpretation. Not built -- no NN code path exists yet to apply it to.

**Where:** `collinearityCheckGerHabitat()`/`GerLandscape()`/`Europe()`'s
`predictorsToUse`/`speciesPredictorTable` arguments (inputs_Monitor).
Branch `feature/reconcile-with-v2-flexible-config`.

---

## 2026-09-25 — BRT learning rate: per-species starting point, persisted across refits

**What:** Each species' BRT learning-rate optimization (`optimizeBRT()`'s
halving/doubling search) starts from, in priority order: (1) an explicit
per-species override (`speciesConfig_general.csv`'s `brt_start_lr` column),
(2) the learning rate a prior run actually converged on for that species,
(3) the scale's shared default (0.08 habitat/landscape, 0.01 Europe).

**Why:** A forced refit (new year's data appended, cache invalidated) was
previously always restarting from the shared default, discarding a
species-specific value already known to converge faster -- wasted
optimization iterations re-walking the same halving/doubling steps.

**Status:** Implementation decision (efficiency), not a methodology change --
the search still explores the same space and converges to the same
per-species answer, just faster on repeat runs.

**Where:** `resolveStartingLR()`/`persistConvergedLR()`
(models_Monitor/R/brtLearningRateState.R), `perSpeciesLR` argument on
`modelEurope()`/`modelGerHabitat()`/`modelGerLandscape()`. Branch
`feature/reconcile-with-v2-flexible-config`.

---

## 2026-09-25 — Habitat ATLAS_CODE ("Brutzeitcode") filter: per-species override available

**What:** Habitat-scale occurrence records already pass a shared, global
ATLAS_CODE filter (excludes the weakest "A"-with-no-number possible-breeding
tier for every species: keeps A1/A2/B3-B9/C10-C16). A per-species ADDITIONAL
filter can now be layered on top via `speciesConfig_general.csv`'s
`brutzeitcode_filter` column (a prefix match, e.g. `"C"` keeps only
confirmed-breeding codes).

**Why:** Buteo buteo (Mäusebussard) is a generalist that may show up in
non-breeding contexts, potentially diluting its habitat-preference signal --
restricting its training data to confirmed-breeding evidence only was
proposed as a targeted refinement (2026-09-25 improvement notes, from the
DDA results-review discussion).

**Verification note (important):** the raw MhB data's actual column is named
`ATLAS_CODE`, not literally "Brutzeitcode" -- verified directly against
`inputs/response/raw/MhB/dbird_observations_CBBM.csv` when asked "is that in
the data?": real values `A, A1, A2, B3-B9, C10-C16` exist, matching the
German atlas possible(A)/probable(B)/confirmed(C) convention. A filter value
is matched as a PREFIX (`startsWith`), not an exact string match, since real
confirmed codes look like `"C11a"`/`"C12"`.

**Status:** Verified against the actual raw data file. Currently applied:
Buteo buteo's habitat row = `"C"`.

**Where:** `occurrencePrepGerHabitat()`'s `brutzeitcodeFilter` argument
(dataPrep_Monitor). Branch `feature/reconcile-with-v2-flexible-config`.

---

## 2026-09-25 — Buteo buteo & Sturnus vulgaris: landscape-scale data source switched to MhB point counts

**What:** At landscape (1km) scale, every species uses DDA territory count
data (`Reviere > 0` -> presence) EXCEPT Buteo buteo and Sturnus vulgaris,
which instead use the same raw MhB point-count CSV `occurrencePrepGerHabitat()`
draws from -- aggregated to the ROUTE level rather than the 200m cell level.

**Construction method (this is a real methodological choice, documented
here explicitly rather than left implicit in code):**
- A route+year is treated as a PRESENCE for a given MhB-routed species if it
  has at least one qualifying breeding-season (April-June) detection of that
  species, at the same ATLAS_CODE evidence threshold
  (A1/A2/B3-B9/C10-C16) `occurrencePrepGerHabitat()` uses by default.
- A route+year is treated as "surveyed" (and thus eligible to be an ABSENCE,
  if the target species wasn't detected there) if it has a qualifying
  detection of ANY MhB-routed species that year -- the same "detection of
  anything is the only survey-effort signal" proxy `occurrencePrepGerHabitat()`
  already uses for its own habitat-scale absences (MhB has no separate
  "visited, saw nothing" log).
- A route with NO qualifying detection of any MhB-routed species that year
  is excluded entirely (neither presence nor absence) -- it was never
  confirmed surveyed.
- Routes are joined to the same Probeflaechen shapefile (shared with the
  DDA-based pipeline) to get coordinates, so downstream covariate
  extraction/thinning/model-fitting code is identical regardless of data
  source.

**Why:** Star (Sturnus vulgaris)'s model was predicting near-uniformly high
suitability almost everywhere, while ADEBAR shows a more textured pattern
with clear hotspots against a widespread-but-lower baseline -- the model
wasn't discriminating "very common" from "extremely common" well. Hypothesis
(2026-09-25 improvement notes, from the DDA results-review discussion):
DDA territory-count data may be too coarse/saturating for a species this
common; point-count data alone might give better spatial discrimination.
User confirmed this as "a possible alternative" and approved implementation
(2026-09-25).

**Status:** Implemented and verified with a synthetic 25-route dataset
covering all four cases (presence, absence-via-surveyed-but-undetected,
weak-evidence-record-correctly-ignored-but-route-still-counted-as-surveyed,
never-surveyed-route-excluded). NOT yet run on real data -- the actual effect
on Star's spatial discrimination problem is still to be evaluated once a
real run completes.

**Where:** `occurrencePrepGerLandscape()`'s `mhbObsPath`/`perSpeciesDataSource`
arguments (dataPrep_Monitor). `speciesConfig_general.csv`'s `data_source`
column: `"MhB point counts"` for Buteo buteo and Sturnus vulgaris' landscape
rows, `"DDA territories"` for every other species. Branch
`feature/reconcile-with-v2-flexible-config`.

---

## Unverified / open items (do not treat as settled)

- **Minimum 10 presences before attempting to fit a model at all**
  (`occurrencePrepGerHabitat()`/`GerLandscape()`, `nPres < 10` -> skip
  species/year entirely). **Checked directly against Wiedenroth et al.'s own
  published reference code** (GitHub: UP-macroecology/Wiedenroth_multi-scale-SDM_2026,
  `03a_occurrence-prep_200m.R` and `05a_occurrence-prep_1km.R`) **and this
  check does NOT exist in the original methodology at all** -- confirmed by
  direct inspection of both files, no such threshold anywhere. It must have
  been added by Lisa Hildebrand in her own v2 port as a practical safety
  guard; our SpaDES port inherited it from her code, not from the paper.
  Rationale for the specific number 10 remains unstated anywhere accessible
  (not in Lisa's v2 comments, not in the published preprint's main text or
  landing page). Best inference (unconfirmed): loosely consistent with the
  separately-documented "1 predictor per 10 occurrences" rule used later in
  collinearity selection, since fewer than 10 of the rarer class would leave
  that formula unable to justify even one predictor -- but this is our own
  reasoning connecting two numbers, not something either source states.
- **Buteo/Star landscape routing's real-world effect on model quality** --
  see the entry above; implemented and unit-tested, not yet validated
  against a real model run.
- **Per-species covariate resolution** (`resolution_m` column) -- captured in
  the config CSV, no consuming code yet. See `improvements.md` item 4.
