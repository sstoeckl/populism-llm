# Populism-LLM website

Static Quarto site: party manifestos scored by three language model families, every score with
its evidence. Live at <https://sstoeckl.github.io/populism-llm/> (preview; not peer-reviewed).

## Build

The site is built from the replication chain of the paper (workbench `3175_populism_llm`, which
contains this repository as `website/`). Nothing on the site is computed differently from the
chain: `_build_site_data.R` recomputes all scores with the chain's aggregation and stops if one
differs from the chain baseline.

```bash
bash scripts/deploy.sh --no-publish   # build data, pages and site into _site/
bash scripts/deploy.sh                # ... and publish to the gh-pages branch
```

| Step | Script | Output |
|---|---|---|
| 1 | `_build_site_data.R` | `data/registry.json`, `data/blocks/<block>/{scores,evidence}.parquet`, `data/manifestos.parquet`, `data/download/`, `data/specs_distinct_pop.csv` |
| 2 | `_build_analysis_assets.R` | `analysis/assets/<analysis>/` (chain CSVs and figures, with `SOURCES.json` md5) |
| 3 | `_build_pages.R` | `manifesto/`, `party/`, `country/` (static Markdown, no R at render time) |
| 4 | `quarto render` | `_site/` |

The workbench is found as a parent folder or via `POPLLM_WORKBENCH`.

## Extending the site

- **New attributes** (for example a party's environmental profile or its stance towards
  democratic institutions): add `registry/<block>.yml` and the files
  `data/blocks/<block>/scores.parquet` (doc_id, dim, model, score; `model = "combined"` for the
  value shown by default) and, optionally, `evidence.parquet`. Every manifesto, party, country and
  browse page picks the block up; see the header of `registry/poplib_v4.yml`.
- **New analysis pages:** add an entry to `analysis/_analyses.yml` (with the chain outputs it
  uses) and `analysis/<id>.qmd`; it appears under *Analyses*.

## Evidence text and rights

The manifesto texts are © their authors and distributed by the Manifesto Project (WZB). The
evidence policy is set in `registry/_models.yml` (`evidence_text`): `quote8` shows only the first
8 words of each quote; `context` shows the quote within at most `context_words` words of its
passage (current setting, decided 2026-10-27 while the Manifesto Project's written permission is
requested). The downloadable evidence file always carries 8-word quotes only.

## License

Scores and evidence flags: CC-BY 4.0. Site code: MIT.
