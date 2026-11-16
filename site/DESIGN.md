# Bond docs site: design

The look, the layouts, the search tags, the favicon and the highlighter come
from the docs theme, the submodule `site/themes/docs-theme`
(agentica-lang/docs-theme); its README lists the params and its `DESIGN.md`
has the design rules. A change of style is a docs-theme PR, then a submodule
bump here. This file lists only what differs. If it and the code disagree, the
code is right: fix this file in the same change.

## Differences

- Title and voice: "Bond", the docs of a small web framework for Agentica
  (`site/hugo.toml` has the title, the tagline, the description and the base
  URL).
- Trimmed features, which Bond does not need:
  - no version badge in the header, no version in the footer, and no release
    links (the version selector below is not part of the theme);
  - no `llms.txt` or `llms-full.txt` output (`[outputs]` of `site/hugo.toml`).
    Every page is still published as Markdown for the page actions, and
    search stays.
- Footer: `site/layouts/_partials/footer.html` links the repository, the
  changelog and the Agentica site. It is the only layout of the site's own.
- Samples: every `agentica` block of `site/content/` is a whole program, run
  through `agentica check` by `tools/check-site-samples.sh` (`make
  site-samples`), and run when an `output` block follows it. The blocks take
  no attributes.
- Build: `make site` (Hugo, Dart Sass, the theme's highlighter) builds one
  version; the Pages workflow builds them all (`site-versions` below).

## Versions

Pages serves one site per final release (`/bond/0.7.0/`, ...), `/bond/dev/`
(`main`) and the latest release again at the root. It is a copy of the version
selector of Agentica (`tools/site_versions.py`, `site/versions/`), with one
change: Bond's header has no version badge, so the selector goes after the
brand.

- `make site-versions` builds them all into `build/site-versions/public` (serve
  it with `python3 -m http.server PORT -d build/site-versions/public`, and pass
  `SITE_BASE_URL=http://localhost:PORT/`). Each `X.Y.Z` tag is built in a git
  worktree with its own `make site`. A tag that uses the docs theme is built
  with the theme commit and the Hugo and Dart Sass that the current checkout
  pins (the theme is only the look); an older tag, with its own layouts, uses
  the pins of its own `pages.yml` (keep the four `env` names of the `build`
  job). Only a tree with no site that is older than every built tag is left
  out; any other failure is tried once more and then fails the run.
  Pre-releases are not versions.
- Search engines see only the root: every page under `/bond/VERSION/` gets a
  canonical URL to the same page at the root (or `noindex,follow` when the
  root has no such page), every page under `/bond/dev/` is `noindex,follow`,
  and their sitemaps are removed. A page built without the theme gets the org
  icons in place of its own.
- The output of a tag is cached by commit sha, base URL and, for a tag with
  the theme, the current theme commit and pins; `dev` is never cached.
- The selector and the banner (`site/versions/selector.{js,css}`) are not part
  of a build: the assembly copies them to `/_versions/` and adds their tags to
  every page, so a cached old build loads the current ones. They use only
  `.site-header`, its `.brand` link and the tokens of the theme.
- `make site-versions-test` runs the assembly on a small git repository
  (`tools/test_site_versions.py`, the standard library only; CI runs it).
- A deploy comes only from `main` (no tag trigger), so a new release shows up
  with the next run of `pages.yml`. A Bond release does not run it: after
  tagging, run `gh workflow run pages.yml --ref main`.
