# Build the paper's BASELINE manifesto-level score table as ONE tidy file.
#
# Output (committed to git — small):
#   data/manifesto_scores.parquet   one row per manifesto (doc_id)
#   data/manifesto_scores.csv       same, for non-R users
#
# Columns:
#   metadata      doc_id, countryname, partyname, partyabbrev, party,
#                 parfam, rile, date, year, token_count
#   baseline      <dim>            = cross-model mean (Sonnet, GPT-4.1-mini, Gemini)
#   per-model     <dim>_sonnet / _gpt41mini / _gemini
#
# Source: data/agg_long.parquet — the canonical per-(manifesto × model × dim)
# verified-only mean score that the website itself renders. Build it first with
#   Rscript data/_prepare.R      (fetch raw_*.parquet from Hugging Face)
#   Rscript data/_build_agg.R    (-> data/agg_long.parquet)
# The cross-model mean columns ARE the paper's headline populism / liberalism
# measures used in the regressions. Scores are 0–10.
suppressPackageStartupMessages({
  library(arrow); library(dplyr); library(tidyr); library(stringr)
})

# Resolve to website root
if (basename(getwd()) == "data") setwd("..")
stopifnot(file.exists("_quarto.yml"))
stopifnot(file.exists("data/agg_long.parquet"))  # run _prepare.R + _build_agg.R first

agg <- read_parquet("data/agg_long.parquet")     # doc_id, dim, score, model
DIMS <- c("pop_anti_elitism","pop_people_centrism","pop_manichean","populism_overall",
          "pop_ideology_left","pop_ideology_right","pop_ideology_centrist","pop_ideology_overall",
          "lib_political","lib_social","lib_economic","lib_financial_market","liberalism_overall")
DIMS <- DIMS[DIMS %in% unique(agg$dim)]

# Cross-model mean (the baseline)
baseline <- agg |>
  group_by(doc_id, dim) |>
  summarise(score = round(mean(score, na.rm = TRUE), 3), .groups = "drop") |>
  pivot_wider(names_from = dim, values_from = score)

# Per-model wide, suffixed (<dim>_<model>)
per_model <- agg |>
  mutate(col = paste0(dim, "_", model)) |>
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

# Column order: metadata, baseline dims, then per-model blocks
meta_cols  <- c("doc_id","countryname","partyname","partyabbrev","party",
                "parfam","rile","date","year","token_count")
model_cols <- unlist(lapply(c("sonnet","gpt41mini","gemini"),
                            function(m) paste0(DIMS, "_", m)))
model_cols <- model_cols[model_cols %in% names(out)]
out <- out |> select(all_of(meta_cols), all_of(DIMS), all_of(model_cols))

# mean(c(NA,NA,NA), na.rm=TRUE) → NaN; normalise to NA
out <- out |> mutate(across(where(is.numeric), ~ ifelse(is.nan(.), NA_real_, .)))

write_parquet(out, "data/manifesto_scores.parquet",
              compression = "zstd", compression_level = 9)
write.csv(out, "data/manifesto_scores.csv", row.names = FALSE, na = "")

cat(sprintf("Wrote data/manifesto_scores.{parquet,csv}: %d manifestos × %d cols (%.0f KB parquet)\n",
            nrow(out), ncol(out), file.size("data/manifesto_scores.parquet")/1024))
cat(sprintf("  populism_overall scored:  %d / %d manifestos\n",
            sum(!is.na(out$populism_overall)), nrow(out)))
cat(sprintf("  liberalism_overall scored: %d / %d manifestos\n",
            sum(!is.na(out$liberalism_overall)), nrow(out)))
