# birdMonitor — Potential ToDo List

Grounded against Wiedenroth et al. (preprint, DOI 10.3897/arphapreprints.e205471),
the paper this pipeline is based on. Their reference code/data links are on Zenodo:
https://doi.org/10.5281/zenodo.20828528 — worth pulling and diffing against our
implementation for several items below, especially #4.

## A. Right after the v3 results (set 4 November 2026, in this order)

0. **URGENT, before everything else after v3: improvements.md item 27** - one template grid per scale (`rasterToMatch`) and the study area for every processed layer, with `Cache` (`prepInputs`/`postProcess`); the crop markers are only a shortcut for the v3 run (project lead, 2026-11-06). The two prep failures of 5-6 November (hedge rim of the larger land-use grids; uncropped heterogeneity and unmapped-share layers) have this one cause.
1. **Residual spatial clustering.** Take the out-of-fold residuals of the v3 models (per species and scale) and compute Moran's I per spatial block. If there is no clustering, nothing more is needed for space; if there is, it decides what replaces the `x`/`y` coordinate term (a smooth term only in GAM/NN, or a regional factor).
2. **DONE 2026-11-05 (before the v3 resubmission): Grauammer without `x`/`y`** (DECISIONS 2026-11-05, audit table S3-10). `spatial_term` is blank for the three Emberiza calandra rows, so no species uses coordinates; v3 fits it without the term from the start, no separate rerun. Left: after the prep, check that the model-ready predictor list of Emberiza calandra has no x/y; after v3, that the maps have no step at 10.7 E and what the accuracy does against v2.
3. **Guard in `completeHedges()`** (audit table S2-28): refuse to run when only some of the land-use years carry the fixed hedge layer, so that a partial recompute cannot overwrite all years with the hedges of the recomputed ones.
4. **Connector check.** After the connector job: count the rows of `/data/birds/viz/_manifest.csv` whose run is not v3 (an empty `_missing.csv` does not prove that everything comes from v3; audit table S5-49).
5. **Audit table, part F** (unexpected results): DDA presence rising for the Red-backed Shrike and the Whitethroat while ours does not; the Grauammer map; the linear features in the Red-backed Shrike maps; the jumps of the combined index in 2017, 2022 and 2024 and its difference from the European farmland index; the 2024-25 maize area (S2-69).
6. **DONE 2026-11-05 (uncommitted, see item 10 for what is left):** **Documentation texts that are wrong** (all listed as red or yellow in the audit table): the `metaHonestEval` parameter text in `models_Monitor.R` (FALSE changes the weights and the maps), the README on `brutzeitcode_filter`, the NN size in `DECISIONS.md`, the `sharedConfig.R` comment on the habitat years, and the claim "no pseudo-absence sampling" in the methods document.
7. **Count the GAM/GLM fallbacks of v3:** `Rscript tools/countAlgoFallbacks.R --run v3` (EVE, after the ensemble fits; module load R first). Put the count into the methods document (GAM row of the algorithm table, where it says "count for v3: to be added") and into the audit table (S3-26).
8. **S9 figures for v3** with the fixed handling of `Reviere = -1` (in the working tree, to be committed) and the check of the v3 manifest.
9. **Do the block-alignment test of the out-of-fold meta-model inputs** (improvements.md item 25; audit table S3-45, S3-47). Per species and scale: share of habitat records whose nearest-record fold differs from the fold of the block that contains them, and the distance to the nearest record. Then, for the species with a high share and for Vanellus vanellus, recompute the ridge weights and honest AUC with the exact folds (BRT member only) and compare with v3. Decides whether the exact (point-in-polygon) assignment is worth building.
10. **Open questions found while aligning the documentation (2026-11-05):** (a) the annual-report functions (`computeCombinedIndex`, `computeChainIndex`, `computeCombinedIndexMSI`) report 95% intervals (`lwr95`/`upr95`), the uncertainty pipeline 90%: check which of them the Monitor and the figures show and make the Methods document say it; (b) DECIDED 2026-11-05 and changed in `runMe.R` (`restrictedYears = 2022:2025`; it had been 2005:2025, which made the restricted chain a copy of the ordinary one). The v3 chain submitted on 5 November comes AFTER the pull of this change, so all its jobs use the new setting and no rerun of the index step is needed; check in the v3 outputs that `combined_index_chain_restricted.csv` differs from `combined_index_chain.csv`; (c) the explained-deviance file `<species>_expl_dev_<scale>.rds` holds an in-sample number (S3-22): rename needs a code change; (d) fixed `--array=1-11` headers in several `cluster/*.sbatch` (the submit scripts override them); (e) rendering: the Handover, Methods, Steering, Executive summary, Figure reference, FAQ and audit table must be rendered once more after v3, and every `[AFTER v3]` mark filled.
11. **Hedge gaps in the next prep (DECISIONS 2026-11-05, audit S2-70):** read the prep log (logs/prep_<jobid>.err) early: (1) the completeHedges line must say 'all files already carry the fixed layer, nothing to do' or 'fixed layer (mean of 2017,2018,2019,2020,2021,2024,2025)', never a shorter list of years (a partial recompute would give a wrong mean; the guard of item 3 does not exist yet); (2) the 'hedges gaps' lines: cells per file, farthest source distance, coordinates. First log of the resubmitted run: 405 cells per 2024/2025 file at 200 m (farthest source 1,200 m), 37 at 700 m (1,400 m): the fill covers the 1 km buffer ring of the larger grids, not only the 2-5 cells inside Germany (DECISIONS 2026-11-05, late evening); read the scale_1 and scale_5 lines too. If it is a few dozen cells or more, or elsewhere, the explanation in DECISIONS is incomplete. Also measure the side finding: do records in the 1 km buffer ring (coastal route centroids) get land-use values in the HCTM years (2005-2023), whose files have no ring at the bounding-box edges?
12. **Water mask for the viz copies (implemented 2026-11-05, DECISIONS 2026-11-05, audit S5-80; improvements.md item 26):** copy `inputs/predictors/raw/water/water_bodies.gpkg` (239 MB, made by `tools/prepareWaterLayer.R`) to EVE before the chain is submitted; after the connector look at the coast (Wadden Sea, bays are not masked) and the widest rivers; add the credit "Contains data from OpenStreetMap contributors (ODbL 1.0)" to the Monitor.
13. **Stale crop markers (DECISIONS 2026-11-06, audit S1-71):** after the next prep check that the 2024-2025 heterogeneity and unmapped-share files are on the grid of the land-use file at all four scales, and that the habitat occurrence step passes 2024 and 2025 for all 14 species. Then look for the same trap elsewhere: any layer that is rewritten by a step but stamped by another (compare the age of every `.studyarea` marker with its file in `inputs/predictors/processed`).
14. **Memory settings for the NEXT run (decided 2026-11-06, `cluster/MEMORY_LEDGER.md`, section 'Decided for the NEXT run'):** BRT europe 3 GB; unc-prepare 96 GB (8 x 12); unc-band 44 GB (4 x 11); unc-community 12 GB; unc-summarize, -assemble, -assembleall, -regionband, -regionassemble, -regionindex, -covcache 4-6 GB. Keep landscape and meta at 13 GB, habitat BRT at 12 GB, covcache (habitat) at 24 GB. Watch item: ens-habitat-rf 32 GB (peak 30.4). Apply in the sbatch files and the submit scripts only after v3, in one commit with the ledger; after every OOM update the ledger first.
15. **Run time of the chain (project lead's question, 2026-11-06):** species already run in parallel (arrays of 14; band 672 tasks, throttle 100); the 85 h come from the slowest species per stage (unc-prepare up to 24 h), the band throttle and every stage waiting for the whole previous array. Try per-species pipelining with sbatch --dependency=aftercorr between the arrays of consecutive stages (species i starts when species i of the previous stage is done) in cluster/submit_eve_clean_run.sh and the submit_eve_*.sh scripts; measure before and after; do not raise the band throttle blindly (fair-share priority drops with queued jobs).
16. **Independence of the species in the uncertainty band** (found 2026-11-10; UNCERTAINTY.md, "What is NOT covered", item 7). The block-bootstrap seed contains the species name, so each species gets its own draw and the species' sampling errors are independent; the band of the national MSI and of the regional index is probably too narrow, because the species share most survey sites. After v3: (a) quantify it (e.g. the correlation of the species' replicate indices, or a band where the species of one replicate share the draw, for species with the same block size); (b) decide whether to share draws (needs one block size for all species) or to state it as a limitation. Also count the replacements of failed member refits in `refit_fallbacks.csv` (item on GAM/GLM fallbacks) for the same statement.

