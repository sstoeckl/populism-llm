#!/usr/bin/env bash
# Local pre-render and deploy to GitHub Pages via the gh-pages branch.
#
# What it does:
#   1. Fetches bulk data from Hugging Face (if not already present)
#   2. Materialises 3,327 per-manifesto .qmd files
#   3. Renders the entire site to _site/
#   4. Pushes _site/ to the gh-pages branch
#   5. GitHub Pages serves the new content
#
# Usage:  bash scripts/deploy.sh

set -euo pipefail

cd "$(dirname "$0")/.."  # → site root

echo "▶ 1/4  Fetching bulk data from Hugging Face..."
Rscript data/_prepare.R

echo "▶ 2/4  Materialising 3,327 per-manifesto qmd files..."
Rscript _render_manifestos.R

echo "▶ 3/4  Rendering site (this takes ~10-30 min for full corpus)..."
quarto render

echo "▶ 4/4  Pushing _site/ to gh-pages branch..."
quarto publish gh-pages --no-render --no-prompt

echo "✓ Deployed. Site live at https://sstoeckl.github.io/populism-llm/"
