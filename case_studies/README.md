# Case studies for the presentation (NOT part of the workflow)

Two places, shown as stories: **Schorfheide-Chorin Biosphere Reserve** (hope) and **Muensterland** (work to do).
Nothing here is read by the pipeline, and nothing here changes a result. It reads finished outputs only.
Started 2026-11-16 for the Steering Consortium presentation; delete the folder when it is no longer needed.

## Steps

| Step | Where | Script | Output |
|---|---|---|---|
| 0 | local | `Rscript case_studies/build_areas.R` | `areas_3035.gpkg` (reserve outline, 3 x 3 cell block, state minus area as control) |
| 1 | EVE | `BIRDMONITOR_RUNNAME=v3 CASE_ARGS="--no-response" sbatch --export=ALL case_studies/eve_case_study.sbatch` (copy `areas_3035.gpkg` to `outputs/v3/case_studies/` first) | `species_site_year.csv`, `landuse_site_year.csv` (and `model_response.csv` without `--no-response`) |
| 2 | local | `Rscript case_studies/make_case_study_figures.R` | PNG figures (1920 x 1080) and the numbers behind them (csv) |
| 3 | local | `python case_studies/make_case_study_slides.py` (needs `python-pptx`) | draft deck, 3 slides per case, every number read from the csv files of step 2; details and sources in the speaker notes |

Inputs of step 2 (default folder `outputs_downloaded/v3_2026-11-14/regional`): `trend_all.tif`, `trend_farmland.tif`
(`regional_index_10km_unc_trend_per_decade.tif` of the two groups, `outputs/v3/uncertainty_*/regional*`), the yearly index maps
`yearly_all/`, `yearly_farmland/` (`/data/birds/viz2/msi_regional_*`), and the three csv files of step 1.

## What the areas are
* **Schorfheide**: the official outline of the Biosphere Reserve (1,291.8 km2; the published area is 1,292 km2). Cells of the 10 km regional grid count as inside when their centre is inside the outline; the species and land-use means use every cell whose centre is inside.
* **Muensterland**: 3 x 3 cells of the regional grid (30 x 30 km, aligned with the grid), around 7.70 E, 52.05 N. Muensterland has no official outline.
* **Control**: the federal state without the area (Brandenburg, North Rhine-Westphalia), because declines are much stronger in the west than in the east; the comparison with Germany as a whole mixes that gradient into the result. The control is NOT matched for soil or climate.

## Sources and licences
* Reserve outline: OpenStreetMap relation 215277 (Schorfheide-Chorin, `boundary=protected_area`, `protect_class=98`), fetched 2026-11-16 through Nominatim/Overpass; (c) OpenStreetMap contributors, ODbL. The BfN service refused automated access (HTTP 403), so the BfN file was not used.
* Base map under the zoom maps: OpenStreetMap standard tiles (tile.openstreetmap.org, a few dozen fetched once, with an identifying User-Agent, as the tile usage policy asks), turned pale grey by the script; (c) OpenStreetMap contributors. Tiles are cached locally, not committed. (CARTO tiles were tried first and now need an API key.)
* State outlines: GADM 4.1 (the pipeline's own copy in `inputs/predictors/raw/gadm`).

## Things to keep in mind when using the results
* 2024-2025 use a different crop map (CTM v302 recoded to HCTM classes). In the Muensterland layers winter cereals fall 31 % from 2023 to 2024 and summer cereals rise elevenfold; the index jumps in the same year. All series are therefore shown to 2023 and 2024-2025 are marked; slopes are 2005-2023 unless the label says 2005-2025 (the regional trend map is the pipeline's 2005-2025 product).
* The model shows direction and relative contrast, not the size of real population change (nationally it captures about 13 % of the observed slope, with the same sign for 11 of 14 species).
* The model has no layer for organic farming, nest losses or predation. A response curve shows what the model has learnt, not proof of a cause.
