# Shared helpers for the site pages that run R at render time (index, browse, cross-model).
# Data come from _build_site_data.R (data/registry.json, data/manifestos.parquet,
# data/blocks/<block>/scores.parquet); the manifesto, party and country pages are static
# (_build_pages.R) and do not use this file.
suppressPackageStartupMessages({
  library(arrow); library(dplyr); library(tidyr); library(stringr); library(purrr); library(jsonlite)
})
.SITE_ROOT <- function() {
  d <- normalizePath(getwd())
  repeat { if (file.exists(file.path(d, "_quarto.yml"))) return(d)
    p <- dirname(d); if (p == d) stop("site root not found"); d <- p }
}
SITE <- .SITE_ROOT()
REG <- fromJSON(file.path(SITE, "data/registry.json"), simplifyVector = FALSE)
VERSION <- REG$version
MSHORT <- setNames(map_chr(REG$models, "short"), map_chr(REG$models, "id"))

block_dims <- function(block = "poplib_v4") {
  b <- keep(REG$blocks, ~ .x$id == block)[[1]]
  map_dfr(c(b$dims, b$derived), ~ tibble(id = .x$id, group = .x$group, label = .x$label, min = .x$min, max = .x$max))
}
load_manifestos <- function() read_parquet(file.path(SITE, "data/manifestos.parquet")) |> filter(scored)
load_scores <- function(block = "poplib_v4") read_parquet(file.path(SITE, "data/blocks", block, "scores.parquet"))

score_band <- function(x, mn = 0, mx = 10) {
  z <- (x - mn) / (mx - mn)
  ifelse(is.na(x), "na", ifelse(z < 0.35, "low", ifelse(z < 0.65, "mid", "high")))
}
`%||%` <- function(a, b) if (is.null(a) || length(a) == 0) b else a
