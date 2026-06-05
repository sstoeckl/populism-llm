# Shared data-access helpers for the website.
# Sources all per-page R chunks via knitr's child mechanism or direct source().
# All paths relative to project root (one level above the website/ folder).
suppressPackageStartupMessages({
  library(arrow); library(dplyr); library(tidyr); library(stringr); library(purrr)
})

# Locate the SITE ROOT (the directory containing _quarto.yml).
# When rendering from website/, cwd is already the site root.
# When rendering a manifesto/*.qmd, cwd is website/manifesto — we drop one level.
.SITE_ROOT <- function() {
  cwd <- normalizePath(getwd())
  if (file.exists(file.path(cwd, "_quarto.yml"))) return(cwd)
  if (file.exists(file.path(cwd, "..", "_quarto.yml")))
    return(normalizePath(file.path(cwd, "..")))
  # Final fallback for `Rscript website/_render_manifestos.R` from project root
  if (file.exists(file.path(cwd, "website", "_quarto.yml")))
    return(normalizePath(file.path(cwd, "website")))
  stop("Could not locate site root from ", cwd)
}
SITE <- .SITE_ROOT()
# All data is now SELF-CONTAINED inside the website repo at website/data/
PROJ <- SITE

# ---- High-level dimension catalogue ----
V4_DIMS <- c("pop_anti_elitism","pop_people_centrism","pop_manichean","populism_overall",
             "pop_ideology_left","pop_ideology_right","pop_ideology_centrist","pop_ideology_overall",
             "lib_political","lib_social","lib_economic","lib_financial_market","liberalism_overall")

DIM_LABELS <- c(
  pop_anti_elitism      = "Anti-Elitism",
  pop_people_centrism   = "People-Centrism",
  pop_manichean         = "Manichaean Worldview",
  populism_overall      = "Populism (Overall)",
  pop_ideology_left     = "Ideology — Left",
  pop_ideology_right    = "Ideology — Right",
  pop_ideology_centrist = "Ideology — Centrist",
  pop_ideology_overall  = "Ideology (Right − Left)",
  lib_political         = "Political Liberalism",
  lib_social            = "Social Liberalism",
  lib_economic          = "Economic Liberalism",
  lib_financial_market  = "Financial-Market Liberalism",
  liberalism_overall    = "Liberalism (Overall)"
)

DIM_GROUP <- c(
  pop_anti_elitism      = "Populism", pop_people_centrism = "Populism",
  pop_manichean         = "Populism", populism_overall    = "Populism",
  pop_ideology_left     = "Ideology", pop_ideology_right  = "Ideology",
  pop_ideology_centrist = "Ideology", pop_ideology_overall= "Ideology",
  lib_political         = "Liberalism", lib_social         = "Liberalism",
  lib_economic          = "Liberalism", lib_financial_market= "Liberalism",
  liberalism_overall    = "Liberalism"
)

# Model registry: which file backs which model. Paths relative to SITE root.
MODEL_REGISTRY <- list(
  sonnet      = list(label  = "Claude Sonnet 4.6",
                     short  = "Sonnet",
                     family = "Anthropic",
                     raw    = "data/raw_sonnet.parquet"),
  gpt41mini   = list(label  = "GPT-4.1-mini",
                     short  = "gpt-4.1-mini",
                     family = "OpenAI",
                     raw    = "data/raw_gpt41mini.parquet"),
  gemini      = list(label  = "Gemini Flash (latest)",
                     short  = "Gemini",
                     family = "Google",
                     raw    = "data/raw_gemini.parquet")
)

# Load manifesto metadata. Source: website/data/manifestos_meta.parquet
# Pre-built from CMP full_data.parquet by data/_prepare.R, no text included.
load_manifestos <- function() {
  read_parquet(file.path(SITE, "data/manifestos_meta.parquet")) |>
    distinct(doc_id, .keep_all = TRUE)
}

