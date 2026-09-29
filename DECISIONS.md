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

**SUPERSEDED 2026-09-28 -- see "Simplify to CSV-driven config" entry below.**
`predictor_mode` (and `"all"`/`"auto"` as alternative predictor SOURCES) is
removed entirely; `speciesConfig_predictors.csv` is now the only source of a
species' candidate predictors, full stop. `select07Blockcv()`'s collinearity
pruning survives as an independent `dropCollinearPredictors` toggle applied
ON TOP of the table, not a mode. Kept below for history only.

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

**PARTIALLY SUPERSEDED 2026-09-28 -- see "Simplify to CSV-driven config"
entry below.** The per-species CSV override (`brt_start_lr` column) is
removed -- a starting learning rate is now a module-level constant only
(`europeInitialLR`/`habitatInitialLR`/`landscapeInitialLR`). The
converged-LR-PERSISTENCE mechanism described below (priority 2:
`resolveStartingLR()`/`persistConvergedLR()`, reusing a prior run's actual
converged value) is unrelated and unchanged.

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

## 2026-09-25 — ATLAS_CODE ("Brutzeitcode") filter: per-species override available (habitat AND landscape)

**CORRECTED 2026-09-26 (see note at the end) -- originally written up as
habitat-only, which was a misattribution on my part. Landscape was the
actual, and currently the only, applied case.**

**What:** Habitat-scale occurrence records already pass a shared, global
ATLAS_CODE filter (excludes the weakest "A"-with-no-number possible-breeding
tier for every species: keeps A1/A2/B3-B9/C10-C16); the landscape scale's
MhB-routed species (see the MhB-landscape-routing entry below) apply the
same baseline filter to their presence-defining detections. A per-species
ADDITIONAL filter can now be layered on top of either scale's baseline via
`speciesConfig_general.csv`'s `brutzeitcode_filter` column (per species
AND scale, same nesting as `thinning_dist_m`) -- a prefix match, e.g.
`"C"` keeps only confirmed-breeding codes.

**Why:** Buteo buteo (Mäusebussard) is a generalist that may show up in
non-breeding contexts, potentially diluting its habitat-preference signal --
restricting its training data to confirmed-breeding evidence only was
proposed as a targeted refinement, bundled with "slightly increase the
landscape scale" in the same 2026-09-25 improvement note (from the DDA
results-review discussion). Buteo's landscape scale was ALSO switched to
MhB point counts at that same meeting (see the entry below) -- before that
switch, landscape used DDA territory counts, which have no ATLAS_CODE at
all, so a "C" filter could not have applied to landscape until MhB-routing
existed. That landscape-scale routing decision is almost certainly what the
bundled note was actually about.

**Verification note (important):** the raw MhB data's actual column is named
`ATLAS_CODE`, not literally "Brutzeitcode" -- verified directly against
`inputs/response/raw/MhB/dbird_observations_CBBM.csv` when asked "is that in
the data?": real values `A, A1, A2, B3-B9, C10-C16` exist, matching the
German atlas possible(A)/probable(B)/confirmed(C) convention. A filter value
is matched as a PREFIX (`startsWith`), not an exact string match, since real
confirmed codes look like `"C11a"`/`"C12"`.

**Status:** Verified against the actual raw data file and against real code
(`occurrencePrepGerLandscape()`'s MhB-routed presence logic now applies this
filter the same way `occurrencePrepGerHabitat()` does). Currently applied:
Buteo buteo's LANDSCAPE row = `"C"` (habitat row left blank).

