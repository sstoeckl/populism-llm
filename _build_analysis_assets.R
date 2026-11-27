# ============================================================
# _build_analysis_assets.R — copies the chain outputs that the analysis pages show
#
# Each analysis page reads its numbers only from these copies (no number is typed into a page).
# Source: <workbench>/output/v2026a/{csv,figures} (R/41-R/44); figures are converted to SVG.
# The list per page is in analysis/_analyses.yml (key `assets`).
# Usage (site root):  Rscript _build_analysis_assets.R
# ============================================================
suppressPackageStartupMessages({ library(yaml); library(jsonlite) })
stopifnot(file.exists("_quarto.yml"))
WB <- Sys.getenv("POPLLM_WORKBENCH", "")
if (!nzchar(WB)) { d <- normalizePath("."); repeat { if (file.exists(file.path(d, "R/1_Aggregation.R"))) break
  p <- dirname(d); if (p == d) stop("workbench not found"); d <- p }; WB <- d }
OUT <- file.path(WB, "output/v2026a")
an <- read_yaml("analysis/_analyses.yml")$analyses
for (a in an) {
  dst <- file.path("analysis", "assets", a$id); dir.create(file.path(dst, "fig"), recursive = TRUE, showWarnings = FALSE)
  # an entry without "/" lives in output/v2026a/csv or /figures; with "/" it is a path below output/v2026a
  csv_src <- function(f) if (grepl("/", f)) file.path(OUT, f) else file.path(OUT, "csv", f)
  fig_src <- function(f) if (grepl("/", f)) file.path(OUT, paste0(f, ".pdf")) else file.path(OUT, "figures", paste0(f, ".pdf"))
  for (f in a$assets$csv) stopifnot(file.copy(csv_src(f), file.path(dst, basename(f)), overwrite = TRUE))
  for (f in a$assets$fig) {
    src <- fig_src(f); stopifnot(file.exists(src))
    rc <- system2("pdftocairo", c("-svg", shQuote(src), shQuote(file.path(dst, "fig", paste0(basename(f), ".svg")))))
    stopifnot(rc == 0)
  }
  md5 <- tools::md5sum(c(vapply(a$assets$csv, csv_src, ""), vapply(a$assets$fig, fig_src, "")))
  write_json(list(source = "output/v2026a", files = as.list(setNames(unname(md5), basename(names(md5))))),
             file.path(dst, "SOURCES.json"), auto_unbox = TRUE, pretty = TRUE)
  message(sprintf("%s: %d csv, %d figures", a$id, length(a$assets$csv), length(a$assets$fig)))
}
