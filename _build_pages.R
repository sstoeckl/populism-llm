# ============================================================
# _build_pages.R  —  writes the manifesto, party and country pages (v2026a)
#
# Pages are plain Markdown with embedded HTML/JSON; no R runs at render time, so `quarto render`
# only converts them (fast, and the pages show exactly the numbers written here).
# Everything is driven by data/registry.json (built by _build_site_data.R from registry/*.yml):
# each attribute block gets its own section on every page, so a new block needs no code change.
#
# Usage (site root):  Rscript _build_pages.R [--sample N]
# ============================================================
suppressPackageStartupMessages({
  library(arrow); library(dplyr); library(tidyr); library(purrr); library(stringr)
  library(jsonlite); library(htmltools); library(yaml)
})
stopifnot(file.exists("_quarto.yml"), file.exists("data/registry.json"))
args <- commandArgs(trailingOnly = TRUE)
SAMPLE <- if ("--sample" %in% args) as.integer(args[which(args == "--sample") + 1]) else NA_integer_
ONLY   <- if ("--only" %in% args) str_split(args[which(args == "--only") + 1], ",")[[1]] else character()   # manifesto ids; writes only those pages

REG    <- fromJSON("data/registry.json", simplifyVector = FALSE)
MODELS <- REG$models
MSHORT <- setNames(map_chr(MODELS, "short"), map_chr(MODELS, "id"))
MCOL   <- setNames(map_chr(MODELS, "colour"), map_chr(MODELS, "id"))
meta   <- read_parquet("data/manifestos.parquet")
VERSION <- REG$version

# ---- blocks: dimension tables and data ----------------------------------------------------
blk <- map(REG$blocks, function(b) {
  dims <- map_dfr(c(b$dims, b$derived), ~ tibble(id = .x$id, group = .x$group, label = .x$label,
                                                  min = .x$min, max = .x$max, description = .x$description))
  dims$derived <- dims$id %in% map_chr(b$derived, "id")
  dims$group_label <- unname(setNames(map_chr(b$groups, "label"), map_chr(b$groups, "id"))[dims$group])
  dims <- dims |> mutate(.g = match(group, map_chr(b$groups, "id")), .o = row_number()) |>
    arrange(.g, derived, .o) |> select(-.g, -.o)          # derived dims at the end of their group
  dir <- file.path("data/blocks", b$id)
  sc <- read_parquet(file.path(dir, "scores.parquet"))
  ev <- if (file.exists(file.path(dir, "evidence.parquet"))) read_parquet(file.path(dir, "evidence.parquet")) else NULL
  js <- if (file.exists(file.path(dir, "justifications.parquet"))) read_parquet(file.path(dir, "justifications.parquet")) else NULL
  list(b = b, dims = dims, scores = sc, ev_split = if (!is.null(ev)) split(ev, ev$doc_id) else list(),
       js_split = if (!is.null(js)) split(js, js$doc_id) else list(), sc_split = split(sc, sc$doc_id))
})
names(blk) <- map_chr(REG$blocks, "id")
scored_ids <- sort(unique(c(unlist(map(blk, ~ unique(.x$scores$doc_id))), meta$doc_id[meta$scored])))
docs <- meta |> filter(doc_id %in% scored_ids) |> arrange(doc_id)
if (!is.na(SAMPLE)) {
  # dev: a sample of whole parties (so party pages are complete) plus their countries
  set.seed(42); keep_p <- sample(unique(docs$party), SAMPLE); docs <- docs |> filter(party %in% keep_p)
}
if (length(ONLY)) docs <- docs |> filter(doc_id %in% ONLY)
message(sprintf("pages: %d manifestos, %d parties, %d countries", nrow(docs), n_distinct(docs$party), n_distinct(docs$countryname)))

# reference means of the combined score (all scored manifestos, and per country)
refs <- map(blk, function(x) {
  cmb <- x$scores |> filter(model == "combined") |> left_join(meta |> select(doc_id, countryname), by = "doc_id")
  list(global = cmb |> group_by(dim) |> summarise(m = mean(score), .groups = "drop"),
       country = cmb |> group_by(countryname, dim) |> summarise(m = mean(score), .groups = "drop"))
})

