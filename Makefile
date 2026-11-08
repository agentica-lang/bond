# Developing Bond needs Agentica 0.27.0 or later (`OpenSSL.HMAC`), and so does a project that uses Bond.
# The check, the format check, the tests of the sources, the documentation site (Hugo), the check of its samples and
# the site of every release (site-versions).

DART_SASS ?= $(HOME)/.local/opt/dart-sass
JOBS ?= 4

.PHONY: check fmt-check test site site-serve site-sass site-samples site-versions site-versions-test

# `agentica check` with no path checks every .agc file of the package, its examples, specs and tests.
check:
	@agentica check

# `agentica fmt --check` with no path lists the files that `agentica fmt` would change, and fails if there are any.
fmt-check:
	@agentica fmt --check

# The features of specs/ and the unit tests of test/, up to JOBS files at once (each file has its own port and folders).
test:
	@agentica test --jobs $(JOBS)

site site-serve site-sass: export PATH := $(DART_SASS):$(PATH)

site-sass:
	@command -v sass >/dev/null || { echo "The site needs Dart Sass: put its sass on PATH or in $(DART_SASS) (pinned version in .github/workflows/pages.yml)" >&2; exit 1; }

site/highlight/node_modules: site/highlight/package.json site/highlight/package-lock.json
	npm ci --prefix site/highlight --ignore-scripts --no-audit --no-fund
	touch $@

# Builds the site into site/public. HUGO_FLAGS="--baseURL URL" sets the address.
site: site-sass site/highlight/node_modules
	hugo --cleanDestinationDir --source site --panicOnWarning $(HUGO_FLAGS)
	node site/highlight/highlight.mjs site/public
	@# The layouts print the title of a home or a list page, so its content must not start with the same heading.
	@bad=0; for f in $$(find site/public -name index.html); do n=$$(grep -o '<h1' $$f | wc -l); [ $$n -eq 1 ] || { echo "$$f has $$n h1" >&2; bad=1; }; done; [ $$bad -eq 0 ]

site-serve: site-sass
	hugo server --source site

# Runs `agentica check` on every agentica block of site/content (needs agentica on PATH).
site-samples:
	tools/check-site-samples.sh

# One site per release plus dev, as pages.yml deploys it (tools/site_versions.py); serve the output with
# `python3 -m http.server PORT -d build/site-versions/public`. SITE_BASE_URL is where the root is served and must
# match that port.
SITE_BASE_URL ?= http://localhost:8000/

site-versions:
	python3 -I tools/site_versions.py build --base-url $(SITE_BASE_URL)

# The assembly of site-versions on a small git repository (the standard library only; CI runs it).
site-versions-test:
	python3 -I tools/test_site_versions.py
