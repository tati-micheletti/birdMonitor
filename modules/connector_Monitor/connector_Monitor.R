## Everything in this file and any files in the R directory are sourced during `simInit()`;
## all functions and objects are put into the `simList`.
## To use objects, use `sim$xxx` (they are globally available to all modules).
## Functions can be used inside any function that was sourced in this module;
## they are namespaced to the module, just like functions in R packages.
## If exact location is required, functions will be: `sim$.mods$<moduleName>$FunctionName`.
defineModule(sim, list(
  name = "connector_Monitor",
  description = paste("Connects the results of the pipeline to the Bird Monitor: keeps ONE folder (the viz folder, e.g. /data/birds/viz) that always holds the",
                       "newest result of every species and every layer the Monitor shows, in the folder structure the Monitor reads (no multilayer maps).",
                       "Whatever is not in the viz folder is not shown, so after a run of only one species or one scale the folder is brought up to date from",
                       "ALL run folders: each result comes from the newest file found, results not touched by the last run keep their earlier file.",
                       "Nothing is deleted and nothing is fitted or predicted here; see the README."),
  keywords = c("bird monitor", "viz", "results", "bucket"),
  authors = structure(list(list(given = "Tati", family = "Micheletti", role = c("aut", "cre"),
                                 email = "tatiane.micheletti@ufz.de", comment = NULL)), class = "person"),
  childModules = character(0),
  version = list(connector_Monitor = "0.0.0.9000"),
  timeframe = as.POSIXlt(c(NA, NA)),
  timeunit = "year",
  citation = list(),
  documentation = list("NEWS.md", "README.md"),
  reqdPkgs = list("PredictiveEcology/SpaDES.core@development (>= 3.2.0)", "terra"),
  parameters = bindrows(
    defineParameter(".useCache", "logical", FALSE, NA, NA, "Should caching of events or module be used?"),
    defineParameter("vizPath", "character", NA_character_, NA, NA,
                    "The folder the Bird Monitor reads (on EVE: /data/birds/viz). No default (errors if unset). Created if needed."),
    defineParameter("runsRoot", "character", NA_character_, NA, NA,
                    "Folder that contains the run folders to take results from (on EVE: /data/birds/birdMonitor/outputs, the permanent copy).",
                    "NA (default): the folder above this simulation's outputPath, i.e. all runs next to the current one."),
    defineParameter("runFolders", "character", NULL, NA, NA,
                    "NULL (default): every run folder in runsRoot except those matched by excludeRuns. Otherwise the names of the run folders to use."),
    defineParameter("excludeRuns", "character", "^(utest|test1|test2|test3|CHECK)", NA, NA,
                    "Regular expression of run folders that are never used (old test and check folders)."),
    defineParameter("tag", "character", "ens_brt-glm-gam-rf-nn", NA, NA,
                    "Tag of the result folders to use: the model ensemble (BRT, GLM, GAM, RF, NN). Folders are metamodel_<res>_<tag>_germany,",
                    "uncertainty_<tag>, regional_index_<tag>_germany."),
    defineParameter("species", "character", NA_character_, NA, NA,
                    "Latin names of the FULL species roster the Monitor must be able to show (e.g. sharedSpecies). No default (errors if unset)."),
    defineParameter("years", "numeric", NA_real_, NA, NA,
                    "Years expected for every species (e.g. predictionYears). No default (errors if unset)."),
    defineParameter("cellKm", "numeric", 10, NA, NA, "Cell size (km) of the regional (MSI) index map shown in the Monitor."),
    defineParameter("folders", "list", list(meta_prob_year = "meta_prob_year", meta_unc_year = "meta_unc_year", richness_year = "richness_year",
                                            msi_regional = "msi_regional", msi_regional_unc = "msi_regional_unc"), NA, NA,
                    "Names of the sub-folders of vizPath for the five products. meta_prob_year, meta_unc_year and msi_regional follow the bucket",
                    "(Confluence BirdTwin / Architektur / EVE Cluster); richness_year and msi_regional_unc are our names until agreed."),
    defineParameter("linkMode", "character", "symlink", NA, NA,
                    "'symlink' (default) for files that need no splitting (single-layer files); 'copy' to copy them. Multilayer files are always written as new files."),
    defineParameter("allowWorkSources", "logical", FALSE, NA, NA,
                    "Allow symbolic links to files under /work. They break when EVE deletes old files there (60 days): keep FALSE and use the copy in /data/birds as runsRoot."),
    defineParameter("dryRun", "logical", FALSE, NA, NA, "TRUE: only report what would be written."),
    defineParameter("failIfIncomplete", "logical", FALSE, NA, NA,
                    "TRUE: stop with an error if a result the Monitor needs is missing from the viz folder (default: warning and a _missing.csv in the folder).")
  ),
  inputObjects = bindrows(
    #expectsInput("objectName", "objectClass", "input object description", sourceURL, ...),
  ),
  outputObjects = bindrows(
    createsOutput("vizManifest", "data.frame",
                  "What the viz folder holds after this run: product, species, year, layer, destination, source file, source time, run, mode, time written.",
                  "The same table is written to <vizPath>/_manifest.csv; the missing results to <vizPath>/_missing.csv.")
  )
))

doEvent.connector_Monitor = function(sim, eventTime, eventType) {
  switch(
    eventType,
    init = {
      if (is.na(P(sim)$vizPath)) stop("connector_Monitor's vizPath parameter must be supplied explicitly (on EVE: /data/birds/viz) -- no default.")
      if (identical(P(sim)$species, NA_character_)) stop("connector_Monitor's species parameter must be supplied explicitly (e.g. sharedSpecies) -- no default.")
      if (identical(P(sim)$years, NA_real_)) stop("connector_Monitor's years parameter must be supplied explicitly (e.g. predictionYears) -- no default.")
      sim <- scheduleEvent(sim, time(sim), "connector_Monitor", "connect")
    },

    connect = {
      # ! ----- EDIT BELOW ----- ! #
      runsRoot <- if (is.na(P(sim)$runsRoot)) dirname(normalizePath(outputPath(sim), winslash = "/", mustWork = FALSE)) else P(sim)$runsRoot
      res <- connectViz(runsRoot = runsRoot, vizPath = P(sim)$vizPath, tag = P(sim)$tag, species = P(sim)$species, years = as.integer(P(sim)$years),
                        cellKm = P(sim)$cellKm, runs = P(sim)$runFolders, excludeRuns = P(sim)$excludeRuns, folders = P(sim)$folders, linkMode = P(sim)$linkMode,
                        allowWorkSources = P(sim)$allowWorkSources, dryRun = P(sim)$dryRun, failIfIncomplete = P(sim)$failIfIncomplete)
      sim$vizManifest <- res$manifest
      # ! ----- STOP EDITING ----- ! #
    },

    warning(noEventWarning(sim))
  )
  return(invisible(sim))
}
