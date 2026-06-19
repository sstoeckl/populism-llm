# Render per-party qmd files. One page per unique CMP party_id that has at
# least one scored manifesto. Usage:
#   Rscript _render_parties.R              # all eligible parties
#   Rscript _render_parties.R --sample 20  # dev: 20 parties only
suppressPackageStartupMessages({
  library(arrow); library(dplyr); library(purrr); library(stringr)
})
if (!file.exists("party/_template.qmd")) {
  if (file.exists("website/party/_template.qmd")) setwd("website")
  else stop("Cannot find party/_template.qmd")
}
source("_data.R")

args <- commandArgs(trailingOnly = TRUE)
sample_n <- NULL
if ("--sample" %in% args) sample_n <- as.integer(args[which(args == "--sample") + 1])

manifestos <- load_manifestos()
# Restrict to parties with at least one scored manifesto in any model
models <- available_models()
scored_doc_ids <- character()
for (mid in names(models)) {
  raw <- read_parquet(file.path(SITE, models[[mid]]$raw), col_select = "doc_id_root")
  scored_doc_ids <- c(scored_doc_ids, unique(raw$doc_id_root))
}
scored_doc_ids <- unique(scored_doc_ids)
scored_parties <- manifestos |> filter(doc_id %in% scored_doc_ids) |>
  distinct(party) |> pull(party)
parties <- manifestos |>
  filter(party %in% scored_parties) |>
  group_by(party) |>
  summarise(
    party_abbrev = na.omit(partyabbrev)[1] %||% "",
    party_name   = na.omit(partyname)[1]   %||% "",
    country      = na.omit(countryname)[1] %||% "",
    parfam       = as.character(na.omit(parfam))[1] %||% "",
    .groups = "drop")
cat("Parties to render:", nrow(parties), "\n")
if (!is.null(sample_n)) {
  set.seed(42); parties <- parties |> slice_sample(n = sample_n)
  cat("DEV MODE: sampling", sample_n, "parties\n")
}

yq <- function(x) {
  if (is.na(x) || is.null(x)) return('""')
  x <- gsub('"', '\\"', as.character(x), fixed = TRUE)
  paste0('"', x, '"')
}

template <- readLines("party/_template.qmd")
for (i in seq_len(nrow(parties))) {
  r <- parties[i, ]
  out <- template
  out <- gsub('party_id: ""',     sprintf('party_id: %s', yq(r$party)),       out, fixed = TRUE)
  out <- gsub('party_abbrev: ""', sprintf('party_abbrev: %s', yq(r$party_abbrev)), out, fixed = TRUE)
  out <- gsub('party_name: ""',   sprintf('party_name: %s', yq(r$party_name)), out, fixed = TRUE)
  out <- gsub('country: ""',      sprintf('country: %s', yq(r$country)),       out, fixed = TRUE)
  out <- gsub('parfam: ""',       sprintf('parfam: %s', yq(r$parfam)),         out, fixed = TRUE)
  writeLines(out, file.path("party", paste0(r$party, ".qmd")))
  if (i %% 50 == 0) cat("  ", i, " / ", nrow(parties), "\n")
}
cat("Done.\n")

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