# ---- helpers ---------------------------------------------------------------------------------
esc <- function(x) htmlEscape(ifelse(is.na(x), "", as.character(x)))
fmt <- function(x, d = 1) ifelse(is.na(x) | !is.finite(x), "–", formatC(x, format = "f", digits = d))
badge <- function(x, mn = 0, mx = 10) {
  if (is.na(x) || !is.finite(x)) return('<span class="score-badge score-na">–</span>')
  z <- (x - mn) / (mx - mn)
  band <- if (z < 0.35) "low" else if (z < 0.65) "mid" else "high"
  sprintf('<span class="score-badge score-%s">%s</span>', band, fmt(x, if (mx - mn <= 2) 2 else 1))
}
front <- function(title, subtitle, extra = list()) {
  y <- c(list(title = title, subtitle = subtitle), extra)
  paste0("---\n", as.yaml(y, line.sep = "\n", handlers = list(logical = function(x) {
    v <- ifelse(x, "true", "false"); class(v) <- "verbatim"; v })), "---\n")
}
html_block <- function(...) paste0("\n```{=html}\n", paste0(..., collapse = ""), "\n```\n")
country_file <- function(cn) cn                                   # page name = country name (as before)
country_href <- function(cn, up = "../") paste0(up, "country/", URLencode(country_file(cn), reserved = TRUE), ".html")
party_label <- function(abbrev, name) ifelse(is.na(abbrev) | abbrev == "", str_trunc(name, 24), abbrev)
yr <- function(d) format(as.Date(d), "%Y")
write_page <- function(path, txt) {
  tmp <- paste0(path, ".tmp"); writeLines(txt, tmp, useBytes = TRUE); file.rename(tmp, path)
}
CTX <- identical(REG$evidence_text, "context")
holistic_note <- paste0(
  '::: {.callout-warning}\n',
  "## How to read this page\n\n",
  "**The scores are holistic judgements.** Each model read the whole manifesto text (in chunks of up to ",
  "20,000 tokens) and rated every dimension from the text as a whole. The passages quoted further down are ",
  "**examples the model cited**, not the basis of the score: a score that rests on two paragraphs cannot be ",
  "reduced to a few words, and a quoted passage alone will often look too weak, or too strong, for the number ",
  "next to it. Read the models' own explanations first; they state the reasoning behind each block of scores. ",
  "The quotes then show where in the text the models looked.\n:::\n")
text_note <- paste0(
  '::: {.callout-note appearance="simple"}\n',
  if (CTX) sprintf("**Evidence shown here:** the quote each model cited (highlighted) with a few words of its surrounding passage, at most %d words in all, and where in the manifesto it appears. ", as.integer(REG$context_words))
  else "**Evidence shown here:** the first 8 words of each quote the model cited, no surrounding text. ",
  "The manifesto texts are © their authors and distributed by the ",
  "[Manifesto Project (WZB)](https://manifesto-project.wzb.eu/); see above for how to obtain the full text. ",
  "A quote marked *counted* entered the score: the model rated its evidence as verified and the quote was found ",
  "verbatim in the manifesto.\n:::\n")

