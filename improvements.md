# birdMonitor — Potential Improvements

Methodology extensions beyond a faithful port of Wiedenroth et al. Unlike `TODO.md`
(engineering/completeness gaps), this file tracks *deliberate methodological
departures* worth discussing before implementing, since they change what the
models actually estimate.

**Process note (applies to every item in this file):** none of these are to be
implemented directly on `master`. Each gets its own feature branch, and
`master` is not touched again until tests exist for the change and it has been
validated -- no exceptions, regardless of how small the change looks. This
applies to every improvement below, not just the data/outputs restructuring.

## 1. Abundance modeling: hurdle model (both scales) vs. N-mixture (habitat only)

Two options, not mutually exclusive -- the choice differs by scale because the
underlying data differs by scale (see item 2's data-availability findings):

- **Hurdle (two-part) model** could be tested at **both** habitat and
  landscape scale -- it only needs a zero vs. non-zero split plus a truncated
  count for the non-zero part, which both `TOTAL_COUNT` and `Reviere` support.
- **N-mixture** could be tested at **habitat scale only** -- it needs real
  repeated-visit data within a closed season, which only the MhB habitat-scale
  data has (confirmed below). It's the more statistically sound option where
  it's usable, since it corrects for imperfect detection directly rather than
  folding detection and true absence together the way both the hurdle model
  and the current presence/absence approach do.

A reasonable comparison worth running once resources allow: fit both at
habitat scale and compare performance/interpretation, since N-mixture is more
rigorous but hurdle is simpler and already reuses validated infrastructure.

### 1a. Hurdle (two-part) model, keeping the meta-model architecture

**The problem this addresses:** the current pipeline models presence/absence at
all three scales, discarding real count/abundance information that exists in two
of the three raw datasets — `TOTAL_COUNT` (MhB point counts, habitat scale) and
`Reviere` (DDA territory counts, landscape scale) are both binarized to
presence/absence early in `occurrencePrepGerHabitat.R`/`occurrencePrepGerLandscape.R`,
well before spatial thinning ever runs. EBBA2 (climate scale) is a coarse
breeding atlas and has no abundance information at all, at any point — that's a
hard data constraint, not a code decision.

**The idea:** a hurdle model (Cragg 1971) splits a zero-heavy count into two
independent parts: (a) a Bernoulli process for zero vs. non-zero, (b)
conditional on non-zero, a zero-truncated count distribution (Poisson or
negative binomial) for the magnitude. This maps directly onto what's already
built:

- The existing presence/absence SDM ensembles (GLM/GAM/RF/BRT per scale) *are*
  the Bernoulli ("zero") part already, fully built and cross-validated. No
  need to touch them.
- Add a second-stage model, fit only on routes/point counts where
  `TOTAL_COUNT > 0` (habitat) or `Reviere > 0` (landscape), regressing the
  truncated count against the same covariates via truncated-Poisson or
  truncated-NB GLM/GAM/RF/BRT.
- Combine: `E(abundance) = P(present) x E(count | present)` at each of the two
  count-capable scales.
- Climate stays a pure occurrence-probability input — ecologically defensible
  on its own terms, since the paper's own scale-importance result (climate
  ~1% importance) already suggests climate behaves like a coarse range-limiting
  gate rather than a fine-grained density driver (consistent with Johnson 1980
  hierarchical habitat selection theory, cited in the paper itself).

**Meta-model layer:** swap the ridge *logistic* regression (`cv.glmnet(family =
"binomial")`) for a ridge *Poisson/NB* regression (`family = "poisson"`), same
`lower.limits = 0` non-negative-coefficient convention Wiedenroth et al.
already use, same three scale-wise predictions as inputs (climate suitability,
log-expected-abundance at habitat and landscape scales).

**Why this is the most tractable extension:** no new data requirements, reuses
the entire validated presence/absence layer, well-established statistical
framework (hurdle/zero-inflated models are standard for exactly this kind of
ecological count data), and the meta-model combination logic barely changes.

**Zero-inflation note:** the published methodology never had to deal with
zero-inflation (excess zeros beyond what a Poisson/NB implies) because
presence/absence responses don't have that problem — `1 - p` directly captures
"how many zeros," no distributional assumption to violate. A hurdle model is
exactly the standard tool for confronting that problem once you do decide to
model counts, so choosing this path means deliberately taking on a modeling
complication the current pipeline currently avoids by construction.

### 1b. N-mixture models — feasible at habitat scale ONLY, confirmed empirically

**The idea:** Royle's (2004) N-mixture model jointly estimates true latent
abundance N and per-visit detection probability p from repeated counts at the
same site within a closed season: `count_it ~ Binomial(N_i, p_t)`. This
corrects for imperfect detection directly, rather than treating a "0" as
necessarily true absence -- a real, more rigorous alternative to both the
current presence/absence approach and the simpler hurdle model above.

**Data availability -- checked directly against the raw files, 2026-08-30:**

- **Habitat scale (MhB, `dbird_observations_CBBM.csv`): feasible.** Verified
  the raw observation CSV has real per-visit timestamped records, not a single
  yearly aggregate. For the 2023 breeding season (April-June), the large
  majority of routes were visited exactly 3 times (1071 of ~1227 routes), 115
  routes 4 times, matching the paper's own "up to four times a year"
  description. This is exactly the repeated-visit-within-a-closed-period
  structure N-mixture models require.
- **Landscape scale (DDA territories, `Reviere`): NOT feasible with data on
  hand.** Checked `BirdStats_Visits2005-2024D.xlsx` directly -- it contains
  only `Nummer`, `Jahr`, `Countdate`, `ROUTENCODE`: one row per route per year,
  with suspiciously uniform `Countdate` values (e.g. "2005-01-01") suggesting
  this is a "route was surveyed this year" administrative flag, not real
  visit-level dates. The repeated within-season visits that go into DDA's own
  internal territory-mapping methodology are not exposed in the data supplied
  to this project -- only the final derived `Reviere` estimate is.

**Implication:** N-mixture modeling could realistically upgrade the
habitat-scale single-scale SDM to a detection-corrected abundance model, but
landscape scale would still need to fall back to the hurdle approach above (or
stay presence/absence) since the raw data doesn't support anything more.
Mixing model classes across scales like this is fine for the *meta-model*
layer (it only needs each scale's *output* to be on a common currency, however
that output was derived) but is a real asymmetry worth deciding on
deliberately rather than discovering midway through implementation.

**Tooling:** `unmarked` or `ubms` (Bayesian) R packages implement N-mixture
models; neither is currently a `dataPrep_Monitor`/`models_Monitor` dependency.

## 2. Separate `data/` (raw inputs) from `outputs/` (pipeline outputs)

**Current state (as of the 2026-08-30 weekend run):** everything -- raw
survey data (EBBA2, MhB, DDA files), downloaded raw tiles (DEM/landuse/
landcover), processed intermediates, and final model outputs -- lives under
one `outputs/test1/` tree, because `outputPath(sim)` was used project-wide
after the earlier `dataPath(sim)`-vs-`outputPath(sim)` fix this session (see
`reference_spades_ai_module_guidelines` memory). That fix was correct as far
as it went (`dataPath(sim)` is per-module-namespaced in SpaDES.core, wrong for
anything shared across modules or across runs), but it left raw, irreplaceable
input data sitting inside a tree that's conceptually "disposable pipeline
output" -- a `outputs/test1` cleanup or a fresh `runName` would put those
files at risk for no reason.

**Target architecture:** a project-root `data/` folder (gitignored) holds
*all* inputs -- both raw survey data supplied by the user and raw
downloaded/cached tiles that shouldn't be re-fetched needlessly. `outputs/`
holds *only* pipeline outputs -- processed rasters, occurrence tables, model
objects, predictions. Conceptually `dataPath` = the `data` folder, `outputPath`
= the `outputs` folder.

**Why this is deferred, not done now:** this touches path-resolution logic
across all three modules (every `dataPath(sim)`/`outputPath(sim)` call site,
every module's default subpath parameters, `runMe.R`'s shared path variables)
in a pipeline that is mid-run and has already been broken once this weekend by
a change that looked safe in isolation. Do this once the current run's models
have finished and been validated, on its own branch, with tests -- per the
process note at the top of this file.

## 3. RAM-aware parallelization of per-species model fitting/prediction

**The problem this addresses:** `models_Monitor` currently loops over species
strictly sequentially, one at a time, within each scale. Observed peak RAM
during the live 2026-08-30 run was ~11-14GB against 64GB available -- meaning
roughly 50GB sits idle the entire time a species is being fit and predicted.
Since species are independent (each species's model fit/predict doesn't read
or write anything another species touches), this is an easy target for
data-parallelism: fit/predict multiple species concurrently, bounded by how
many "species-sized" memory budgets actually fit in available RAM.

**The idea:** rather than hardcoding a worker count, compute it from actual
resources at run time:

- Query available system RAM (e.g. `memuse::Sys.meminfo()`, which is
  cross-platform -- works the same on the current Windows machine and on
  EVE's Linux nodes later) or accept a user-supplied override (a
  `ramBudgetGB`-style parameter) for cases where auto-detection isn't
  reliable or the user wants to reserve headroom for other work on the same
  machine.
- Also query available CPU cores (`parallel::detectCores()` /
  `parallelly::availableCores()`).
- `nWorkers = min(floor(availableRAM_GB / ramPerSpeciesGB), availableCores)`
  -- bounded by whichever resource is more restrictive. `ramPerSpeciesGB`
  itself should default to the empirically observed peak (~11-14GB, with
  margin) and be overridable, since it likely varies by scale (habitat vs.
  landscape vs. europe) and possibly by species (data volume differs).
- Dispatch species across workers via `future.apply`/`furrr`
  (`future::plan(multisession, workers = nWorkers)`), or an EVE-appropriate
  equivalent (SLURM array jobs, batchtools) when this is eventually ported
  there -- same sizing logic, just fed `Sys.getenv("SLURM_MEM_PER_NODE")`
  instead of local OS memory.

**A real gotcha worth designing around up front:** nested parallelism. Some
algorithms already used here (e.g. `ranger` for RF, GDAL raster ops under the
hood) can spawn their own internal threads. If each of 4 concurrent
species-workers *also* internally multithreads across all available cores,
you get 4x oversubscription and contention instead of a speedup. Any
implementation needs to force single-threaded execution *within* each
species-worker (e.g. `ranger(num.threads = 1)`, `GDAL_NUM_THREADS=1`) and let
the outer species-level parallelism be the only layer of concurrency.

**Must degrade gracefully on modest hardware (the personal-laptop case):**
this won't only run on a 64GB workstation -- development/testing (e.g. running
a small species/year subset to check a change works) will often happen on an
ordinary personal laptop with 8-16GB total RAM, likely with other things
(IDE, browser) already using a chunk of it. The design needs two guardrails
from the start, not as an afterthought:

- **A hard floor of `nWorkers = 1`, always.** If `availableRAM_GB <
  ramPerSpeciesGB` (a real possibility on a modest laptop against an
  ~11-14GB-per-species budget), fall back to today's sequential loop with a
  clear message -- never error out, and never force a worker to spawn anyway
  just because the arithmetic said so. The sequential path must stay the
  *exact* same code path as today, not a separate "nWorkers == 1" special case
  that ends up less tested than the parallel one.
- **Budget off free RAM minus a safety margin, not off total/available RAM.**
  A personal laptop running this is likely being used interactively at the
  same time; a workstation or cluster node usually isn't. Reserve a
  configurable chunk (a fixed GB amount, or a percentage) before computing
  `nWorkers`, so the default behavior doesn't leave the machine unusable for
  anything else while a test run is going. This reserve should have a
  sensible default but be tunable, since "sensible" differs a lot between a
  laptop and a dedicated machine.

