# Build the paper's BASELINE manifesto-level score table as ONE tidy file.
#
# Output (committed to git — small):
#   data/manifesto_scores.parquet   one row per manifesto (doc_id)
#   data/manifesto_scores.csv       same, for non-R users
#
# Columns:
#   metadata      doc_id, countryname, partyname, partyabbrev, party,
#                 parfam, rile, date, year, token_count
#   baseline      <dim>            = cross-model mean of the per-model
#                                    confidence-weighted within-manifesto means
#   per-model     <dim>_sonnet / _gpt41mini / _gemini
#
# AGGREGATION — matches the paper's headline / the spec-curve BASELINE cell
# (R/20_Spec_Curve_Compute.R):
#   within-manifesto: confidence-weighted mean over VERIFIED chunks,
#                     w = pmax(populism_confidence, 0.1)   ("cwm")
#   between-model:    plain mean across the three models    ("mean")
# Scores are 0–10. Source = the three raw per-chunk parquets fetched from HF by
# data/_prepare.R (raw_sonnet / raw_gpt41mini / raw_gemini).
suppressPackageStartupMessages({
  library(arrow); library(dplyr); library(tidyr); library(purrr); library(stringr)
})

# Resolve to website root
if (basename(getwd()) == "data") setwd("..")
stopifnot(file.exists("_quarto.yml"))

RAW <- c(sonnet    = "data/raw_sonnet.parquet",
         gpt41mini = "data/raw_gpt41mini.parquet",
         gemini    = "data/raw_gemini.parquet")
stopifnot(all(file.exists(RAW)))   # run data/_prepare.R first

DIMS <- c("pop_anti_elitism","pop_people_centrism","pop_manichean","populism_overall",
          "pop_ideology_overall","pop_ideology_left","pop_ideology_right","pop_ideology_centrist",
          "lib_political","lib_social","lib_economic","lib_financial_market","liberalism_overall")

# Per-model, per-manifesto confidence-weighted mean over verified chunks (cwm).
# Weight column is populism_confidence for every dimension, matching R/20 exactly.
model_cwm <- function(path, model_id) {
  raw <- read_parquet(path)
  rows <- raw |> distinct(doc_id_root) |> rename(doc_id = doc_id_root)
  for (d in DIMS) {
    sc <- paste0(d, "_score"); st <- paste0(d, "_status")
    if (!sc %in% names(raw)) next
    agg <- raw |>
      filter(.data[[st]] == "verified", !is.na(.data[[sc]])) |>
      group_by(doc_id_root) |>
      summarise(!!d := weighted.mean(.data[[sc]], w = pmax(populism_confidence, 0.1), na.rm = TRUE),
                .groups = "drop") |>
      rename(doc_id = doc_id_root)
    rows <- left_join(rows, agg, by = "doc_id")
  }
  rows |> mutate(model = model_id, .before = 1)
}

per_model_long <- imap_dfr(RAW, model_cwm) |>
  pivot_longer(all_of(DIMS), names_to = "dim", values_to = "score") |>
  filter(is.finite(score))

# Between-model: plain mean across models (the baseline cell)
baseline <- per_model_long |>
  group_by(doc_id, dim) |>
  summarise(score = round(mean(score, na.rm = TRUE), 3), .groups = "drop") |>
  pivot_wider(names_from = dim, values_from = score)

# Per-model wide, suffixed (<dim>_<model>)
per_model <- per_model_long |>
  mutate(col = paste0(dim, "_", model), score = round(score, 3)) |>
  select(doc_id, col, score) |>
  pivot_wider(names_from = col, values_from = score)

# Metadata
meta <- read_parquet("data/manifestos_meta.parquet") |>
  distinct(doc_id, .keep_all = TRUE) |>
  select(doc_id, countryname, partyname, partyabbrev, party,
         parfam, rile, date, year, token_count)

out <- meta |>
  inner_join(baseline,  by = "doc_id") |>
  left_join(per_model, by = "doc_id") |>
  arrange(countryname, party, year)

meta_cols  <- c("doc_id","countryname","partyname","partyabbrev","party",
                "parfam","rile","date","year","token_count")
model_cols <- unlist(lapply(c("sonnet","gpt41mini","gemini"),
                            function(m) paste0(DIMS, "_", m)))
model_cols <- model_cols[model_cols %in% names(out)]
# Ideology direction in [-1,+1], as in the paper (R/4_Stats pop_ideology_overall2):
# (right - left) / (right + left + centrist), on the cross-model-mean cwm scores.
out <- out |>
  mutate(pop_ideology_direction = (pop_ideology_right - pop_ideology_left) /
           (pop_ideology_right + pop_ideology_left + pop_ideology_centrist))

out <- out |> select(all_of(meta_cols), all_of(DIMS), pop_ideology_direction, all_of(model_cols))
out <- out |> mutate(across(where(is.numeric), ~ ifelse(is.nan(.), NA_real_, .)))

write_parquet(out, "data/manifesto_scores.parquet",
              compression = "zstd", compression_level = 9)
write.csv(out, "data/manifesto_scores.csv", row.names = FALSE, na = "")

cat(sprintf("Wrote data/manifesto_scores.{parquet,csv}: %d manifestos × %d cols (%.0f KB parquet)\n",
            nrow(out), ncol(out), file.size("data/manifesto_scores.parquet")/1024))
cat(sprintf("  aggregation = cwm (within) + mean (between) — matches paper headline\n"))
cat(sprintf("  populism_overall scored:  %d / %d\n", sum(!is.na(out$populism_overall)), nrow(out)))
cat(sprintf("  liberalism_overall scored: %d / %d\n", sum(!is.na(out$liberalism_overall)), nrow(out)))
