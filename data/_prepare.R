# Fetch bulk data from Hugging Face into the local data/ folder.
# Only large per-chunk parquet files are remote; the small manifesto metadata
# is committed directly to git.
#
# Usage:
#   cd website        # or from project root: cd ../website
#   Rscript data/_prepare.R                # uses default HF dataset
#   Rscript data/_prepare.R sstoeckl/foo   # override the HF dataset slug
#
# After this runs, `quarto render` will work.
suppressPackageStartupMessages({
  library(arrow)
})

# Resolve site root
if (basename(getwd()) == "data" && basename(dirname(getwd())) == "website") {
  setwd("..")
}
if (basename(getwd()) != "website") {
  if (file.exists("website/_quarto.yml")) setwd("website")
}
stopifnot(file.exists("_quarto.yml"))

# Configuration — point to your HF dataset
args <- commandArgs(trailingOnly = TRUE)
HF_DATASET <- if (length(args) > 0) args[1] else "sstoeckl/populism-llm"
HF_REVISION <- "main"

# Files to fetch (HF path → local path under website/data/)
FILES <- list(
  raw_sonnet     = "data/raw_sonnet.parquet",
  raw_gpt41mini  = "data/raw_gpt41mini.parquet",
  raw_gemini     = "data/raw_gemini.parquet"
)

dir.create("data", showWarnings = FALSE)

# Use base R download instead of HF library so we have no Python dependency
hf_url <- function(path) {
  sprintf("https://huggingface.co/datasets/%s/resolve/%s/%s",
          HF_DATASET, HF_REVISION, path)
}

cat("Fetching from Hugging Face dataset:", HF_DATASET, "@", HF_REVISION, "\n\n")
for (stem in names(FILES)) {
  url <- hf_url(FILES[[stem]])
  out <- file.path("data", basename(FILES[[stem]]))
  cat("  ", stem, "← ", url, "\n", sep = "")
  res <- tryCatch(
    download.file(url, out, mode = "wb", quiet = TRUE),
    error = function(e) { cat("    ⚠ ", conditionMessage(e), "\n", sep = ""); 1L }
  )
  if (file.exists(out) && file.size(out) > 1000) {
    cat(sprintf("    ✓ %.1f MB\n", file.size(out) / 1024 / 1024))
  } else {
    cat("    ⚠ not available (yet?) on HF — skipping\n")
  }
}

cat("\nDone. Next: quarto render\n")
cat("(Run `quarto preview` for live reload during dev.)\n")
