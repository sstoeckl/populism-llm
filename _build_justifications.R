# ============================================================
# _build_justifications.R — the models' free-text reasoning per block (poplib_v4)
#
# Each model returns, per chunk, one justification for the populism block, one for the populist
# ideology block and one for the liberalism block (schema fields pop_justification,
# pop_ideology_justification, lib_justification). They are model-written English text, not
# manifesto text. Guard: any run of 9 or more consecutive words that also occurs verbatim in the
# manifesto text is cut after its 8th word (our 8-word rule for public material).
# Reads the RESTRICTED raw files of the workbench; writes data/blocks/poplib_v4/justifications.parquet
# (doc_id, chunk_id, model, block, text, n_words, guarded).
# Usage (site root): Rscript _build_justifications.R
# ============================================================
suppressPackageStartupMessages({ library(arrow); library(dplyr); library(tidyr); library(purrr); library(stringr) })
stopifnot(file.exists("_quarto.yml"))
WB <- Sys.getenv("POPLLM_WORKBENCH", "")
if (!nzchar(WB)) { d <- normalizePath("."); repeat { if (file.exists(file.path(d, "R/1_Aggregation.R"))) break
  p <- dirname(d); if (p == d) stop("workbench not found"); d <- p }; WB <- d }
RAW <- c(sonnet = "raw_claude_rev2.parquet", gpt41mini = "raw_gpt41mini.parquet", gemini = "raw_gemini.parquet")
BLOCKS <- c(pop_justification = "populism", pop_ideology_justification = "ideology", lib_justification = "liberalism")

j <- map_dfr(names(RAW), function(m) {
  r <- read_parquet(file.path(WB, "data/CMP/v2026a", RAW[[m]]), col_select = c("doc_id_root", "chunk_id", all_of(names(BLOCKS))))
  r |> pivot_longer(all_of(names(BLOCKS)), names_to = "block", values_to = "text") |>
    transmute(doc_id = doc_id_root, chunk_id, model = m, block = unname(BLOCKS[block]), text = str_squish(text)) |>
    filter(!is.na(text), nzchar(text))
})

# ---- guard against verbatim manifesto runs ----------------------------------------------------
txt <- bind_rows(read_parquet(file.path(WB, "data/CMP/full_data_update_2026a.parquet"), col_select = c("doc_id", "text")),
                 read_parquet(file.path(WB, "data/CMP/full_data.parquet"), col_select = c("doc_id", "text"))) |>
  filter(!is.na(text)) |> distinct(doc_id, .keep_all = TRUE)
N <- 9L
tok <- function(s) { w <- str_split(str_to_lower(str_squish(s)), " ")[[1]]; w[nzchar(w)] }
grams <- function(w, n = N) if (length(w) < n) character() else vapply(seq_len(length(w) - n + 1), function(i) paste(w[i:(i + n - 1)], collapse = " "), "")
guard_doc <- function(texts, doc_text) {
  tg <- grams(tok(doc_text)); if (!length(tg)) return(list(texts = texts, guarded = rep(FALSE, length(texts))))
  tg <- unique(tg); guarded <- logical(length(texts))
  for (i in seq_along(texts)) {
    w <- str_split(str_squish(texts[i]), " ")[[1]]; lw <- str_to_lower(w)
    g <- grams(lw); hit <- which(g %in% tg)
    if (!length(hit)) next
    # cut each run after its 8th word: drop word positions 9..end of the run
    drop <- logical(length(w))
    for (h in hit) drop[(h + N - 1L)] <- TRUE          # the 9th word of each matching window
    # a window at h covers h..h+8; mark positions beyond the 8th of the maximal run
    runs <- split(hit, cumsum(c(1, diff(hit) != 1)))
    for (rn in runs) { s <- min(rn); e <- max(rn) + N - 1L; if (e - s + 1 > 8) drop[(s + 8L):e] <- TRUE }
    if (any(drop)) { w2 <- w; w2[drop] <- NA
      out <- paste(ifelse(is.na(w2), "[…]", w2), collapse = " ") |> str_replace_all("(\\[…\\] )+\\[…\\]", "[…]")
      texts[i] <- out; guarded[i] <- TRUE }
  }
  list(texts = texts, guarded = guarded)
}
j$guarded <- FALSE
for (d in unique(j$doc_id)) {
  t <- txt$text[match(d, txt$doc_id)]; if (is.na(t)) next
  idx <- which(j$doc_id == d); g <- guard_doc(j$text[idx], t)
  j$text[idx] <- g$texts; j$guarded[idx] <- g$guarded
}
j <- j |> mutate(n_words = str_count(text, "\\S+")) |> arrange(doc_id, block, model, chunk_id)
dir.create("data/blocks/poplib_v4", recursive = TRUE, showWarnings = FALSE)
write_parquet(j, "data/blocks/poplib_v4/justifications.parquet", compression = "zstd")
message(sprintf("justifications: %d rows (%d manifestos, %d guarded), median %d words",
                nrow(j), n_distinct(j$doc_id), sum(j$guarded), median(j$n_words)))
