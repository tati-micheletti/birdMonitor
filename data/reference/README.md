# Reference data (not produced by birdMonitor)

## eurostat_farmland_bird_index_EU27.csv
European farmland bird indicator for the comparison figure `S3_vs_european_farmland_index` (tools/makeStCoFigures.R).

- Source: Eurostat dataset `sdg_15_60` "Common bird index by type of species - EU aggregate" (DOI 10.2908/SDG_15_60), fetched 2026-10-15 from
  `https://ec.europa.eu/eurostat/api/dissemination/statistics/1.0/data/sdg_15_60?format=JSON&lang=EN` (dataset last updated 2026-02-16). Original data: European Bird Census Council (EBCC) / PECBMS,
  BirdLife, RSPB, CSO. Annual values 1990-2024, EU27 aggregate, SMOOTHED estimates (statinfo SME).
- What it is: multi-species indicator of abundance, 39 common farmland species (comspec CO_FARM); also all common species (168) and forest species (34).
- Columns: `<group>_I00` = index with 2000 = 100, `<group>_I90` = index with 1990 = 100 (both as published); `CO_FARM_rebased_2005` = farmland I00 divided by its 2005 value x 100 (added here).
- NOT the same thing as the 60% decline 1980-2021 quoted by BirdLife (Europe-wide, 30 countries, from 1980), and NOT the German Agrarland indicator of the DDA.
