# Bond docs site: design

The Bond site uses the design of the Agentica docs site: rules, tokens,
components and accessibility notes are in
[site/DESIGN.md of Agentica][agentica-design]. The theme files in
`site/layouts/` and `site/assets/` are copies of that site, and a change to the
theme is ported from there. This file lists only what differs. If it and the
code disagree, the code is right: fix this file in the same change.

## Differences

- Title and voice: "Bond", the docs of a small web framework for Agentica
  (title, description and base URL are in `site/hugo.toml`).
- Icon: the favicon is a "B" cut out of an accent-colored rounded square, with
  the same light and dark mechanism as Agentica (`--accent` of both themes) but
  its own shape (`site/layouts/baseof.html`).
- Trimmed features, which Bond does not need:
  - no version badge in the header, no version in the footer, and no release
    links (the version selector below is not part of the theme);
  - no tour and no language specification (no grammar mount);
  - no `llms.txt` or `llms-full.txt` output. Every page is still published as
    Markdown for the page actions, and search stays.
- Header and footer: a link to the Bond repository in both, and the footer
  links to the changelog and to the Agentica site.
- Highlighter: `site/highlight/` is the Agentica one. It fails when a scope
  that the samples use stops matching, and a few scopes that Bond's samples do
  not use are optional (`OPTIONAL` in `highlight.mjs`).
- Samples: every `agentica` block of `site/content/` is a whole program, run
  through `agentica check` by `tools/check-site-samples.sh` (`make
  site-samples`), and run when an `output` block follows it. The blocks take
  no attributes.
- Build: `make site` (Hugo, Dart Sass, the highlighter) builds one version; the
  Pages workflow is the one of Agentica (`site-versions` below).

## Versions

Pages serves one site per final release (`/bond/0.7.0/`, ...), `/bond/dev/`
(`main`) and the latest release again at the root. It is a copy of the version
selector of Agentica (`tools/site_versions.py`, `site/versions/`), with one
change: Bond's header has no version badge, so the selector goes after the
brand.

- `make site-versions` builds them all into `build/site-versions/public` (serve
  it with `python3 -m http.server PORT -d build/site-versions/public`, and pass
  `SITE_BASE_URL=http://localhost:PORT/`). Each `X.Y.Z` tag is built from its
  own tree with its own `make site`, using the Hugo and Dart Sass pinned in that
  tag's `pages.yml` (keep the four `env` names of the `build` job). Only a tree
  with no site that is older than every built tag is left out; any other
  failure is tried once more and then fails the run. Pre-releases are not
  versions.
- The output of a tag is cached by commit sha and base URL; `dev` is never
  cached.
- The selector and the banner (`site/versions/selector.{js,css}`) are not part
  of a build: the assembly copies them to `/_versions/` and adds their tags to
  every page, so a cached old build loads the current ones. They use only
  `.site-header`, its `.brand` link and the tokens of `_tokens.scss`.
- `make site-versions-test` runs the assembly on a small git repository
  (`tools/test_site_versions.py`, the standard library only; CI runs it).
- A deploy comes only from `main` (no tag trigger), so a new release shows up
  with the next run of `pages.yml`. A Bond release does not run it: after
  tagging, run `gh workflow run pages.yml --ref main`.

[agentica-design]:
  https://github.com/agentica-lang/agentica/blob/master/site/DESIGN.md
