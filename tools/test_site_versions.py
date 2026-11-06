#!/usr/bin/env python3
"""The multi-version site: tools/site_versions.py builds each release tag, caches it by commit sha, assembles one folder.

`make site-versions-test` (and CI) runs it; the standard library only. The real Hugo build runs in `make site-versions`
and pages.yml. This test runs the whole assembly on a small git repository whose `make site` writes two pages: the tags
that become versions (and the ones that do not), the tag with no site left out, a tag that fails (or no tag built at
all) failing the run, the latest release served at the root, the selector tags added to every page once and to nothing
else, and a second run that builds only what is not cached.
"""
import contextlib
import importlib.util
import io
import json
import os
import shutil
import subprocess
import tempfile
import unittest
from pathlib import Path
from unittest import mock

ROOT = Path(__file__).resolve().parents[1]

# Each tag's `make site` records its own base URL and version in its pages; a tree with a FAIL file fails.
MAKEFILE = (
    ".PHONY: site\n"
    "site:\n"
    "\t@test ! -e FAIL\n"
    "\t@if [ -e FLAKY ] && [ ! -e $(ONCE) ]; then touch $(ONCE); exit 1; fi\n"
    "\t@echo run >> $(RUNS)\n"
    "\tmkdir -p site/public/guide\n"
    "\tprintf '<html><head></head><body>%s %s</body></html>' '$(HUGO_FLAGS)' \"$$(cat VERSION)\""
    " > site/public/guide/index.html\n"
    "\tprintf '<html><head></head><body>%s</body></html>' '$(HUGO_FLAGS)' > site/public/index.html\n"
    "\tprintf 'see <head></head> /bond/' > site/public/llms.txt\n"
)

SELECTOR_TAGS = (
    '<link rel="stylesheet" href="/docs/_versions/selector.css">'
    '<script src="/docs/_versions/selector.js" defer></script>'
)


def load_tool():
    spec = importlib.util.spec_from_file_location("bond_site_versions_tool", ROOT / "tools" / "site_versions.py")
    module = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(module)
    return module


tool = load_tool()


def git(repo, *args):
    identity = ["-c", "user.name=t", "-c", "user.email=t@t"]
    subprocess.run(["git", *identity, "-C", str(repo), *args], check=True, capture_output=True)


def release(repo, version, tag=None, fail=False, flaky=False):
    """Commit a version; `fail` makes its `make site` fail always, `flaky` only the first time."""
    (repo / "VERSION").write_text(version + "\n")
    for name, on in (("FAIL", fail), ("FLAKY", flaky)):
        marker = repo / name
        if on:
            marker.write_text("")
        elif marker.exists():
            marker.unlink()
    git(repo, "add", "-A")
    git(repo, "commit", "-q", "-m", version)
    if tag:
        git(repo, "tag", tag)