# ---- manifesto pages ---------------------------------------------------------------------------
BLOCK_LBL <- c(populism = "Populism", ideology = "Populist ideology", liberalism = "Liberalism")
justification_html <- function(x, d) {
  js <- x$js_split[[d]]; if (is.null(js) || !nrow(js)) return("<p><em>No explanations recorded.</em></p>")
  mods <- intersect(unlist(x$b$models), unique(js$model)); multi <- n_distinct(js$chunk_id) > 1
  out <- character()
  for (bk in names(BLOCK_LBL)) {
    jb <- js |> filter(block == bk); if (!nrow(jb)) next
    items <- map_chr(mods, function(m) {
      jm <- jb |> filter(model == m) |> arrange(chunk_id); if (!nrow(jm)) return("")
      paras <- map_chr(seq_len(nrow(jm)), function(i) sprintf("<p>%s%s</p>",
        if (multi) sprintf("<span class='ev-meta'>chunk %d · </span>", jm$chunk_id[i]) else "", esc(jm$text[i])))
      sprintf("<div class='just-model'><div class='just-head' style='border-color:%s'><span class='ev-tag' style='border-color:%s'>%s</span></div>%s</div>",
              MCOL[m], MCOL[m], esc(MSHORT[m]), paste(paras, collapse = ""))
    })
    out <- c(out, sprintf("<h4>%s</h4><div class='just-grid'>%s</div>", esc(BLOCK_LBL[[bk]]), paste(items, collapse = "")))
  }
  paste(out, collapse = "\n")
}
score_table <- function(x, d, cn) {
  sc <- x$sc_split[[d]]; if (is.null(sc)) return("<p><em>Not scored in this block.</em></p>")
  mods <- intersect(c("combined", unlist(x$b$models)), unique(sc$model))
  gref <- refs[[x$b$id]]$global; cref <- refs[[x$b$id]]$country |> filter(countryname == cn)
  head <- paste0("<th>Dimension</th>", paste0("<th class='num'>", esc(MSHORT[mods]), "</th>", collapse = ""),
                 "<th class='num ref'>", esc(cn), " mean</th><th class='num ref'>All mean</th>")
  rows <- character(); grp <- ""
  for (i in seq_len(nrow(x$dims))) {
    dm <- x$dims[i, ]
    if (dm$group_label != grp) { grp <- dm$group_label
      rows <- c(rows, sprintf("<tr class='grp'><td colspan='%d'>%s</td></tr>", length(mods) + 3, esc(grp))) }
    cells <- map_chr(mods, function(m) { v <- sc$score[sc$model == m & sc$dim == dm$id]
      paste0("<td class='num'>", badge(if (length(v)) v else NA, dm$min, dm$max), "</td>") })
    rv <- function(t) { v <- t$m[t$dim == dm$id]; fmt(if (length(v)) v else NA, if (dm$max - dm$min <= 2) 2 else 1) }
    rows <- c(rows, sprintf("<tr><td title='%s'>%s</td>%s<td class='num ref'>%s</td><td class='num ref'>%s</td></tr>",
                            esc(dm$description), esc(dm$label), paste(cells, collapse = ""), rv(cref), rv(gref)))
  }
  paste0("<table class='score-table'><thead><tr>", head, "</tr></thead><tbody>", paste(rows, collapse = ""), "</tbody></table>")
}

evidence_html <- function(x, d) {
  ev <- x$ev_split[[d]]; if (is.null(ev) || !nrow(ev)) return("<p><em>No evidence records.</em></p>")
  out <- character()
  for (i in which(!x$dims$derived)) {
    dm <- x$dims[i, ]; e <- ev |> filter(dim == dm$id)
    if (!nrow(e)) next
    withq <- e |> filter(!is.na(quote), nzchar(quote)) |> arrange(desc(counted), model, chunk_id)
    summ <- e |> group_by(model) |> summarise(k = sum(counted), n = n(), .groups = "drop") |>
      mutate(t = sprintf("%s %d/%d", MSHORT[model], k, n)) |> pull(t) |> paste(collapse = " · ")
    items <- if (nrow(withq)) paste0(map_chr(seq_len(nrow(withq)), function(j) {
      r <- withq[j, ]
      why <- if (r$counted) "<span class='ev-ok'>counted</span>" else if (!identical(r$status, "verified"))
        sprintf("<span class='ev-no'>not counted: status %s</span>", esc(r$status)) else
        "<span class='ev-no'>not counted: quote not found verbatim</span>"
      txt <- if (CTX && "ctx_pre" %in% names(r) && !is.na(r$ctx_pre))
        sprintf("<span class='ev-ctx'>%s%s <mark>%s</mark> %s%s</span>",
                if (nzchar(r$ctx_pre)) "… " else "", esc(r$ctx_pre), esc(r$quote), esc(r$ctx_post), if (nzchar(r$ctx_post)) " …" else "")
      else sprintf("<q>%s%s</q>", esc(r$quote), if (str_count(r$quote, "\\S+") >= 8) " …" else "")
      where <- if ("text_pos" %in% names(r) && !is.na(r$text_pos)) sprintf(" · at about %d%% of the text", as.integer(r$text_pos)) else ""
      sprintf("<li class='ev %s'><span class='ev-tag' style='border-color:%s'>%s</span> <span class='ev-meta'>chunk %s · score %s%s</span> %s<br>%s</li>",
              if (r$counted) "ev-counted" else "ev-not", MCOL[r$model], esc(MSHORT[r$model]), r$chunk_id,
              fmt(r$score, 0), where, why, txt)
    }), collapse = "") else "<li><em>no quote</em></li>"
    out <- c(out, sprintf("<details class='ev-dim'><summary><b>%s</b> <span class='ev-sum'>counted chunks: %s</span></summary><ul class='ev-list'>%s</ul></details>",
                          esc(dm$label), esc(summ), items))
  }
  paste(out, collapse = "\n")
}

