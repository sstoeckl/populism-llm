# ============================================================
# _build_site_data.R  —  data layer of the website (v2026a)
#
# Reads ONLY public material:
#   <workbench>/data/CMP/v2026a_public/   redacted model output (quotes cut to 8 words, no
#                                         contexts), span-check flags, coverage   (R/72)
#   <workbench>/output/v2026a/website_data/   chain scores and metadata, no text  (R/60)
#   <workbench>/output/v2026a/spec_curve/, csv/, figures/   paper results           (R/41-R/44)
# and the block registry in registry/*.yml. Writes into data/ and analysis/assets/.
#
# The per-model and combined scores are recomputed from the public inputs with the chain's own
# aggregation (R/1_Aggregation.R, rule (a')) and must equal the chain baseline exactly; the
# script stops otherwise. So every number on the site is the paper's number, and every
# evidence quote shown as "counted" is one that entered the score.
#
# Usage (from the site root):  Rscript _build_site_data.R
# Workbench location: env POPLLM_WORKBENCH, else the nearest parent folder with R/1_Aggregation.R.
# ============================================================
suppressPackageStartupMessages({
  library(arrow); library(dplyr); library(tidyr); library(purrr); library(stringr)
  library(yaml); library(jsonlite)
})
stopifnot("run from the site root" = file.exists("_quarto.yml"))

find_wb <- function() {
  env <- Sys.getenv("POPLLM_WORKBENCH")
  if (nzchar(env)) return(normalizePath(env))
  d <- normalizePath(".")
  repeat {
    if (file.exists(file.path(d, "R", "1_Aggregation.R"))) return(d)
    p <- dirname(d); if (p == d) stop("workbench not found; set POPLLM_WORKBENCH"); d <- p
  }
}
WB  <- find_wb()
PUB <- file.path(WB, "data/CMP/v2026a_public")
WEB <- file.path(WB, "output/v2026a/website_data")
OUT <- file.path(WB, "output/v2026a")
message("workbench: ", WB)

# ---- chain aggregation on the public inputs ---------------------------------------------
source(file.path(WB, "R/1_Aggregation.R"))
PIPE_IN  <- PUB
V26_REV  <- c(claude = "rev2", gpt41mini = "", gemini = "")
v26_file <- function(kind, stem) {
  f <- file.path(PIPE_IN, sprintf("%s_%s%s.parquet", kind, stem,
                                  if (nzchar(V26_REV[[stem]])) paste0("_", V26_REV[[stem]]) else ""))
  if (!file.exists(f)) stop("input missing: ", f); f
}
cl     <- load_chunk_dims(dir = PUB)
within <- aggregate_within(cl, validation = "quote", statuses = "verified")
comb   <- combine_models(within, stat = "cwm", between = "mean")

base <- read_parquet(file.path(WEB, "manifesto_scores.parquet"))
chk <- comb |> select(doc_id, all_of(AGG_DIMS), IDEO) |>
  pivot_longer(-doc_id, values_to = "site") |>
  full_join(base |> select(doc_id, all_of(AGG_DIMS), IDEO = pop_ideology_direction) |>
              pivot_longer(-doc_id, values_to = "chain"), by = c("doc_id", "name"))
dev <- with(chk, ifelse(is.na(site) & is.na(chain), 0, abs(site - chain)))
if (any(is.na(dev)) || max(dev) > 1e-12)
  stop("site scores differ from the chain baseline (", sum(is.na(dev) | dev > 1e-12), " cells)")
message("check passed: public recomputation == chain baseline for ", nrow(base), " manifestos")

# ---- registry ---------------------------------------------------------------------------
reg_files <- sort(list.files("registry", "^[^_].*\\.yml$", full.names = TRUE))
blocks <- map(reg_files, read_yaml) |> (\(b) b[order(map_dbl(b, "order"))])()
cfg <- read_yaml("registry/_models.yml")
stopifnot(cfg$evidence_text %in% c("quote8", "context"))
dir.create("data", showWarnings = FALSE)
write_json(list(blocks = blocks, models = cfg$models, evidence_text = cfg$evidence_text, context_words = cfg$context_words,
                corpus = cfg$corpus, version = fromJSON(file.path(WEB, "version.json"))),
           "data/registry.json", auto_unbox = TRUE, pretty = TRUE)

# ---- block poplib_v4: scores and evidence ----------------------------------------------
B <- "data/blocks/poplib_v4"; dir.create(B, recursive = TRUE, showWarnings = FALSE)
scores <- bind_rows(
  within |> transmute(doc_id, dim, model, score = cwm, n_chunks),
  comb |> select(doc_id, all_of(AGG_DIMS), pop_ideology_direction = IDEO) |>
    pivot_longer(-doc_id, names_to = "dim", values_to = "score") |>
    filter(is.finite(score)) |> mutate(model = "combined", n_chunks = NA_integer_)) |>
  arrange(doc_id, dim, model)
