# Generate all manifesto + party qmd files for FULL render.
suppressPackageStartupMessages({library(arrow); library(dplyr); library(purrr)})
if (!file.exists("party/_template.qmd")) setwd("website")
source("_data.R")

manifestos <- load_manifestos()
models <- available_models()
scored_ids <- character()
for (mid in names(models)) {
  raw <- read_parquet(file.path(SITE, models[[mid]]$raw), col_select = "doc_id_root")
  scored_ids <- c(scored_ids, unique(raw$doc_id_root))
}
scored_ids <- unique(scored_ids)
manifestos <- manifestos |> filter(doc_id %in% scored_ids)
cat("Manifests with at least one model score:", nrow(manifestos), "\n")

parties <- manifestos |> distinct(party, partyabbrev, partyname, countryname, parfam)
cat("Parties with at least one scored manifesto:", nrow(parties), "\n")

yq <- function(x) {
  if (is.na(x) || is.null(x)) return('""')
  x <- gsub('"', '\\"', as.character(x), fixed = TRUE)
  paste0('"', x, '"')
}

# Party qmds
ptmp <- readLines("party/_template.qmd")
for (i in seq_len(nrow(parties))) {
  r <- parties[i, ]
  out <- ptmp
  out <- gsub('party_id: ""',     sprintf('party_id: %s', yq(r$party)),       out, fixed = TRUE)
  out <- gsub('party_abbrev: ""', sprintf('party_abbrev: %s', yq(r$partyabbrev)), out, fixed = TRUE)
  out <- gsub('party_name: ""',   sprintf('party_name: %s', yq(r$partyname)), out, fixed = TRUE)
  out <- gsub('country: ""',      sprintf('country: %s', yq(r$countryname)),  out, fixed = TRUE)
  out <- gsub('parfam: ""',       sprintf('parfam: %s', yq(as.character(r$parfam))), out, fixed = TRUE)
  writeLines(out, file.path("party", paste0(r$party, ".qmd")))
}

# Manifesto qmds
mtmp <- readLines("manifesto/_template.qmd")
for (i in seq_len(nrow(manifestos))) {
  r <- manifestos[i, ]
  out <- mtmp
  out <- gsub('doc_id: ""',    sprintf('doc_id: %s', yq(r$doc_id)),       out, fixed = TRUE)
  out <- gsub('party: ""',     sprintf('party: %s', yq(r$partyabbrev)),   out, fixed = TRUE)
  out <- gsub('country: ""',   sprintf('country: %s', yq(r$countryname)), out, fixed = TRUE)
  out <- gsub('year: ""',      sprintf('year: %s', yq(as.character(r$year))), out, fixed = TRUE)
  out <- gsub('partyname: ""', sprintf('partyname: %s', yq(r$partyname)), out, fixed = TRUE)
  out <- gsub('language: ""',  sprintf('language: %s', yq(r$language)),    out, fixed = TRUE)
  out <- gsub('parfam: ""',    sprintf('parfam: %s', yq(as.character(r$parfam))), out, fixed = TRUE)
  writeLines(out, file.path("manifesto", paste0(r$doc_id, ".qmd")))
  if (i %% 500 == 0) cat("  ", i, " / ", nrow(manifestos), " manifesto qmds\n")
}
cat("DONE. Party qmds:", nrow(parties), "  Manifesto qmds:", nrow(manifestos), "\n")