**Correction note (2026-09-26):** this entry originally said the filter was
applied to Buteo's HABITAT row, with a "habitat-preference-signal dilution"
rationale invented to justify that scope. User corrected this directly
("You got it wrong before... it was originally supposed to be on
LANDSCAPE"). At the time of the original write-up, `occurrencePrepGerLandscape()`
had no `brutzeitcodeFilter` argument at all -- only habitat scale could
technically consume the CSV value, which likely drove the mistaken
attribution rather than the actual intent. Fixed by adding a
`brutzeitcodeFilter` parameter to `occurrencePrepGerLandscape()` (applied
only to MhB-routed species' presence-defining detections, same semantics as
habitat's), threading it through `prepareOccurrenceData()`/`dataPrep_Monitor.R`
per scale, and moving the CSV value to Buteo's landscape row.

**Where:** `occurrencePrepGerHabitat()`/`occurrencePrepGerLandscape()`'s
`brutzeitcodeFilter` arguments (dataPrep_Monitor). Branch
`feature/reconcile-with-v2-flexible-config`.

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

## 2026-09-26 — Canonical species table: one source for roster + name lookup

**What:** `speciesCanonical.csv` (repo root) is now the ONLY source for (1)
which species the pipeline runs (`include` column) and (2) the Latin↔German
name mapping the raw MhB/DDA files need (`german_name` column). It also
carries `english_name` (reference only, no code depends on it) and
`euring_code` (pulled directly from the real DDA territories data, for
future cross-referencing against any source keyed by EURING rather than
name). Replaces two previously separate, manually-synced things:
`sharedConfig.R`'s old hardcoded `sharedSpecies` vector, and
`dataPrep_Monitor`'s old `speciesLookup()` data.frame.

**Why:** live incident during this session's first local test run. Anthus
pratensis showed `Too few presences (0)` at habitat scale for every year
2022-2025, despite the raw MhB CSV genuinely having 2295 real records for
it (verified directly). Root cause: `speciesLookup()` was never updated
when Anthus pratensis was added to `sharedSpecies` (2026-09-24, commit
`2108c38`) -- it's a completely separate file, and nothing checked the two
stayed in sync. `occurrencePrepGerHabitat()`/`GerLandscape()` filtered the
raw data by German name via this stale lookup, silently matching zero rows
for the missing species instead of erroring. User's own diagnosis: *"We
need ONE canonical source! And we need only ONE way to check."*

**Also fixed as part of the same change:** `occurrencePrepGerHabitat()` no
longer uses any name lookup at all -- the raw MhB CSV already carries both
`SPECIES_NAME_GERMAN` and `SPECIES_NAME_SCIENTIFIC` natively, so it now
filters directly on the scientific name, removing one entire class of
future name-mismatch bug for that data source. Landscape scale still needs
`germanNames` (now an explicit, required function argument instead of an
internal lookup call) since the raw DDA data has no Latin-name column at
all, only German.

**Milvus milvus** is flagged excluded (`include` column blank) in this same
file, finally implementing the 2026-09-24 Confluence decision to drop it
from scope (see `project_birdmonitor_confluence_decisions` memory) --
previously decided but never actually reflected in code until this change.

**Status:** Verified against real data on multiple fronts: `loadSpeciesCanonical()`
correctly rejects a species missing a German name (the exact bug class this
prevents); the real MhB CSV confirms Anthus pratensis now resolves to real
presence counts (576/551/577/591 across 2022-2025) via the direct
scientific-name filter; EURING codes matched exactly against the real DDA
file, not guessed.

**Where:** `speciesCanonical.csv`, `sharedSpeciesCanonical.R` (repo root),
threaded through `sharedConfig.R` -> `runMe.R` -> `dataPrep_Monitor.R` ->
`occurrencePrepGerLandscape()`'s `germanNames` argument. Branch
`feature/reconcile-with-v2-flexible-config`.

---

## 2026-09-26 — EBBA2 climate-scale data gap: stale extract, not absent data

**What:** Anthus pratensis showed 0 presences at Europe/climate scale too,
but for a DIFFERENT reason than the habitat/landscape lookup bug above --
directly confirmed the raw `ebba2_data_occurrence_50km.csv` genuinely has
no row for this species under any name/spelling (checked all 11 distinct
species names in the file, no partial match on "pratensis" or "Anthus"
either). The file on disk is dated 2026-07-17; the species was added to
the roster on 2026-09-24, two months later. Lisa's own earlier success
modeling this species doesn't contradict this -- she must have had a more
current EBBA2 extract.

**Status:** Confirmed genuine external data gap, NOT a code bug (unlike
the habitat/landscape lookup issue above). No code fix possible until a
refreshed EBBA2 extract covering all 12 canonical species is obtained --
see `improvements.md` item 9 for the scoped follow-up (a real,
programmatic EBBA2 refresh mechanism is possible in principle, unlike DDA,
but needs its own design work, not a quick fix).

**Where:** `occurrencePrepEurope()` now has the same minimum-10-presences
guard `occurrencePrepGerHabitat()`/`GerLandscape()` already had, so a
future data gap like this one fails cleanly at data-prep time with a clear
message, instead of silently building an all-absence table that only
surfaces later as an `optimizeBRT()` failure. Branch
`feature/reconcile-with-v2-flexible-config`.

---

## 2026-09-26 — An unfittable BRT skips its species, does not crash the run

**What:** When `optimizeBRT()` cannot converge (learning-rate search hits
its floor/ceiling/iteration cap -- see the EBBA2/canonical-species entries
above for the real incident that triggered this), it now returns `NULL`
with a `warning()`, and
`modelEurope()`/`modelGerHabitat()`/`modelGerLandscape()` all check for
that and skip to the next species with their own warning, rather than
erroring.

**Why:** user correction -- a hard `stop()` here would propagate up and
crash the entire multi-species run over one bad species, which is strictly
worse than silently producing no output for just that species. None of the
three model functions previously checked `optimizeBRT()`'s return value at
all, so this required fixing both the function and all three call sites
together, not just one.

**Status:** Verified for real: `optimizeBRT()` returns `NULL` (not an
error) when a mocked `gbm.step()` always fails; `modelEurope()` skips a
zero-variance-response species cleanly and still produces a correct result
for the next species in the same run.

**Where:** `optimizeBRT()`, `modelEurope()`/`modelGerHabitat()`/
`modelGerLandscape()` (models_Monitor). Branch
`feature/reconcile-with-v2-flexible-config`.

---

## 2026-09-26 — Solar radiation dropped as a predictor, for every species

**What:** `solar_radiation` removed entirely: no longer a candidate
predictor (`covariatePredictorColumns()`), no longer listed for any species
in `speciesConfig_predictors.csv`, and no longer loaded/stacked into the
covariate rasters at all (`loadCovariates()`/`loadHabitatCovariates()`,
both dataPrep_Monitor and models_Monitor copies). The underlying DEM
derivative file itself is left alone (still computed/written upstream) --
only its use as a model covariate is removed, since nothing else in the
pipeline depends on it.

**Why:** flagged as "under reconsideration for removal across all species
-- may not be well-scaled, possibly capturing noise from other unmodeled
factors" in the 2026-09-24 DDA-UFZ meeting notes. User confirmed this as a
final decision on 2026-09-26 ("For all species: remove the solar
radiation").

**Status:** Implemented and verified: `speciesConfig_predictors.csv` and
`covariatePredictorColumns()` confirmed to have zero remaining
`solar_radiation` references; the three `collinearityCheck*()` functions
never offer it as a candidate regardless of mode (table/all/auto).

**Where:** `covariatePredictorColumns()` (inputs_Monitor),
`speciesConfig_predictors.csv`, `loadCovariates()`/`loadHabitatCovariates()`
(both dataPrep_Monitor and models_Monitor copies -- kept byte-identical,
checked via `tools/check_duplicated_functions.R`). Branch
`feature/reconcile-with-v2-flexible-config`.

---

## 2026-09-26 — Spatial coordinates (x/y) added as predictors, for every species

**What:** Every species, at every scale (climate/landscape/habitat), now
always gets the location's own projected coordinates -- `x`/`y`, in
whatever CRS the pipeline's shared `targetCRS` is (a metric, equal-area
projection; NOT raw GPS latitude/longitude) -- added as two extra
predictors on top of whatever `predictorsToUse` mode (table/all/auto)
resolves. Precedent set by the meta-model regularly showing "unexplained
regional clustering not captured by current environmental covariates
alone" for at least one species (Grauammer/Emberiza calandra); generalized
to every species on the user's instruction rather than singled out for one.

**Terminology note (user asked directly):** this is NOT a formal
statistical "random effect" -- that term specifically means a
hierarchical/mixed-model variance component (GLMM/GAMM machinery), which
`dismo::gbm.step()` (BRT, the model class this whole pipeline uses) has no
concept of at all. What's actually implemented is a **spatial trend-surface
predictor**: the raw coordinates themselves become ordinary splitting
variables the tree can use, which is the standard/pragmatic way to let a
BRT (or any non-hierarchical model) absorb residual spatial pattern. A true
random-effects/spatial-hierarchical model would require switching model
class entirely (tracked separately, `improvements.md` item 7 -- GLM/RF/NN
alternatives). Related but distinct question the user also asked --
whether this "captures functional diversity (or ... a species being more
adapted to its own region)": **not the right term** -- functional
diversity is a community-ecology concept (trait diversity across species
within an assemblage), unrelated here. What a trend-surface term actually
absorbs is generic **residual spatial autocorrelation**: any region-level
pattern in occurrence not explained by the measured environmental
covariates, whatever its real cause (unmeasured local factors, dispersal
limitation, historical biogeography, etc.) -- it doesn't identify *why* a
region differs, just that it does.

**Status:** Implemented and verified end-to-end with a real (not mocked)
`dismo::gbm.step()` call: trained with `x`/`y` among its predictors on
synthetic presence/absence data, then predicted onto a synthetic raster via
`predictBRTToRaster()` -- confirmed valid probability output (no "missing
predictor" errors), even though the raster covariate stack has no literal
`x`/`y` layers (they're derived from the raster's own cell coordinates via
`as.data.frame(..., xy = TRUE)`, matching exactly how the training data's
own `x`/`y` columns were originally extracted). Verified for all three
`predictorsToUse` modes (table/all/auto). NOT yet observed on a real model
run -- effect on Grauammer's (or any other species') spatial discrimination
is still to be seen.

**Where:** `collinearityCheckEurope()`/`GerHabitat()`/`GerLandscape()`
(inputs_Monitor) -- append `c("x", "y")` to `predSel` after mode
resolution, unconditionally. `predictBRTToRaster()` (models_Monitor) --
now excludes `x`/`y` from the raster layer subset and relies on
`as.data.frame(xy = TRUE)` to supply them instead.
`modelGerHabitat()`/`modelGerLandscape()`'s missing-predictor raster checks
updated to not flag `x`/`y` as missing (they're never real layers by
design). `modelEurope()` needed no change (no such check existed there).
Branch `feature/reconcile-with-v2-flexible-config`.

---

## 2026-09-26 — 2026-09-25 DDA results-meeting follow-up items: final disposition

Consolidating the 5 concrete asks from the 2026-09-25 results-review
meeting (`project_birdmonitor_model_results_20260925` memory) against what
actually got implemented:

- Mäusebussard (Buteo buteo): restrict habitat training to confirmed-
  breeding ("C") codes -- **done** (see the Brutzeitcode-filter entry
  above).
- Mäusebussard: slightly increase landscape scale -- **dropped from scope**
  per user instruction 2026-09-26 ("probably remove... won't help"). Not
  implemented; per-species `resolution_m` remains a separate, still-open
  item (`improvements.md` item 4) for unrelated reasons.
- Star (Sturnus vulgaris): point-count data only, not combined with
  territories -- **done** (see the MhB-landscape-routing entry above).
- Neuntöter (Lanius collurio) / Goldammer (Emberiza citrinella): add hedges
  -- **done** (both listed in `speciesConfig_predictors.csv`'s table-mode
  predictor lists).
- Neuntöter / Goldammer: add edge density and/or field size -- **not done,
  deferred**. These data layers don't exist in the codebase at all yet;
  Lisa will build them (per user, week of 2026-09-28). No code path
  currently consumes them -- once the layers exist, they'd be added to
  `covariatePredictorColumns()` and the relevant species' rows in
  `speciesConfig_predictors.csv`, same pattern as `hedges`.
- Grauammer (Emberiza calandra): add a spatial term -- **done, but
  generalized to every species** rather than singled out for Grauammer
  alone (see the spatial-coordinate-predictor entry above).

**Where:** n/a (documentation-only entry, consolidating status already
described above). Branch `feature/reconcile-with-v2-flexible-config`.

---

## 2026-09-28 — Real per-species cache invalidation via reproducible::Cache()

**What:** Every "cache" check across all 3 modules (`isValidRDSFile()`,
`isValidCachedRDS()`, `isValidPredictionRaster()`) was pure file-existence
memoization -- "does this exact path already have a non-empty file?" -- with
zero awareness of whether the inputs that produced it had changed. Replaced
throughout with real `reproducible::Cache()` calls, scoped per species(-year),
in all 9 places this pattern occurred:
- dataPrep_Monitor: `occurrencePrepGerLandscape()`/`GerHabitat()`/`Europe()`
  (per-species(-year) occurrence-table building).
- inputs_Monitor: `collinearityCheckGerHabitat()`/`GerLandscape()`/`Europe()`
  (per-species predictor resolution + table assembly -- this one had NO
  caching at all before, not even the naive file-existence kind).
- models_Monitor: `modelEurope()`/`GerHabitat()`/`GerLandscape()`, each split
  into a cached BRT fit step, a cached block-CV eval step, and a cached
  per-year `predictBRTToRaster()` prediction step.

Each conversion follows the same pattern: the actual per-unit computation is
extracted into a small helper taking only the arguments that determine
correctness for that species (its own data subset, resolved config values,
etc.) -- NOT the whole multi-species pooled table, which would cross-
invalidate every species whenever any other species' data changed. `Cache()`
wraps that helper; the result is then written, unconditionally, to the same
known output path every other part of the pipeline already expects (a cheap
mirror write, whether `Cache()` hit or missed) -- so no downstream file
layout changed.

**Why:** user request, following a real live case: Buteo buteo's landscape
`brutzeitcode_filter` or a hedges entry in `speciesConfig_predictors.csv`
(Neuntöter/Goldammer) changing should only trigger recompute for that one
species, not force a manual guess about which cached files are now stale (or
a full rerun of everything).

**Cache location:** a new, persistent `cache/` folder (`runMe.R`'s
`setupProject(paths = list(..., cachePath = "cache"))`), sibling to `inputs/`
and `outputs/<runName>/` -- NOT nested inside the per-run timestamped output
folder. This matters: `outputs/<runName>/` gets a fresh timestamp every
`runMe.R` invocation, so models_Monitor's old file-existence check never
actually found a cross-run hit before this change (it only helped within a
single crashed-and-resumed run). The new persistent `cache/` is shared across
every future run regardless of `runNameBase`; each run's own
`outputs/<runName>/` still gets a full copy of every result (instant on a
cache hit), so a run folder stays self-contained and browsable.

`predictBRTToRaster()` changed shape as part of this: it now RETURNS the
prediction raster instead of writing it to a fixed path (a Cache()-returned
value has no path of its own) -- its terra-two-layer-stacking-bug workaround
moved to a new `combineTwoLayerRaster()` helper (`writeTwoLayerRaster()` now
just calls it and writes the result, unchanged for its other caller,
`predictRidgeToRaster()`, which was not touched).

**Status:** Verified end-to-end at every one of the 9 conversion points with
real computation (real `dismo::gbm.step()` fits, real `reproducible::Cache()`
-- nothing mocked): a config change for one species correctly changes that
species' result (recomputed) while an unrelated species stays a cache hit,
first call onward, at every stage from raw occurrence data through to the
final prediction raster.

**Side finding (not a caching bug, a pre-existing property of the modeling
code):** `evalSDM()`/`blockCVPredictBRT()` are not perfectly deterministic
re-run to re-run -- no fixed seed, so re-computing them fresh for an
unchanged model can give a slightly different threshold/AUC each time. This
surfaced as a brief one-time transition effect in testing: the very first
re-run after a model's fit becomes a cache hit, its eval/predict steps
recompute once more (since a freshly-computed model object and the same
model reloaded from the cache don't digest identically) before settling into
full cache hits on every subsequent identical re-run. The actually-
deterministic part of a prediction (`mean_prob`) was confirmed to reproduce
exactly throughout; only the stochastic threshold-dependent `binary` layer
showed the transition. Not fixed as part of this change (out of scope --
`evalSDM()`/`blockCVPredictBRT()` predate this session); flagged here so it
isn't mistaken for a caching regression later.

**Where:** All 9 files listed above, plus `runMe.R` (`cachePath` in
`paths`), and each module's own `doEvent`/`.R` file threading `cachePath(sim)`
through. `reproducible` added as a required package in all 3 modules. Branch
`feature/reconcile-with-v2-flexible-config` (root: `feature/config-data-folder`,
per the 2026-09-28 branch-discipline change -- see below).

---

## 2026-09-28 — Simplify to CSV-driven config; consume `resolution_m`; deprecate several mechanisms

**What:** A cluster of related simplifications, triggered by asking "is
`speciesConfig_general.csv`'s `resolution_m` column actually consumed
anywhere?" (answer: no -- the only per-species-resolution mechanism,
`landscapeResolutionOverrides`/`resolveSpeciesResolution()` in
`models_Monitor`, only ever took effect via `tools/runClusterTask.R`'s
`--landscape-resolution` CLI flag, never from the CSV, and was always a
no-op in a normal batched `runMe.R` run):

1. **`resolution_m` is now consumed.** `models_Monitor` resolves each
   species' own habitat/landscape resolution from a new `resolutionConfig`
   parameter (species -> scale -> resolution (m), via
   `extractResolutionConfig()` in `sharedSpeciesConfig.R`) and reads/writes
   that species' covariates and model outputs from its own `scale_X`
   folder -- a per-species override now genuinely works in a batched
   multi-species run, not just a single-species cluster task.
   `inputs_Monitor`'s spatial blocking groups species by resolved
   resolution the same way. `landscapeResolutionOverrides`/
   `resolveSpeciesResolution()` are deleted; `tools/runClusterTask.R`
   builds and forwards the same `resolutionConfig` instead of its old
   `--landscape-resolution` flag.
   `dataPrep_Monitor`'s per-resolution raster GENERATION is also done:
   `computeLanduse()`/`computeLandcover()`/`processDEM()` (+ their
   `prepare*` wrappers) now accept a vector of distinct resolutions per
   scale, generating each exactly once (not once per species); their
   existing "independent per-scale-entry cache check" (a resolution
   already valid is skipped even when another needs recomputing)
   generalizes cleanly from exactly 2 entries to however many are needed.
   `occurrencePrepGerHabitat()`/`GerLandscape()` re-key their covariate
   lookups by each species' own resolved resolution the same way --
   habitat scale additionally groups species by resolution and reruns its
   reference-grid/cell-extraction pass once per group (genuinely
   resolution-dependent); landscape scale only needed its covariate-stack
   lookup re-keyed (presence/absence construction there never touches a
   resolution-specific grid).
2. **`brt_start_lr` removed from the CSV entirely.** A BRT's starting
   learning rate is a one-time, technical/algorithmic bootstrap value, not
   an ecological per-species decision -- and the existing converged-LR-
   persistence mechanism (`resolveStartingLR()`/`persistConvergedLR()`,
   unrelated and unchanged) already adapts per species across successive
   runs, making a CSV-level starting override redundant. Module-level
   `europeInitialLR`/`habitatInitialLR`/`landscapeInitialLR` constants only.
3. **`predictor_mode` removed entirely** -- `speciesConfig_predictors.csv`
   is now the ONLY source of a species' candidate predictors (no more
   `"table"`/`"all"`/`"auto"` selector; a species missing from that CSV is
   now a hard error, not a silent `"auto"` fallback). `select07Blockcv()`'s
   real block-CV collinearity selection survives as an independent
   `dropCollinearPredictors` toggle (`inputs_Monitor`, module-level,
   default `FALSE`) applied ON TOP of the table's own list, never
   substituting a different candidate set.
