# Sanity check of the cached monthly CHELSA rasters that the bioclim windows are built from. READ-ONLY.
#   Rscript tools/checkClimateMonthly.R
# Prints: months present per year/variable, implausible months (fill values, zeros, wrong units), and the mean tasmin/tasmax before
# and after the change of source (monthly CHELSA product up to 2021, daily aggregation from 2022). A break of more than ~1 K between
# the two means that the sources are NOT consistent (found 2026-10-07: min/max of the daily values instead of their mean, +5 K / -4 K).
suppressMessages(library(terra))
d <- file.path("inputs", "predictors", "raw", "chelsa_monthly", "europe")
fs <- list.files(d, pattern = "^(tasmin|tasmax|prec)_[0-9]{4}_[0-9]{2}(_dmean)?[.]tif$", full.names = TRUE)
info <- do.call(rbind, lapply(fs, function(f) { p <- strsplit(sub("_dmean", "", sub("[.]tif$", "", basename(f))), "_")[[1]]
  g <- unlist(global(rast(f), c("mean", "min", "max"), na.rm = TRUE)[1, ])
  data.frame(var = p[1], year = as.integer(p[2]), month = as.integer(p[3]), dmean = grepl("_dmean", f), mean = g[1], min = g[2], max = g[3]) }))
rownames(info) <- NULL
# when both the old and the "_dmean" file of a month exist, the _dmean file is the one the pipeline uses
info <- info[order(info$var, info$year, info$month, !info$dmean), ]; info <- info[!duplicated(info[, c("var", "year", "month")]), ]
cat("files used:", nrow(info), "| years", min(info$year), "-", max(info$year), "\n\nmonths per year (variables tasmin/tasmax/prec; 12 = complete):\n")
print(table(info$year, info$var))
t <- info$var != "prec"
bad <- info[(t & (info$min < 180 | info$max > 345 | info$mean < 250 | info$mean > 300)) | (!t & (info$min < 0 | info$max > 3000)), ]
cat("\nIMPLAUSIBLE months (temperature: min < 180 K, max > 345 K, mean outside 250-300 K; precipitation: < 0 or > 3000 mm):\n")
if (nrow(bad)) print(bad[, c("var", "year", "month", "mean", "min", "max")], row.names = FALSE) else cat("none\n")
ok <- info[t & info$year >= 2015 & !paste(info$var, info$year, info$month) %in% paste(bad$var, bad$year, bad$month), ]
cmp <- aggregate(mean ~ var + after2021, data = transform(ok, after2021 = year >= 2022), FUN = mean)
cat("\nmean over Europe, 2015-2021 (monthly product) vs 2022+ (daily aggregation); the two should differ by well under 1 K:\n"); print(cmp)
