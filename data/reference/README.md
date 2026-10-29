# Reference data (not produced by birdMonitor)

## pecbms_farmland_bird_index_1980base.csv
The European Farmland Bird Index of the Pan-European Common Bird Monitoring Scheme (PECBMS / EBCC), used by the comparison figure `S3_vs_european_farmland_index` (tools/makeResultFigures.R).

- Source: PECBMS, "Wild Bird Indices for Europe and the EU produced by the PECBMS in 2025", file `indicators-europeeu-till2024.xlsx`
  (https://pecbms.info/wp-content/uploads/2025/12/indicators-europeeu-till2024.xlsx; sheet "Indicators", base year 1980, indicator "Farmland Bird Index"), downloaded 2026-10-15. Methods: https://pecbms.info/methods/3-multispecies-indicators/
- Contents: regions `Europe` and `EU`, years 1980-2024, 1980 = 100. Columns: `smoothed` (smoothed indicator), `lowerCL` and `upperCL` (confidence limits of the smoothed indicator), `unsmoothed`. Species and country lists are on the other sheets of the original file.
- It is an index of ABUNDANCE of common farmland species (counts from national breeding bird schemes), Europe-wide; it is not the German indicator of the DDA and not made from our probability-of-occurrence maps.

## uba_agrarland_subindex_Germany.csv
The German national indicator "Artenvielfalt und Landschaftsqualitaet", sub-index Agrarland (farmland birds): UBA/BfN, with data of the Dachverband Deutscher Avifaunisten (DDA).

- Source: Umweltbundesamt 2025, data file `de-en_indikator_terr-02_artenvielfalt_2025-11-18_1.xlsx` (sheet "Daten", column "Teilindex Agrarland") of the indicator page
  https://www.umweltbundesamt.de/daten/umweltindikatoren/indikator-artenvielfalt-landschaftqualitaet , downloaded 2026-10-15. The page lists no values by year in its text; the numbers are in the Excel file.
- Contents: `agrarland_pct_of_target` = "Zielerreichungsgrad in Prozent" (percent of the target value, 100 = target for 2030), 1990, 1995 and every year 2000-2023; `total_index_pct_of_target` = the total index (agricultural land, forests, settlements, inland waters).
- It is an index of ABUNDANCE of selected representative farmland birds (about ten species according to the UBA/BfN texts; the species list was not checked here), expressed as percent of a target. The series was revised in 2019-2022, so older
  publications show other values. Dividing by the value of 2005 gives a series with 2005 = 100 (used in the comparison figure); this is an approximation of the relative change because of the target scaling.