4. **Small cleanups:** dead `hedgesTreatment` scaffolding (already
   commented-out, never active) removed; `dataPrep_Monitor`/`inputs_Monitor`'s
   hardcoded, stale 11-species `species` parameter defaults replaced with
   `NA_character_` (errors if a caller doesn't supply `sharedSpecies`
   explicitly, instead of silently drifting from the real roster); the
   vestigial pre-SpaDES-pipeline root `config.yaml` deleted (confirmed
   unreferenced -- the two Python scripts mentioning it in a comment
   explicitly do NOT read it, by design); README.md's hand-typed
   `testSpecies` escape hatch replaced with the sanctioned
   `speciesCanonical.csv`'s `include` column approach (the only way every
   module and the cluster path see the same restricted roster
   automatically).

**Governing principle** (stated by the user, now the header comment in
`sharedSpeciesConfig.R`): config CSVs hold "ecological" decisions --
predictors, data origin/source, scales/resolution, which species are
included, per-species evidence filters, the spatial-term opt-in.
"Technical" decisions about how the optimizer/algorithm itself behaves (a
BRT's cold-start learning rate, which predictor-selection algorithm to run)
belong in the module as a simple shared constant, not a per-species CSV
knob.

**Why:** `predictor_mode` never had a real per-species decision to make
(every species always used `"table"`) -- a mode selector with one
observed value is complexity without payoff. `resolution_m` being
collected but unconsumed was worse than not having the column at all: it
looked authoritative (a human reading the CSV would assume it took
effect) while silently doing nothing.

**Status:** Verified end-to-end with real (non-mocked) computation at
every point: `models_Monitor`'s per-species resolution resolution tested
with two species (one default, one 15x coarser override) via real
`optimizeBRT()`/`dismo::gbm.step()` fits -- confirmed each species' model,
performance, and prediction rasters land in its own resolved `scale_X`
output folder, reading its own resolution's covariate stack.
`dropCollinearPredictors` tested with real `select07Blockcv()` over a
synthetic near-collinear predictor pair -- confirmed `FALSE` keeps the
table's list as-is and `TRUE` prunes it; confirmed a species missing from
`speciesConfig_predictors.csv` now hard-errors. `inputs_Monitor`'s
resolution-based spatial-blocking grouping verified with a synthetic
mixed default/override species vector. `dataPrep_Monitor`'s raster
generation verified with real synthetic categorical/DEM rasters at two
distinct resolutions per scale for `computeLanduse()`/`computeLandcover()`/
`processDEM()`; occurrence-prep verified with real synthetic MhB/DDA
data + Probeflaechen shapefile at two distinct resolutions, confirming
correct per-group reference-grid routing (habitat) and per-species
covariate-stack routing (landscape), each producing valid model-ready
output.

**Where:** All 4 repos, branch `feature/reconcile-with-v2-flexible-config`
(root: `feature/config-data-folder`). `sharedSpeciesConfig.R`,
`data/speciesConfig_general.csv`, `runMe.R` (root); `inputs_Monitor.R`,
`R/collinearityCheckGerHabitat.R`/`GerLandscape.R`/`Europe.R`
(inputs_Monitor); `models_Monitor.R`, `R/modelGerHabitat.R`/
`modelGerLandscape.R`, new `R/resolveResolutionM.R` (models_Monitor,
replacing deleted `resolveSpeciesResolution.R`/`extractScaleStartingLR.R`);
`tools/runClusterTask.R` (root).

---

## 2026-09-28 — Each scale's fitting-year window is dictated by its own survey, not shared; extrapolation risk differs by scale accordingly

**What:** The three scale-level BRTs are each calibrated against a
different real occurrence survey with a different real temporal
footprint -- not a modeler choice: Europe/climate is a single fixed EBBA2
atlas vintage (anchored to `ebba2TrainingYear`, currently 2017); German
landscape (1km) is DDA territory counts, collected annually 2005-2025;
German habitat (200m) is MhB point counts, which only exist 2022-2025.
Each scale's model is then asked to predict across the SAME full German
modeling period (`landscapeYears`, currently 2005-2025) regardless of how
far that range sits from its own training window -- so each scale's
predictions carry a different, scale-specific amount of built-in
extrapolation:
- **Habitat**: trained on 4 years (2022-2025), predicts 21 years --
  everything outside 2022-2025 is an extrapolation of increasing risk the
  further from that window (e.g. 2005 is a 17-year hindcast).
- **Landscape**: trained on the full 2005-2025 range already, so its own
  predictions across that same range carry almost no extrapolation risk.
- **Climate**: trained on one atlas-period snapshot, predicted onto 21
  separate rolling bioclim windows -- extrapolating in a different sense
  (climatology drift across rolling windows, not survey-year drift).

The ridge meta-model separately extrapolates its OWN fitted weights across
2005-2021 (already documented in `metaModel()`'s own docstring: "2005-2021
are hindcasts, assuming stable scale weighting over time") -- this entry
adds the fact that its three INPUT features (the scale-level suitability
predictions it combines) are themselves extrapolations of very different
magnitudes, compounding on top of the meta-model's own hindcast
assumption, not a separate, independent source of uncertainty.

**Why:** Raised as a direct question -- "shouldn't all training years for
all 3 scales be the same?" Answer: no, and they can't be without
discarding real data (throwing away 20 years of real DDA counts) or
fabricating data that doesn't exist (MhB pre-2022). The scales are
independently-fit base models in a stacking/ensemble design; the
meta-model's own training window is correctly anchored to `habitatYears`
specifically (the only years with a real ground-truth response to
regress against), not to some shared "all scales' fitting years" concept
that doesn't exist. What DOES need to be visible to anyone interpreting
results is that "habitat suitability in 2005" and "landscape suitability
in 2005" rest on very different amounts of extrapolation, even though
both feed the same meta-model prediction for that year.

**Status:** Documented assumption/limitation, not a bug -- no code change.
Worth surfacing in any results write-up or figure caption that presents
hindcast years (pre-2022) alongside habitat-informed years, so a reader
doesn't implicitly assume uniform confidence across the full 2005-2025
series.

**Where:** Conceptually applies to `modelEurope()`/`modelGerHabitat()`/
`modelGerLandscape()`/`metaModel()` (models_Monitor). No specific file
changes from this entry.

---

## 2026-09-28 — `runIndex_Monitor`: index/report extraction into its own SpaDES module, chained into `runMe.R`

**What:** The multi-species index/report functions (previously loose files
in `models_Monitor/R/`, driven by a hand-rolled root-level `runIndex.R`
script run manually AFTER `runMe.R` finished) are extracted into their own
real SpaDES module, `runIndex_Monitor`, and chained directly into `runMe.R`'s
own pipeline (`loadOrder`'s last module) -- one `runMe.R` invocation now
produces data prep -> inputs -> models -> index/report. `runIndex.R` is
retired.

**Function boundary** (confirmed via cross-reference grep across
`models_Monitor.R`+`R/*.R` before moving anything): 17 functions form a
self-contained subgraph, reachable only from `runIndex.R`/each other, never
from `metaModel()` or any core fitting function --
`computeAnnualReport`/`computeChainIndex`/`computeChangeCI`/
`computeChangeMaps`/`computeCombinedIndex`/`computeCombinedIndexAnalytical`/
`computeCombinedIndexMSI`/`computeGriddedCombinedIndex`/`computeIndexSE`/
`computeRegionalIndex`/`computeSRMap`/`computeSpeciesIndex`/
`extractMetaProbSD`/`extractMetaProbSeries`/`aggregateSpeciesToGrid`/
`smoothGriddedIndex`/`smoothIndex` -- these moved verbatim (logic
unchanged, aside from the two terra fixes below) and were deleted from
`models_Monitor/R/`. `extractSuitability`/`loadSuitability`/
`getOrBuildSuitX`/`computeVariableImportance`/`fitDevRatio` (used directly
inside `metaModel()`'s own training) and `metamodelLabel`/`scaleLabel`
(used by `models_Monitor.R`'s own `metaModel` event) stayed in
`models_Monitor` -- `metamodelLabel.R`/`scaleLabel.R`/
`isValidPredictionRaster.R` got duplicated (byte-identical) into
`runIndex_Monitor` too, the same pattern already used for `scaleLabel.R`
across 3 modules (checked automatically by
`tools/check_duplicated_functions.R`, which discovers duplicates by
filename with no watched-list to maintain).

**Ordering:** SpaDES processes same-`time(sim)` events in scheduling order
-- `runIndex_Monitor` last in `loadOrder` means its `init` is scheduled
after every one of `models_Monitor`'s own events, the same mechanism
`metaModel` already relies on to run after
`modelEurope`/`modelGerHabitat`/`modelGerLandscape` within `models_Monitor`
itself. For a cluster run (`tools/runClusterTask.R`, one SLURM array task
per species x scale, no natural "last one out" moment across the WHOLE
roster), a new self-rescheduling `checkAllInputs` event polls every
`pollIntervalSeconds` (real wall-clock `Sys.sleep()`, not simulated time --
this pipeline's `timeunit = "year"` is already a formality) whether every
species has a complete `metaModel()` output for every year it needs
(`checkAllSpeciesMetaReady()`, new helper generalizing
`checkAllScalesReady()`'s per-species-per-scale pattern to the whole
roster), and only then proceeds. `pollTimeoutHours` bounds this: after
timeout, WARN (never stop) which species are still missing and proceed
anyway with whatever is available.

**New `validateIndexYears()`**: before computing, warns (never stops)
exactly which years a requested comparison (`baselineYear`/`currentYear`/
`vsLastYear`/`vs5YearsAgo`/the Chain-index `restrictedYears` robustness
check) needs and which are missing a real `metaModel()` output --
`computeChangeMaps()`'s comparisons already degraded gracefully to
`NULL`/`NA` for a missing year, silently; this surfaces the same gaps up
front, by species, before the (possibly long-running) computation starts.

**Two real terra bugs found and fixed while chaining into the live SpaDES
session** (both worked fine called standalone in a fresh R session, which
is how the pre-existing `runIndex.R` script always ran them -- neither was
ever exercised inside a live `simInit()` session before):
1. `computeChangeMaps()` directly `c()`-combined several DERIVED (computed,
   not read-from-disk) rasters -- the same class of bug
   `writeTwoLayerRaster.R`/`combineTwoLayerRaster()` (models_Monitor) was
   already found and worked around for a 2-layer case ("Stacking a derived
   raster... together with its source raster and writing directly causes
   the source layer's values to zero out in some terra versions"). Fixed
   with a new, generalized N-layer version of that same workaround
   (`combineLayersSafely()`: write each layer to its own temp file, then
   re-read and combine) plus force-materializing every computed raster
   into memory immediately after computing it
   (`terra::values(x) <- terra::values(x)`) -- the arithmetic RESULT
   otherwise stays lazily linked to its source rasters, which can go
   invalid later in a long-lived session with many other raster
   reads/writes in between.
2. `computeChangeMaps()`/`computeGriddedCombinedIndex()` called the BARE
   `mean()`/`sum()` generics on `SpatRaster` objects. Something about the
   chained SpaDES session's package loading (not yet root-caused --
   `mgcv`/`nlme`, both required for the GAM smoothing in
   `smoothIndex()`/`smoothGriddedIndex()`, are the leading suspect) breaks
   `mean()`'s S3/S4 dispatch to terra's `SpatRaster` method partway through
   the session -- `sum()` kept working throughout (it's a primitive, not
   an ordinary S3 generic, and dispatches differently), but bare
   `mean(spatRaster)` silently fell through to `mean.default()`, returning
   a bare numeric `NA` instead of a raster, cascading into a `writeRaster`
   type error downstream. Fixed by calling `terra::mean()`/
   `terra::app(fun = "sum")` explicitly, namespaced, everywhere a
   `SpatRaster` (not a plain numeric vector -- `computeCombinedIndex()`'s/
   `computeCombinedIndexAnalytical()`'s/`computeCombinedIndexMSI()`'s own
   `mean(log(...))` calls on numeric index VALUES are unaffected and
   untouched) is involved, sidestepping the dispatch issue regardless of
   its exact root cause.

**Why:** Chaining lets one `runMe.R` run produce the full report, and gives
the index/report step SpaDES's own parameter validation plus the
init-time year-sufficiency check that was the actual original ask. The
two terra fixes are real, pre-existing latent bugs the chaining exposed --
not something introduced by the extraction itself, but only fixable once
actually exercised inside a live session, which the extraction is what
finally did.

**Status:** Verified end-to-end with real (non-mocked) `simInit()`/
`spades()` runs: a fast path (all species ready immediately, `checkAllInputs`
resolves on its first check, full annual report + regional index complete)
and a timeout-and-proceed path (one species' output deliberately never
appears, confirms real wall-clock polling via `Sys.sleep()`, times out,
warns naming the missing species, still completes the report for the
species that IS ready).

**Where:** New module `modules/runIndex_Monitor/` (own future GitHub repo,
`tati-micheletti/runIndex_Monitor` -- not yet a real git submodule as of
this entry; built and tested locally, `runMe.R`'s `useGit = FALSE` reads
straight from disk regardless). `runMe.R` (module added to `modules`/
`loadOrder`, new `params$runIndex_Monitor` block, root `runIndex.R`
deleted). `models_Monitor/R/` (17 files removed).

---

## Unverified / open items (do not treat as settled)

- **`evalSDM()`/`blockCVPredictBRT()` have no fixed seed** -- re-running
  either on an unchanged model can give a slightly different AUC/TSS/
  threshold each time (see the reproducible::Cache() entry above for how
  this surfaced). Worth a real fix (e.g. `set.seed()` inside, or an explicit
  seed argument) at some point for fully reproducible performance metrics,
  but out of scope for the caching work that found it.
- **Minimum 10 presences before attempting to fit a model at all**
  (`occurrencePrepGerHabitat()`/`GerLandscape()`/`Europe()`, `nPres < 10` ->
  skip species/year entirely). **Checked directly against Wiedenroth et al.'s
  own published reference code** (GitHub: UP-macroecology/Wiedenroth_multi-scale-SDM_2026,
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
  Note: verified this floor is currently INERT for the real 2022-2025 MhB
  data across the entire 12-species roster (lowest real count: Perdix
  perdix, 41 in 2022) -- it never actually fires with real data as of
  2026-09-26.
- **Buteo/Star landscape routing's real-world effect on model quality** --
  see the entry above; implemented and unit-tested, not yet validated
  against a real model run.
- **Per-species covariate resolution** (`resolution_m` column) -- captured in
  the config CSV, no consuming code yet. See `improvements.md` item 4.
