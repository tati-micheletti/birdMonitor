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
