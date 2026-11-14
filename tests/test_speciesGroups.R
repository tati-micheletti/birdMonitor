# Local test of the species-groups checks (tools/sharedSpeciesGroups.R) and of the real data/speciesGroups.csv against the real roster.
#   Rscript tests/test_speciesGroups.R        (from the repo root)
source("tools/sharedSpeciesCanonical.R"); source("tools/sharedSpeciesGroups.R")
ok <- 0L; fail <- 0L
check <- function(what, cond) { if (isTRUE(cond)) { ok <<- ok + 1L; message("ok   ", what) } else { fail <<- fail + 1L; message("FAIL ", what) } }
roster <- paste("Species", LETTERS[1:10])
tmp <- function(df) { f <- tempfile(fileext = ".csv"); utils::write.csv(df, f, row.names = FALSE); f }
rows <- function(g, sp, label = g) data.frame(group = g, label = label, latin_name = sp)
good <- rbind(rows("all", roster, "Bird Index"), rows("farm", roster[1:8], "Farm Index"))
res <- loadSpeciesGroups(tmp(good), roster, minSpecies = 8L)
check("good file: groups all and farm, members in roster order, labels", identical(res$groups, c("all", "farm")) && identical(res$members$farm, roster[1:8]) && identical(unname(res$labels), c("Bird Index", "Farm Index")))
check("groupSuffix: '' for all (and unset), '_farm' otherwise", identical(groupSuffix("all"), "") && identical(groupSuffix(NULL), "") && identical(groupSuffix(""), "") && identical(groupSuffix("farm"), "_farm"))
err <- function(df, ...) tryCatch({ loadSpeciesGroups(tmp(df), roster, ...); "no error" }, error = function(e) conditionMessage(e))
check("a species that is not modelled stops the run (typo, or a species removed from the roster)", grepl("not modelled", err(rbind(good, rows("farm", "Species Z", "Farm Index")))))
check("no group 'all' stops", grepl("must define the group 'all'", err(rows("farm", roster))))
check("'all' that is not the whole roster stops", grepl("exactly the modelled species", err(rbind(rows("all", roster[1:9]), rows("farm", roster[1:8])))))
check("the same species twice in a group stops", grepl("twice", err(rbind(good, rows("farm", roster[1], "Farm Index")))))
check("a group code with capitals or spaces stops (it goes into file names)", grepl("lower case", err(rbind(good, rows("Farm land", roster[1:8], "x")))))
check("two labels for one group stop", grepl("more than one label", err(rbind(good, rows("farm", roster[9], "Other label")))))
w <- character(); withCallingHandlers(loadSpeciesGroups(tmp(rbind(rows("all", roster), rows("tiny", roster[1:3]))), roster, minSpecies = 8L), warning = function(x) { w <<- c(w, conditionMessage(x)); invokeRestart("muffleWarning") })
check("a group with very few species warns (unstable geometric mean)", length(w) == 1L && grepl("unstable", w))
# the real files
sc <- loadSpeciesCanonical("data/speciesCanonical.csv"); ro <- canonicalIncludedSpecies(sc)
real <- loadSpeciesGroups("data/speciesGroups.csv", ro)
check("real file: group 'all' = the whole modelled roster", setequal(real$members$all, ro))
check("real file: farmland = the roster without the raptors Buteo buteo and Falco tinnunculus", setequal(real$members$farmland, setdiff(ro, c("Buteo buteo", "Falco tinnunculus"))))
check("real file: the removed species Perdix perdix, Streptopelia turtur, Milvus milvus are in no group", !any(c("Perdix perdix", "Streptopelia turtur", "Milvus milvus") %in% real$table$latin_name))
check("real file: no comma in any label (the cluster scripts read the file with awk)", !any(grepl(",", real$labels)))
message("\n", ok, " passed, ", fail, " failed"); if (fail) quit(status = 1)
