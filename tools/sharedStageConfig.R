################### PIPELINE STAGE SELECTION (cluster runs)
# Lets ONE runMe.R drive each non-model-fitting piece of the workflow as its
# own SLURM job on EVE, so the cluster can run the WHOLE pipeline end to end:
#
#   BIRDMONITOR_STAGE=all    (default) today's behavior -- one run does
#                             everything, sequentially (local runs).
#   BIRDMONITOR_STAGE=prep   dataPrep_Monitor + inputs_Monitor only: builds
#                             covariates, occurrence tables, spatial blocks
#                             and the model_ready/ tables the model arrays
#                             read.
#   BIRDMONITOR_STAGE=index  runIndex_Monitor only: builds the index from the
#                             finished metaModel() outputs.
#
# Model fitting itself (climate/habitat/landscape/meta, one task per species)
# is deliberately NOT a runMe.R stage on a cluster -- it runs as the SLURM
# arrays in modules/models_Monitor/cluster/ via tools/runClusterTask.R, which
# is what parallelizes the expensive part. cluster/submit_eve_pipeline.sh
# chains prep -> model arrays -> index.
#
# BIRDMONITOR_RUNNAME pins the run name exactly (no timestamp appended), so
# every stage -- and the model arrays' --run-name -- write to the SAME
# outputs/<runName>/ folder. Unset (default): runNameBase + a timestamp, as
# before.

pipelineStageModules <- function(stage = Sys.getenv("BIRDMONITOR_STAGE", "all")) {
  allModules <- c("dataPrep_Monitor", "inputs_Monitor", "models_Monitor", "runIndex_Monitor")
  switch(stage,
         all = allModules,
         prep = allModules[1:2],
         index = allModules[4],
         stop("BIRDMONITOR_STAGE must be one of: all, prep, index (got: \"", stage, "\")",
              call. = FALSE))
}

# Keep only the params blocks for the modules actually being loaded.
paramsForStage <- function(params, stageModules) {
  params[intersect(names(params), stageModules)]
}

resolveRunName <- function(runNameBase) {
  pinned <- Sys.getenv("BIRDMONITOR_RUNNAME", "")
  if (nzchar(pinned)) pinned else paste0(runNameBase, "_", format(Sys.time(), "%Y%m%d_%H%M%S"))
}
