# Renderer for the 3,327 per-manifesto pages.
# Generates one .qmd per manifesto from the _template.qmd, parameterised with
# the doc_id and metadata. Quarto then renders all of them to HTML in parallel.
#
# Usage:
#   Rscript website/_render_manifestos.R [--sample 50]   # for dev: only 50
#   Rscript website/_render_manifestos.R                  # full corpus
suppressPackageStartupMessages({
  library(arrow); library(dplyr); library(purrr); library(stringr)
})

# Locate website/ directory whether invoked from website/ or project root
if (!file.exists("manifesto/_template.qmd")) {
  if (file.exists("website/manifesto/_template.qmd")) setwd("website")
  else stop("Cannot find website/manifesto/_template.qmd. Run from project root.")
}
source("_data.R")

args <- commandArgs(trailingOnly = TRUE)
sample_n <- NULL
if ("--sample" %in% args) {
  i <- which(args == "--sample")
  sample_n <- as.integer(args[i+1])
}

manifestos <- load_manifestos()
if (!is.null(sample_n)) {
  set.seed(42)
  manifestos <- manifestos |> slice_sample(n = sample_n)
  message("DEV MODE: rendering only ", sample_n, " manifestos")
}

# Quote each value for YAML
yq <- function(x) {
  if (is.na(x) || is.null(x)) return('""')
  x <- gsub('"', '\\"', as.character(x), fixed = TRUE)
  paste0('"', x, '"')
}

template <- readLines("manifesto/_template.qmd")
# Find params block — we replace each parameter
write_one <- function(row) {
  out <- template
  # Convert params (in YAML front-matter) to actual values
  out <- gsub('doc_id: ""', sprintf('doc_id: %s', yq(row$doc_id)), out, fixed = TRUE)
  out <- gsub('party: ""', sprintf('party: %s', yq(row$partyabbrev)), out, fixed = TRUE)
  out <- gsub('country: ""', sprintf('country: %s', yq(row$countryname)), out, fixed = TRUE)
  out <- gsub('year: ""', sprintf('year: %s', yq(as.character(row$year))), out, fixed = TRUE)
  out <- gsub('partyname: ""', sprintf('partyname: %s', yq(row$partyname)), out, fixed = TRUE)
  out <- gsub('language: ""', sprintf('language: %s', yq(row$language)), out, fixed = TRUE)
  out <- gsub('parfam: ""', sprintf('parfam: %s', yq(as.character(row$parfam))), out, fixed = TRUE)
  outpath <- file.path("manifesto", paste0(row$doc_id, ".qmd"))
  writeLines(out, outpath)
}

message("Writing ", nrow(manifestos), " manifesto .qmd files to website/manifesto/ ...")
for (i in seq_len(nrow(manifestos))) {
  write_one(manifestos[i, ])
  if (i %% 200 == 0) message("  ", i, " / ", nrow(manifestos))
}
message("Done. To build, run: quarto render website/")
