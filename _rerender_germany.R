# Re-materialize German party and manifesto qmd files (after Gemini data added).
suppressPackageStartupMessages({
  library(arrow); library(dplyr); library(purrr)
})
if (!file.exists("party/_template.qmd")) setwd("website")
source("_data.R")

meta <- load_manifestos() |> filter(countryname == "Germany")
parties <- meta |> distinct(party, partyabbrev, partyname, countryname, parfam)
cat("German parties:", nrow(parties), "  manifestos:", nrow(meta), "\n")

yq <- function(x) {
  if (is.na(x) || is.null(x)) return('""')
  x <- gsub('"', '\\"', as.character(x), fixed = TRUE)
  paste0('"', x, '"')
}

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

mtmp <- readLines("manifesto/_template.qmd")
for (i in seq_len(nrow(meta))) {
  r <- meta[i, ]
  out <- mtmp
  out <- gsub('doc_id: ""',    sprintf('doc_id: %s', yq(r$doc_id)),       out, fixed = TRUE)
  out <- gsub('party: ""',     sprintf('party: %s', yq(r$partyabbrev)),   out, fixed = TRUE)
  out <- gsub('country: ""',   sprintf('country: %s', yq(r$countryname)), out, fixed = TRUE)
  out <- gsub('year: ""',      sprintf('year: %s', yq(as.character(r$year))), out, fixed = TRUE)
  out <- gsub('partyname: ""', sprintf('partyname: %s', yq(r$partyname)), out, fixed = TRUE)
  out <- gsub('language: ""',  sprintf('language: %s', yq(r$language)),    out, fixed = TRUE)
  out <- gsub('parfam: ""',    sprintf('parfam: %s', yq(as.character(r$parfam))), out, fixed = TRUE)
  writeLines(out, file.path("manifesto", paste0(r$doc_id, ".qmd")))
}
cat("Wrote", nrow(parties), "party qmds and", nrow(meta), "manifesto qmds\n")