write_parquet(scores, file.path(B, "scores.parquet"), compression = "zstd")

first_words <- function(x, n = 8L) {
  w <- str_split(x, "\\s+")
  out <- vapply(w, function(v) paste(head(v[nzchar(v)], n), collapse = " "), "")
  out[is.na(x)] <- NA_character_; out
}
quotes <- map_dfr(AGG_MODELS, function(m) {
  r <- read_parquet(v26_file("raw", AGG_FILE_STEM[[m]]), col_select = c("doc_id", ends_with("_quote")))
  r |> pivot_longer(-doc_id, names_to = "dim", values_to = "quote") |>
    mutate(dim = sub("_quote$", "", dim), model = m)
})
ev <- cl |> filter(!is.na(score) | !is.na(status)) |>
  left_join(quotes, by = c("doc_id", "dim", "model")) |>
  transmute(doc_id = doc_id_root, chunk_id, model, dim, score, status,
            quote = first_words(quote), quote_ok,
            counted = status %in% "verified" & !is.na(score) & quote_ok) |>
  arrange(doc_id, dim, model, chunk_id)
stopifnot("a quote longer than 8 words" = all(is.na(ev$quote) | lengths(str_split(ev$quote, "\\s+")) <= 8))
n_counted <- ev |> filter(counted) |> count(model, doc_id, dim)
stopifnot("counted evidence must match the chunks in the score" =
            nrow(inner_join(n_counted, within, by = c("model", "doc_id", "dim")) |> filter(n != n_chunks)) == 0,
          nrow(n_counted) == nrow(within))
ev_public <- ev                                   # 8-word quotes: the download file
if (cfg$evidence_text == "context") {
  # Context window from the RESTRICTED canonical raw files (see registry/_models.yml), and a
  # position pointer: where the quote sits in the manifesto text (share of characters).
  RAWDIR <- file.path(WB, "data/CMP/v2026a")
  STEM <- c(sonnet = "raw_claude_rev2.parquet", gpt41mini = "raw_gpt41mini.parquet", gemini = "raw_gemini.parquet")
  full <- map_dfr(AGG_MODELS, function(m) {
    r <- read_parquet(file.path(RAWDIR, STEM[[m]]), col_select = c("doc_id", ends_with("_quote"), ends_with("_context")))
    q <- r |> select(doc_id, ends_with("_quote")) |> pivot_longer(-doc_id, names_to = "dim", values_to = "quote_full") |>
      mutate(dim = sub("_quote$", "", dim))
    k <- r |> select(doc_id, ends_with("_context")) |> pivot_longer(-doc_id, names_to = "dim", values_to = "context") |>
      mutate(dim = sub("_context$", "", dim))
    inner_join(q, k, by = c("doc_id", "dim")) |> mutate(model = m)
  })
  NW <- cfg$context_words
  # Window of at most NW words: the quote (cut to NW words if longer) plus context words before
  # and after it, split as evenly as the context allows. Quotes not found in their context are
  # shown alone.
  window <- function(quote, context) {
    n <- length(quote); out <- character(n); pre <- character(n); post <- character(n)
    for (i in seq_len(n)) {
      q <- str_squish(quote[i]); qw <- str_split(q, " ")[[1]]
      out[i] <- paste(head(qw, NW), collapse = " ")
      cx <- str_squish(coalesce(context[i], ""))
      pos <- if (nzchar(cx)) stringi::stri_locate_first_fixed(cx, q)[1, 1] else NA
      room <- NW - length(qw)
      if (is.na(pos) || room <= 0) next
      before <- str_split(str_trim(substr(cx, 1, pos - 1)), " ")[[1]]; before <- before[nzchar(before)]
      after  <- str_split(str_trim(substr(cx, pos + nchar(q), nchar(cx))), " ")[[1]]; after <- after[nzchar(after)]
      nb <- min(length(before), ceiling(room / 2)); na_ <- min(length(after), room - nb)
      nb <- min(length(before), room - na_)
      pre[i]  <- paste(tail(before, nb), collapse = " ")
      post[i] <- paste(head(after, na_), collapse = " ")
    }
    tibble(q_show = out, ctx_pre = pre, ctx_post = post)
  }
  w <- full |> filter(!is.na(quote_full), nzchar(quote_full))
  w <- bind_cols(w |> select(doc_id, dim, model, quote_full), window(w$quote_full, w$context))
  stopifnot("context window above the cap" = all(str_count(paste(w$ctx_pre, w$q_show, w$ctx_post), "\\S+") <= NW))
  # position pointer in the manifesto text (2026-1 text for updated documents, else the June text)
  txt <- bind_rows(read_parquet(file.path(WB, "data/CMP/full_data_update_2026a.parquet"), col_select = c("doc_id", "text")),
                   read_parquet(file.path(WB, "data/CMP/full_data.parquet"), col_select = c("doc_id", "text"))) |>
    filter(!is.na(text)) |> distinct(doc_id, .keep_all = TRUE) |>
    mutate(text = str_squish(gsub("\u2022", "", text, fixed = TRUE)))
  w <- w |> mutate(root = sub("_ch[0-9]+$", "", doc_id))
  tx <- txt$text[match(w$root, txt$doc_id)]
  loc <- stringi::stri_locate_first_fixed(tx, str_squish(w$quote_full))[, 1]
  w$text_pos <- ifelse(is.na(loc), NA_real_, round(100 * loc / nchar(tx)))
  ev <- ev |> left_join(cl |> distinct(doc_id_chunk = doc_id, doc_id = doc_id_root, chunk_id), by = c("doc_id", "chunk_id")) |>
    left_join(w |> select(doc_id_chunk = doc_id, dim, model, q_show, ctx_pre, ctx_post, text_pos),
              by = c("doc_id_chunk", "dim", "model")) |>
    mutate(quote = coalesce(q_show, quote)) |> select(-doc_id_chunk, -q_show)
  message(sprintf("context windows: %d quotes, position found for %.1f%%", sum(!is.na(ev$ctx_pre)), 100 * mean(!is.na(ev$text_pos[!is.na(ev$quote)]))))
}
write_parquet(ev, file.path(B, "evidence.parquet"), compression = "zstd")
message(sprintf("poplib_v4: %d score rows, %d evidence rows (%d counted)", nrow(scores), nrow(ev), sum(ev$counted)))