## 0. Found while reading the paper — methodology-fidelity gaps

Not on your original list, but concrete and worth fixing before treating any
model output as scientifically final:

- **RESOLVED 2026-10-06 (`fitRidgeCv()`, `lower.limits = 0`; DECISIONS.md): Ridge meta-model allowed negative coefficients; the paper's doesn't.**
  Paper (Results/Methods): *"As the lowest relevancy of a scale was no
  relevancy, we did not allow negative coefficients in the model."* — i.e.
  `glmnet` fit with `lower.limits = 0`. Our `metaModel()`
  (`modules/models_Monitor/R/metaModel.R`) fits `cv.glmnet(..., alpha = 0)`
  unconstrained. This was already a self-acknowledged gap in the original
  (pre-SpaDES) script's own comments — I preserved it faithfully rather than
  silently fixing it, since it's a modeling-methodology decision, not a code
  bug. Worth an explicit decision: match the paper, or intentionally diverge
  (and say why in the eventual paper/methods section).
- **Spatial blocks: paper uses hexagon-shaped blocks; check `cv_spatial()`'s
  `block_type` isn't defaulting to something else** in
  `spatialBlockingEurope()`/`GerHabitat()`/`GerLandscape()` (inputs_Monitor).
- **Single-scale SDMs in the paper are 4-algorithm ensembles** (GLM+GAM+RF+BRT,
  arithmetic mean) — this directly motivates your item #4 below; it's not
  just "more model choices," it's matching the actual published method, which
  our pipeline currently only partially implements (BRT alone).
