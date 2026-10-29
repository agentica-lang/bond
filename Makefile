# The documentation site (Hugo) and the check of its samples.

DART_SASS ?= $(HOME)/.local/opt/dart-sass

.PHONY: site site-serve site-sass site-samples

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

site-serve: site-sass
	hugo server --source site

# Runs `agentica check` on every agentica block of site/content (needs agentica on PATH).
site-samples:
	tools/check-site-samples.sh