plot_json <- function(x, d) {
  sc <- x$sc_split[[d]]; if (is.null(sc)) return(NULL)
  dd <- x$dims |> filter(!derived, min == 0, max == 10)
  sc |> filter(dim %in% dd$id) |>
    transmute(score = round(score, 2), dim_lbl = dd$label[match(dim, dd$id)],
              model_lbl = unname(MSHORT[model]), group = dd$group_label[match(dim, dd$id)])
}

write_manifesto <- function(r) {
  d <- r$doc_id; pl <- party_label(r$partyabbrev, r$partyname)
  body <- c(front(sprintf("%s · %s %s", pl, r$countryname, yr(r$date)),
                  sprintf("%s · manifesto %s", r$partyname, d),
                  list(`page-layout` = "full", toc = TRUE, `toc-depth` = 2, search = FALSE)),   # keep the search index small
    html_block(sprintf(
      "<div class='manifesto-meta'><span class='item'><b>Country</b> <a href='%s'>%s</a></span> · <span class='item'><b>Party</b> <a href='../party/%s.html'>%s</a> (%s)</span> · <span class='item'><b>Date</b> %s</span> · <span class='item'><b>Party family</b> %s</span> · <span class='item'><b>Tokens</b> %s</span> · <span class='item'><b>Manifesto id</b> <code>%s</code></span></div><p class='cmp-link'>%s</p>",
      country_href(r$countryname), esc(r$countryname), r$party, esc(pl), esc(r$partyname),
      format(as.Date(r$date), "%B %Y"), esc(r$parfam), format(r$token_count, big.mark = ","), d,
      sprintf(paste0("&#128196; <b>Full text:</b> the scored text is the Manifesto Corpus version %s, key <code>%s</code>, ",
                     "available through the <a href='https://manifesto-project.wzb.eu/information/documents/api' target='_blank' rel='noopener'>Manifesto Project API</a> ",
                     "(free registration), e.g. in R: <code>manifestoR::mp_corpus(data.frame(party = %s, date = %s))</code>. ",
                     "The position given with each quote (&ldquo;at about N%% of the text&rdquo;) refers to that text."),
              "2026-1", d, r$party, sub("^[0-9]+_", "", d)))),
    holistic_note)
  for (x in blk) {
    if (is.null(x$sc_split[[d]]) && is.null(x$ev_split[[d]])) next
    pj <- plot_json(x, d)
    body <- c(body, sprintf("\n## %s\n\n%s\n", x$b$label, x$b$description %||% ""),
      "\n### What the models say about this manifesto\n\nEach model's own explanation of its scores, one per block of dimensions, written together with the scores.\n",
      html_block(justification_html(x, d)),
      "\n### Scores\n", html_block(score_table(x, d, r$countryname)),
      if (!is.null(pj) && nrow(pj)) html_block(sprintf(
        "<div id='plot-%s'></div><script src='../assets/manifesto-plot.js'></script><script>window.addEventListener('DOMContentLoaded',()=>renderManifestoPlot('plot-%s',%s,{dimOrder:%s}));</script>",
        x$b$id, x$b$id, toJSON(pj, dataframe = "rows", auto_unbox = TRUE),
        toJSON(x$dims$label[!x$dims$derived], auto_unbox = TRUE))),
      "\n### Passages the models cited\n\nClick a dimension to see the passage each model cited for it; counts are counted chunks / chunks with a record.\n",
      text_note, html_block(evidence_html(x, d)))
  }
  body <- c(body, sprintf("\n---\n\n<small>Data version %s · %s · scores as in Rode & Stöckl (2026). [How the scores are built](../methodology.qmd) · [Download](../download.qmd)</small>\n",
                          VERSION$baseline_version, VERSION$corpus))
  write_page(file.path("manifesto", paste0(d, ".qmd")), paste(body, collapse = "\n"))
}

