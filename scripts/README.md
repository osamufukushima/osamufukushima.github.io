# Data Sync Scripts

This directory contains scripts for maintaining the Jekyll data files in `_data`.

## Validate local data

```sh
ruby scripts/validate_data.rb
```

## Format YAML spacing

```sh
ruby scripts/format_yaml_spacing.rb
```

This inserts a blank line between top-level list items in `_data/*.yml`.

## Normalize publication titles

```sh
ruby scripts/normalize_publication_titles.rb
```

This ensures every publication has both `title_latex` and `title_html`.
`title_latex` is intended for LaTeX/CV output, while `title_html` is intended for
the website. Inline LaTeX math written as `$...$` is converted to MathJax
`\(...\)` in `title_html` when `title_html` is missing.

To regenerate all `title_html` values from `title_latex`, run:

```sh
ruby scripts/normalize_publication_titles.rb --force-html
```

## Render HTML from YAML

```sh
ruby scripts/render_pages.rb
```

The live publications and presentations pages are Liquid templates processed by
GitHub Pages/Jekyll. This script is kept as a local preview and backup generator.
By default it writes preview files:

```text
web/publications/index.generated.html
web/presentations/index.generated.html
```

Only if you intentionally want to replace the Liquid templates with generated
static HTML, overwrite the live HTML with:

```sh
ruby scripts/render_pages.rb --in-place
```

You can render one page at a time:

```sh
ruby scripts/render_pages.rb --page publications
ruby scripts/render_pages.rb --page presentations
```

## Sync article metadata from INSPIRE HEP

```sh
ruby scripts/sync_inspire.rb
```

By default this queries literature records associated with INSPIRE author record `1818804`,
merges them into `_data/publications.yml`, and caches raw API responses under
`data_raw/inspire`.

Useful options:

```sh
ruby scripts/sync_inspire.rb --query 'a O.Fukushima.1'
ruby scripts/sync_inspire.rb --author-id 1818804
ruby scripts/sync_inspire.rb --output _data/publications_inspire.yml
```

Manual display fixes can be placed in `_data/publication_overrides.yml`.

## Sync public works from ORCID

```sh
ruby scripts/sync_orcid.rb
```

The default ORCID iD is `0000-0001-7205-5324`. You can override it with:

```sh
ruby scripts/sync_orcid.rb --orcid 0000-0001-7205-5324
ORCID_ID=0000-0001-7205-5324 ruby scripts/sync_orcid.rb
```

If ORCID requires an access token for your environment, set `ORCID_ACCESS_TOKEN`.
