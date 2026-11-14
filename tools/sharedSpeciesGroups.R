################### SPECIES GROUPS = WHICH SPECIES GO INTO WHICH INDEX (2026-11-14)
# data/speciesGroups.csv says which of the MODELLED species (data/speciesCanonical.csv, include = X) are combined into which index and which richness map.
# Every group listed there is calculated: national index, regional index and richness/community maps of that group. The per-species work (models, ensemble,
# uncertainty bands, species maps) is done ONCE per species and is shared by all groups.
#   - one row per (group, species); `group` = short code used in folder and file names (lower case, no spaces), `label` = name shown to people (no commas)
#   - the group "all" is the general one and must hold EXACTLY the modelled species: it keeps the folder and file names the pipeline always had (no suffix)
#   - any other group (e.g. "farmland") gets the suffix "_<group>" on the folders and files of the combining steps (see groupSuffix())
# A species that is modelled but in no group other than "all" is simply not in the other indices (e.g. the raptors are not in the farmland index).

#' Load and check the species groups
#'
#' @param path Character. Path to speciesGroups.csv.
#' @param roster Character. The modelled species (Latin names, `canonicalIncludedSpecies()`).
#' @param minSpecies Integer. A group with fewer species gets a warning: the geometric-mean index of very few species is unstable.
#' @return list(table = the file as data.frame, groups = character, members = named list of Latin names (in roster order), labels = named character).
loadSpeciesGroups <- function(path, roster, minSpecies = 8L) {
  if (!file.exists(path)) stop("speciesGroups.csv not found: ", path)
  df <- utils::read.csv(path, stringsAsFactors = FALSE, colClasses = "character", fileEncoding = "latin1")
  df[] <- lapply(df, trimws)
  need <- c("group", "label", "latin_name")
  if (length(miss <- setdiff(need, names(df)))) stop("speciesGroups.csv is missing column(s): ", paste(miss, collapse = ", "))
  if (anyNA(df$group) || any(!nzchar(df$group)) || any(!nzchar(df$latin_name))) stop("speciesGroups.csv: empty group or latin_name.")
  if (any(!grepl("^[a-z][a-z0-9]*$", df$group))) stop("speciesGroups.csv: `group` must be lower case letters and digits (it is used in file names): ", paste(unique(df$group[!grepl("^[a-z][a-z0-9]*$", df$group)]), collapse = ", "))
  if (anyDuplicated(df[, c("group", "latin_name")])) stop("speciesGroups.csv: the same species twice in one group: ", paste(unique(df$latin_name[duplicated(df[, c("group", "latin_name")])]), collapse = ", "))
  lab <- tapply(df$label, df$group, function(x) unique(x))
  if (any(vapply(lab, length, 1L) != 1L)) stop("speciesGroups.csv: a group has more than one label: ", paste(names(lab)[vapply(lab, length, 1L) != 1L], collapse = ", "))
  groups <- unique(df$group)
  members <- lapply(stats::setNames(groups, groups), function(g) roster[roster %in% df$latin_name[df$group == g]])
  for (g in groups) {                       # a group may only name modelled species: a typo or a removed species must stop the run, not shrink the index silently
    unknown <- setdiff(df$latin_name[df$group == g], roster)
    if (length(unknown)) stop("speciesGroups.csv: group '", g, "' names species that are not modelled (include = X in speciesCanonical.csv): ", paste(unknown, collapse = ", "))
    if (length(members[[g]]) < minSpecies) warning("speciesGroups.csv: group '", g, "' has only ", length(members[[g]]), " species (< ", minSpecies, "): its geometric-mean index is unstable with so few species.", call. = FALSE)
  }
  if (!"all" %in% groups) stop("speciesGroups.csv must define the group 'all' (every modelled species): it keeps the unchanged folder and file names.")
  if (!setequal(members$all, roster)) stop("speciesGroups.csv: the group 'all' must hold exactly the modelled species. Missing: ", paste(setdiff(roster, members$all), collapse = ", "), ".")
  list(table = df, groups = groups, members = members, labels = vapply(lab, function(x) x[[1]], character(1)))
}

#' Suffix of the folders and files of a group's combining steps: "" for the group "all", "_<group>" otherwise
groupSuffix <- function(group) if (is.null(group) || !nzchar(group) || identical(group, "all")) "" else paste0("_", group)
