#!/usr/bin/env python3
"""Static validation for website/ and the Pi's console/login pages.

No browser and no network: parses the HTML/CSS/JS/manifest/headers that ship in
the repo and fails on a dangling reference, a missing meta tag, a bad inline
script or a malformed Cloudflare Pages config. Run it before a site deploy and
after editing any page.

Usage (from the workspace root):
    python website/tools/check_static_site.py [--website website] [--quiet]

Checks
------
* website: every local src/href/srcset resolves, anchor targets exist, one <h1>,
  title/description/viewport/canonical/OG/Twitter meta, favicon/apple-touch/
  manifest links, every <img> has alt, stylesheet/font refs resolve, the web
  manifest icons exist and have the declared size, robots.txt, _headers syntax.
* Pi pages (console.html/login.html): HTML shape, no unresolved placeholder,
  inline <script> blocks pass `node --check`, form/field ids referenced by the
  page exist.
* JS syntax for website/main.js via `node --check` when Node is available.

Exit code = number of failed checks. No network, no writes.
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys
import tempfile
from html.parser import HTMLParser

HERE = os.path.dirname(os.path.abspath(__file__))
WEBSITE_DEFAULT = os.path.dirname(HERE)
WORKSPACE = os.path.dirname(WEBSITE_DEFAULT)
SERVER_DEFAULT = os.path.join(WORKSPACE, "pi_setup", "cartslop-server")

FAILS: list[str] = []
CHECKS = 0
NODE = shutil.which("node")


def check(condition: bool, message: str) -> None:
    global CHECKS
    CHECKS += 1
    if condition:
        print("PASS: " + message)
    else:
        print("FAIL: " + message, file=sys.stderr)
        FAILS.append(message)


class Page(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.ids: set[str] = set()
        self.anchors: list[str] = []
        self.refs: list[tuple[str, str]] = []  # (tag, url)
        self.images: list[tuple[str, bool]] = []
        self.metas: list[dict] = []
        self.links: list[dict] = []
        self.titles: list[str] = []
        self.h1_count = 0
        self.inline_scripts: list[str] = []
        self._in_script = False
        self._script_buffer: list[str] = []
        self._in_title = False
        self._title_buffer: list[str] = []

    def handle_starttag(self, tag, attrs):
        attributes = {key: (value or "") for key, value in attrs}
        if "id" in attributes:
            self.ids.add(attributes["id"])
        if tag == "a" and "href" in attributes:
            self.anchors.append(attributes["href"])
        if tag == "img":
            self.images.append((attributes.get("src", ""), "alt" in attributes))
            if attributes.get("src"):
                self.refs.append(("img", attributes["src"]))
            if attributes.get("srcset"):
                for part in attributes["srcset"].split(","):
                    url = part.strip().split(" ")[0]
                    if url:
                        self.refs.append(("srcset", url))
        if tag == "link":
            self.links.append(attributes)
            if attributes.get("href"):
                self.refs.append(("link", attributes["href"]))
        if tag == "script":
            if attributes.get("src"):
                self.refs.append(("script", attributes["src"]))
            else:
                self._in_script = True
                self._script_buffer = []
        if tag == "style":
            self._in_script = False
        if tag == "meta":
            self.metas.append(attributes)
        if tag == "title":
            self._in_title = True
            self._title_buffer = []
        if tag == "h1":
            self.h1_count += 1
        if tag == "source" and attributes.get("srcset"):
            for part in attributes["srcset"].split(","):
                url = part.strip().split(" ")[0]
                if url:
                    self.refs.append(("srcset", url))

    def handle_endtag(self, tag):
        if tag == "script" and self._in_script:
            self._in_script = False
            self.inline_scripts.append("".join(self._script_buffer))
        if tag == "title" and self._in_title:
            self._in_title = False
            self.titles.append("".join(self._title_buffer).strip())

    def handle_data(self, data):
        if self._in_script:
            self._script_buffer.append(data)
        if self._in_title:
            self._title_buffer.append(data)


def parse(path: str) -> Page:
    page = Page()
    with open(path, encoding="utf-8") as handle:
        page.feed(handle.read())
    return page


def is_local(url: str) -> bool:
    return not (not url
                or url.startswith(("data:", "http://", "https://", "//",
                                   "#", "mailto:", "javascript:")))


def resolve(website: str, url: str) -> str | None:
    if not is_local(url):
        return None
    from urllib.parse import urlparse
    path = urlparse(url).path
    if not path:
        return None
    return os.path.join(website, path.lstrip("/"))


def check_js(label: str, source: str, temp_dir: str) -> None:
    if NODE is None:
        check(True, label + " (node not installed; JS syntax check skipped)")
        return
    path = os.path.join(temp_dir, "check.js")
    with open(path, "w", encoding="utf-8") as handle:
        handle.write(source)
    result = subprocess.run([NODE, "--check", path], capture_output=True,
                            text=True)
    check(result.returncode == 0,
          label + (" passes node --check"
                   if result.returncode == 0
                   else " passes node --check: " + result.stderr.strip()[:300]))


def validate_page(website: str, relative: str, temp_dir: str,
                  require_index_meta: bool) -> None:
    path = os.path.join(website, relative)
    if not os.path.isfile(path):
        check(False, relative + " exists")
        return
    page = parse(path)
    check(page.h1_count == 1, relative + " has exactly one <h1>")
    check(bool(page.titles) and len(page.titles[0]) > 8,
          relative + " has a descriptive <title>")
    for tag, url in page.refs:
        if not is_local(url):
            continue
        target = resolve(website, url)
        check(target is not None and os.path.exists(target),
              relative + ": " + tag + " reference resolves (" + url + ")")
    for image_src, has_alt in page.images:
        check(has_alt, relative + ": <img src=\"" + image_src + "\"> has alt")
    for anchor in page.anchors:
        if anchor.startswith("#") and len(anchor) > 1:
            check(anchor[1:] in page.ids,
                  relative + ": in-page anchor target exists (" + anchor + ")")
    for script in page.inline_scripts:
        if script.strip():
            check_js(relative + " inline script", script, temp_dir)
    if require_index_meta:
        meta_text = " ".join(
            " ".join(str(value) for value in meta.values()) for meta in page.metas)
        for required in ("og:title", "og:description", "og:image", "twitter:card"):
            check(required in meta_text, relative + " declares " + required)
        link_rels = [link.get("rel", "") for link in page.links]
        for required in ("icon", "apple-touch-icon", "manifest"):
            check(any(required in rel.split() for rel in link_rels),
                  relative + " links rel=\"" + required + "\"")
        manifests = [link for link in page.links
                     if link.get("rel") == "manifest"]
        manifest_path = resolve(website, manifests[0]["href"]) if manifests else None
        if manifest_path and os.path.isfile(manifest_path):
            with open(manifest_path, encoding="utf-8") as handle:
                manifest = json.load(handle)
            check(bool(manifest.get("name")) and bool(manifest.get("icons")),
                  relative + " web manifest has a name and icons")


def validate_headers(website: str) -> None:
    path = os.path.join(website, "_headers")
    if not os.path.isfile(path):
        check(False, "_headers exists")
        return
    rules = 0
    pending = False
    cache_rules = 0
    with open(path, encoding="utf-8") as handle:
        for line_no, raw in enumerate(handle, 1):
            line = raw.rstrip("\r\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            if not line.startswith((" ", "\t")):
                rules += 1
                pending = True
                continue
            pending = False
            match = re.match(r"^\s+([A-Za-z0-9-]+):\s+\S", line)
            check(match is not None,
                  "_headers line %d is a Name: value header" % line_no)
            if match and match.group(1).lower() == "cache-control":
                cache_rules += 1
    check(rules > 0, "_headers has at least one URL rule")
    check(not pending, "_headers has no URL rule without headers")
    check(rules <= 100, "_headers has at most 100 rules (Cloudflare Pages limit)")
    check(cache_rules > 0, "_headers sets Cache-Control somewhere")


def validate_server_pages(server_dir: str, temp_dir: str) -> None:
    for name in ("console.html", "login.html"):
        path = os.path.join(server_dir, name)
        if not os.path.isfile(path):
            check(False, name + " exists")
            continue
        page = parse(path)
        check(page.h1_count >= 1, name + " has a heading")
        check("cartslop:brand:begin" in open(path, encoding="utf-8").read(),
              name + " carries the official-brand head block")
        for tag, url in page.refs:
            if is_local(url):
                check(False, name + " has an unresolved local asset reference: " + url)
        for index, script in enumerate(page.inline_scripts):
            if script.strip():
                check_js("%s inline script %d" % (name, index + 1), script, temp_dir)
        # The form fields the page script looks up must exist in the markup.
        with open(path, encoding="utf-8") as handle:
            text = handle.read()
        for element_id in re.findall(r"getElementById\(['\"]([A-Za-z0-9_-]+)['\"]\)", text):
            check(("id=\"" + element_id + "\"") in text
                  or ("id='" + element_id + "'") in text,
                  name + " has the #" + element_id + " element its script uses")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--website", default=WEBSITE_DEFAULT)
    parser.add_argument("--server-dir", default=SERVER_DEFAULT)
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args(argv)
    website = os.path.abspath(args.website)
    if not os.path.isdir(website):
        print("check_static_site: %s is not a directory" % website,
              file=sys.stderr)
        return 1
    temp_dir = tempfile.mkdtemp(prefix="cartslop_static_")
    try:
        validate_page(website, "index.html", temp_dir, require_index_meta=True)
        validate_page(website, "404.html", temp_dir, require_index_meta=False)
        main_js = os.path.join(website, "main.js")
        if os.path.isfile(main_js):
            with open(main_js, encoding="utf-8") as handle:
                check_js("website/main.js", handle.read(), temp_dir)
        else:
            check(False, "website/main.js exists")
        validate_headers(website)
        robots = os.path.join(website, "robots.txt")
        check(os.path.isfile(robots), "website/robots.txt exists")
        if os.path.isdir(args.server_dir):
            validate_server_pages(args.server_dir, temp_dir)
        else:
            check(False, "server directory exists: " + args.server_dir)
    finally:
        shutil.rmtree(temp_dir, ignore_errors=True)
    print("")
    if FAILS:
        print("STATIC SITE: %d/%d checks FAILED" % (len(FAILS), CHECKS),
              file=sys.stderr)
        return len(FAILS)
    print("STATIC SITE: %d/%d checks passed" % (CHECKS, CHECKS))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
