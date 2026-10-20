---
name: spatial-io
description: Use whenever deciding what the Bird Monitor can show in UFZ's spatial.IO (also written Spatio.IO), how to name, split, format or upload result rasters (probability, uncertainty, richness, MSI maps) so spatial.IO can display them, or when answering what spatial.IO can and cannot do. Facts come from public pages read on 2026-10-20; what is NOT documented is listed as open questions for the spatial.IO team.
---

# spatial.IO (UFZ spatial data infrastructure), as far as it is documented

Official name: **spatial.IO** (the project lead writes "Spatio.IO"). The Bird Monitor's maps are shown through it. Everything below was read from public pages
(see Sources). **Marked "OPEN" = not in the public documentation: ask the spatial.IO team before relying on it.** Contact listed on the Helmholtz software page:
Christian Schulz (UFZ, christian.schulz@ufz.de). Creators of version 1.0.0: Weber, Lange, Biskamp, Panda, Schnicke, Bumberger (UFZ).

## What it is
- UFZ's spatial data infrastructure (SDI): ingestion, publication, metadata and interactive visualization of raster, vector and time-series geodata, "self-service", open source (EUPL-1.2),
  container-based (Docker/Helm), microservices. Version 1.0.0 (June 2026) = "stable, production-ready". Production uses: WIS-D (German water data), UFZ Forest Condition Monitor.
- Funded through the DataHub initiative (BMBF, Helmholtz). Related: time.IO, SMS, SaQC.

## Components (version 0.6.0 paper / 1.0.0 record)
| Component | Role |
|---|---|
| MinIO | S3-compatible storage; accepts any file format (this is the "bucket") |
| Worker | runs in the background, watches MinIO for new or changed data, creates GeoServer datastores, links data to the THREDDS server, creates/updates GeoNetwork metadata |
| GeoServer | OGC web services (WMS etc.) for netCDF, GeoTIFF and COG; **COG needs a manually created ImageMosaic** |
| GeoNetwork | metadata catalogue (CSW, download links); metadata supplied as an external JSON file |
| THREDDS (TDS) | OPeNDAP access; netCDF only |
| AggregationAPI (pygeoapi) | OGC API - Processes: aggregated values over polygons, for netCDF and GeoTIFF/COG |
| Admin frontend + Django backend + PostgreSQL | manage MinIO data in projects, connect it to GeoServer/GeoNetwork/TDS, create and configure WebGIS instances |
| WebGIS (Vue, OpenLayers) | the viewer |
| FROST-Server | sensor data (OGC SensorThings API), time series |

## Supported data
- Listed formats: netCDF (primary, full automated workflow, binding regulations "Binding Regulations for Storing Data as netCDF Files"), **Cloud-Optimized GeoTIFF**, **GeoTIFF**, Shapefile,
  GeoJSON, GeoPackage, CSV, SensorThings.
- Non-netCDF formats (GeoTIFF/COG) currently need **manual work steps**; automation is "planned for later versions" (README, 2024 paper). Whether 1.0.0 automates them: OPEN.
- WebGIS component types: netCDF, GeoTIFF, GeoPackage, STA, WFS (CSV). COG is handled as an **ImageMosaic**.

## What the viewer can do (2024 paper, version 0.6.0)
Swiper to compare two datasets; time slider; selection of federal states and districts; shapefile upload; aggregation of values over a polygon (state, district, uploaded shapefile);
time-series diagram of several datasets; filter datasets by variable; save map as PDF; save time series and aggregation results as CSV.

## What is NOT documented (OPEN, ask the team)
1. Does the time slider work for GeoTIFF/COG ImageMosaics (the pages name it, but not for rasters)? How is the time of a file taken (file name pattern)?
2. Exact folder and file naming the Worker expects in the bucket; is one folder = one layer/mosaic? CRS and datatype requirements; maximum file size or number of files.
3. Styling: colour scales, legend, value range per layer; can uncertainty layers (mean, sd, lwr, upr, width) be shown next to the probability (swiper?) or as a band/hatch?
4. Is the "no multilayer maps" rule a requirement of the Worker/ImageMosaic, or only of the Monitor?
5. Are non-Germany pixels (NA / nodata) handled, and how is nodata declared?
6. Who creates the ImageMosaic and metadata for new COG layers (manual steps) and how long does an update of existing files take to appear?
7. Download rights of the displayed rasters and how users are asked to cite/acknowledge the data (the DDA data in particular).

## Consequences for the Bird Monitor results (inferences from the documentation, not from the team)
- GeoServer ImageMosaics build the time dimension from the **file name** (a date pattern read by a regular expression, e.g. `..._YYYYMMDD.tif`, `timeregex.properties`) and one mosaic = one folder of
  files of the same kind. This is consistent with the Confluence requirements "subfolder per species" and "exported per year": one folder per species, one single-layer file per year.
  The file names `<Species>_<year>.tif` may therefore have to follow a date pattern the mosaic can parse (e.g. `<Species>_<year>0101.tif`): OPEN question 1/2, to settle with the team before the first upload.
- COG is the listed raster format for ImageMosaics. Our files are plain GTiff (DEFLATE). A COG can be written with `terra::writeRaster(r, f, filetype = "COG")` or
  `gdal_translate in.tif out.tif -of COG -co COMPRESS=DEFLATE` (GDAL >= 3.1). Not yet done in `connector_Monitor`; add as a parameter once the team confirms.
- Uncertainty has to be separate single-layer files (mean, sd, lwr, upr, width) in their own folder, as in `connector_Monitor`.
- The viewer aggregates over polygons itself (AggregationAPI): the Monitor does not need to ship regional means for that.

## Sources (read 2026-10-20)
- Helmholtz software page: https://helmholtz.software/software/spatialio
- Zenodo record of version 1.0.0 (June 2026): https://zenodo.org/records/20761736
- Zenodo record of version 0.6.0 (Schulz et al. 2024, components and viewer functions): https://zenodo.org/records/13347341
- README (GitLab, UFZ SDI): https://codebase.helmholtz.cloud/ufz-sdi/spatialio
- Demo instances (not readable without a browser; privacy dialog only): https://web.app.ufz.de/wis-d/ and https://web.app.ufz.de/waldzustandsmonitor/
- GeoServer COG mosaic and time-series ImageMosaic documentation (general GeoServer behaviour, NOT spatial.IO documentation): https://docs.geoserver.org/main/en/user/community/cog/mosaic/