# ---- party pages -------------------------------------------------------------------------------
write_party <- function(p, dd) {
  r1 <- dd[nrow(dd), ]; pl <- party_label(r1$partyabbrev, r1$partyname); cn <- r1$countryname
  body <- c(front(sprintf("%s", r1$partyname), sprintf("%s%s · all scored manifestos", if (!is.na(r1$partyabbrev)) paste0(r1$partyabbrev, " · ") else "", cn),
                  list(`page-layout` = "full", toc = TRUE)),
    html_block(sprintf("<div class='manifesto-meta'><span class='item'><b>Country</b> <a href='%s'>%s</a></span> · <span class='item'><b>Party family</b> %s</span> · <span class='item'><b>CMP party code</b> %s</span> · <span class='item'><b>Scored manifestos</b> %d (%s–%s)</span></div>",
                       country_href(cn), esc(cn), esc(r1$parfam), p, nrow(dd), yr(min(dd$date)), yr(max(dd$date)))))
  for (x in blk) {
    sc <- bind_rows(x$sc_split[dd$doc_id]); if (!nrow(sc)) next
    hd <- x$dims |> filter(id %in% c(unlist(x$b$headline), x$dims$id[x$dims$group == "liberalism"])) |> distinct(id, .keep_all = TRUE)
    rows <- sc |> filter(dim %in% hd$id) |> left_join(dd |> select(doc_id, date), by = "doc_id") |>
      transmute(year = as.numeric(format(as.Date(date), "%Y")) + (as.numeric(format(as.Date(date), "%m")) - 1) / 12,
                dim, score = round(score, 3), model)
    rf <- refs[[x$b$id]]
    rj <- setNames(map(hd$id, function(i) list(global = rf$global$m[rf$global$dim == i][1],
                                                country = rf$country$m[rf$country$dim == i & rf$country$countryname == cn][1])), hd$id)
    cmb <- sc |> filter(model == "combined") |> select(doc_id, dim, score) |> pivot_wider(names_from = dim, values_from = score)
    tcols <- hd$id
    trs <- map_chr(seq_len(nrow(dd)), function(j) {
      dj <- dd[j, ]; v <- cmb[cmb$doc_id == dj$doc_id, ]
      cells <- map_chr(seq_along(tcols), function(k) { val <- if (nrow(v) && tcols[k] %in% names(v)) v[[tcols[k]]] else NA
        sprintf("<td class='num' data-v='%s'>%s</td>", ifelse(is.na(val), "", val), badge(val, hd$min[k], hd$max[k])) })
      sprintf("<tr><td data-v='%s'>%s</td><td><a href='../manifesto/%s.html'>%s</a></td>%s</tr>",
              dj$date, format(as.Date(dj$date), "%b %Y"), dj$doc_id, dj$doc_id, paste(cells, collapse = ""))
    })
    tbl <- sprintf("<table class='score-table sortable'><thead><tr><th>Date</th><th>Manifesto (evidence)</th>%s</tr></thead><tbody>%s</tbody></table>",
                   paste0("<th class='num' title='", esc(hd$description), "'>", esc(hd$label), "</th>", collapse = ""), paste(trs, collapse = ""))
    body <- c(body, sprintf("\n## %s\n", x$b$label), "\n### Over time\n",
      html_block(sprintf("<div id='pp-%s'></div><script src='../assets/party-plot.js'></script><script>window.addEventListener('DOMContentLoaded',()=>renderPartyPlot('pp-%s',%s,%s,%s,%s,%s));</script>",
        x$b$id, x$b$id, toJSON(rows, dataframe = "rows"),
        toJSON(hd |> select(id, label, min, max), dataframe = "rows"),
        toJSON(map(MODELS, ~ .x[c("id", "short", "colour")]), auto_unbox = TRUE),
        toJSON(rj, auto_unbox = TRUE, na = "null"), toJSON(cn, auto_unbox = TRUE))),
      "\n### Manifestos\n\nCross-model scores (the paper's values); click a manifesto for the per-model scores and the evidence.\n",
      html_block(tbl))
  }
  write_page(file.path("party", paste0(p, ".qmd")), paste(body, collapse = "\n"))
}

