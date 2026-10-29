# Helpers of 5_Figure_reference.Rmd (sourced from the first chunk). Reads the figure manifest written by tools/makeResultFigures.R and emits the html of each figure:
# a small JPEG (made by make_small_figures.py) that is embedded in the page, linked to the full-resolution PNG in figures_fullreport/.
# Only the model ensemble is shown: figures of the BRT-only run, and figures that put the two runs together, are left out (they stay in the folder).
runName <- Sys.getenv("BIRDMONITOR_RUNNAME", "test4")                     # the run this page documents (the clean run is v2)
runDir  <- file.path("..", "outputs", runName)
figDir  <- file.path(runDir, "figures_fullreport")
man     <- read.csv(file.path(figDir, "figures_manifest.csv"), stringsAsFactors = FALSE)
hiddenIds <- man$id[man$variant %in% c("brt", "both", "brt+big5", "")]   # BRT-only figures and figures of both runs (the figure ids keep "big5" for the model ensemble)
man     <- man[!(man$id %in% hiddenIds), ]
cleanLab <- function(x) {                                                 # the model ensemble is the only run shown, so it is not named in titles (older figures still carry "Big 5" in their titles)
  x <- gsub(" (Big 5)", "", x, fixed = TRUE); x <- gsub(", Big 5)", ")", x, fixed = TRUE); x <- gsub(", Big 5", "", x, fixed = TRUE); gsub("big 5", "model ensemble", x, fixed = TRUE)
}
man$title <- cleanLab(man$title); man$what <- cleanLab(man$what)
tabDir  <- file.path(figDir, "tables")

# small JPEG copies of the figures that the page embeds (the page links to the full-size PNGs); remade at every render
smallDir <- file.path(runDir, "figures_small")
makeSmall <- function(files) {
  suppressMessages(library(magick)); n <- 0
  for (f in files) {
    src <- file.path(figDir, f); out <- file.path(smallDir, sub("[.]png$", ".jpg", f))
    dir.create(dirname(out), recursive = TRUE, showWarnings = FALSE)       # always remade: a downloaded PNG keeps the (older) time of the cluster, so file times cannot tell which copy is newer
    image_write(image_resize(image_read(src), "1300x>"), out, format = "jpeg", quality = 80); n <- n + 1
  }
  if (n) message(n, " small figures made")
}
makeSmall(man$file)
speciesCanonical <- read.csv("../data/speciesCanonical.csv", stringsAsFactors = FALSE)
# The species of the page are the species that HAVE results in the run (the table of the figure tool, one row per species), named from data/speciesCanonical.csv (all rows, whether
# the species is ON in the roster or not). So species can be added to or removed from the roster without touching this page: a run made with 11 species gives an 11-species page,
# a run made with 14 gives 14. The species number in the texts is nSp.
runSpecies <- unique(read.csv(file.path(tabDir, "S4_trendtest_shares.csv"), stringsAsFactors = FALSE)$species)
unknown <- setdiff(runSpecies, speciesCanonical$latin_name); if (length(unknown)) stop("Species with results that are not in data/speciesCanonical.csv: ", paste(unknown, collapse = ", "))
speciesCanonical <- speciesCanonical[speciesCanonical$latin_name %in% runSpecies, ]
speciesCanonical <- speciesCanonical[order(speciesCanonical$english_name), ]
nSp <- nrow(speciesCanonical)
spId <- function(latin) gsub(" ", "_", latin)

shown <- character(0)                                                    # ids that appear in the page (checked at the end: nothing may be left out)
fig <- function(id, what = FALSE, title = NULL) {                        # html of one figure; what = TRUE adds the explanation of the manifest
  r <- man[man$id == id, ]
  if (nrow(r) != 1) { if (!(id %in% hiddenIds)) warning("figure not in the manifest: ", id); return(invisible("")) }
  shown <<- c(shown, id)
  small <- file.path("..", "outputs", runName, "figures_small", sub("[.]png$", ".jpg", r$file))
  big <- file.path("figures_fullreport", r$file)
  shortId <- gsub("_big5", "", id, fixed = TRUE)                            # the files keep "big5" in their names; the page does not show it
  cat(sprintf('<figure class="fig" id="fig-%s"><a href="%s" target="_blank" title="open in full size"><img src="%s" alt="%s"></a><figcaption><b>%s</b>%s<span class="fid">%s</span></figcaption></figure>\n',
              id, big, small, shortId, if (is.null(title)) r$title else title,
              if (what) paste0("<br><span class=\"what\">", r$what, "</span>") else "", shortId))
  invisible("")
}
figs <- function(ids, what = FALSE) for (i in ids) fig(i, what)
browse <- function(text, ids, what = FALSE) {                            # a collapsed block (for the other grid sizes and the other comparisons)
  ids <- ids[ids %in% man$id]; if (!length(ids)) return(invisible(""))
  cat(sprintf('\n<details class="more"><summary>%s</summary>\n\n', text)); figs(ids, what); cat("\n</details>\n\n")
}
ens <- function(base, what = FALSE) fig(paste0(base, "_big5"), what)      # the model ensemble version of a figure
tab <- function(name) read.csv(file.path(tabDir, paste0(name, ".csv")), stringsAsFactors = FALSE, check.names = FALSE)
fmt <- function(x, d = 1) formatC(x, format = "f", digits = d)