Because per-species RAM footprint likely differs by scale (200m habitat vs.
1km landscape vs. 50km climate), `ramPerSpeciesGB` should probably default
per-scale rather than as one flat number across all three -- and default on
the conservative/pessimistic side, since running slower is a much better
failure mode than a laptop swapping/thrashing on slower storage than a
workstation would.

**Relationship to the EVE cluster item:** complementary, not redundant --
this is worth doing locally now (real, immediate 64GB-sitting-mostly-idle
waste), and the same worker-sizing approach becomes the natural building
block for the EVE migration later, just re-pointed at a cluster memory
allocation instead of local `Sys.meminfo()`.

## 4. Per-species scale sizing (habitat/landscape/climate resolution)

**Status update 2026-09-28 (see `DECISIONS.md`'s "Simplify to CSV-driven
config" entry for the full write-up):** the "pass a per-species resolution
config" design requested below is now fully implemented.
`speciesConfig_general.csv`'s `resolution_m` column is consumed end to
end: `dataPrep_Monitor` generates each scale's distinct resolutions
exactly once (the "cost implication" paragraph below is handled -- a
resolution shared by multiple species is computed once, not once per
species) and re-keys occurrence extraction by each species' own resolved
resolution; `inputs_Monitor` groups spatial blocking the same way;
`models_Monitor` reads/writes each species' own `scale_X` folder for
models and predictions. The `Cache()` migration this section anticipated
("this is exactly the moment to bring in `reproducible::Cache()`") is also
done, generically, across all 3 modules (see the 2026-09-28 cache entry in
`DECISIONS.md`). Remaining: the literature-informed/data-driven-grid-search
resolution VALUES themselves (the table below) haven't been applied to any
species yet -- `resolution_m` is still every species' current shared
default in the CSV today; this section's mechanism is ready, the actual
per-species numbers are the next step.

**Confirmed not a birdMonitor bug -- this is a real, independently reproduced
scientific finding.** Lisa Hildebrand's own notes ("Notes & decisions on 1st
round of models.md", non-SpaDES BRT-only run on her own machine) show
essentially the *same* four species struggling at landscape scale, with
near-identical numbers to this weekend's SpaDES run -- e.g. her
`Lanius collurio` landscape AUC = 0.674 vs. this run's 0.683. Two independent
implementations landing on the same weak species is strong evidence the issue
is scientific/methodological, not a porting error. Lisa's own notes
independently raised the same hypotheses discussed here before this document
existed: *"M. milvus: has a restricted range; is a bird of prey that is
far-ranging and therefore perhaps landscape features at 1x1 km are too
fine-scale already... B. buteo: very ubiquitous and a generalist -- perhaps
habitat preferences not distinct enough... S. vulgaris: also here I'm a bit
surprised."*

**The hypothesis, now with real literature backing (not just plausibility):**
a fixed landscape-scale window (1x1km for every species, following
Wiedenroth et al.'s two-species case study) doesn't match every species'
actual home range. Territory-size literature review (`Territory sizes of 13
MVP farmland bird species.csv`) gives approximate radii for most of
birdMonitor's 11 species:

| Species | Approx. home range / territory radius | vs. 1km landscape scale |
|---|---|---|
| Emberiza citrinella | ~63m | far smaller |
| Lanius collurio | ~122m | far smaller |
| Saxicola rubetra | ~120m | far smaller |
| Alauda arvensis | ~120-180m | far smaller |
| Lullula arborea | ~158-221m | far smaller |
| Emberiza calandra | ~158-273m (200-400m foraging) | smaller |
| Perdix perdix | ~195-347m | smaller |
| Sturnus vulgaris | ~663m | somewhat smaller, same order |
| Buteo buteo | ~0.8-1.6km (my own radius conversion from the cited 2.1-8.3 km² kernel areas; not in the source table directly) | close to 1km |
| Milvus milvus | ~4.4-6.0km (same caveat -- converted from 60.7-114.5 km² territories) | far larger |
| Vanellus vanellus | **no data found** ("Coming up empty...?" -- literature search came up empty) |  |

This sharpens, rather than just confirms, the hypothesis: **Milvus milvus and
Lanius collurio sit at opposite extremes**, 1-2 orders of magnitude away from
the fixed 1km window in opposite directions -- exactly the two species where
pure scale mismatch is the cleanest explanation. **Buteo buteo and Sturnus
vulgaris's actual home ranges are much closer to 1km already** -- for these
two, Lisa's alternative hypothesis (ecological generalism making habitat
preference hard to discriminate regardless of scale) is likely doing more of
the work than scale mismatch. Don't expect per-species scale tuning to fix all
four species equally; it's a strong candidate fix for two of them specifically.
**Vanellus vanellus has no home-range literature at all** -- would need a
data-driven approach (see below), not literature lookup, before it could get a
custom scale.

**Methodological precedent for why this matters beyond CV metrics:** Lipsey et
al. (2017, in the meso-scale importance lit review) found that single/fixed-
scale models can predict species present in large areas where they don't
actually occur, while a properly-scaled hierarchical approach matched
independent survey data far better (96% vs. 84% overlap) -- *despite almost
no difference in AUC (0.77 vs 0.78)*. Their argument: AUC rewards aggregate
discrimination but doesn't penalize spatial incorrectness. This means fixing
scale mismatch might not show up cleanly as an AUC/TSS improvement in our own
metrics either -- worth adding a spatial-overlap-style diagnostic (e.g.
against a held-out independent subset of occurrence points) when evaluating
whether new per-species scales actually help, not just AUC/TSS/D2 alone.

**Also worth noting:** the confidential Wiedenroth et al. (in prep) manuscript
Lisa was given access to (same broader project, different farmland-bird case
studies) shows landscape-context variable importance ranging from 12.6%
(whinchat) to 41% (yellowhammer) across nine species -- independent
confirmation that scale importance genuinely varies a lot by species even
within this same project family, not just an artifact of these particular 11
species or this particular pipeline.

**Design requested:** pass a per-species resolution config -- a list of
species names, each with its own habitat/landscape/climate resolution --
rather than the current global `habitatResolutionM`/`landscapeResolutionM`
parameters shared by all species. Two ways to source the actual numbers, not
mutually exclusive:
1. **Literature-informed**, per species, from the table above where data
   exists.
2. **Data-driven grid search** for species without good literature (Vanellus
   vanellus) or as a validation check on the literature-informed values: test
   a small set of candidate window sizes per species, pick by CV performance.
   Needs *nested* CV (an inner loop picks the scale, an outer loop reports
   honest performance) to avoid the optimistic bias of picking a "hyperparameter"
   against the same folds used to report performance.

**This is exactly the moment to bring in `reproducible::Cache()`.** Once
resolution varies per species, the current cache-hit convention
(`isValidRasterFile()`/`isValidRDSFile()` checking whether an output file
exists, with resolution baked into a fixed output directory structure, not the
filename or a cache key) stops being safe -- two species at two different
landscape resolutions must never silently read or overwrite each other's
covariate rasters. `Cache()` hashes actual function arguments (including
resolution) into the cache key automatically, which is the robust way to
avoid that collision rather than hand-rolling resolution-aware filenames
everywhere. This was already discussed and deferred pending this exact kind
of trigger -- see the "silently wrong" caching discussion earlier this
session; the installed `reproducible` version (3.2.1.9001) already includes
the digest-correctness fixes (`digestVersion 4`) that were the historical
concern.

**Cost implication (same caveat as the abundance-modeling items):**
covariates currently get computed *once* per resolution, shared across all 11
species. Per-species resolution means re-deriving covariates per species per
resolution -- multiplying the raster-processing burden this weekend's run
just finished. Proper `Cache()` use mitigates this by reusing any covariate
computation two species happen to share (e.g. if both end up needing 1km
after all), rather than blindly recomputing per species regardless of overlap.

## 5. Test excluding hedges as a covariate

**Status 4 November 2026 (the backfill described below is no longer used):** since 3 November the hedge layer is ONE fixed layer in every land-use file (the mean of the layers of the years with CTM hedge data, 2017-2021 and 2024-2025; `completeHedges(mode = "mean")`, DECISIONS.md 2026-11-03), so hedges carry no time signal and the "temporally constant" worry below is now by design. The test asked for here (hedges against no hedges) was run on the DDA data with a GLM: no benefit for Motacilla flava and Streptopelia turtur (hedges and heterogeneity removed for them), a dAIC of +2.0 and +1.2 for hedges in Passer montanus and Falco tinnunculus (no benefit; heterogeneity helps both, dAIC -44.6 and -28.3), which keep hedges for now (audit table S2-58, S2-66; outputs/v2/diagnostics/hedges_vs_heterogeneity_glm.csv). The text below is the original description, kept for history.

**The problem:** Lisa's notes flag this as a "MAJOR DISCUSSION POINT" already:
`hedges` data only genuinely exists for 2017-2022 and 2024-2025 in the Thünen
dataset. All other years are backfilled with a flat value from a reference
year rather than real temporal data --
`occurrencePrepGerHabitat.R`/`computeLanduse.R`'s current logic (`refYear <-
if (yr <= 2016) 2017L else if (yr %in% c(2022, 2023)) 2021L`) faithfully
reproduces the exact same backfilling approach Lisa's original notes describe.
This means `hedges` is treated as temporally constant across many years where
it almost certainly isn't, in reality -- a real source of noise or
artificial signal in a covariate the paper (and Lisa's notes) both flag as
ecologically important for farmland birds specifically.

**The test:** re-run models with `hedges` excluded entirely from the predictor
set, compare performance (AUC/TSS/D2) against the current with-hedges runs.
If performance is similar or better without it, that's evidence the backfilled
`hedges` covariate is contributing noise rather than signal, and it should
either be dropped or given a real temporal treatment (e.g., only used for the
years where genuine data exists, gappy elsewhere, rather than backfilled) as a
separate follow-up decision.

## 6. Generalize the study-area crop/mask beyond "Germany"

**DONE 2026-10-21 (phase 1):** one study-area definition (`sharedStudyArea`, `BIRDMONITOR_STUDY_AREA`) drives layers, records, models and index; see DECISIONS.md 2026-10-21. Open: crop at download time, explicit climate fit-area setting, water mask (version 2).

**Current state:** the post-hoc masking tool (`tools/maskToGermany.R`) and the
planned source-level fix (cropping the working extent in `dataPrep_Monitor`
before any calculation starts, using a `rasterToMatch`/`studyArea` pattern --
see the EVE-cluster-parallelization project discussion) are both hardcoded to
Germany's national boundary.

**Why this needs to be flexible, not hardcoded:** two real future needs
already identified: (1) running the same pipeline for other European
countries, which needs a different national boundary and a different
full-Europe-bbox-relative crop; (2) cropping to sub-national regions
*within* Germany (individual Bundesländer or smaller), for regional analyses
that don't need the full national extent. Both need the same crop/mask
mechanism, just pointed at a different boundary vector -- design the
`studyArea` input as a parameter (a boundary file path, or a GADM
country+level+region specification), not a hardcoded "Germany" assumption,
so the same code serves all three cases (full Germany, another country, a
sub-national region) without duplication.

## 7. Alternative model families (GLM/RF/NN) alongside BRT, per Wiedenroth (Levin) et al.'s meta-model paper

**Status: explicitly deferred (2026-09-25) -- scope only, no implementation yet.**
Approved for a later, separate branch once items 1-6 above (and the current
run) are settled: *"Correct. New branch for these... But we will work on it
later."*

**The problem this addresses:** every scale (`modelEurope`/`modelGerHabitat`/
`modelGerLandscape`) currently fits exactly one algorithm, BRT
(`optimizeBRT()` / `dismo::gbm.step()`), hardcoded as the only option. There's
no way to compare BRT against another algorithm, or to combine several, without
duplicating an entire `modelX()` function per algorithm.

**What the source paper (Levin Wiedenroth et al., "A meta-model approach for
multi-scale species distribution models", preprint DOI
10.3897/arphapreprints.e205471) actually does -- read in full 2026-09-25, this
is NOT just "swap in a different algorithm":**

1. At **each** single scale (climate/landscape/habitat), they fit **four**
   algorithms independently: GLM, GAM, random forest (RF), and BRT -- then
   average the four predictions (arithmetic mean) into one per-scale
   *ensemble* prediction. Same 5-fold spatial block CV as we already use.
2. They then combine the **three scales'** ensemble predictions into a
   cross-scale **meta-model** via *stacked generalization* (Wolpert 1992): a
   ridge-regression meta-learner (logistic, L2-penalized) trained on the three
   scales' downscaled predictions as its only inputs, at 200x200m resolution.
   Scale importance = reduction in explained deviance when that scale's
   prediction is excluded from the meta-model.
3. The paper explicitly notes the two-step structure (ensemble algorithms per
   scale, *then* ensemble scales) is a deliberate choice for interpretability,
   not the only option -- "the ensembling of algorithms and scales could also
   happen simultaneously within the meta-model" (their own discussion).

**What was actually requested here, which is narrower than the full paper:**
"we need to add the implementation of the other models as well (glm, RF, NN as
per Levin)... one model per function and we will need to make sure we can loop
through all models (which should be defined as a parameter of which models to
run)... I also want to add a NN in there!" -- i.e., **item (1) above** (algorithm
diversity *within* a scale), refactored so each algorithm lives in its own
function (`fitGLM()`/`fitRF()`/`fitBRT()`/`fitNN()`, mirroring `optimizeBRT()`'s
existing shape) and a `modelsToRun` parameter loops through whichever subset is
requested per scale, rather than the current single hardcoded call to
`optimizeBRT()`. NN is an addition beyond Levin's own four algorithms, not
covered by the paper -- needs its own design (framework/architecture choice;
`nnet`/`keras`/`torch` all plausible, unevaluated as of this writing).

**What was NOT explicitly requested, flagged here for a separate decision
later:** **item (2) above**, the cross-scale ridge-regression meta-model /
stacked generalization step. This is the paper's actual headline contribution,
and it's architecturally bigger than swapping in new algorithms -- it changes
how the three scales' predictions get combined into a final prediction, which
today happens via the completely different multi-species/geometric-mean index
logic (`computeCombinedIndex()`/`computeGriddedCombinedIndex()`). Worth
discussing explicitly once the per-scale algorithm-diversity piece exists,
rather than assuming it's wanted just because it's in the source paper.

**Design notes for the eventual branch:**
- One function per algorithm (`fitGLM.R`, `fitGAM.R`, `fitRF.R`, `fitBRT.R`
  wrapping the existing `optimizeBRT()`, `fitNN.R`), each returning a common
  shape so `blockCVPredictBRT()`/`evalSDM()`-equivalent evaluation code can
  stay algorithm-agnostic rather than special-casing each one.
- A `modelsToRun` parameter (character vector, e.g. `c("glm", "rf", "brt")`)
  per scale, defaulting to `"brt"` alone so existing runs/behavior are
  unaffected until this is deliberately turned on.
- Needs its own `Cache()`/output-file-naming scheme once more than one
  algorithm can produce a model for the same species+scale (today's
  `<species>_BRT_habitat.rds`-style naming assumes exactly one algorithm).

## 8. Move the multi-species index/report into its own module

**Status: DONE, 2026-09-28** -- see `DECISIONS.md`'s 2026-09-28
"runIndex_Monitor" entry for the full write-up (function boundary moved,
chained into `runMe.R`'s own `loadOrder`, cluster-mode polling, the
init-time year-sufficiency check, and two real terra bugs found and fixed
along the way). Kept below for history/context only.

**The problem this addresses:** `runIndex.R` (repo root) is a standalone
script, not a SpaDES module. It manually re-sources every file in
`modules/models_Monitor/R/` just to get access to `computeAnnualReport()`/
`computeRegionalIndex()` and their dependencies -- functions that already
live in a module's `R/` folder but were never wrapped in their own
`defineModule()`. That means no parameter validation, no self-documentation
(`?indexReport_Monitor`-style), no participation in SpaDES's own
caching/output-path conventions, and no natural place in `runMe.R`'s
`modules =` list alongside `dataPrep_Monitor`/`inputs_Monitor`/`models_Monitor`
-- it has to be run as a completely separate, manually-invoked step instead
of a 4th pipeline stage.

**The idea:** a 4th module (e.g. `indexReport_Monitor`) wrapping
`computeAnnualReport()`/`computeRegionalIndex()` with proper
`defineParameter()`s (`species`, `baselineYear`, `currentYear`, `allYears`,
`restrictedYears`, `cellSizesM`, etc.), consuming `models_Monitor`'s
`metaModel()` output the same way `models_Monitor` consumes
`inputs_Monitor`'s output -- scheduled as a real step in `runMe.R`'s own
`modules=`/`loadOrder`, not a separate script run by hand afterward.

**Why not now:** the standalone-script approach needs to actually work
first. Once `runIndex.R` has been run for real (this weekend's 4-species
test) and its output format/edge cases are known to be right, wrapping it
as a proper module is a much lower-risk refactor than doing both at once.

## 9. Programmatic EBBA2 download/refresh mechanism

**The problem this addresses:** unlike DEM/landcover/landuse (each with a
Python download script under `modules/dataPrep_Monitor/python/`), EBBA2
occurrence data (`ebba2_data_occurrence_50km.csv`) is a manually-supplied
static file with no download mechanism at all -- the same manual-supply
status as DDA territories data. Confirmed directly (2026-09-26): the file on
disk is dated 2026-07-17, more than two months before Anthus pratensis was
added to the species roster (2026-09-24), so it simply doesn't contain that
species at all -- not a code bug, but a stale input that will recur for
every future species addition unless this becomes a repeatable, trackable
process instead of "whoever has EBBA2 access re-exports it by hand."

**Why this is NOT the same situation as DDA:** DDA has no public data
source at all -- it's proprietary to DDA, genuinely manual-only forever.
EBBA2 has one real public access option: free, open-access 50km occurrence
data directly from [ebba2.info/data-request](https://ebba2.info/data-request/)
(per EBCC's own data-access policy -- some data is open, some requires
request approval). This is a request/approval process, not confirmed to be
a scriptable API -- "programmatic" here likely means "a repeatable request
process we do deliberately," not "a script that just runs."

**GBIF is a dead end for this, checked directly and ruled out (2026-09-26):**
the GBIF dataset that looks like an EBBA match
([c779b049-...](https://www.gbif.org/dataset/c779b049-28f3-4daf-bbf4-0a40830819b6))
is actually **EBBA1**, the original 1997 atlas (fieldwork 1972-1995) -- a
completely different, ~30-years-older survey, not a mirror or different
format of EBBA2. Confirmed further via the EBCC's own GBIF organization
record: `numPublishedDatasets: 1` -- they have published exactly one
dataset to GBIF, and it's that same 1997 atlas. **EBBA2 itself is not on
GBIF at all.** Do not revisit `rgbif` for this -- there is nothing there to
fetch. ebba2.info's own request portal is the only real path.

**Why not built yet:** even via ebba2.info, this needs scoping (confirm
whether their data-access process can be made a routine, repeatable
request rather than a one-off manual ask; if the returned format needs any
reprocessing to match `ebba2_grid50x50_v1.shp`'s exact grid) before
building anything, same reasoning as every other item in this file.
Meanwhile: Anthus pratensis's missing climate-scale data is a low-cost gap
for any given run in practice -- climate contributes 0-1.1% to every
species' meta-model regardless (see the model-results memory/DECISIONS.md),
so this does not block running the pipeline while unresolved.

## 10. Reviewer defense for the asymmetric multi-scale training-window design

**Status: queued, deliberately deferred (2026-09-29) -- "will happen later
on."** Not started. See `DECISIONS.md`'s 2026-09-28 "Each scale's fitting-
year window is dictated by its own survey, not shared" entry for the full
context this responds to.

Two committed follow-ups, both still to do:
1. **Temporal holdout validation** -- refit habitat's BRT on 2022-2024
   only, validate against the held-out 2025 it never saw, to empirically
   test one-year-forward extrapolation reliability. Real code + a results
   write-up, not just a caveat.
2. **Literature grounding** -- pull 2-3 precedents from the multi-scale/
   stacked-SDM line this project already draws from (Wiedenroth et al.)
   showing asymmetric training windows across component models is
   accepted practice.

## 11. MetaModel flexible to a variable scale count (`metaModelScales`)

**Status: queued, deliberately deferred (2026-09-29).** Raised alongside the
new `scalesToRun` module parameter (see `DECISIONS.md`'s 2026-09-29 entry),
which controls which of the 4 stages get *fitted/attempted* per species.
This item is different and bigger: making the **meta-model itself** flexible
to running the ridge regression on a *subset* of already-fitted scales'
suitability, so e.g. "with climate niche" vs. "without climate niche" could
be compared *after the fact*, for species where all 3 scales did get fitted.

**Why this is a real, moderate-to-substantial refactor, confirmed by reading
the code (not assumed):** `extractSuitability.R`, `loadSuitability.R`, and
`getOrBuildSuitX.R` all hardcode exactly climate/landscape/habitat as the
three suitability inputs. `computeVariableImportance.R`'s output has fixed
field names (`imp_climate`/`imp_landscape`/`imp_habitat`) that downstream
reporting presumably reads by name. `metaModel.R` itself has a hardcoded
3-way coefficient-printing message. None of this is a quick parameter add --
every one of those functions would need to accept and thread through a
variable-length scale set instead of three fixed named slots.

**Confirmed NOT needed for the "just skip meta for an unfitted scale" case**
(the thing `scalesToRun` actually needed): `metaModel()`'s own per-species
loop already degrades gracefully today -- `extractSuitability()` ->
`loadSuitability()` returns `NULL` per-scale if that species/scale's
prediction file is missing, `metaModel.R` (lines ~81-86) filters those out,
and if nothing remains it `warning()`s and skips that species entirely, no
crash. That existing behavior is sufficient for `scalesToRun` excluding a
scale entirely. This item is only about deliberately *comparing* "with" vs.
"without" a scale for the *same* species where all scales exist -- a genuine
ablation-style feature, not a robustness fix.

**Companion parameter, also deferred:** `metaModelScales` -- a per-species
override of which already-fitted scales' suitability actually feeds the
ridge regression (defaulting to "whatever was fit"), which is what would
make the "with/without climate niche" comparison possible without refitting
anything.

## 12. Rename `modelEurope`/its event name to `modelClimate`

**Status: queued, deliberately deferred (2026-09-29).** `resolutionConfig`
and the new `scalesToRun` parameter (see `DECISIONS.md`'s 2026-09-29 entry)
both use `"climate"` as the scale-name vocabulary, matching
`modelGerHabitat`/`modelGerLandscape`'s own `"habitat"`/`"landscape"`
naming -- only `modelEurope` doesn't say `"climate"`, a naming mismatch
that's been carried since the module's original port.

**Why deferred:** a real rename, not just a comment fix -- touches the
event name itself in `models_Monitor.R`'s `doEvent` switch,
`tools/runClusterTask.R`'s `--scale europe` -> event-name mapping, the
cluster `.sbatch` templates (`eve_array_*.sbatch`), and the
`sim$europeModels` output object name. Mechanical but multi-file and
higher blast-radius than anything needed for the near-term tests -- do
this on its own branch with its own verification pass, per this file's
process note.

## 13. Replace the ridge-regression meta-model with Talluto et al. (2016)'s hierarchical Bayesian metamodeling framework

**Status: queued, not started (2026-09-30).**

**The idea, as described:** Talluto et al.'s "metamodel" framework
statistically combines several different, already-existing models --
e.g. a fine-scale demographic/dispersal model and a coarse-scale
climate-envelope model -- into one integrated prediction via
hierarchical Bayesian methods, with uncertainty propagating through
every component model rather than being estimated only at the final
combination step.

**Citation:** Talluto MV, Boulangeat I, Ameztegui A, Aubin I, Berteaux
D, Butler A, Doyon F, Drever CR, Fortin M-J, Franceschini T, Liénard J,
McKenney D, Solarik KA, Strigul N, Thuiller W, Gravel D. 2016.
Cross-scale integration of knowledge for predicting species ranges: a
metamodeling framework. *Global Ecology and Biogeography* 25:338-349.

**Why this is directly relevant here:** this pipeline's own
`metaModel()` (`models_Monitor`) already does the SAME conceptual job
Talluto et al.'s framework targets -- combining multiple already-fitted,
independent scale-level models (climate/landscape/habitat) into one
final prediction -- but via a much simpler mechanism: a ridge (L2-
penalized) logistic regression on the three scales' point suitability
predictions, with no explicit uncertainty propagation from the
component models into the combined result (the combined model's own
AUC/TSS/D2 reflect the RIDGE step's own block-CV performance, not
uncertainty carried forward from each scale's own fit). Swapping in a
hierarchical Bayesian metamodeling framework would be a genuine
architectural change to how "combine climate + landscape + habitat"
works, not a parameter tweak -- worth comparing directly against the
current ridge approach, and against the source paper's (Wiedenroth et
al.) own approach, once ready to invest in it.

**Not scoped or designed yet** -- needs its own read of the source paper
in full (this entry is based on the framing given when the improvement
was requested, not yet independently verified against the paper itself),
and a concrete plan for what changes in `metaModel.R` (or whether it
becomes a new, alternative meta-model function altogether, selectable
alongside the existing ridge approach) before any implementation starts.

## 14. Exact-resolution covariate layers: aggregate straight to the target cell size

**Raised 2026-10-03 (while debugging the first EVE run); to think about, not decided.**

**What the pipeline does today** (every covariate: DEM elevation/slope, landuse and
landcover proportions, dist_to_woodland), in `aggregateAndSave()`,
`makeCategoryProportionLayer()` and `computeDistToWoodland()`:

1. `terra::aggregate(x, fact = round(targetRes / nativeRes), fun = "mean")` -- a real block
   mean, but only to an INTEGER multiple of the native cell size (30 m x 23 = 690 m, not
   700 m; 30 m x 7 = 210 m, not 200 m; 30 m x 167 = 5010 m, not 5000 m).
2. A second step interpolates that grid onto the exact target size (bilinear). Until
   2026-10-03 this was `terra::project()`; it is now `regridToResolution()` (a `resample()`
   onto a template grid -- EVE's older GDAL/PROJ reject `project()`'s area-of-use check
   for large LAEA rasters; output verified identical to the old call).

**The methodological issue (independent of the EVE fix).** The mean is taken over blocks
of the "wrong" size, and the bilinear step then smooths between neighbouring blocks. The
effective cell value is therefore a slightly blurred mean over an area a few percent
larger or smaller than the nominal cell: ~1.4 % in linear size at 700 m (690 -> 700),
5 % at 200 m (210 -> 200), 0.2 % at 5 km. Small for smooth layers (elevation), possibly
more noticeable for sparse categorical proportions (e.g. `hops`, `grapevine`) and for
slope, whose value depends on the averaging window.

**Option A -- aggregate straight to the target grid.** Build the exact target grid and take
the area-weighted mean of the native cells that overlap each target cell, e.g.
`terra::resample(x30m, targetGrid, method = "average")`. Exact cell size, no second
smoothing step. Costs: slower/heavier on the 46 GB 30 m DEM (needs a check on EVE), and --
the real catch -- it would change the layers of EVERY scale already built (200 m, 1 km,
50 km), so models and past results would no longer be comparable without rebuilding and
refitting everything.

**Option B -- keep as is, document it.** Consistent with all existing layers and with the
published multi-scale approach we follow; the effect is small. Record the nominal vs
effective window in the methods.

**Option C -- choose resolutions that are integer multiples of the native cell size**
(e.g. 690 m, 210 m, 5010 m) and skip the second step entirely. Cleanest, but resolutions
no longer match the literature values we picked (700 m, 5 km, 200 m).

**To decide / check before changing anything:**
- Measure the actual difference between the current layers and Option A on 1-2 test scales
  (correlation and mean absolute difference per layer), before deciding if it matters.
- If it matters for any scale: rebuild all scales with the chosen option and refit; do not
  mix methods across scales.
- Related: `dist_to_woodland` is a distance (not a proportion) -- a mean of distances over
  690 m blocks and then bilinear is also fine, but note it is computed on the 100 m CORINE
  grid, so its native-to-target factors differ (fact = 7 for 700 m).

**Where:** `modules/dataPrep_Monitor/R/regridToResolution.R` (the single place to change the
second step), `aggregateAndSave.R`, `makeCategoryProportionLayer.R`,
`computeDistToWoodland.R`.

## 15. Model uncertainty: confidence layers for maps and per-pixel trends (bootstrap of the BRTs)

**Decided 2026-10-05; BUILT 2026-10-06 as a separate workflow -- see `modules/models_Monitor/UNCERTAINTY.md` and DECISIONS.md (2026-10-06); not yet run on EVE, timings below are still estimates.** Before it, the pipeline had NO uncertainty on the BRT predictions:
`blockCVPredictBRT()` keeps only the out-of-fold predictions (the per-fold models are discarded), the final maps come
from one BRT per scale plus one ridge meta-model, `nBootTrend` (ridge-only bootstrap, area-mean trend) is off by default
and `useBootstrapSE` is FALSE. Lisa Hildebrand's options (A fold ensemble, B block bootstrap, C algorithm ensemble,
D ensemble + bootstrap) were checked against the code (see conversation 2026-10-05).

**Chosen: option B (block bootstrap of the BRTs), in the spirit of the Boreal Avian Modelling Project** (bootstrapped
BRTs with the number of trees fixed from cross-validation; percentile intervals) -- cite BAM for the general approach, but
read their methods before claiming equivalence (we resample spatial blocks and add a ridge meta-model).

- **Interval:** 90% (5th and 95th percentiles) for now.
- **Years:** ALL prediction years (2005-2025), not just key years.
- **Outputs per species:** per-year maps of mean / SD / lower / upper percentile; per-pixel change maps (vs baseline,
  vs 5 years ago, vs last year) with their interval; **CI width** and **share of replicates decreasing (or increasing)**
  as the confidence layer; per-replicate area means for annual index CIs.
- **Method:** per replicate and per scale, resample SPATIAL BLOCKS with replacement (blocks from the saved
  `blockCV::cv_spatial()` objects, not the 5 fold ids), refit gbm with the FIXED hyperparameters of the main fit (3-6 s),
  predict all years, apply the ridge meta-model, and compute every derived quantity (changes, trends, area means) INSIDE
  the replicate before taking percentiles -- this is what carries spatial AND temporal uncertainty into per-pixel trends.
- **Cost (single-core, unmeasured on EVE; prediction dominates, not fitting):** habitat 2.2-5.8 core-min per year per model
  (about 8.9M valid cells at 200 m), landscape 9-22 s, climate negligible. All 21 years: B=50 -> 38-100 core-h per
  species (420-1,100 total); B=100 -> 77-216 per species (850-2,400 total). Wall time = core-hours / cores available;
  about 100 cores -> 9-24 h at B=100. Plan: B=50 first, store replicates (int16) so replicates can be ADDED later.
- **Not built / not covered (candidate improvements, to state in the methods):**
  1. **Hyperparameter-tuning uncertainty** -- tuning is done once; bootstrap replicates reuse the settings (as BAM does).
  2. **Covariate error** -- the predictor layers (land use, climate, DEM, ...) are treated as exact.
  3. **Structural / model-form uncertainty** -- one algorithm (BRT) per scale; option C (algorithm ensemble: GLM/RF/NN,
     see item 7) is planned for spring, and option D (ensemble + bootstrap) after that.
  4. Also not covered: bias in the survey data (DDA vs MhB selection), spatial/temporal autocorrelation beyond what block
     resampling captures, and the thinning randomness (`thin()` is unseeded).
- **Option A (fold models, block jackknife):** NOT part of this plan. It is cheap (~5% of B=100) but adds little once B
  exists; its spread across 5 folds underestimates the sampling error (jackknife inflation of the SD by ~1.8, only 4
  degrees of freedom) and the jackknife is unreliable for non-smooth estimators such as trees. Could serve later as an
  independent cross-check.
- **Interval meaning:** percentile intervals of the fitted probability surface (and of derived changes/trends), NOT
  prediction intervals for observed occurrences.

---

## 16. Meta-model trained on in-sample scale predictions (stacking with out-of-fold predictions)

**Noted 2026-10-06 (not changed; the baseline and the uncertainty workflow both follow the current design).** `metaModel()`
fits the ridge regression on the predictions of the three scale BRTs at the SAME habitat records those BRTs were trained on.
A boosted-tree model fits its own training records more closely than new records, so those predictions are optimistic and the
ridge may give the scale that overfits most (probably habitat) more weight than it deserves. The textbook remedy for stacking
(Wolpert 1992; Breiman 1996, "Stacked regressions") is to train the combiner on out-of-fold predictions. The per-fold BRTs are
already saved (`<species>_foldModels_<scale>.rds`), so out-of-fold suitability at the habitat records can be built without
refitting. **Check, don't assume:** compare the ridge coefficients (and block-CV AUC of the final map) with in-sample vs
out-of-fold training; if they barely differ the issue is immaterial and this item can be closed.

**Update 2026-10-06:** the check was run (`tools/runMetaCheck.R`): the pipeline's meta-model AUC (~0.99) was inflated; the honest
number is about that of the habitat BRT alone. Two parts of this item exist:
(a) the REPORTED ACCURACY -- DONE: `metaModel()` now reports the out-of-fold accuracy (`metaHonestEval`, default TRUE), the old
    number stays in `<species>_perf_meta_inSample.rds` (note: the same switch also decides the weights, see (b));
(b) the WEIGHTS (ridge trained on out-of-fold inputs) -- DONE 2026-10-06 as well (baseline and replicates; DECISIONS.md).

---

## 17. Bootstrap replicates with a constant map (Perdix perdix): report a second interval without them

**Noted 2026-10-13 (decision: do it AFTER the Steering Consortium meeting; for now the replicates stay in the interval and the issue is
stated as a caveat in the methods document).** In the BRT-only run (`uncertainty_honest2`, penalty rule = the baseline's, ten random folds,
`lambda.1se`) 9 of the 50 replicates of *Perdix perdix* have an index of exactly 100 in every year (replicates 5, 11, 16, 18, 21, 29, 33, 37,
42): the replicate map is constant, i.e. the meta-model found no usable signal in that resample and the index is fixed at 100 by construction,
not by evidence. Perdix has the largest ridge penalty of all species also in the main model (0.264 against 0.04 to 0.15), so its meta-model is
weak to begin with. The effect on the combined index is small (Perdix is one of 11 species); on the Perdix interval it is large (84.7 to 100.0).
- **What to do:** run `tools/sensitivityConstantReplicates.R` (already written and pushed; read-only; `Rscript tools/sensitivityConstantReplicates.R test4 honest2`).
  It (1) counts, for EVERY species, the replicates whose index is constant over all years (we only know Perdix so far; confirm that it is the
  only species), (2) gives the interval of each affected species with and without them, and (3) gives the combined SBI interval three ways
  (all replicates; constant species-replicate cells dropped; replicates with a constant species dropped). Report this second interval next
  to the main one (sensitivity analysis, not a change of the rule).
- **Also check:** (a) that the all-zero weights are the cause (read the replicate ridge files: `diagnoseReplicateBias.R` prints only the
  share of zero climate weights); (b) the same count for the big 5 run (`... test4 ens_brt-glm-gam-rf-nn`).
- **Not recommended:** choosing `lambda.min` instead of `lambda.1se` in the replicates, because it breaks the principle that a bootstrap
  repeats the main procedure on resampled data (DECISIONS.md, 2026-10-10).

---

## 18. Regional index: floor and cap on extreme ratios (to discuss later, not needed for now)

**Noted 2026-10-13 (decision: not a point for the Steering Consortium now; to be discussed later, possibly with the DDA).** The regional index of
a species in a grid cell is 100 x (cell mean in year t) / (cell mean in the baseline year 2005). Where a species is almost absent in 2005 the ratio
can explode. At the moment a species is left out of a cell only when its baseline cell mean is below `minBaseline` = 1e-6 (set in two places:
`computeGriddedCombinedIndex()` for the baseline and the `minBaseline` argument of the `regionindex` step for the uncertainty run).
- **Check on the current data (2026-10-09, Germany-only maps, 2005 against 2025 only; `tools/floorCounts.R`):** no baseline cell mean is below
  0.001 except 7 cells of Lullula arborea at 10 km; the ratio between 2005 and 2025 exceeds 10 in no species at any grid size; the largest regional
  index value is 122 and no cell lies above 200 or below 50; a floor of 0.01 would remove only 7 species-cells at 10 km and 2 at 20 and 50 km.
  Intermediate years were not counted.
- **Options:** (A) raise the floor (candidates 1e-4, 1e-3, 1e-2); (B) a cap on extreme ratios or a truncation of very small values (Soldaat et al.
  2017 truncate small index values at a small positive value; whether and how the DDA caps ratios was NOT verified); (C) both; (D) keep as is.
- **Recommendation so far:** keep 1e-6 for these results and add a documented truncation of ratios above 10 as an inactive safeguard, so that other
  species or later runs cannot produce explosive cells. If the floor changes it must be changed in both places.

---

## 19. Predict only inside Germany: replace the bounding box by the study-area outline at the source

**DONE 2026-10-21 (for the layers and records):** the processed layers are cropped and masked to the study area plus a buffer, so predictions exist only there; the `_germany` copies cut the buffer to the reporting area (DECISIONS.md 2026-10-21, clean run v1).

**Noted 2026-10-13 (project lead: "we are SUPPOSED to predict only for Germany for now ... we REALLY need to address this"; to be done after the Steering
Consortium meeting; supersedes the interim Germany-only masking).** All predictions are made on a rectangle, the bounding box of Germany, not on Germany.
- **Numbers (job 63182183, year 2025):** the window has 13.9 million pixels of 200 m, 8.97 million inside Germany. Seven species (Alauda, Anthus, Buteo,
  Emberiza calandra, Perdix, Saxicola, Vanellus) have predictions over the whole window (35.4% outside Germany); four (Emberiza citrinella, Lanius,
  Lullula, Sturnus) only inside Germany (0.1% outside), because their models use `hedges` / `landscape_heterogeneity`, which appear to exist for Germany
  only (from the predictor lists; the layers were not opened). So a model predicts only where all of its predictor layers have a value.
- **Consequences:** about a third of the predictions of seven species are outside the study area (wasted compute and storage); the national means averaged
  different areas for different species (area means differed by up to 55%; fixed for now by Germany-only copies, `tools/maskMetaModels.R`,
  `area_mean_replicates_germany.csv`, `maskmaps`); predictions outside Germany are extrapolations of models trained on German records.
- **Origin of the box (project lead, 2026-10-13):** Lisa's code used a bounding box instead of a German shapefile, and it stayed. In the code the 200 m
  reference grid is the solar-radiation raster cropped to the habitat prediction window; the exact place where that window is defined still has to be
  found when this item is done.
- **To do:** (1) find the place in the code where the window is defined and replace it; (2) cut every input to the outline at the source (climate, elevation, land use, land cover, derived layers), through a
  `studyArea` parameter (see item 6); (3) decide the scope of the climate scale, which is trained on EBBA2 data for Europe (cropping its predictions is
  mechanical, cropping its training data is a modelling change); (4) check that `inputs_Monitor`, the band prediction and `runIndex_Monitor` carry no
  bounding-box assumption; (5) recompute baseline, big 5 and uncertainty once; sanity test: the new national means must equal the interim Germany-only
  means to rounding error; (6) build the outline with the closed-form `uncOutlineLAEA()` (two places still project it with terra: `metaModel()` and
  `aggregateSpeciesToGrid()`).

---

## 20. Bootstrap: check how much the intervals depend on the block size, and the other weak points

**Noted 2026-10-13 (project lead: "definitely; we will have to check this afterwards"; after the Steering Consortium meeting).** The uncertainty is a cluster (block)
bootstrap: blocks are drawn with replacement, all records of a drawn block enter (`uncRowIndex()`). It is standard, but it is an approximate interval and its coverage
has never been validated.
- **Check 1, block size:** repeat the intervals (BRT-only, a few species and years are enough) with half and double the block size, with the existing switch
  `BIRDMONITOR_UNC_BLOCKMULT` (0.5, 1, 2) and compare interval widths of the combined index and of a few species indices.
- **Weak points to keep in mind or test:** (a) the climate scale has only about 13 blocks for Europe (capped at 1500 km), too few for a reliable cluster bootstrap;
  (b) the block size comes from the autocorrelation range of the predictors, not of the residuals; (c) blocks are treated as independent although neighbouring blocks are
  correlated, so intervals may be somewhat too narrow; (d) percentile intervals are not bias-corrected (replicate mean 96.1 against main model 95.6 for the combined
  index 2025); (e) model settings are fixed in the replicates, which narrows the interval; (f) inside a replicate the ridge penalty is chosen with ten random folds over
  rows that contain duplicated blocks, so copies of one record can sit on both sides of a split (the out-of-fold step keeps duplicates in the same fold); (g) 50 replicates
  give noisy 5th and 95th percentiles (25 for the big 5); (h) with a weak meta-model some replicates collapse to a constant map (item 17).
- **Optional:** a small simulation (a known truth, repeated sampling) to see whether the nominal 90% interval covers about 90%.

---

## 21. Test the hindcast and the model assumptions

**Noted 2026-10-13 (project lead: "could we test these? if so, how?"; to do after the Steering Consortium meeting).** The intervals do not cover the hindcast
assumption (that each species responded to habitat in 2005-2021 as it does in 2022-2025) or the model assumptions. Some of them can be tested; each test says
what it can and cannot show.
- **T1. Temporal hold-out and leave-one-year-out (cheap, partly in item 10).** Refit the habitat BRT without one habitat year (2022-2024 train, 2025 test; then
  every year in turn) and compare the AUC and the calibration. Shows whether the model transfers between years, a one-year-forward test only, not a test of 2005.
  About 2-3 days.
- **T2. Independent historical data (the strongest test, depends on data).** (a) DDA territory-mapping data exist for 2005-2024 and trained only the landscape
  scale: compare the habitat-based hindcast (2005-2021) with the territory counts or presences per 1 km cell and year (rank correlation, AUC per year, does the
  fit get worse the further back we go?). (b) Compare the national species indices with the published trends of the DDA / PECBMS for 2005-2021 (rank correlation
  of the 11 species trends, sign agreement; Kamp et al. 2021 for the DDA). (c) Compare with the MhB point counts before 2022, with the caveat that these records
  were judged inconsistent. Effort depends on the data; (b) needs only published numbers (1 day).
- **T3. Extrapolation per year (cheap).** Share of pixels in each hindcast year whose covariates lie outside the range of the 2022-2025 training data (MESS or
  similar; `tools/diagnoseYearJump.R` already reports a share of cells outside the training range per top predictor). If the share is small the hindcast is an
  interpolation in covariate space. About 1 day.
- **T4. What drives the trend (cheap).** Counterfactual maps: predict 2025 with the landscape covariates of 2005 (or with the climate of 2005) to split the
  trend into the part due to land use, land cover and climate. Shows whether the "decline" is a landscape change under fixed preferences, which is exactly what
  the hindcast statement says. About 2 days.
- **T5. Simulation with virtual species (tests the machinery and the interval, not the real birds).** Generate species with a known habitat response on the real
  covariate layers (2005-2025), a known true trend, and sample them like the survey data; run the whole chain and see (i) whether the true trend is recovered and
  (ii) whether the 90% interval covers the truth in about 90% of the cases (the coverage test of item 20). With a drift in the habitat preference after 2021 it
  also quantifies the bias that the hindcast assumption can cause. Weeks of work, the most informative test of the method.
- **T6. Calibration.** Reliability plots of the out-of-fold probabilities per species (do 0.3 predictions occur about 30% of the time?). Indices are ratios of mean
  probabilities, so a stable calibration matters more than the AUC. About 1 day from the saved out-of-fold files.
- **Not testable with the present data:** whether habitat preferences really did not change before 2022; only T2 can speak to it.

## 22. Independent check of every reported number

**Noted 2026-10-13 (project lead: yes, add it).** Three levels. (1) Document against source: done on 13 October by hand for the species and combined-index tables of
the executive summary (12 rows, no mismatch); still to do for the main-model column, the AUC and weight tables of the handover (sections 7.5 and 7.8) and the
statements that all checks pass. (2) Internal consistency: the MSI combined index equals the geometric mean of the 11 species means in both runs (93.621222 and
96.218287); baseline 2005 = 100; lower <= mean <= upper; 50 and 25 replicates. (3) Independent recomputation from the maps: `tools/checkReportedNumbers.R` (read-only):
maps -> area means -> species index -> combined index -> interval from the replicates, for two species and three years by default, for the BRT-only run and the big 5.
- **Run:** `bash --login -c 'module load GCC/13.3.0 OpenMPI/5.0.5 R/4.5.1 GDAL/3.10.3 CMake ImageMagick/7.1.1-38 UDUNITS/2.2.28 && Rscript tools/checkReportedNumbers.R test4 honest2'`
  and the same with `ens_brt-glm-gam-rf-nn`; add more species or years as arguments.
- **Result so far (13 October):** BRT-only run, Alauda arvensis and Saxicola rubetra, 2005, 2015 and 2025: 18 of 18 comparisons OK (maps -> area means -> species index -> combined index 95.575 -> interval over 50 replicates 94.04 to 98.17). Still to do: the big 5 run, and the other nine species.
- **Limit:** these checks show that the arithmetic and the transfer of the numbers are right; they do not show that the model is right (item 21).

## 23. DDA `Reviere` = -1 is treated as an absence in the occurrence tables (should be a presence)

**Noted 2026-10-13 (project lead: yes, add it; found while preparing the PreVal bird data).** The DDA/MhB documentation (Confluence) says: `Reviere` = 0 is set by hand when
a bird was seen outside the plot (it must not count as a territory); `Reviere` = -1 means the observer could not give an exact count, so no territory count exists, it drops out of
the official MhB statistics, but in practice it is a PRESENCE (it cannot be used as a density).
- **Where:** `modules/dataPrep_Monitor/R/occurrencePrepGerLandscape.R`, the presence/absence matrix (`Reviere` NA replaced by 0, then `occurrence = as.integer(Reviere > 0)`): a -1 becomes `occurrence` = 0.
- **Size:** 67 route-year records over the 11 species (2005-2024): Sturnus vulgaris 21, Emberiza citrinella 16, Buteo buteo 11, Alauda arvensis 11, Lanius collurio 3, Vanellus vanellus 2,
  Lullula arborea 1, Anthus pratensis 1, Saxicola rubetra 1, Perdix perdix 0, Emberiza calandra 0; at most 0.14% of the presences of a species. The effect on the maps and indices is expected to be negligible.
- **Fix:** `occurrence = as.integer(Reviere > 0 | Reviere == -1)`; keep `Reviere` as is (or NA) so that nothing uses -1 as a count; bump `occurrenceCacheSchema` so that the cached tables are rebuilt; add a unit test with a -1 row.
  Then rerun the landscape occurrence tables of the affected species and everything downstream (landscape BRTs, meta-models, indices, uncertainty): only worth doing together with the next full recomputation.
- **DONE 2026-10-21 (for the first clean run, version 1):** `occurrence = as.integer(Reviere > 0 | Reviere == -1)`, `Reviere` of those rows set to NA, `occurrenceCacheSchema` 3 -> 4 (all occurrence tables are rebuilt in the clean run). PreVal still excludes -1 rows from its count response.

## 24. `thin()` is quadratic: a faster version that gives exactly the same points

**Noted 2026-10-30 (project lead: yes, add it; do it once the Monitor is up and running, not during a run).** In the first clean run (v2) the habitat occurrence tables took hours: a species with about 5,000
records (Alauda arvensis 2022) needed 55 minutes in `thin()` (`modules/dataPrep_Monitor/R/thin.R`), a species with a few hundred records 1 to 3 minutes. Habitat is thinned for every species and year (2022:2025),
and the same function is used for the Europe (100 km) and landscape tables (`occurrencePrepEurope.R`, `occurrencePrepGerLandscape.R`, `occurrencePrepGerHabitat.R`).

- **Why it is slow.** Each pass of the `while` loop removes ONE point and then rebuilds the neighbour lists of ALL points (`purrr::map(bi, setdiff, ...)` and `purrr::map_dbl(bi, length)`), five times (`runs = 5`). The cost is about
  (points removed) x (points), so it grows with the square of the number of records.
- **Same result, no change of method.** The algorithm does not have to change, only the bookkeeping. Keep `st_buffer` and `st_intersects` exactly as they are (this fixes the neighbour lists, including the point itself and the
  small asymmetry of the buffer polygon), keep one integer vector `ni` (number of neighbours), and per removal do only this: take the candidates `which(ni == max(ni))` among the points still present (the same ascending order as the names
  of the old list), draw with the SAME call, `sample(length(cand), 1)`, mark the point as removed (`ni[id] <- -1L`), and subtract 1 from the points whose list contained it. Those points come from a reverse index of the lists made once
  (`split(rep.int(seq_len(n), lengths(nb)), unlist(nb))`), NOT from the assumption that neighbours are symmetric. The result of a run is the points still present, in ascending order, which is what `unique(unlist(bi))` gave (every remaining
  list holds only the point itself). `set.seed(i)` per run, `seeds <- sample.int(runs)` and the final choice among the largest runs stay as they are, so the sequence of random draws is identical and the retained rows are identical.
- **Expected gain:** each removal costs one vectorised pass over `ni` (microseconds) instead of thousands of small R calls; a run should take well under a second instead of minutes. To be measured, not assumed.
- **How to prove it is the same (do this before using it):** a test (`modules/dataPrep_Monitor/tests/test_thin.R`) that keeps the old function as `thinOld` and checks `identical(thinOld(x, d, runs = 5), thinNew(x, d, runs = 5))` on many random point sets with fixed
  seeds: clustered points on a 200 m grid (like the habitat data), points at distances just below and above the thinning distance (this is where an asymmetry of the buffer polygon would show), sets with no neighbours at all, and sets of 1 and 2 points.
  Then once on the real table of one big species-year (Alauda arvensis 2022): thin with both versions and compare the retained rows.
- **Pitfalls.** (1) Do not replace the `st_buffer`/`st_intersects` step by `st_is_within_distance`: the exact circle and the buffer polygon differ at the boundary, so the points would differ. (2) Do not change the order of the
  random draws (for instance by sampling from a differently ordered vector). (3) `reproducible::Cache()` of the occurrence tables may or may not include the code of `thin()` in its key: check on one species before the full run; if the key changes, all tables are
  rebuilt once (acceptable, but plan for it). (4) The repository checks that duplicated functions are identical across modules (`tools/check_duplicated_functions.R`); `thin.R` exists only in `dataPrep_Monitor`, so there is nothing to copy.
- **Done 2026-11-03 (project lead: yes, before the v3 run).** `thin.R` now follows the plan above; `modules/dataPrep_Monitor/tests/test_thin.R` keeps the old function as `thinOld` and checks identical retained points on 16 constructed cases (1,000 points on a 200 m grid at several distances including exactly the grid spacing and just below/above it, identical coordinates, chains, no neighbours, 1 and 2 points, 25 clusters), 40 random sets and runs = 1, 3, 10 (all identical), plus 1,800 further random comparisons. Speed: 750 clustered points 12.3 s -> 0.08 s; 5,000 points 0.59 s (the old function: about 55 minutes). Cache keys are no concern in v3 because every occurrence table is rebuilt anyway (the land-use layers changed). NOT yet done: the check on one real big species-year (Alauda arvensis 2022) on EVE; the v2 tables are the reference for it.

## 25. Exact fold assignment of the out-of-fold meta-model inputs (point-in-polygon per scale, or one block layout)

**Noted 2026-11-05 (idea from a colleague's tip on stacking, not changed; v3 keeps the current design).** The meta-model weights are trained on out-of-fold predictions, but the folds are exact only at the habitat scale. For climate and landscape,
a habitat record gets the fold of the NEAREST record of that scale's own table (`uncOofContext()` in `uncOof.R`) and is predicted by the model that left that fold out (audit table S3-45). Near a block border the nearest record can lie in another
block, so the model that predicts the record may have seen its neighbourhood; at the 50 km climate scale the nearest cell is far from the habitat point. The out-of-fold inputs are then slightly too good for those two scales, and the weights
could favour them a little too much. The size of the effect is not known.

**The fix (two options; the first is probably the right one).** (A) Keep the block layout of each scale, with the block size that suits that scale (50 km climate cells need blocks of several hundred km, 200 m habitat records
much smaller ones; the code uses floors and caps per scale), and replace the nearest-record lookup by a point-in-polygon lookup: the fold of a habitat record at a scale is the fold of the block of THAT scale's layout that contains
the record. Each scale's input is then exactly out-of-block for its own layout. This needs the block polygons of each scale to be saved (to be checked). (B) One block layout for all scales: then the blocks must be as large as the
coarsest scale needs, which leaves few, large blocks for the habitat scale (a harsher but coarser test, and uneven fold sizes). Option (A) keeps the scales' own spatial-independence distances; (B) makes the held-out regions identical for all scales.

**Test it before changing anything (needs the v3 outputs; see TODO.md section A, item 9).** (1) Per species, how often does the nearest-record fold differ from the fold of the block polygon that really contains the habitat record, per scale,
and how far is the nearest record? (2) For the species where the share is high (and for Vanellus vanellus, audit S3-47): recompute the ridge weights and the honest AUC with the exact folds and compare. Part (2) is cheap for the BRT member (the fold
models are saved); the other ensemble members do not keep their fold models, so an exact ensemble check would mean refitting their folds.

**If the effect is small:** keep the design and state the limit (already in the Methods document). **If it is large:** one block layout for all scales in the next version (this changes the spatial blocking in `inputs_Monitor`, so all fits and
the uncertainty replicates have to be rerun).

## 26. Water mask for the Monitor maps (last step, on the viz copies only)

**DONE 2026-11-05 for v3 (code, tests, water layer; not yet run on EVE).** See DECISIONS.md 2026-11-05 (water mask) and audit table S5-80. `connectViz(waterFile = ...)` sets the cells whose water share is at least 0.5 to NA in the viz COPIES of the species probability, its uncertainty layers and the richness layers; the originals in `outputs/v3` are never changed; the regional index is not masked. Water layer: OpenStreetMap water polygons (HOT/oex export, ODbL) prepared by `tools/prepareWaterLayer.R` into `inputs/predictors/raw/water/water_bodies.gpkg`.

**Left:** (1) copy `water_bodies.gpkg` to `inputs/predictors/raw/water/` on EVE before the chain is submitted (the submit script checks); (2) look at the first v3 maps at the coast (Wadden Sea, bays are not masked) and at the widest rivers; (3) add the credit "Contains data from OpenStreetMap contributors (ODbL 1.0)" to the Monitor; (4) if the OSM layer is not accepted, the official BKG DLM250 hydrography can replace it (the connector takes any polygon file); (5) a threshold other than 0.5 needs no model rerun.

## 27. URGENT, right after the v3 run: one template grid per scale (`rasterToMatch`) and the study area for EVERY processed layer, with `Cache` (project lead, 2026-11-06)

**Why.** The v3 prep failed twice for the same reason: layers that are on different grids and are put right afterwards. (1) The land-use files of different years are on different grids (HCTM footprint for 2005-2023, the larger CTM grid for 2024-2025), so the fixed hedge mean had no value in the rim of the larger grids (DECISIONS 2026-11-05, audit S2-70). (2) The heterogeneity and unmapped-share files were created on the uncropped land-use grid and the later crop step skipped them because of an old marker (DECISIONS 2026-11-06, audit S1-71). Today every layer is made on the grid of its own source and cropped later in place (`applyStudyAreaToProcessed()`, marker `<file>.studyarea`, DECISIONS 2026-10-21 item 3).

**Proposal.** Define one template raster per scale (the study area plus the buffer, one fixed origin and cell size) and put EVERY processed layer on it when it is made, with `reproducible::prepInputs()`/`postProcess()` (`studyArea`, `rasterToMatch`) inside `Cache()`: the grid is then the same however and whenever a layer was made, and a rewritten source changes the cache key, so a stale marker cannot exist. The markers and the crop step would go; `completeHedges()` would no longer need its rim fill.

**Cost and risk.** Layers are resampled onto a fixed grid (the method for classes and shares must be chosen: average for shares, nearest for classes), which changes values slightly and therefore the models; every builder (`computeLanduse`, `computeLandcover`, heterogeneity, unmapped share, distance to woodland, DEM) and the loaders in `models_Monitor` are touched; the land-use step has to be rerun (more than 12 h at 200 m). Project lead 2026-11-06: the crop fix of the stale markers is only a shortcut for the v3 run; this item is URGENT for right after v3 (its own branch with tests, compared with v3). Layers must never be created on the grid of their source and fixed afterwards.

---

## 28. Drivers the model does not have: why the modelled index is flat and how to add them

**Noted 2026-11-11 (project lead: "How could we implement those to improve the models?"). Nothing here is built, and every cause below is a hypothesis, not a finding.** Evidence (S9 comparison with the DDA territory series, `outputs/v3/figures_S9_trim/`): the observed abundance changes from year to year with a median SD of 0.10 (log change), the final model line with 0.012, about 7 times less (3 to 39 times by species; Common Buzzard 39, Common Kestrel 24, Common Starling 23). The year-to-year changes of the two lines correlate at about 0.05 (median over species; range -0.42 to +0.38, noise with 18 changes per species). The LEVEL over the years is better: observed abundance against the final map 0.50, against the landscape scale alone 0.69 (median over species). By scale the SD is climate 0.008, landscape 0.022, habitat 0.010, final 0.012: the meta-model damps the most variable scale. The only sources of year-to-year variation are the yearly climate and land-use predictors; there is no year term (DECISIONS.md 2026-11-03). The model predicts the probability of OCCURRENCE, so a decline inside occupied sites cannot appear in it (Yellowhammer: observed abundance falls to 71, occupancy to 90).

**Where a new driver can enter (decide this first, it determines what S9 can still show).**
- *Spatially varying driver* (a value per cell and year, e.g. crop-specific pesticide pressure): a normal predictor in the landscape and habitat scale models. Their training years differ (landscape 2005-2024 for most species, habitat 2022-2025 with a hindcast before), so a predictor that only varies in time is learnt from 20 years at the landscape scale and from 4 at the habitat scale.
- *Driver with one value per year for the whole country* (Sahel rainfall, national pesticide sales, a vole index): it cannot go into the spatial presence/absence models as a normal predictor, it would be one more year effect fitted to 20 years. It belongs in a SECOND STAGE: a per-species annual multiplier on the national index (and on the maps), fitted with at most 1-2 covariates, leave-one-year-out cross-validation, and a prior or penalty, and reported separately from the main model.
- *Calibration of the year effect to the monitoring index* (a free year term per species, fitted to the DDA/PECBMS series): the most effective way to get the swings right and the least informative, because it absorbs every missing driver and explains none. If it is ever used it must be labelled calibration, and S9 then is no longer an independent check. It would also need a decision about the hindcast before 2022 (what the habitat scale hindcast is for).

**Step 0 (cheap, do first, local, no EVE): what do the residuals look like?** From `S9_observed_vs_modelled_series.csv` take, per species, observed minus modelled on the log scale, and look at (a) the correlation of the residual series between species and (b) a PCA over the 14 species. A residual axis shared by all species points to a country-wide driver (weather, pesticides, policy); an axis shared only by the migrants (on the present roster: Red-backed Shrike, Whinchat, Common Whitethroat, Western Yellow Wagtail; Turtle Dove is not on it) points to the winter quarters or the passage; an axis shared by Kestrel and Buzzard points to prey; a species with its own residual points to something species-specific. With 14 series and 19 years this is a screening tool, not a test. Effort: about half a day.

**Result of Step 0 (run 2026-11-11, `S9_observed_vs_modelled_series.csv`, 14 species, 2006-2024, log observed abundance minus log modelled index; scratch scripts `resid_pca.R`, `resid_pca2.R`):**
- *Levels:* the first axis (45% of the residual variance) is a divergence of the observed series from the flat model line from 2020 on (axis score from about -1 to +6 over 2020-2024). Observed minus model, mean 2006-2019 to mean 2020-2024: Kestrel +0.54, Corn Bunting +0.50, Woodlark +0.31, Red-backed Shrike +0.30 (observed above the model); Whinchat -0.28, Yellowhammer -0.14, Tree Sparrow -0.13, Lapwing -0.12 (observed below). It has OPPOSITE signs in two groups of species, so it is not one country-wide driver; any trending series gives a large first axis, so this is a description, not evidence.
- *Year-to-year changes:* the mean correlation of the residual changes between species is 0.11 (years shuffled within species: 95% limit 0.046), so there is a small shared signal; the first axis explains 24.4% (shuffled limit 24.1%, i.e. not distinguishable from chance). 7 of 91 species pairs have |r| >= 0.5 (shuffled: 3.1 on average, 95% limit 6). With 18 yearly changes a single correlation has an error of about 0.24; these are hints, not tests.
- *The pairs above 0.5:* Lapwing-Buzzard 0.65, Buzzard-Kestrel 0.60, Lapwing-Kestrel 0.50 (open-country early breeders: the raptors and the Lapwing move together); Yellowhammer-Tree Sparrow 0.58 (resident seed-eaters); Wagtail-Whitethroat 0.56 and Wagtail-Whinchat 0.51 (migrants). The migrants correlate 0.23 on average with each other, 0.06 with the others. The most negative years on the first axis of the changes are 2009 and 2013 (2013 had a cold late spring: only a hypothesis; the climate layer cannot show it, because it is a 6-year mean at 50 km, see item 29).
- *Reading:* the weather of the breeding season (open-country early breeders) and winter or farming conditions of the resident seed-eaters are the more specific hints; the Kestrel-Buzzard link alone does not prove prey, because the Lapwing is linked to both.

### 28a. Pesticides, food supply and farming intensity

**What is missing:** insecticide and herbicide pressure (insects as chick food, weed seeds for Skylark, Yellowhammer, Corn Bunting, Partridge), crop-specific management, the fallow and set-aside rules.
**Data (named from memory, availability and resolution NOT checked):** national sales of plant protection products per active substance and year (BVL; national only, one number per year); cropland share and crop type per cell, which we already have (HCTM, CTM). **Project lead 2026-11-11: colleagues have compiled pesticide data that can serve as proxies.** Which data, which years, which spatial unit and who holds them: still to ask. The JKI farm-survey route was dropped (project lead: "I don't like the idea"). These proxies, not the national sales, are the candidate for a spatial layer.
**How:** a pesticide-pressure layer = sum over crops of (crop share in the cell and year x national treatment frequency of that crop and year). Its spatial pattern is then the crop mix, which the models already contain, and the new information is only the yearly change of the treatment intensity of each crop. Add it as a predictor at landscape and habitat scale, or as a second-stage covariate.
**Risks:** collinear with the crop shares (the model may not be able to separate them); a nation-wide treatment frequency per crop and year has no spatial signal beyond the crop map; with 20 years a trend in pesticide use is confounded with every other trend (land-use change, climate, the species' own decline). Expect to be able to say "consistent with", not "caused by".
**First check:** do the residuals of the seed- and insect-dependent farmland species (Step 0) trend with the national treatment index?

### 28b. Winter quarters and migration (the long-distance migrants)

**What is missing:** survival in Africa and on passage; none of it is in a model that only knows the breeding season conditions. Species: the four long-distance migrants on the roster (`data/speciesCanonical.csv`, include = X): Red-backed Shrike, Whinchat, Common Whitethroat, Western Yellow Wagtail (Turtle Dove is not on it). Lapwing, Skylark, Starling and Meadow Pipit are partial migrants and are not covered by an African covariate. **Priority: low (project lead is doubtful it will work, and the residual check below gives only a weak hint).**
**Data:** none proposed at present. The African rainfall route (CHIRPS) was dropped on 2026-11-11 (project lead: "I don't like the idea"); this item stays in the file only as a described possibility.
**How:** second stage only (one value per year). Per migrant species: log(observed index / modelled index) in year t regressed on the covariate of the preceding winter, one covariate, leave-one-year-out CV; accept it only if it beats a model with no covariate out of sample.
**Risks:** wintering ranges differ by species and population (Germany's birds winter where?), the covariate choice is a forking path (use one pre-specified covariate per species, from the literature, before looking at the residuals); with the DDA series as the target, a hit is only a hint (the same series is the "truth" and the target).
**Cost:** low, a few days, once the covariates are chosen. It cannot be used to project beyond the last year of the covariate.

### 28c. Prey cycles (Kestrel, Buzzard, perhaps Owls if they enter)

**What is missing:** the vole cycle, which drives breeding density and success of both raptors.
**Data (to verify):** no national vole index is known to us. Possible proxies: the species' own previous-year counts (not allowed in the model, it would be circular), regional vole or raptor monitoring series from the federal states, winter snow cover and autumn conditions, the beech mast year (rodent pulse).
**How:** as 28b, a second-stage covariate; or a species-specific yearly effect with a regional structure if regional vole data exist.
**Risks and expectation:** probably the least feasible of the four for lack of data; cycles are partly regional and out of phase, so one national covariate would blur them. Ask the Monitor team and the raptor monitoring groups what exists before planning anything.

### 28d. Density inside occupied sites (the structural limit)

**What is missing:** the model predicts presence, so a decline in the number of territories where the species still occurs is invisible.
**Implementation, already described:** item 1a (hurdle, DDA `Reviere` counts at the landscape scale, point counts at the habitat scale) and item 1b (N-mixture, habitat scale only). For the S9 problem the landscape-scale count model is the relevant one: truncated Poisson or negative binomial on routes with `Reviere` > 0, same covariates, plot as a random effect, then E(abundance) = P(present) x E(count | present). Only then can the model line move like the abundance series. The Yellowhammer case (abundance 71, occupancy 90) is the test case; the meta-model would have to move from the logistic to a Poisson/NB ridge (item 1a).
**Cheaper first look:** compare our line against the OCCUPANCY series only (already in the S9 table) and count how many species are then inside the band; this says how much of the gap is the occurrence-versus-density difference alone.

### 28e. The 2024 step and the land-use switch (not a missing driver, a possible artefact)

10 of 14 species have a 2024 step in the modelled index larger than 2 times their own usual change (Kestrel +9%, Red-backed Shrike +14%, Corn Bunting +10%, Whinchat -13%). 2024 is the first year with the CTM v302 recoded to HCTM classes (HCTM ends in 2023; Zenodo record 10.5281/zenodo.20815677 checked 2026-11-11, no 2024/2025 maps). In the country means maize rises 15.5%, vegetables fall 38%, fallow rises 30%, root crops rise 13%; fallow and vegetables are the classes where the recode matches HCTM worst. The observed series also rises in 2024 for Kestrel, Shrike and Corn Bunting, so part of the step may be real. NOT proven either way. Tests, cheapest first:
1. Counterfactual: predict 2024 with the 2023 land use (and 2023 with the 2024 land use if there is a way to build one) for Kestrel, Shrike, Whinchat and Corn Bunting; the part of the step that disappears is due to land use. Needs the models on EVE (the T4 counterfactual of item 21 is the same machinery).
2. Compare the recoded 2024 crop areas with Destatis acreage statistics for 2023 and 2024 (national and by federal state): the change should match the official change.
3. Ask the HCTM authors and Thünen whether 2024 and 2025 maps in HCTM classes are planned, or whether an overlap year (a year mapped by both) exists to calibrate the recode.
4. Corn Bunting's 2024 step comes from the CLIMATE scale (-10%), not from land use: look at the 2024 climate predictors separately.

### Data availability, checked 2026-11-11 (web search and page fetch only; formats, licences and exact limits still to confirm before use)

| Source | Time | Space | Covers Germany? | Note |
|---|---|---|---|---|
| BVL domestic sales of plant protection products and active substances (bvl.bund.de/psmstatistiken; summary by [UBA](https://www.umweltbundesamt.de/daten/land-forstwirtschaft/pflanzenschutzmittelverwendung-in-der)) | sales since 1977; active-substance groups 2012-2021 in the 2021 report; 2024: 87,022 t products, 28,639 t active substances | national only; no federal-state breakdown found | yes, as ONE number per year | sales are not use (stocking, exports across years); no crop or place |
| DWD gridded monthly precipitation (opendata.dwd.de, grids_germany) | monthly from 1881 | 1 km | Germany only | station-based |
| DWD HYRAS-DE | daily from 1931, precipitation and temperature, monthly products exist | 1 km | Germany only | ideal for yearly spring weather at the landscape and habitat scales |
| UFZ German Drought Monitor (soil moisture index) | daily, online since 2009, index calibrated on 1953-2014 | 4 km | Germany only | simulated (mHM) from DWD data; download format and exact time span not confirmed |

What this means: the BVL sales are national, one number per year; the spatial pesticide layer has to come from the proxies compiled by the project lead's colleagues (28a). Weather and soil moisture exist at 1-4 km for all of Germany for every year 2005-2025; for the landscape scale the first choice is UFZ's own products (item 29), with the CHELSA source of the climate scale as the fallback. A vole index was not searched again and none is known. (The JKI PAPA and CHIRPS rows were removed on 2026-11-11 at the project lead's request.)

### Suggested order and cost

1. Step 0: DONE 2026-11-11 (result above, weak hints only); the occupancy-only comparison is already in the S9 table.
2. 28e tests 2 and 3 (small, decide whether 2024 can be trusted); test 1 on EVE.
3. 28b for the migrants (a few days; second stage; pre-specify the covariate).
4. 28d (weeks; the hurdle model of item 1a, the only one that changes what the model estimates).
5. 28a once the colleagues' pesticide proxies are identified (what, which years, which spatial unit); 28c only if data turn out to exist (check with the Monitor team and the raptor monitoring groups before spending time). 28b: no data proposed, low priority.
6. Item 29 (climate and local conditions at the landscape scale) is the project lead's decided direction (2026-11-11) and comes BEFORE 28a-28c.

Per the process note at the top, each of these gets its own feature branch with tests; none touches `master` until validated. Whatever is added, S9 stays a comparison with the DDA series: say in the methods which variants were fitted to that series (28b second stage, any calibration) and which were not.

---

## 29. Physical (environmental) indicators for the landscape and habitat scales

**Noted 2026-11-11 (comment received today: the landscape and habitat scales should have physical, i.e. environmental, indicators). Project lead, same day: "We need to add climate and local conditions to the landscape scale". The DIRECTION is decided; the design below is not; nothing is built, and no test is to be set up for now (project lead 2026-11-11: "just add as a potential improvement").**

**What the two scales have now** (`data/speciesConfig_predictors.csv`): land use and land cover shares (23 classes), elevation, slope, and for some species landscape heterogeneity, hedges (one fixed layer) and distance to woodland. Weather appears ONLY in the climate scale (bio1-19 at 50 km, from CHELSA); soil, wetness, aspect and vegetation state appear nowhere. So the landscape and habitat scales cannot see a wet spring, a drought, a cold winter or a soil type, and their only year-to-year signal is the land-use change.

**Two kinds of indicator with different jobs (this is the main point):**
- *Static (one layer, does not change with the year).* Improve the spatial pattern (discrimination, AUC, where the species is), do NOT add year-to-year signal, so they cannot make the modelled lines move. Candidates: topographic wetness index, aspect, roughness and solar radiation (all derivable from the 30 m DEM we already process: no new download); soil texture, organic carbon and pH (SoilGrids at 250 m is global; a German soil map from the BGR is an alternative; availability and licence to check); distance to groundwater or a wetness class (partly in `wetland_peat`). Relevant for the species that depend on soil moisture and soil fauna (Lapwing, Starling, Skylark, Meadow Pipit, Whinchat) and on dry, sandy or south-facing ground (Woodlark, Shrike, Wagtail).
- *Dynamic (a value per year, or per season and year).* The only way to bring weather or vegetation into the yearly signal at the fine scales. Project lead 2026-11-11: UFZ's own products are preferred where they exist. *Soil moisture and drought:* the UFZ German Drought Monitor (soil-moisture index, 4 km, daily, online since 2009; simulated with UFZ's mHM model from DWD data; what is downloadable, in which format and for which years is NOT confirmed: ask the Drought Monitor team at UFZ, also whether finer mHM outputs exist). *Temperature, precipitation, snow:* the Drought Monitor is run with DWD observations as input, so the UFZ group (Drought Monitor / mHM) probably holds daily gridded meteorological forcing and simulated snow for the same years: ask for them first (not confirmed). Reasons for an internal product (project lead: "isn't it better to have an internal product?"): one consistent chain for temperature, precipitation, snow, soil moisture and drought; daily values for every year, which the event variables below need; direct contact for questions and corrections; a citable dataset record with DOI and licence exists for the Drought Monitor. Fallback only for what UFZ cannot supply: the CHELSA source the climate scale already uses (its monthly files cannot give frost, snow, hot or heavy-rain days; whether daily CHELSA exists for every year 2005-2025 has to be checked). DWD HYRAS-DE is no longer proposed as a separate option (it is what the UFZ product is built on); also vegetation greenness (NDVI/EVI from MODIS at 250 m since 2000, or Landsat at 30 m; Sentinel-2 starts in 2015, too late for the hindcast), snow cover. All exist for 2005-2025, so the hindcast years are covered (see the data table in item 28).

**Candidate variables (project lead, 2026-11-11: "winter temperature, days of snow, summer temperature, drought events... anything that might affect these birds directly or indirectly via the trophic chain"; to be chosen per species group, not all at once).** Each is a yearly value per cell, with the previous year's value as a lag (as the climate scale already has one lag year):
- *Winter (Dec-Feb):* mean and minimum temperature, number of frost days, number of days with snow cover or snow depth (survival of residents, access to ground food, snow cover protects voles: Kestrel, Buzzard).
- *Spring (Mar-Jun):* mean temperature, precipitation total, late-frost days (early breeders: Lapwing, Skylark, Starling, the raptors; the 2013 hint of Step 0), heavy-rain days in the chick period (May-July).
- *Summer (Jun-Aug):* mean temperature, number of hot days (30 degrees C or more), growing-degree sum (insect emergence, vegetation).
- *Drought:* days below a soil-moisture threshold and the length of the longest event in the breeding season and in the previous summer (soil fauna for Starling, Lapwing, Whinchat; vegetation structure; crop yield).
- *Trophic chain in this list:* insects (temperature sums, cold and wet chick-rearing weather), voles (snow cover, winter), earthworms and leatherjackets (soil moisture), seeds and crops (drought). Event counts (frost, snow, hot, heavy-rain, drought days) need DAILY data for every year 2005-2025, which is one more reason to ask UFZ first.

**Why the climate layer we already have does not do this (checked in the code and in the v3 results, 2026-11-11):**
- *It is a 6-year mean.* `computeBioclimYear()` averages each calendar month over a rolling window of `sharedClimateWindowLength` = 6 years (`tools/sharedConfig.R`) before computing BIO1-19. One cold spring is one sixth of a monthly mean, so a single bad year barely moves any of the 19 variables.
- *It is annual in content and coarse in space.* BIO1-19 are annual or quarterly summaries, not March-June conditions, at 50 km (`sharedClimateResolutionM`).
- *It learns space, not years.* The climate scale is trained on the EBBA2 atlas (2013-2017), so it learns where the species lives along the climate gradient, not how it reacts to a cold year.
- *The meta-model gives it almost no weight (v3, `imp_*` of the 14 species).* Climate 0 to 0.097 (median 0.01), landscape 0.002 to 0.594 (median 0.31), habitat 0.41 to 1.00 (median 0.63). The weights are trained on the habitat records of 2022-2025, which is where the habitat scale is strongest.
- *The climate scale also moves little:* SD of its yearly line 0.008 (the scales analysis of 2026-11-11), against 0.022 for the landscape scale and 0.010 for the habitat scale.
So weather IS in the model, but in the scale that is both the coarsest and the least weighted, in an averaged form. Putting climate into the landscape scale is not a duplicate; the question is the form (window, season, resolution), not whether.

**Proposed form (to decide):**
1. (Fallback, or in addition to the UFZ variables) compute BIO1-19 with the existing code at the landscape resolution (1 km; 700 m shrike, 5 km buzzard, as for the other landscape layers) from the CHELSA files we already download. CHELSA's native grid is about 1 km, so no new source and no new download of different data. Cost to check: reading and projecting 12 months of tasmin, tasmax and prec per year at 1 km for Germany, for every year 2005-2025 (the climate scale does this at 50 km).
2. Window length. The reason for the 6 years of the climate scale (Y-5 to Y) is closed (project lead, 2026-11-11; it is not written in the code, DECISIONS.md or the Methods document, which only state it): the window matches the EBBA2 atlas period (2013-2017), and one lag year was added to the five atlas years to capture the effect of a block of years on the following year. The climate scale is trained on ONE such climatology (2012-2017), so for it a prediction year is described by the same kind of variable. That does not bind the landscape scale, where the response is yearly (DDA 2005-2024), so a yearly predictor is consistent with how the model is trained. The same 6 years as the climate scale would keep the two scales alike but washes out a single year; a 1-year window (or the 12 months before the survey) gives the yearly signal. Test both (test (c) below); this is the one design choice that decides whether the lines can move.
3. Season: add breeding-season (March-June) mean temperature and precipitation total on top of or instead of BIO1-19 (19 correlated variables at 1 km for a BRT is a lot; consider a chosen subset).
4. Static local conditions (DEM-derived and soil, above) in the same step.
5. Habitat scale: do NOT add yearly climate there first (4 training years). But note that the habitat scale carries a median 63% of the meta-model weight and is nearly flat, so a landscape-scale yearly signal may reach the final line only in proportion to the landscape weight (median 0.31), which is why the final SD (0.012) is already lower than that of the landscape scale (0.022). Decide, after test (c), whether the meta-model weights or the habitat scale need to change too.

**Cautions that decide the design:**
1. The habitat scale is fitted to 4 years (2022-2025); a response to yearly weather cannot be learnt from 4 years and would be extrapolated into 2005-2021 (the hindcast assumption of item 21). The landscape scale uses DDA data for 2005-2024 for most species, so yearly weather can be learnt there. Start with the landscape scale.
2. Yearly covariates are confounded with every other yearly change (trends in management, land use, other drivers); the result can be read as "consistent with", not as cause.
3. More predictors on thin habitat data raise overfitting and collinearity (soil with land use and elevation); use the honest block-CV AUC and the out-of-fold meta-model weights (item 16), not the in-sample fit.
4. Static layers change the spatial pattern, so every scale that gets them has to be refitted and the uncertainty replicates rerun.
5. The pipeline rule from item 27 applies: put every new layer on the scale's template grid when it is made.

**Test before adopting (cheap first, own branch, one species group at a time):**
- (a) Static set derived from the DEM (TWI, aspect, roughness, solar radiation): one species at landscape and habitat scale, compare block-CV AUC and the meta-model weight; no new data.
- (b) Soil layers: same comparison for Lapwing, Starling, Skylark, Meadow Pipit, Whinchat.
- (c) Dynamic weather at the landscape scale (DDA 2005-2024): add the CHELSA climate at the landscape resolution (BIO1-19 or a chosen subset, with a 1-year and a 6-year window; plus March-June temperature and precipitation), compare (i) block-CV AUC and (ii) the S9 diagnostic that matters here: the correlation of the yearly changes of the modelled and observed series (now 0.05 median) and the SD of the modelled line (now 0.012 against 0.10 observed). If neither moves, weather at that scale does not help and the idea can be closed.
- (d) Check the 2009 and 2013 hint of Step 0 (item 28): does the residual of the raptors and the Lapwing follow the spring temperature of the single year (UFZ product, or CHELSA)?

**Expectation, stated so that it can be wrong:** static indicators will probably give a modest gain in spatial accuracy and no change in the flat lines; dynamic indicators are the only candidate for the year-to-year signal, but the Step 0 hints are weak (shared residual correlation 0.11), so a large gain should not be assumed.

---

*Some of these have started -- for discussion once the current run's
models are complete. See also `TODO.md` item 6/7 (unrelated: raster-processing
performance, EVE cluster) and item 0 (methodology-fidelity gaps already found
while reading the paper). Make sure to look at both files.*
