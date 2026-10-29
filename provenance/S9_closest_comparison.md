# Provenance of the figure "Our combined index and the observed trends of the same 11 species in Germany"

Figure files (written by `tools/makeResultFigures.R`, section S9): `S3_indices/S9_closest_comparison.png` (without the German indicator) and `S9_closest_comparison_german.png` (with it).
Plotted values: `tables/S9_closest_comparison_values.csv` (one row per year; every number on the figure is in it).
Code version: git commit `64b22e5` (main) or later. The calculation is deterministic (the Monte Carlo uses `set.seed(42)`): the same inputs give the same numbers.
Final version: to be built on EVE (needs the replicate area means there): `FIG_ARGS="--sections S9 --variants big5" sbatch --export=ALL cluster/eve_figures.sbatch`.
Written 2026-10-16. Items marked **OPEN** are not yet verified. Numbers marked **to be filled** come from the EVE run.

## 1. What is plotted (all set to 100 in 2006, geometric means over the same 11 species)

| Line | What it is | Source |
|---|---|---|
| Our MSI (orange, band) | Index of the mean predicted probability of occurrence over German pixels, per species; the 11 species combined the PECBMS way: estimate from the main model, band by Monte Carlo | Section 3 |
| Observed occupancy (green) | Share of surveyed DDA plots with at least one territory | Section 2 |
| Observed abundance (black, dashed) | Number of territories on the surveyed DDA plots | Section 2 |
| German indicator Agrarland (purple; only in the `_german` version) | UBA/BfN sub-index for farmland birds, percent of a target value, divided by its 2006 value | Section 4 |

The 11 species: Vanellus vanellus, Lanius collurio, Lullula arborea, Alauda arvensis, Saxicola rubetra, Emberiza calandra, Emberiza citrinella, Buteo buteo, Sturnus vulgaris, Perdix perdix, Anthus pratensis (`data/speciesCanonical.csv`, column `include`; species matched in the DDA data by EURING code).

## 2. Observed series (DDA territory data)

Origin: the DDA files were supplied directly by the DDA, a project partner (information from the project lead, 2026-10-16). The data are being built into a continuous pipeline.
**OPEN:** acknowledgement or permission wording for showing indices derived from these data in the public monitor (to agree with the DDA contact).

Raw files (never modified), `inputs/response/raw/territories/`:

| File | Bytes | File date | sha256 |
|---|---|---|---|
| `BirdStats_Daten2005-2024D_alle.xlsx` | 26,259,817 | 2026-06-23 | `2ec10249efa1a8ad09d5d935333543e9a5588463897f89c0c2891ff349caf3d6` |
| `BirdStats_Visits2005-2024D.xlsx` | 495,979 | 2026-05-13 | `e80de559e6052c97306290b79631bb73eefd34d96fedd7efe7ebdd205a23b218` |

Columns: Data = Nummer, Countdate, EURING, Reviere (territories), Art deutsch, ROUTENCODE, Cov1 (698,273 rows). Visits = Nummer, Jahr, Countdate, ROUTENCODE (20,824 rows; one row per plot and survey year).

Conversion to csv: `tools/convertDdaTerritories.py` (cell for cell; nothing filtered or recoded), output `inputs/response/processed/territories_csv/`:
`dda_data.csv` sha256 `566e07d4cf5dbca37d63858fd2ed601dc34d72b8c991d6ed6356cdaf6fc1dc2b`, `dda_visits.csv` sha256 `3fee3f754e79b2563b121f1063380c6b0fbfe8457a5d382a46585fc7645f557a`.
Checked 2026-10-16: the script reproduces both csv files byte for byte. On EVE the same csv files are used; compare their sha256 with the values above (`sha256sum`).

Index calculation (S9 block of `tools/makeResultFigures.R`), the rules of Kamp et al. 2021 (J Ornithol 162):
- only plots surveyed in at least two years (2,116 plots); the first survey year of each plot is dropped; reference year 2006;
- a plot-and-year multiplicative model (expected value = plot effect x year effect, fitted by iterative scaling) on the territory counts (abundance) and on presence/absence (occupancy), per species; index = 100 x year effect / year effect of 2006;
- the 11 species are combined by the geometric mean.

**This is our own calculation from the raw DDA data, not the index that the DDA publishes.** It has no observer correction (the file has no observer id) and does not use TRIM or its error model.
Number of plots in the calculation, per year (2006 ... 2024): 267, 506, 657, 745, 789, 835, 896, 951, 958, 1053, 1098, 1114, 1102, 1152, 1289, 1226, 1278, 1137, 1344. The reference year 2006 rests on the fewest plots (267), so the early part of the observed lines is noisy (for example the 107 for occupancy in 2007).
Plausibility check: for 2006-2019 the observed abundance line follows the German indicator closely (see the `_german` figure).

