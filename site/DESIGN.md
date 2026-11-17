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
    links (the version selector below comes from the theme,
    `params.versions`);
  - no `llms.txt` or `llms-full.txt` output (`[outputs]` of `site/hugo.toml`).
    Every page is still published as Markdown for the page actions, and
    search stays.
- Footer: `site/layouts/_partials/footer.html` is the theme's (all releases,
  page source, the repository, the org home) plus the changelog and the
  Agentica site. It is the only layout of the site's own.
- Links between pages name the `.md` file (`[Filters](filters.md)`): with
  `repoPublic`, a relative link that Hugo cannot resolve becomes a link to the
  source on GitHub, and `make site` fails on one.
- Samples: every `agentica` block of `site/content/` is a whole program, run
  through `agentica check` by `tools/check-site-samples.sh` (`make
  site-samples`), and run when an `output` block follows it. The blocks take
  no attributes.
- Build: `make site` (Hugo, Dart Sass, the theme's highlighter) builds one
  version; the Pages workflow builds them all (`site-versions` below).

## Versions

Pages serves one site per final release (`/bond/0.7.0/`, ...), `/bond/dev/`
(`main`) and the latest release again at the root, with the version selector
of the docs theme (`params.versions`; the theme's README, Versions). Bond's
header has no version badge, so the selector goes after the brand; on a phone
it is the first row of the menu.

- `make site-versions` builds them all into `build/site-versions/public` (serve
  it with `python3 -m http.server PORT -d build/site-versions/public`, and pass
  `SITE_BASE_URL=http://localhost:PORT/`). Each `X.Y.Z` tag is built in a git
  worktree with its own `make site`. A tag that uses the docs theme is built
  with the theme commit that HEAD pins (not the one checked out in the working
  tree, so commit a theme bump before `make site-versions`) and the Hugo and
  Dart Sass of the current checkout (the theme is only the look); an older
  tag, with its own layouts, uses the pins of its own `pages.yml` (keep the
  four `env` names of the `build` job). Only a tree with no site that is
  older than every built tag is left out; any other failure is tried once
  more and then fails the run.
  Pre-releases are not versions.
- Search engines see only the root: every page under `/bond/VERSION/` gets a
  canonical URL to the same page at the root (or `noindex,follow` when the
  root has no such page), every page under `/bond/dev/` is `noindex,follow`,
  and their sitemaps are removed. A page built without the theme gets the org
  icons in place of its own.
- The output of a tag is cached by commit sha, base URL and, for a tag with
  the theme, the theme commit that HEAD pins and the pins; `dev` is never
  cached.
- The selector and the banner are the theme's. `tools/site_versions.py` turns
  them on in every build with the theme (`HUGO_PARAMS_VERSIONS_*`), the root
  build publishes them at `/_versions/`, and every page of every version loads
  that copy, so a theme bump applies to every version at the next deploy. A
  tag from before the theme (0.14.0 and older) gets the same two tags from the
  assembly.
- `make site-versions-test` runs the assembly on a small git repository
  (`tools/test_site_versions.py`, the standard library only; CI runs it).
- A deploy comes only from `main` (no tag trigger), so a new release shows up
  with the next run of `pages.yml`. A Bond release does not run it: after
  tagging, run `gh workflow run pages.yml --ref main`.
