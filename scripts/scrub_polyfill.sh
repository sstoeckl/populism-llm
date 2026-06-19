#!/usr/bin/env bash
# Post-render: strip polyfill.io references (supply-chain risk since 2024).
SITE_DIR="${1:-_site}"
find "$SITE_DIR" -name "*.html" -exec sed -i '/polyfill\.io/d' {} +
echo "Scrubbed polyfill.io from $(find "$SITE_DIR" -name "*.html" | wc -l) HTML files."
