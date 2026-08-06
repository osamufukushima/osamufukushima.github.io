# Osamu Fukushima Website

Personal website repository for <https://osamufukushima.github.io/web/>.

The public pages are under `web/`. Most pages are static HTML, while
`web/publications/index.html` and `web/presentations/index.html` are
HTML + Liquid templates processed by GitHub Pages/Jekyll. Publication and
presentation data are maintained as YAML files under `_data/`.

## Directory Layout

```text
.
├── _data/
│   ├── publications.yml
│   ├── publication_overrides.yml
│   ├── presentations.yml
│   └── presentation_categories.yml
├── data_raw/
│   ├── inspire/
│   └── orcid/
├── scripts/
│   ├── sync_inspire.rb
│   ├── sync_orcid.rb
│   ├── render_pages.rb
│   ├── validate_data.rb
│   └── format_yaml_spacing.rb
└── web/
    ├── css/style.css
    ├── index.html
    ├── activities/index.html
    ├── miscellanies/index.html
    ├── miscellanies/*.JPG
    ├── publications/index.html
    ├── publications/master_thesis_v3.pdf
    └── presentations/index.html
```

The `web/` directory contains the published site:

Jekyll/GitHub Pages configuration is kept in the repository-root `_config.yml`.
There is no separate `web/_config.yml`.

`web/index.html` is the home page.

`web/publications/index.html` and `web/presentations/index.html` are Liquid
templates. GitHub Pages/Jekyll expands them using `_data/*.yml` when the site is
published.

`web/activities/index.html` and `web/miscellanies/index.html` are currently
maintained directly as static HTML.

`web/css/style.css` contains the shared site styling.

`web/miscellanies/*.JPG` and `web/publications/master_thesis_v3.pdf` are static
assets used by the site.

`web/google79b68362aab0b6d3.html` is a Google site verification file.

## Data Files

`_data/publications.yml` is the canonical publication database for articles,
books, and theses.

`_data/presentations.yml` is the canonical presentation database.

`_data/publication_overrides.yml` is optional. Use it when you want a correction
to override INSPIRE/ORCID metadata without editing the main publication record.

`data_raw/inspire/` and `data_raw/orcid/` store raw API JSON responses. These are
useful for debugging and checking what the APIs returned, but the website itself
is generated from `_data/*.yml`.

## Common Workflow

Validate YAML data:

```sh
ruby scripts/validate_data.rb
```

Sync article metadata from INSPIRE HEP:

```sh
ruby scripts/sync_inspire.rb
```

Sync public works from ORCID:

```sh
ruby scripts/sync_orcid.rb
```

Format YAML files with blank lines between top-level items:

```sh
ruby scripts/format_yaml_spacing.rb
```

Generate optional preview HTML from YAML:

```sh
ruby scripts/render_pages.rb
```

This writes:

```text
web/publications/index.generated.html
web/presentations/index.generated.html
```

The live pages normally do not need this script, because GitHub Pages/Jekyll
processes Liquid automatically. `render_pages.rb` is kept as a local preview and
backup generator. If you intentionally want to replace the Liquid templates with
generated static HTML, run:

```sh
ruby scripts/render_pages.rb --in-place
```

## Notes On Manual Edits

Manual entries in `_data/publications.yml` are kept when `sync_inspire.rb` is
run. For articles, the script matches records by `arxiv`, `doi`, or `inspire_id`.
For books and theses, records are preserved because they are not managed by
INSPIRE.

For display corrections such as `title_html`, `journal_html`, `journal_url`, or
author formatting, editing `_data/publications.yml` directly is fine. Be careful
when changing identifier fields such as `id`, `arxiv`, `doi`, and `inspire_id`,
because they are used to recognize matching records during sync.

More script details are documented in `scripts/README.md`.