class SiteVersionsTest(unittest.TestCase):
    def setUp(self):
        scratch = tempfile.TemporaryDirectory()
        self.addCleanup(scratch.cleanup)
        self.tmp = Path(scratch.name)
        self.repo = repo = self.tmp / "repo"
        (repo / "site" / "versions").mkdir(parents=True)
        (repo / ".github" / "workflows").mkdir(parents=True)
        (repo / "Makefile").write_text(MAKEFILE)
        git(repo, "init", "-q")
        release(repo, "0.1.0", "0.1.0")  # before the site existed: no site/hugo.toml, no pages.yml
        (repo / "site" / "hugo.toml").write_text("")
        for name in tool.SELECTOR_FILES:
            shutil.copy(ROOT / "site" / "versions" / name, repo / "site" / "versions" / name)
        pins = "HUGO_VERSION: 1.0.0\n  HUGO_SHA256: a\n  DART_SASS_VERSION: 1.0.0\n  DART_SASS_SHA256: b\n"
        (repo / ".github" / "workflows" / "pages.yml").write_text("env:\n  " + pins)
        release(repo, "0.9.0", "0.9.0")
        release(repo, "0.10.0-beta.1", "0.10.0-beta.1")
        release(repo, "0.10.0", "0.10.0")
        release(repo, "0.11.0", "0.11.0")
        release(repo, "0.12.0", "not-a-version")
        for patcher in (
            mock.patch.object(tool, "ROOT", repo),
            mock.patch.object(tool, "tool_env", lambda workflow, tools: dict(os.environ)),
            mock.patch.dict(os.environ, {
                "RUNS": str(self.tmp / "runs"),
                "ONCE": str(self.tmp / "once"),
                "GITHUB_STEP_SUMMARY": str(self.tmp / "summary.md"),
                "GITHUB_OUTPUT": str(self.tmp / "output"),
            }),
        ):
            patcher.start()
            self.addCleanup(patcher.stop)

    def build(self):
        """Run the CLI; returns its exit code, its output, the output folder and how many `make site` runs there were."""
        (self.tmp / "output").unlink(missing_ok=True)
        stdout = io.StringIO()
        with contextlib.redirect_stdout(stdout):
            code = tool.main([
                "build", "--out", str(self.tmp / "out"), "--cache", str(self.tmp / "cache"),
                "--tools", str(self.tmp / "tools"), "--base-url", "https://example.org/docs",
            ])
        runs = self.tmp / "runs"
        return code, stdout.getvalue(), self.tmp / "out", runs.read_text().count("run") if runs.exists() else 0

    def test_pins_come_from_the_real_workflow(self):
        pinned = tool.pins((ROOT / ".github" / "workflows" / "pages.yml").read_text())
        self.assertEqual(pinned["HUGO_VERSION"].count("."), 2)
        self.assertEqual(pinned["DART_SASS_VERSION"].count("."), 2)
        self.assertEqual((len(pinned["HUGO_SHA256"]), len(pinned["DART_SASS_SHA256"])), (64, 64))

    def test_one_folder_per_release_with_the_latest_at_the_root(self):
        code, _, out, _ = self.build()
        self.assertEqual(code, 0)
        self.assertEqual(json.loads((out / "versions.json").read_text()), [
            {"version": "0.11.0", "path": "0.11.0/", "latest": True},
            {"version": "0.10.0", "path": "0.10.0/"},
            {"version": "0.9.0", "path": "0.9.0/"},
            {"version": "dev", "path": "dev/"},
        ])
        # Each build bakes in its own base URL; the root is the latest release under the root URL.
        self.assertIn("--baseURL https://example.org/docs/0.9.0/ 0.9.0", (out / "0.9.0" / "guide" / "index.html").read_text())
        self.assertIn("--baseURL https://example.org/docs/ 0.11.0", (out / "guide" / "index.html").read_text())
        self.assertIn("--baseURL https://example.org/docs/dev/", (out / "dev" / "index.html").read_text())
        self.assertFalse((out / "0.1.0").exists() or (out / "0.10.0-beta.1").exists())
        self.assertIn("`0.1.0`", (self.tmp / "summary.md").read_text())
        self.assertTrue((out / "_versions" / "selector.js").exists() and (out / "_versions" / "selector.css").exists())

    def test_every_html_page_loads_the_selector_once_and_the_cache_skips_builds(self):
        _, _, out, first = self.build()
        pages = list(out.rglob("*.html"))
        self.assertTrue(pages)
        self.assertTrue(all(page.read_text().count(SELECTOR_TAGS) == 1 for page in pages))
        # Other files are not touched, even when they look like a page.
        self.assertEqual((out / "llms.txt").read_text(), "see <head></head> /bond/")
        # 0.9.0, 0.10.0 and 0.11.0 (versioned and at the root) and dev; 0.1.0 has no site and never runs make.
        self.assertEqual(first, 5)
        code, _, out, total = self.build()
        self.assertEqual((code, total - first), (0, 1))  # only dev builds again: the working tree is never cached
        self.assertTrue(all(page.read_text().count(SELECTOR_TAGS) == 1 for page in out.rglob("*.html")))

    def test_a_tag_that_fails_fails_the_run(self):
        release(self.repo, "0.11.1", "0.11.1", fail=True)
        release(self.repo, "0.12.0")
        code, printed, _, _ = self.build()
        self.assertEqual(code, 1)
        self.assertIn("FAIL 0.11.1", printed)
        self.assertIn("Failed: `0.11.1`", (self.tmp / "summary.md").read_text())

    def test_a_tag_that_fails_once_is_retried_and_built(self):
        release(self.repo, "0.11.1", "0.11.1", flaky=True)
        release(self.repo, "0.12.0")
        code, printed, out, _ = self.build()
        self.assertEqual(code, 0)
        self.assertIn("retry 0.11.1", printed)
        self.assertEqual(json.loads((out / "versions.json").read_text())[0],
                         {"version": "0.11.1", "path": "0.11.1/", "latest": True})

    def test_a_tag_without_a_site_newer_than_a_built_tag_fails_the_run(self):
        config = self.repo / "site" / "hugo.toml"
        config.unlink()  # a tree the script reads as "no site", though a newer release than 0.11.0 has one
        release(self.repo, "0.11.1", "0.11.1")
        config.write_text("")
        release(self.repo, "0.12.0")
        code, printed, _, _ = self.build()
        self.assertEqual(code, 1)
        self.assertIn("FAIL 0.11.1", printed)

    def test_the_cache_keeps_only_current_builds_and_says_when_something_is_new(self):
        self.build()
        self.assertEqual((self.tmp / "output").read_text(), "fresh=true\n")
        stray = self.tmp / "cache" / "old-tag-entry"
        stray.mkdir()
        # 0.9.0, 0.10.0, 0.11.0 and the root copy of 0.11.0, and the stray one.
        self.assertEqual(len(list((self.tmp / "cache").iterdir())), 5)
        self.build()
        self.assertEqual((self.tmp / "output").read_text(), "fresh=false\n")
        self.assertFalse(stray.exists())
        self.assertEqual(len(list((self.tmp / "cache").iterdir())), 4)

    def test_a_run_with_no_version_fails(self):
        with mock.patch.object(tool, "final_tags", lambda: ["0.1.0"]):
            code, _, _, _ = self.build()
        self.assertEqual(code, 1)


if __name__ == "__main__":
    unittest.main()
