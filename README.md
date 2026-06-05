# Populism-LLM website

Static Quarto site for the **Populism-LLM** dataset — a cross-validated LLM
annotation of European party manifestos on populism and liberalism dimensions.

🚧 **Currently in preview / draft mode.** Numbers and methodology may change.
Do not cite without contacting <sebastian.stoeckl@uni.li>. Bulk data and
DOI-citable releases are forthcoming.

## What this repo serves

- A landing page describing the corpus and methodology
- An interactive [browser](https://sstoeckl.github.io/populism-llm/browse.html)
  of all 3,327 scored manifestos
- A per-manifesto evidence page for each manifesto showing every score from
  every model, with the verbatim quote the model cited
- A [cross-model agreement](https://sstoeckl.github.io/populism-llm/cross-model.html)
  view comparing the three LLM families
- An [interactive regression module](https://sstoeckl.github.io/populism-llm/interactive/regression.html)
  (WebR — runs in your browser, filters by country/year/model, recomputes
  panel regression on the fly)

## Repo structure

```
populism-llm/
├── _quarto.yml                       # Site config
├── index.qmd                          # Landing page
├── browse.qmd                         # 3,327-row interactive browser
├── cross-model.qmd                    # Pairwise model agreement
├── methodology.qmd                    # Pipeline + prompts + validation
├── download.qmd                       # Bulk download links + citations
├── interactive/regression.qmd         # WebR-powered live regressions
├── manifesto/_template.qmd            # Per-manifesto page template
├── manifesto/<doc_id>.qmd             # Generated, gitignored
├── _data.R                            # Shared data-access helpers
├── _render_manifestos.R               # Materialise 3,327 .qmd files
├── data/
│   ├── manifestos_meta.parquet        # Identification fields only (no text)
│   ├── raw_sonnet.parquet             # Per-chunk scores + quotes (Anthropic)
│   ├── raw_gpt41mini.parquet          # Per-chunk scores + quotes (OpenAI)
│   └── raw_gemini.parquet             # Per-chunk scores + quotes (Google)
├── assets/css/                        # Styles
└── .github/workflows/quarto.yml       # Auto-build + deploy to gh-pages
```

The full original manifesto text is **not** in this repo — see
[manifesto-project.wzb.eu](https://manifesto-project.wzb.eu/) (CMP / WZB
licensed). We only ship derived annotations and short verbatim quotes.

## Local development

```bash
# 1) Materialise per-manifesto .qmd files (3,327 of them, ~30 s)
Rscript _render_manifestos.R          # or `--sample 50` for dev
# 2) Build the site
quarto render                          # writes _site/
# 3) Live preview
quarto preview
```

R prerequisites: `arrow`, `dplyr`, `tidyr`, `purrr`, `stringi`, `htmltools`,
`reactable`, `ggplot2`, `lubridate`, `knitr`. WebR-dependent packages for the
interactive module are listed in `interactive/regression.qmd`.

## License

- Annotations (scores, statuses, derived metrics): **CC-BY 4.0**
- Verbatim quotes ≤ 50 words: fair use for scientific commentary; always cite `manifesto_id`
- Site source code: **MIT**
- Original manifesto texts: © Manifesto Project / WZB

## Citation

```bibtex
@article{stoeckl2026populism,
  author  = {Stoeckl, Sebastian},
  title   = {Populism and Liberalism in European Party Manifestos:
             A Cross-Validated LLM Approach},
  year    = {2026},
  note    = {Working paper; dataset DOI: tba}
}
```
