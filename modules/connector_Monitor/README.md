# connector_Monitor

Connects the results of the pipeline to the Bird Monitor. It keeps ONE folder, the **viz folder** (on EVE: `/data/birds/viz`), that always holds
the newest result of every species and every layer the Monitor shows. **Whatever is not in the viz folder is not shown in the Monitor**, so the folder
must be complete after every run, also after a run of only one species or one scale.

## What it does
- Looks in **all run folders** (`runsRoot/<run>/...`, ensemble tag `ens_brt-glm-gam-rf-nn`, Germany-only versions) and takes, for every result, the
  **newest** file. A species that was not part of the last run keeps its file from the earlier run.
- Writes one file per layer (**no multilayer maps**) in the structure of the bucket (Confluence BirdTwin / Architektur / EVE Cluster):

| Folder in viz | File | Content |
|---|---|---|
| `meta_prob_year/<Species>/` | `<Species>_<year>.tif` | probability of occurrence |
| `meta_unc_year/<Species>/` | `<Species>_<year>_<layer>.tif` | uncertainty, layer = mean, sd, lwr, upr, width |
| `richness_year/` | `richness_<year>_<layer>.tif` | expected richness (mean) and its uncertainty, every year |
| `msi_regional/` | `msi_10km_<year>.tif` | regional index (MSI) 10 km, raw |
| `msi_regional_unc/` | `msi_10km_<year>_<layer>.tif` | its uncertainty |
| `msi_regional_clear/` | `msi_10km_<year>.tif` | the regional index with every cell whose 90% interval includes 100 set to 100 (2026-11-11): the file for the Monitor map; `msi_regional` is unchanged |
| `msi_national/` | `msi_national.csv` | national trend: method, year, estimate, median, lwr, upr, `preliminary` (TRUE for the years after the last published national indicator year) |

- Results that are already there and still current are left alone; a file is replaced only by a **newer** source. **Nothing is ever deleted.**
- Writes `_manifest.csv` (every file, where it came from, which run, when) and `_missing.csv` (expected but not there) into the viz folder, and
  warns when something is missing. `failIfIncomplete = TRUE` makes that an error.
- Files that need no splitting are linked (symbolic link), never linked to `/work` (EVE deletes old files there): use the copy in `/data/birds`
  as `runsRoot`.

## How to run
On EVE, after `cluster/copy_to_data_birds.sh` has copied the new results to `/data/birds/birdMonitor/outputs`:

    cd ~/projects/birdMonitor && git pull && sbatch cluster/eve_connector.sbatch

`DRY=1` in front of `sbatch --export=ALL ...` only reports. Environment variables of `tools/runConnector.R`: `BIRDMONITOR_VIZ_PATH` (default
`/data/birds/viz`), `BIRDMONITOR_RUNS_ROOT` (default `/data/birds/birdMonitor/outputs`), `BIRDMONITOR_VIZ_RUNS` (comma-separated run folders, default all),
`BIRDMONITOR_VIZ_DRY`.

The expected richness is built for every mapped year by the community step (it was the report year only until 2026-10-28). The national trend marks the years after `sharedNationalIndicatorLastYear` (tools/sharedConfig.R, or `BIRDMONITOR_NATIONAL_LAST_YEAR`) as preliminary; changing it needs only a new connector run, not new models.

## Water mask (since 2026-11-05)

No probability of occurrence is shown over lakes and big rivers. With `waterFile` (parameter; `tools/runConnector.R` takes `sharedWaterMaskFile` from `tools/sharedConfig.R` or `BIRDMONITOR_WATER_FILE`, value `none` = off on purpose) the cells whose water share is at least `waterMinShare` (0.5) are NA in the COPY in the viz folder, for the products in `waterProducts` (species probability, its uncertainty layers, richness). The source files are never changed, masked files are written and never linked, the regional index (MSI) is not masked, and the manifest records the setting (a changed setting makes the files again). The file is OpenStreetMap water polygons prepared by `tools/prepareWaterLayer.R` (credit: contains data from OpenStreetMap contributors, ODbL 1.0); a missing file stops the job at its start. See DECISIONS.md 2026-11-05.


## Species groups and the viz2 layout (since 2026-11-14)

The Monitor can show more than one index: the species of each GROUP in `data/speciesGroups.csv` are combined into their own richness map, regional index and national trend (`DECISIONS.md`, 2026-11-14). The per-species products do not depend on a group. With `BIRDMONITOR_VIZ_GROUPS=1` (and `BIRDMONITOR_VIZ_PATH=/data/birds/viz2`) `tools/runConnector.R` writes every group of the file into one folder, the group in the name of every group product:

```
viz2/meta_prob_year/<Species>/<Species>_<year>.tif                  same as viz (all modelled species)
viz2/meta_unc_year/<Species>/<Species>_<year>_<layer>.tif           same as viz
viz2/richness_year_<group>/richness_<year>_<layer>.tif              expected richness of the species of the group; layer = mean, sd, lwr, upr, width
viz2/msi_regional_<group>/msi_<km>km_<year>.tif                     regional index of the group, raw
viz2/msi_regional_unc_<group>/msi_<km>km_<year>_<layer>.tif         its uncertainty
viz2/msi_regional_clear_<group>/msi_<km>km_<year>.tif               regional index, cells whose 90% interval includes 100 set to 100
viz2/msi_national/msi_national_<group>.csv                          national trend of the group (method, year, estimate, median, lwr, upr, preliminary)
viz2/_groups.csv                                                    group, label, number and names of the species, the folders of the group
viz2/_manifest.csv, _missing.csv (first group), _missing_<group>.csv
```

Without `BIRDMONITOR_VIZ_GROUPS` the connector works as before: the group `all` only, in the folders of the list above (viz). In code: `connectViz(groupSuffix, nationalFile, missingFile, folders)` once per group; the species products are brought in with the first group only.
