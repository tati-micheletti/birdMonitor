# Renders the figure reference page (pdf_export/5_Figure_reference.Rmd) -> outputs/test4/5_Figure_reference.html.
# In Positron / RStudio: open this file and run it (Source), from any working folder inside the repository; it finds the repository by birdMonitor.Rproj.
# The page makes the small copies of new figures by itself. It reads outputs/test4/figures_fullreport (made by tools/makeResultFigures.R on EVE) and is written next to that folder,
# so that the click-to-enlarge links work.
root <- normalizePath(getwd(), winslash = "/")
while (!file.exists(file.path(root, "birdMonitor.Rproj")) && dirname(root) != root) root <- dirname(root)
if (!file.exists(file.path(root, "birdMonitor.Rproj"))) stop("Run this from a folder inside the birdMonitor repository (birdMonitor.Rproj not found above ", getwd(), ")")
setwd(file.path(root, "pdf_export"))                                     # the page and its helpers use paths relative to pdf_export/
pandoc <- file.path(Sys.getenv("LOCALAPPDATA"), "Programs", "Positron", "resources", "app", "quarto", "bin", "tools")
if (!nzchar(Sys.getenv("RSTUDIO_PANDOC")) && dir.exists(pandoc)) Sys.setenv(RSTUDIO_PANDOC = pandoc)
run <- Sys.getenv("BIRDMONITOR_RUNNAME", "test4")                                   # the run the page documents (BIRDMONITOR_RUNNAME; the clean run is v2)
rmarkdown::render("5_Figure_reference.Rmd", output_format = "html_document", output_dir = file.path(root, "outputs", run), quiet = TRUE)
cat("rendered ->", file.path(root, "outputs", run, "5_Figure_reference.html"), "\n")
