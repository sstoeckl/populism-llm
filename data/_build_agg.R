# Build a slim aggregate "long" parquet that party/manifesto pages can read
# fast (10 KB per page instead of 30 MB).
# Output: data/agg_long.parquet — one row per (doc_id × model × dim) verified
# mean score.
suppressPackageStartupMessages({
  library(arrow); library(dplyr); library(tidyr); library(purrr)
})
if (!file.exists("_quarto.yml")) {
  if (file.exists("website/_quarto.yml")) setwd("website")
}
source("_data.R")

models <- available_models()
out <- bind_rows(lapply(names(models), function(mid) {
  a <- load_model_agg(mid)
  if (is.null(a)) return(NULL)
  a |> select(doc_id, any_of(V4_DIMS)) |>
    pivot_longer(-doc_id, names_to = "dim", values_to = "score") |>
    filter(is.finite(score)) |>
    mutate(model = mid, score = round(score, 2))
}))
write_parquet(out, "data/agg_long.parquet",
              compression = "zstd", compression_level = 9)
cat(sprintf("Built data/agg_long.parquet: %d rows, %.1f KB\n",
            nrow(out), file.size("data/agg_long.parquet") / 1024))
