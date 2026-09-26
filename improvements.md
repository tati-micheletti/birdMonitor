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

**Status: deferred, explicitly not yet** -- "we need to move the runIndex
to its own MODULE! But not yet" (2026-09-25). Noted here so it isn't lost,
not to be started until the current `runIndex.R` script approach has been
validated (this weekend's local test with the index step included).

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

---

*Some of these have started -- for discussion once the current run's
models are complete. See also `TODO.md` item 6/7 (unrelated: raster-processing
performance, EVE cluster) and item 0 (methodology-fidelity gaps already found
while reading the paper). Make sure to look at both files.*
