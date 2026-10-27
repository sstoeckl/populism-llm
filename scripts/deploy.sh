#!/usr/bin/env bash
# Build the site from the replication chain and deploy it to GitHub Pages (gh-pages branch).
#
#   1. _build_site_data.R      public model output + chain scores -> data/ (checks: site == chain)
#   2. _build_analysis_assets.R chain tables/figures for the analysis pages -> analysis/assets/
#   3. _build_pages.R          static manifesto / party / country pages from data/registry.json
#   4. quarto render           -> _site/
#   5. quarto publish gh-pages
#
# Needs the workbench (3175_populism_llm) as a parent folder or POPLLM_WORKBENCH set.
# Quarto renders nothing when the site folder sits below a hidden directory (e.g. a git worktree
# in .claude/worktrees/): build there, then rsync to a normal folder and render from it.
# Usage:  bash scripts/deploy.sh [--no-publish]
set -euo pipefail
cd "$(dirname "$0")/.."
Rscript _build_site_data.R
Rscript _build_analysis_assets.R
Rscript _build_pages.R
quarto render
du -sh _site
if [[ "${1:-}" != "--no-publish" ]]; then
  quarto publish gh-pages --no-render --no-prompt
fi