## 3. Our modelled series

Inputs (on EVE, `outputs/<run>/`; the S9 block reads them through the variant `big5`, the model ensemble):
- `annual_report_ens_brt-glm-gam-rf-nn_germany/species_index.csv`: species index of the **main model** (2005 = 100), Germany-only pixels. The values on the local copy: file date 2026-10-09 05:50, 4,109 bytes, sha256 `ed6424e037ac6403d0fa2b7f3ddf7900d1cdef4e52038244302fa2fcab8715ae`.
- `uncertainty_ens_brt-glm-gam-rf-nn/<Species>/area_mean_replicates_germany.csv`: for every species, replicate (0 = main model, 1-25 = bootstrap replicates) and year, the mean predicted probability over German pixels. **To be filled from the EVE run:** sha256 of the 11 files and the number of replicates found (printed in the table column `replicatesForInterval`).

Calculation (`tools/makeResultFigures.R`, S9; `tools/msiMonteCarlo.R`):
- main-model species index rebased to 2006: 100 x index(year) / index(2006), per species;
- standard error of a species index = standard deviation across the replicates of 100 x area mean(year) / area mean(2006), computed replicate by replicate (so it is 0 in 2006);
- estimate = geometric mean over the 11 species of the main-model indices;
- band = 5th to 95th percentile of 1,000 Monte Carlo draws (seed 42) of that geometric mean, each species drawn from a normal distribution on the log scale with its index as mean and its standard error (Soldaat et al. 2017, the method of PECBMS).
This is the rule of the "MSI" rows in `combined_index_uncertainty.csv` (`modules/runIndex_Monitor/R/computeIndexUncertainty.R`), except that this calculation centres on the main model; the pipeline file centres on the replicate mean. `tools/msiMonteCarlo.R` was checked against the pipeline code on synthetic data (identical results).
The band shows the model uncertainty given the training data. It is not a sampling interval.
Earlier version of this figure (replicate-mean line, 2006 rebasing of the pipeline's MSI row) gave 94.1 in 2024; the main-model geometric mean is 93.7.

What the model is, and what it is not (state this with the figure):
- Probability of occurrence (presence/absence), not abundance. Mean over German pixels, so it measures how the average predicted suitability changes.
- Habitat scale (200 m) fitted on point counts of 2022-2025 only; the meta-model weights are fitted on the same years. All years before 2022 are hindcast, and the hindcast has not been validated against independent data.
- Landscape scale (1 km) fitted on DDA territory data 2005-2024 (Buteo buteo and Sturnus vulgaris: point-count data 2022-2025). **The model therefore saw part of the observed data: the comparison is not an independent test.**
- Climate scale: European atlas data (EBBA2) and climate of a rolling window.
- Time-varying inputs are land-use shares and climate only; there is no year term.
- Ensemble of BRT, GLM, GAM, RF and NN at three scales plus a ridge meta-model; 25 spatial-block bootstrap replicates (replicate 0 = the main model).
**OPEN:** the git commit and package versions of the EVE run (written in `run_info_*.txt` in the uncertainty folder of each species on EVE). To be read when the final version is set.

## 4. German indicator (only in the `_german` version)

`data/reference/uba_agrarland_subindex_Germany.csv`, from Umweltbundesamt 2025, `de-en_indikator_terr-02_artenvielfalt_2025-11-18_1.xlsx`, sheet "Daten", column "Teilindex Agrarland" (percent of a target value), downloaded 2026-10-15; see `data/reference/README.md`.
Divided by its 2006 value to set 2006 = 100; this approximates the relative change because the series is scaled to a target. It has about 10 species (the list was not checked), 7 of which are among our 11, and ends in 2023.

## 5. Questions that may come, and the answers the files support

- *Is the observed line the DDA index?* No. It is our calculation from the raw DDA territory data with the DDA rules (Section 2), without observer correction and TRIM.
- *Is this a validation?* No. The landscape scale was fitted on part of the same data; the habitat and meta-model fit covers only 2022-2025.
- *Why do the lines differ?* Not established. Same-plot checks show the models get the direction of change right for all nine species that could be tested (Buteo and Sturnus excluded: records start in 2022) but only part of its size; see `tools/panelTrendAnalysis.R` and `outputs/test4/panel_trend_check/`.
- *Why 2006?* The DDA rules drop the first year of each plot series; 2006 is the reference year of Kamp et al. 2021 for the new scheme. It rests on 267 plots.
- *Is the DDA index the standard?* The steering committee said it should not be treated as the absolute standard.