# Available models: which exist on disk RIGHT NOW
available_models <- function() {
  keep <- names(MODEL_REGISTRY)[map_lgl(MODEL_REGISTRY, ~ file.exists(file.path(SITE, .x$raw)))]
  setNames(MODEL_REGISTRY[keep], keep)
}

# Per-model: per-manifesto verified-only mean score per dimension
load_model_agg <- function(model_id) {
  m <- MODEL_REGISTRY[[model_id]]; if (is.null(m)) stop("unknown model: ", model_id)
  if (!file.exists(file.path(SITE, m$raw))) return(NULL)
  raw <- read_parquet(file.path(SITE, m$raw))
  rows <- raw |> distinct(doc_id_root) |> rename(doc_id = doc_id_root)
  for (d in V4_DIMS) {
    sc <- paste0(d,"_score"); st <- paste0(d,"_status")
    if (!sc %in% names(raw)) next
    agg <- raw |>
      filter(.data[[st]] == "verified", !is.na(.data[[sc]])) |>
      group_by(doc_id_root) |>
      summarise(!!d := mean(.data[[sc]]), .groups = "drop") |>
      rename(doc_id = doc_id_root)
    rows <- left_join(rows, agg, by = "doc_id")
  }
  rows |> mutate(model = model_id, .before = 1)
}

# Load evidence (verified spans for a single manifesto across all models)
load_evidence <- function(doc_id_root) {
  out <- list()
  for (mid in names(MODEL_REGISTRY)) {
    m <- MODEL_REGISTRY[[mid]]
    if (!file.exists(file.path(SITE, m$raw))) next
    raw <- read_parquet(file.path(SITE, m$raw))
    sub <- raw |> filter(doc_id_root == !!doc_id_root)
    if (nrow(sub) == 0) next
    for (d in V4_DIMS) {
      qc <- paste0(d,"_quote"); cc <- paste0(d,"_context"); sc <- paste0(d,"_score"); st <- paste0(d,"_status")
      if (!qc %in% names(sub)) next
      for (i in seq_len(nrow(sub))) {
        if (is.na(sub[[qc]][i]) || !nzchar(sub[[qc]][i])) next
        out[[length(out)+1]] <- tibble(
          model = mid, dim_name = d, doc_id = sub$doc_id[i],
          chunk_id = sub$chunk_id[i],
          score = sub[[sc]][i], status = sub[[st]][i],
          quote = sub[[qc]][i], context = sub[[cc]][i] %||% NA_character_
        )
      }
    }
  }
  if (length(out) == 0) return(tibble())
  bind_rows(out)
}

# Score → low/mid/high band for badge colouring
score_band <- function(x) {
  ifelse(is.na(x) | !is.finite(x), "na",
  ifelse(x < 3.5, "low",
  ifelse(x < 6.5, "mid", "high")))
}
score_badge_html <- function(x) {
  band <- score_band(x)
  txt <- ifelse(is.na(x) | !is.finite(x), "–", sprintf("%.1f", x))
  sprintf('<span class="score-badge score-%s">%s</span>', band, txt)
}

# Highlight `quote` (substring) inside `context` text with <mark>
highlight_quote_in_context <- function(quote, context) {
  if (is.na(context) || !nzchar(context)) return("")
  if (is.na(quote) || !nzchar(quote)) return(htmltools::htmlEscape(context))
  pos <- stringi::stri_locate_first_fixed(context, quote)
  if (is.na(pos[1,"start"])) return(htmltools::htmlEscape(context))
  pre  <- substr(context, 1, pos[1,"start"] - 1)
  mid  <- substr(context, pos[1,"start"], pos[1,"end"])
  post <- substr(context, pos[1,"end"] + 1, nchar(context))
  paste0(htmltools::htmlEscape(pre),
         "<mark>", htmltools::htmlEscape(mid), "</mark>",
         htmltools::htmlEscape(post))
}

`%||%` <- function(a, b) if (is.null(a)) b else a