# ---- country pages -----------------------------------------------------------------------------
write_country <- function(cn, dd) {
  body <- c(front(cn, sprintf("%d scored manifestos · %d parties · %s–%s", nrow(dd), n_distinct(dd$party), yr(min(dd$date)), yr(max(dd$date))),
                  list(`page-layout` = "full", toc = TRUE)))
  for (x in blk) {
    sc <- bind_rows(x$sc_split[dd$doc_id]) |> filter(model == "combined"); if (!nrow(sc)) next
    hd <- x$dims |> filter(id %in% c(unlist(x$b$headline), x$dims$id[x$dims$group == "liberalism"])) |> distinct(id, .keep_all = TRUE)
    wide <- sc |> filter(dim %in% hd$id) |> select(doc_id, dim, score) |> pivot_wider(names_from = dim, values_from = score) |>
      left_join(dd |> select(doc_id, party, partyabbrev, partyname, date), by = "doc_id") |>
      mutate(year = as.integer(format(as.Date(date), "%Y")), label = party_label(partyabbrev, partyname)) |> select(-date)
    multi <- wide |> count(party) |> filter(n >= 2) |> pull(party)
    spec <- setNames(map(seq_len(nrow(hd)), ~ list(label = hd$label[.x], min = hd$min[.x], max = hd$max[.x])), hd$id)
    ps <- wide |> group_by(party) |> arrange(year, .by_group = TRUE) |>
      summarise(label = last(label), name = last(partyname), n = n(), first = min(year), last = max(year),
                pop = mean(populism_overall, na.rm = TRUE), lib = mean(liberalism_overall, na.rm = TRUE),
                ideo = mean(pop_ideology_direction, na.rm = TRUE), .groups = "drop") |> arrange(desc(n))
    trs <- sprintf("<tr><td><a href='../party/%s.html'>%s</a></td><td>%s</td><td class='num'>%d</td><td class='num'>%d</td><td class='num'>%d</td><td class='num'>%s</td><td class='num'>%s</td><td class='num'>%s</td></tr>",
                   ps$party, esc(ps$label), esc(ps$name), ps$n, ps$first, ps$last, fmt(ps$pop, 2), fmt(ps$lib, 2), fmt(ps$ideo, 2))
    body <- c(body, sprintf("\n## %s\n", x$b$label),
      "\n### Parties over time and in the populism–liberalism space\n\nParties with at least two scored manifestos. Click a party in the legend to toggle it, double-click to isolate it.\n",
      html_block(sprintf("<div id='ts-plot'></div><div id='scatter-plot'></div><script src='../assets/country-plots.js'></script><script>window.addEventListener('DOMContentLoaded',()=>renderCountryPlots('ts-plot','scatter-plot',%s,%s,%s));</script>",
        toJSON(wide |> filter(party %in% multi) |> arrange(party, year), dataframe = "rows", na = "null"),
        toJSON(cn, auto_unbox = TRUE), toJSON(spec, auto_unbox = TRUE))),
      "\n### Parties\n\nMeans of the cross-model scores over the party's manifestos. Click a column header to sort.\n",
      html_block(sprintf("<table class='score-table sortable'><thead><tr><th>Party</th><th>Name</th><th class='num'>Manifestos</th><th class='num'>First</th><th class='num'>Last</th><th class='num'>Populism</th><th class='num'>Liberalism</th><th class='num'>Ideology direction</th></tr></thead><tbody>%s</tbody></table><script src='../assets/party-plot.js'></script>",
                         paste(trs, collapse = ""))))
  }
  write_page(file.path("country", paste0(country_file(cn), ".qmd")), paste(body, collapse = "\n"))
}

`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a

# ---- write -------------------------------------------------------------------------------------
for (dir in c("manifesto", "party", "country")) {
  dir.create(dir, showWarnings = FALSE)
  if (length(ONLY)) next                      # --only: rewrite the named manifesto pages, delete nothing
  old <- setdiff(list.files(dir, "\\.qmd$", full.names = TRUE), file.path(dir, "_template.qmd"))
  unlink(old)
}
t0 <- Sys.time()
walk(seq_len(nrow(docs)), function(i) { write_manifesto(docs[i, ]); if (i %% 500 == 0) message("  manifestos ", i) })
pp <- split(docs |> arrange(date), docs |> arrange(date) |> pull(party))
cc <- split(docs, docs$countryname)
if (!length(ONLY)) {                          # party and country pages need all manifestos of a party / country
  iwalk(pp, function(dd, p) write_party(p, dd))
  iwalk(cc, function(dd, cn) write_country(cn, dd))
}
message(sprintf("written: %d manifesto, %d party, %d country pages in %.0f s", nrow(docs), length(pp), length(cc),
                as.numeric(difftime(Sys.time(), t0, units = "secs"))))
