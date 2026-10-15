# Reference data (not produced by birdMonitor)

## pecbms_farmland_bird_index_1980base.csv
The European Farmland Bird Index of the Pan-European Common Bird Monitoring Scheme (PECBMS / EBCC), used by the comparison figure `S3_vs_european_farmland_index` (tools/makeStCoFigures.R).

- Source: PECBMS, "Wild Bird Indices for Europe and the EU produced by the PECBMS in 2025", file `indicators-europeeu-till2024.xlsx`
  (https://pecbms.info/wp-content/uploads/2025/12/indicators-europeeu-till2024.xlsx; sheet "Indicators", base year 1980, indicator "Farmland Bird Index"), downloaded 2026-10-15. Methods: https://pecbms.info/methods/3-multispecies-indicators/
- Contents: regions `Europe` and `EU`, years 1980-2024, 1980 = 100. Columns: `smoothed` (smoothed indicator), `lowerCL` and `upperCL` (confidence limits of the smoothed indicator), `unsmoothed`. Species and country lists are on the other sheets of the original file.
- It is an index of ABUNDANCE of common farmland species (counts from national breeding bird schemes), Europe-wide; it is not the German indicator of the DDA and not made from our probability-of-occurrence maps.