# ---- manifestos (identifiers only; no CMP coding variables) -----------------------------
parfam_lbl <- unlist(cfg$parfam)
meta <- read_parquet(file.path(WEB, "manifestos_meta.parquet")) |>
  transmute(doc_id, countryname, partyname, partyabbrev = na_if(partyabbrev, ""), party = as.integer(party),
            date, year, token_count, parfam = unname(parfam_lbl[as.character(parfam)]),
            scored = doc_id %in% base$doc_id) |>
  left_join(read_parquet(file.path(WB, "data/CMP/full_data_2026a_meta.parquet"), col_select = c("doc_id", "pdf_url")) |>
              distinct(doc_id, .keep_all = TRUE) |>
              mutate(pdf_url = ifelse(is.na(pdf_url) | !nzchar(pdf_url), NA_character_, paste0(cfg$pdf_base, pdf_url))),
            by = "doc_id") |>
  distinct(doc_id, .keep_all = TRUE) |> arrange(doc_id)
write_parquet(meta, "data/manifestos.parquet", compression = "zstd")

# ---- downloads ----------------------------------------------------------------------------
D <- "data/download"; dir.create(D, showWarnings = FALSE)
dl <- base |> select(-any_of(c("rile", "parfam"))) |>
  left_join(meta |> select(doc_id, parfam), by = "doc_id") |> relocate(parfam, .after = partyabbrev)
write_parquet(dl, file.path(D, "manifesto_scores_v2026a.parquet"), compression = "zstd")
write.csv(dl, file.path(D, "manifesto_scores_v2026a.csv"), row.names = FALSE, na = "")
write_parquet(ev_public |> select(-quote_ok), file.path(D, "evidence_poplib_v4_v2026a.parquet"), compression = "zstd")

# ---- regression module: distinct specifications of the populism slope --------------------
sd <- read_parquet(file.path(WEB, "specs_distinct.parquet")) |> filter(estimand == "pop") |>
  select(validation, gemini_norm, gap_legs, parse_repaired, model_set, within_agg, between_agg,
         outcome, sample_key, fe_key, coef, se, t, p, n, is_baseline)
stopifnot(nrow(sd) == 20592L)
write.csv(sd |> mutate(across(c(coef, se, t), ~ signif(.x, 6)), p = signif(p, 4)),
          "data/specs_distinct_pop.csv", row.names = FALSE, na = "NA")
file.copy(file.path(WEB, "version.json"), "data/version.json", overwrite = TRUE)
file.copy(file.path(OUT, "csv", "40_model_provenance.csv"), "data/model_provenance.csv", overwrite = TRUE)
message("done: data/registry.json, data/blocks/, data/manifestos.parquet, data/download/, data/specs_distinct_pop.csv")