- `scripts/extras/test_class_imbalance_options.R` shows the original team
  investigated site-weighting/absence-downsampling for class imbalance
  (e.g. Vanellus vanellus ~9.7% prevalence) but it never made it into the
  final scripts we ported. Worth a conscious decision, not silent omission.

## 1. Complete the `.Rmd` files (module documentation)

Each module has a stub `<moduleName>.Rmd`. Needs, per module:
- [ ] `dataPrep_Monitor.Rmd` — the 5 events in order (climate/DEM/landuse/
      landcover/occurrence), every parameter with its meaning, the raw-data
      placement contract (`dataPath(sim)/raw/...`), CLMS token setup steps
      (can mostly point at `python/download_landcover.py`'s own docstring),
      the auto-provisioned reticulate venv.
- [ ] `inputs_Monitor.Rmd` — explain the "always run, strategy toggle"
      architecture (real vs. mimicked spatial blocking; real/override/all
      collinearity), and the table-schema contract downstream code depends on.
- [ ] `models_Monitor.Rmd` — the 4 events, the deliberate duplication of
      `loadCovariates`/`loadHabitatCovariates` (link to
      `tools/check_duplicated_functions.R`), hindcast years caveat.
- [ ] Root-level `README.md`/`runMe.R` walkthrough tying the 3 modules together.

## 2. Fill in default inputs — standalone, testable modules

Currently each module's `.inputObjects()` is an empty stub; every module
structurally depends on either raw data already being on disk or another
module having run. To make each module `simInit()`-able alone:
- [ ] `dataPrep_Monitor`: small synthetic/mock raw files (tiny EBBA2 CSV+SHP,
      tiny MhB CSV, tiny DDA xlsx+SHP) so occurrence prep can run without your
      real (multi-GB) survey data.
- [ ] `inputs_Monitor`: mock `sim$inputsData`-shaped input so
      spatialBlocking/collinearityCheck are testable without dataPrep_Monitor
      having run.
- [ ] `models_Monitor`: mock `sim$inputsData` (small, few rows) so BRT/ridge
      fitting logic can be exercised without a real multi-hour data prep pass.
- [ ] Consider a `mockData/` folder per module (gitignored raw size, but a
      tiny fixture set committed) — this is also exactly what the tests in
      item 3 will need as fixtures.

## 3. Tests

`scripts/extras/` (12 files) — checked, I do have access. These are **ad hoc
sanity-check/exploration scripts**, not `testthat` unit tests:
- `sanitycheck_*.R` (7 files): plausibility-range checks on outputs (e.g.
  bioclim values within physically sane bounds) — good source material to
  turn into real `testthat::expect_*` assertions.
- `test_*.R` (2 files, `test_class_imbalance_options.R`,
  `test_predict_landscape.R`): one-off methodology experiments, not repeatable
  tests as-is.
- `aggregate_prec_daily_to_monthly.R`, `plot_partial_dependence.R`: utility
  scripts, not tests at all.

Each module already has `tests/testthat/test-template.R` (SpaDES boilerplate,
empty) and `tests/unitTests.R`. To do:
- [ ] Convert the plausibility bounds in `sanitycheck_*.R` into real
      `testthat` assertions per module (e.g. bioclim range checks →
      `dataPrep_Monitor` tests).
- [ ] Unit tests for pure/deterministic functions — **no real data or network
      needed**, can be written and run today regardless of the current run's
      progress: `corineYear()`, `stripYearSuffixes()`, `resolvePath()`,
      `determineBlockSize()` (with synthetic points), `mimicSpatialBlocks()`
      (structure/shape checks), `evalSDM()`/`explDeviance()`/`tssScore()`
      (synthetic obs/pred vectors with known answers),
      `makeCategoryProportionLayer()` (tiny synthetic raster).
- [ ] Integration-style tests using the item-2 mock fixtures once those exist.
- [ ] Add `tools/check_duplicated_functions.R` as an actual `testthat` check
      (or CI step) rather than a manually-run script.

## 4. Implement the other model types (GLM, GAM, RF; NN as an extension)

Per the paper: each single-scale SDM is an ensemble of GLM + GAM + RF + BRT,
averaged via arithmetic mean (not BRT alone, which is all we have now).
Neural networks aren't in the paper — that'd be a deliberate extension beyond
Wiedenroth et al., worth flagging as such if it goes in the eventual manuscript.
- [ ] Design: a shared "fit one algorithm, get comparable predictions" interface
      so `modelEurope`/`modelGerHabitat`/`modelGerLandscape` can loop over
      algorithms instead of hardcoding `optimizeBRT()`.
- [ ] GLM, GAM (mgcv, already a dependency via inputs_Monitor's
      `computeUnivarCV`), RF (ranger or randomForest), ensemble-average step.
- [ ] Decide: keep per-algorithm CV performance, or only ensemble-level?
      (Paper reports per-scale ensemble performance, not per-algorithm.)
- [ ] NN as an opt-in 5th algorithm, clearly labeled as beyond-paper.

## 5. Discuss improvements related to presence/absence vs. abundance

See `improvements.md` -- once the current run's models are complete:
(1) abundance modeling -- a hurdle/two-part model testable at both habitat and
landscape scale (reusing the existing presence/absence ensembles as the "zero
part"), or N-mixture detection-corrected modeling, the more statistically
sound option but confirmed feasible at habitat scale only (landscape-scale
`Reviere` doesn't expose the repeat-visit data N-mixture needs); (2) separating
`data/` (raw inputs, gitignored) from `outputs/` (pipeline outputs only) --
everything currently lives under `outputs/test1/`, including irreplaceable raw
survey data; (3) RAM-aware parallelization of per-species model fitting --
auto-detect (or accept a user-supplied) RAM budget to run multiple species
concurrently instead of the current fully-sequential loop, which leaves most
of a 64GB machine idle at ~11-14GB peak observed usage; (4) per-species scale
sizing (habitat/landscape/climate resolution) -- confirmed via independent
non-SpaDES results (Lisa Hildebrand) and real home-range literature that a
fixed 1km landscape window is a genuine scale mismatch for at least Milvus
milvus and Lanius collurio specifically; also the natural trigger to finally
bring in `reproducible::Cache()`; (5) test excluding `hedges` as a covariate,
given it's currently backfilled with flat values across most years rather
than real temporal data. Every item in `improvements.md` gets its own feature
branch -- `master` is not touched until tests exist and the change is
validated.

## 6. Speed up `computeLanduse`/`computeLandcover` category-proportion loop

At full-Germany 10m resolution (post-2016 CTM/Tetteh datasets), each land use
category took ~700s/category (~2.75hrs/year) in `computeLanduse()`
(`modules/dataPrep_Monitor/R/computeLanduse.R`) — makes a multi-year run tight
against any deadline. Root cause identified and a fix was verified *offline*
but reverted after crashing the live 2026-08-28 weekend run — do not reapply
without finishing the investigation below first.

- **Confirmed, safe win (not yet reapplied):** `makeCategoryProportionLayer()`
  (`modules/dataPrep_Monitor/R/makeCategoryProportionLayer.R`) is called twice
  per category — once for habitat scale, once for landscape scale — and each
  call independently recomputes the same expensive binary mask via
  `terra::app(categoricalMap, function(x) as.integer(x %in% codes))`, even
  though the mask doesn't depend on target resolution at all. Benchmarked:
  `categoricalMap %in% codes` (terra's native vectorized op) is ~4.8x faster
  than `app()` + R closure, with verified bit-identical output (synthetic data
  AND the real `CTM_GER_2018` tile, both checked via `all.equal(values(...))`).
  Computing the mask once and reusing it for both scales removes the 2x
  duplication on top of that. Combined estimate: ~2.4x per-category speedup.
- **What broke:** applying this (new file `aggregateProportionLayer.R` +
  edits to `computeLanduse.R`/`computeLandcover.R`/
  `makeCategoryProportionLayer.R`) crashed the live SpaDES run with
  `unable to find an inherited method for function 'res' for signature
  'x = "logical"'` — i.e. `cropMap %in% codes` returned a plain logical
  vector instead of a SpatRaster *only inside the live multi-module SpaDES
  session*, not in isolated repro attempts.
- **Ruled out empirically** (both via standalone `Rscript` tests matching
  `dataPrep_Monitor`'s own `reqdPkgs` load order, `terra, dismo, raster,
  spatialEco, sf`, and using the real `CTM_GER_2018_rst_v202_COG.tif` tile
  after `project()`): `%in%` dispatched to the correct `SpatRaster` method
  every time. So it is **not** simply "wrong package masks `%in%`" in the
  order `dataPrep_Monitor` alone declares, and not something specific to the
  real raster's data/type.
- **Real, confirmed, but unconfirmed-as-root-cause fact:** both `terra` and
  `raster` export their own function literally named `%in%` (checked via
  `getNamespaceExports()`). `raster` is also a `reqdPkg`, loaded after
  `terra`. This is a genuine collision, just not one that reproduced in the
  isolated per-module test above.
- **Not yet tried:** `runMe.R` loads all three modules
  (`dataPrep_Monitor`, `inputs_Monitor`, `models_Monitor`) together via
  `SpaDES.project::setupProject()`, which combines each module's `reqdPkgs`
  — check whether `inputs_Monitor`/`models_Monitor` also declare `raster` (or
  another `%in%`-exporting package) in a way that changes the *combined*
  attach order versus `dataPrep_Monitor`'s order alone, and reproduce against
  that actual combined load rather than a single module in isolation.
- Once root-caused and re-verified against a real multi-module `simInit()`
  (not just a standalone script), reapply the mask-dedup fix — same approach
  as this list's other saved-for-later item, item 6 below (EVE cluster): both
  are performance work better done with time to properly verify, not under a
  live deadline.

## 7. EVE cluster migration + parallelization

See saved session memory `project_eve_cluster_parallelization` — birdMonitor's
raster processing is currently sequential/single-threaded; local peak RAM
observed on a real full-Germany 10m run was ~11GB (out of 64GB available), so
there's headroom for parallelism that wasn't exploited under weekend deadline
pressure. When migrating to UFZ's EVE cluster:
- [ ] Design chunked/tiled or category-level parallelism (`future.apply`,
      `parallel`, or SLURM array jobs per year) sized to the cluster's actual
      allocated cores/memory, not retrofitted locally.
- [ ] Use the ~11GB local peak as a per-worker memory budget floor when
      estimating how many parallel workers a given EVE node allocation could
      support.

## 8. Verify whether Anthus pratensis's climate-scale 0-presence result is stale

Cross-references `improvements.md` item 9 (the broader "no EBBA2 refresh
mechanism" gap). During an unrelated block-CV investigation (2026-09-30),
the cached `Anthus_pratensis_inputs.rds` at climate scale was confirmed to
have 0 presence records in all 670 rows -- matching the documented stale
2026-07-17 EBBA2 extract (predates the species being added to the roster,
2026-09-24), which is why `optimizeBRT()` correctly returns `NULL` and the
caller skips this species/scale rather than fitting on an all-absence
response.

**But the raw file on disk right now is newer** --
`inputs/response/raw/ornitho/ebba2_data_occurrence_50km.csv` is dated
2026-09-26 and contains 2149 rows matching "pratensis" (case-insensitive
grep). This strongly suggests the raw data gap may already be resolved,
and the 0-presence result is reading a stale CACHED/processed occurrence
extract that predates this refresh, not a currently-still-missing-data
problem.

- [ ] Force a re-extraction (delete/invalidate the cached
      `Anthus_pratensis_inputs.rds` at climate scale, or set the relevant
      `rerun*` flag in `dataPrep_Monitor`) and confirm whether real
      presence data now flows through to the model-ready table.
- [ ] If yes: the data gap is resolved -- `optimizeBRT()` should no longer
      skip this species/scale. Update `improvements.md` item 9 and
      `DECISIONS.md` to record the resolution, then re-run climate-scale
      fitting for this species.
- [ ] If the extract still comes up empty despite the refreshed raw file:
      investigate why (check the occurrence-prep/filter logic for climate
      scale for anything that could be excluding these rows for a
      different reason -- e.g. a name-matching mismatch, a bbox/grid-cell
      filter, a date-range filter), then plan the real fix.
- [ ] Separately: `inputs/response/raw/ornitho/ebba2_data_occurrence_50km_pipit.csv`
      exists on disk (also contains the same 2149 "pratensis" rows) but is
      not referenced anywhere in the code (confirmed by grep). Confirm
      whether it's a leftover manual-verification artifact safe to
      delete, or something that should actually be wired in (e.g. if it
      was meant as the actual fix and the main file's refresh was
      coincidental/unrelated).

## 9. Make `dataPrep_Monitor` `scalesToRun`-aware, so it can skip a scale nothing active needs

**Confirmed real, expensive, and observed live (2026-09-30):** `scalesToRun`
(`models_Monitor`'s per-species stage restriction, added 2026-09-29 -- see
`DECISIONS.md`) only gates which of `modelEurope`/`modelGerHabitat`/
`modelGerLandscape`/`metaModel` actually run. `dataPrep_Monitor` has no
visibility into it at all -- it unconditionally prepares climate data
(CHELSA bioclim, one full 6-year rolling window average per
`climateTargetYears` entry), DEM derivatives, land cover, and land use for
every configured year/resolution, regardless of whether any currently-
active species will ever consume that scale's output.

**Real cost, not theoretical:** during the Buteo buteo/Sturnus vulgaris
habitat+landscape-only comparison test (`scalesToRun` excludes `"climate"`
for both species -- neither will ever run `modelEurope()`),
`prepareClimateData` still spent ~10+ minutes computing 4 overlapping
6-year climate windows (2022-2025) that get thrown away entirely, since
no active species' `inputsData$europe` survives `models_Monitor`'s own
`scalesToRun` filter. The same issue affects DEM/land cover/land use
prep if every active species excludes `"habitat"` or `"landscape"` --
today's code would still fully process that scale for nothing.

**Confirmed a second instance the same run (2026-09-30), and it's
expensive too -- corrected from an earlier "cheap" guess:**
`prepareOccurrenceData` also unconditionally loads/cleans/thins the full
EBBA2 (climate-scale) occurrence dataset for every active species,
regardless of `scalesToRun`. Timed directly from the real run's own
timestamps: Buteo buteo's climate-scale spatial thinning (100km distance,
~4,093 candidate cells) took ~20.5 minutes; Sturnus vulgaris's took
another ~20.7 minutes -- ~41 minutes combined, thrown away entirely since
neither species uses climate scale this run.

**Root cause of the cost, confirmed by direct comparison, not guessed:**
it's the thinning RADIUS that dominates cost, not record count. The same
run's habitat-scale thinning (400m distance, 1,655 records for Buteo) took
only ~87 seconds -- roughly 14x faster despite a similar-order record
count. A 100km exclusion radius means checking far more candidate
neighbor pairs per point than a 400m one. This means any species-year
combination using climate scale's default 100km thinning distance
(`sharedConfig.R`'s default, or `speciesConfig_general.csv`'s
`thinning_dist_m` override) pays this cost, independent of how few
records it actually has.

**Practical implication:** this makes the `scalesToRun`-awareness fix
above more valuable than first estimated -- it's not just ~10 minutes of
wasted covariate rasters, it's now looking like ~40+ minutes of wasted
occurrence-prep thinning too, for a species/run combination that never
touches climate scale. The eventual fix should gate `prepareOccurrenceData`
too, not just `prepareClimateData`/`prepareDEM`/`prepareLanduse`/
`prepareLandcover`.

**The fix, roughly:** derive, once in `runMe.R` (mirroring how
`distinctHabitatResolutions`/`distinctLandscapeResolutions` are already
computed from `resolutionConfig`), which of `climate`/`habitat`/
`landscape` are actually needed by *any* species in `scalesToRun` (default:
all 3, if `scalesToRun` is unset -- today's behavior, unchanged). Pass
that down as a new `dataPrep_Monitor` parameter (e.g. `scalesNeeded`), and
gate `prepareClimateData`'s whole event, and the per-resolution loops
inside `prepareDEM`/`prepareLanduse`/`prepareLandcover`/
`prepareDerivedCovariates`, on whether that specific scale is actually
needed at all before doing any real work for it.

**Why not fixed immediately (2026-09-30):** discovered mid-run, during a
live test -- the right fix touches `dataPrep_Monitor`'s `init` event and
every one of its 5 preparation events, plus `runMe.R`'s own scale-
resolution derivation logic already used for `resolutionConfig`. A
same-session, code-level fix is documented here as commissioned but not
yet built.

---

*Not yet started on any of these — this file is a starting point, not a
commitment. Update/reorder as priorities shift.*
