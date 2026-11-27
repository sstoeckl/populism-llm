#!/usr/bin/env bash
# Change the paper status shown in the banner and on the results page without re-rendering the site.
#   bash scripts/set_status.sh "R&R at APSR"     # set
#   bash scripts/set_status.sh ""                # clear
# Writes data/status.json in the source and pushes only that file to the gh-pages branch.
set -euo pipefail
cd "$(dirname "$0")/.."
python3 - "$1" <<'PY'
import json, sys
p = "data/status.json"; j = json.load(open(p, encoding="utf-8")); j["status"] = sys.argv[1]
json.dump(j, open(p, "w", encoding="utf-8"), indent=2, ensure_ascii=False)
PY
tmp=$(mktemp -d); trap 'rm -rf "$tmp"' EXIT
git clone -q --depth 1 --branch gh-pages "$(git remote get-url origin)" "$tmp"
mkdir -p "$tmp/data"; cp data/status.json "$tmp/data/status.json"
cd "$tmp"; git add data/status.json
git diff --cached --quiet && { echo "status unchanged"; exit 0; }
git commit -q -m "Paper status: ${1:-(none)}"; git push -q origin gh-pages
echo "status set to: ${1:-(none)} (live in about a minute)"
