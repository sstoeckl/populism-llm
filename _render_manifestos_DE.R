# Generate manifesto qmd files for German parties only.
# Use existing _template.qmd from manifesto/.
suppressPackageStartupMessages({
  library(arrow); library(dplyr); library(purrr)
})
if (!file.exists("manifesto/_template.qmd")) setwd("website")
source("_data.R")

manifestos <- load_manifestos() |> filter(countryname == "Germany")
models <- available_models()
scored_ids <- character()
for (mid in names(models)) {
  raw <- read_parquet(file.path(SITE, models[[mid]]$raw), col_select = "doc_id_root")
  scored_ids <- c(scored_ids, unique(raw$doc_id_root))
}
manifestos <- manifestos |> filter(doc_id %in% unique(scored_ids))
cat("German manifestos to render:", nrow(manifestos), "\n")

yq <- function(x) {
  if (is.na(x) || is.null(x)) return('""')
  x <- gsub('"', '\\"', as.character(x), fixed = TRUE)
  paste0('"', x, '"')
}
template <- readLines("manifesto/_template.qmd")

for (i in seq_len(nrow(manifestos))) {
  r <- manifestos[i, ]
  out <- template
  out <- gsub('doc_id: ""',    sprintf('doc_id: %s', yq(r$doc_id)), out, fixed = TRUE)
  out <- gsub('party: ""',     sprintf('party: %s', yq(r$partyabbrev)), out, fixed = TRUE)
  out <- gsub('country: ""',   sprintf('country: %s', yq(r$countryname)), out, fixed = TRUE)
  out <- gsub('year: ""',      sprintf('year: %s', yq(as.character(r$year))), out, fixed = TRUE)
  out <- gsub('partyname: ""', sprintf('partyname: %s', yq(r$partyname)), out, fixed = TRUE)
  out <- gsub('language: ""',  sprintf('language: %s', yq(r$language)), out, fixed = TRUE)
  out <- gsub('parfam: ""',    sprintf('parfam: %s', yq(as.character(r$parfam))), out, fixed = TRUE)
  writeLines(out, file.path("manifesto", paste0(r$doc_id, ".qmd")))
}
cat("Done — wrote", nrow(manifestos), "qmd files\n")
