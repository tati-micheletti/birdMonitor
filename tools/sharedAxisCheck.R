# One-line log of how EPSG:3035 transformations behave RIGHT NOW in this R session (see DECISIONS.md,
# 2026-10-05). Called from runMe.R before/after setupProject() and (as reportAxisState()) at the start of
# every dataPrep_Monitor event, to show where the axis order changes in the full SpaDES session on EVE.
# Shared libraries of the geo stack that this R process has actually loaded (Linux only). Two different
# libproj/libgdal files in one process = mixed installations (cf. rspatial/terra#1378).
loadedGeoLibs <- function() {
  tryCatch({
    if (!file.exists("/proc/self/maps")) return("n/a (not Linux)")
    m <- readLines("/proc/self/maps", warn = FALSE)
    p <- sub("^.* ", "", m[grepl("lib(proj|gdal|geos|sqlite3|netcdf|hdf5)[^/]*[.]so", m)])
    paste(sort(unique(p)), collapse = "; ")
  }, error = function(e) paste("?", conditionMessage(e)))
}

axisCheck <- function(label) {
  tryCatch({
    if (!requireNamespace("sf", quietly = TRUE)) { message("[axis] ", label, ": sf not available yet"); return(invisible(NULL)) }
    p <- sf::st_as_sf(data.frame(lon = 11.5, lat = 48.1), coords = c("lon", "lat"), crs = 4326)
    xy <- sf::st_coordinates(sf::st_transform(p, 3035))
    cfg <- tryCatch(paste(unlist(terra::getGDALconfig("OSR_DEFAULT_AXIS_MAPPING_STRATEGY")), collapse = ""), error = function(e) "?")
    message("[axis] ", label, ": (11.5E, 48.1N) -> EPSG:3035 x=", round(xy[1, 1]), " y=", round(xy[1, 2]),
            if (xy[1, 1] < xy[1, 2]) "  <<< SWAPPED" else "  (ok)",
            " | GDAL axis-strategy config='", cfg, "' | sf ", as.character(utils::packageVersion("sf")),
            " | loaded: ", paste(intersect(c("terra", "sf", "reproducible", "SpaDES.core", "Require", "reticulate", "raster", "sp", "rgdal"),
                                          loadedNamespaces()), collapse = ","))
    message("[axis-libs] ", label, ": ", loadedGeoLibs(), " | PROJ_DATA='", Sys.getenv("PROJ_DATA"), "' PROJ_LIB='", Sys.getenv("PROJ_LIB"),
            "' proj search paths: ", tryCatch(paste(sf::sf_proj_search_paths(), collapse = ","), error = function(e) "?"))
  }, error = function(e) message("[axis] ", label, ": check failed: ", conditionMessage(e)))
  invisible(NULL)
}
