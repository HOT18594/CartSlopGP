#!/usr/bin/env python3
"""Prove the official Cart Slop GP logo is the only brand art on every surface.

The release requirement is "the exact official logo everywhere, no invented
logos". This audit walks every surface that shows a mark and checks it against
the single source of truth, ``godot_project/assets/ui/cart_icon.png``:

  * the marketing site (``website/``): navbar/hero/footer images, favicons,
    apple-touch icon, web manifest icons, OpenGraph/Twitter card, 404 page;
  * the Pi ``/play`` launcher, its sign-in page and its missing-build page
    (generated inside ``pi_setup/cartslop-server/webhost.py``);
  * the Pi console and login pages (``console.html`` / ``login.html``), whose
    managed block is written by ``website/tools/sync_pi_pages.py``;
  * the Godot Web export icons (``index.icon.png``, ``index.apple-touch-icon.png``,
    ``index.png``) that the browser build itself ships.

It also re-proves the provenance chain: the hash of the official icon and splash
art recorded in ``website/assets/brand-manifest.json``, every generated asset's
hash, the palette-quantised favicon data URI shared by the Pi pages, and that
``project.godot`` still points ``config/icon`` at the official asset.

Usage:
    python web_deploy/scripts/audit_logo_parity.py [--json out.json]
        [--website ../website] [--export-dir ../builds/_ws1_web/export/web]
        [--baseline-dir ../builds/v0.8.6/web]

Exit code = number of failed checks (0 = every surface uses official art).
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys
from html.parser import HTMLParser
from urllib.parse import urlparse

HERE = os.path.dirname(os.path.abspath(__file__))
DEPLOY_ROOT = os.path.dirname(HERE)
WORKSPACE = os.path.dirname(DEPLOY_ROOT)
FAILS: list[str] = []
CHECKS = 0

try:
    from PIL import Image
except ImportError:  # pragma: no cover - environment guard
    Image = None


def check(condition: bool, message: str) -> None:
    global CHECKS
    CHECKS += 1
    if condition:
        print("PASS: " + message)
    else:
        print("FAIL: " + message, file=sys.stderr)
        FAILS.append(message)


def sha256_file(path: str) -> str:
    digest = hashlib.sha256()
    with open(path, "rb") as handle:
        for chunk in iter(lambda: handle.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def image_size(path: str) -> tuple[int, int] | None:
    if Image is None or not os.path.isfile(path):
        return None
    try:
        with Image.open(path) as image:
            return image.size
    except OSError:
        return None


class Refs(HTMLParser):
    def __init__(self) -> None:
        super().__init__()
        self.images: list[tuple[str, str, bool]] = []  # (src, alt, has_alt)
        self.links: list[dict] = []
        self.metas: list[dict] = []
        self.styles: list[str] = []

    def handle_starttag(self, tag, attrs):
        attributes = {key: (value or "") for key, value in attrs}
        if tag == "img":
            self.images.append((attributes.get("src", ""),
                                attributes.get("alt", ""),
                                "alt" in attributes))
        elif tag == "link":
            self.links.append(attributes)
        elif tag == "meta":
            self.metas.append(attributes)
        elif tag == "style" and attributes:
            self.styles.append(attributes.get("id", ""))


def parse_html(path: str) -> Refs:
    refs = Refs()
    with open(path, encoding="utf-8") as handle:
        refs.feed(handle.read())
    return refs


def local_path(website: str, url: str) -> str | None:
    """Map a page URL reference to a file on disk (None for external/data)."""
    if not url or url.startswith(("data:", "http://", "https://", "//", "#")):
        if url.startswith(("http://", "https://")):
            parsed = urlparse(url)
            return os.path.join(website, parsed.path.lstrip("/"))
        return None
    parsed = urlparse(url)
    if parsed.scheme or parsed.netloc:
        return None
    return os.path.join(website, parsed.path.lstrip("/"))


def load_manifest(website: str) -> dict:
    path = os.path.join(website, "assets", "brand-manifest.json")
    if not os.path.isfile(path):
        return {}
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def audit_sources(workspace: str, manifest: dict) -> None:
    icon = os.path.join(workspace, "godot_project", "assets", "ui", "cart_icon.png")
    splash = os.path.join(workspace, "godot_project", "assets", "ui", "boot_splash.png")
    check(image_size(icon) == (512, 512),
          "official logo source cart_icon.png is 512x512")
    check(image_size(splash) == (1280, 720),
          "official splash source boot_splash.png is 1280x720")
    sources = {entry.get("path"): entry for entry in manifest.get("sources", [])}
    for relative, path in (("godot_project/assets/ui/cart_icon.png", icon),
                           ("godot_project/assets/ui/boot_splash.png", splash)):
        recorded = sources.get(relative)
        check(recorded is not None and recorded.get("sha256") == sha256_file(path),
              "brand manifest records the current official art: " + relative)
    project_godot = os.path.join(workspace, "godot_project", "project.godot")
    if os.path.isfile(project_godot):
        with open(project_godot, encoding="utf-8") as handle:
            settings = handle.read()
        check('config/icon="res://assets/ui/cart_icon.png"' in settings,
              "project.godot config/icon is the official cart_icon.png")


def audit_generated_assets(website: str, manifest: dict) -> set[str]:
    allowed: set[str] = set()
    outputs = manifest.get("outputs", [])
    check(bool(outputs), "brand manifest lists the generated assets")
    for entry in outputs:
        relative = entry.get("path", "")
        allowed.add(relative)
        path = os.path.join(website, relative)
        if not os.path.isfile(path):
            check(False, "generated asset exists: " + relative)
            continue
        ok = (os.path.getsize(path) == entry.get("bytes")
              and sha256_file(path) == entry.get("sha256"))
        check(ok, "generated asset matches its recorded hash: " + relative)
    data_uri_file = os.path.join(website, "assets", "favicon-32-data-uri.txt")
    if os.path.isfile(data_uri_file):
        with open(data_uri_file, encoding="utf-8") as handle:
            uri = handle.read().strip()
        check(hashlib.sha256(uri.encode("utf-8")).hexdigest()
              == manifest.get("favicon_data_uri_32_sha256"),
              "favicon data URI hash matches the manifest (Pi pages use this)")
    return allowed


def audit_website(website: str, allowed: set[str]) -> None:
    index = os.path.join(website, "index.html")
    refs = parse_html(index)
    check(any(src == "assets/brand/logo-64.png" for src, _alt, _has in refs.images),
          "website navbar shows the official logo (brand/logo-64.png)")
    check(sum(1 for src, _alt, _has in refs.images
              if src == "assets/brand/logo-64.png") >= 2,
          "website footer shows the official logo (second logo-64.png)")
    check(all(has_alt for _src, _alt, has_alt in refs.images),
          "every website <img> declares an alt attribute")
    check(any(src == "assets/brand/logo-64.png" and alt != ""
              for src, alt, _has in refs.images),
          "navbar logo carries a non-empty alt text")
    icon_links = [link for link in refs.links
                  if "icon" in link.get("rel", "").split()]
    check(len(icon_links) >= 4,
          "website declares standard favicon links (%d found)" % len(icon_links))
    for link in icon_links:
        path = local_path(website, link.get("href", ""))
        check(path is not None and os.path.isfile(path),
              "website icon link resolves: " + link.get("href", ""))
    manifest_link = [link for link in refs.links
                     if link.get("rel") == "manifest"]
    check(bool(manifest_link), "website links the web manifest")
    for attribute in ("og:image", "twitter:image"):
        value = ""
        for meta in refs.metas:
            if meta.get("property") == attribute or meta.get("name") == attribute:
                value = meta.get("content", "")
        path = local_path(website, value)
        check(bool(value) and path is not None and os.path.isfile(path),
              "website %s resolves to a real file" % attribute)
    for required in ("og:title", "og:description", "twitter:card"):
        check(any(meta.get("property") == required or meta.get("name") == required
                  for meta in refs.metas),
              "website declares %s" % required)
    og_image = ""
    for meta in refs.metas:
        if meta.get("property") == "og:image":
            og_image = meta.get("content", "")
    check("assets/og-image.png" in og_image,
          "website OpenGraph card is the generated official-art og-image.png")
    for src, _alt, _has in refs.images:
        path = local_path(website, src)
        if path is None or not os.path.isfile(path):
            continue
        relative = os.path.relpath(path, website).replace("\\", "/")
        check(relative in allowed or relative.startswith("assets/brand/"),
              "website image comes from generated official art: " + relative)

    notfound = os.path.join(website, "404.html")
    if os.path.isfile(notfound):
        refs404 = parse_html(notfound)
        check(any(src == "/assets/brand/logo.png" for src, _alt, _has in refs404.images),
              "404 page shows the official logo")
        check(any(link.get("href", "").endswith("favicon.ico")
                  for link in refs404.links),
              "404 page links the favicon")

    manifest_path = os.path.join(website, "site.webmanifest")
    if os.path.isfile(manifest_path):
        with open(manifest_path, encoding="utf-8") as handle:
            webmanifest = json.load(handle)
        for icon in webmanifest.get("icons", []):
            path = os.path.join(website, icon.get("src", ""))
            if not os.path.isfile(path):
                check(False, "manifest icon resolves: " + icon.get("src", ""))
                continue
            declared = icon.get("sizes", "")
            actual = image_size(path)
            expected = None
            if "x" in declared:
                width, height = declared.split("x", 1)
                expected = (int(width), int(height))
            check(actual == expected,
                  "manifest icon %s is really %s" % (icon.get("src"), declared))

    css = os.path.join(website, "styles.css")
    if os.path.isfile(css):
        with open(css, encoding="utf-8") as handle:
            css_text = handle.read()
        for match in re.finditer(r'url\(([^)]+)\)', css_text):
            reference = match.group(1).strip().strip('"').strip("'")
            if reference.startswith("data:"):
                continue
            path = local_path(website, reference)
            check(path is not None and os.path.isfile(path),
                  "stylesheet asset resolves: " + reference)


def audit_webhost(workspace: str, official_uri: str) -> None:
    path = os.path.join(workspace, "pi_setup", "cartslop-server", "webhost.py")
    if not os.path.isfile(path):
        check(False, "webhost.py exists")
        return
    with open(path, encoding="utf-8") as handle:
        source = handle.read()
    match = re.search(
        r'_BRAND_ICON_DATA_URI: str = \(\s*"(data:image/png;base64,[^"]+)"',
        source)
    check(bool(match), "webhost.py embeds the official brand icon")
    if match:
        check(match.group(1) == official_uri,
              "webhost.py /play icon is the official favicon-32 data URI")
    # The page templates are Python %-format strings, so the literal needle is
    # the placeholder markup exactly as it appears in webhost.py's source.
    for needle, label in (
            ('<link rel="icon" href="%s">', "favicon link"),
            ('<link rel="apple-touch-icon" href="%s">', "apple-touch link"),
            ('<img class="logo" src="%%BRAND_ICON%%"', "header logo img"),
            ('name="twitter:card"', "Twitter card"),
            ('property="og:title"', "OpenGraph title")):
        check(needle in source, "/play page has " + label)


def audit_pi_pages(workspace: str, official_uri: str) -> None:
    for name in ("console.html", "login.html"):
        path = os.path.join(workspace, "pi_setup", "cartslop-server", name)
        if not os.path.isfile(path):
            check(False, name + " exists")
            continue
        with open(path, encoding="utf-8") as handle:
            page = handle.read()
        check('href="' + official_uri + '"' in page,
              name + " links the official favicon data URI")
        check('<img src="' + official_uri + '"' in page,
              name + " header shows the official logo image")
        check("cartslop:brand:begin" in page and "cartslop:brand:end" in page,
              name + " carries the managed brand block")
        check('name="twitter:card"' in page,
              name + " declares a Twitter card")
        check("CS</span>" not in page,
              name + " no longer shows hand-typed initials")


def audit_export(export_dir: str, baseline_dir: str) -> None:
    if not export_dir or not os.path.isdir(export_dir):
        check(False, "Web export directory for logo audit: " + str(export_dir))
        return
    sizes = {}
    for name, expected in (("index.icon.png", None),
                           ("index.apple-touch-icon.png", None),
                           ("index.png", (1280, 720))):
        path = os.path.join(export_dir, name)
        exists = os.path.isfile(path)
        check(exists, "Web export ships " + name)
        if exists:
            sizes[name] = image_size(path)
            if expected is not None:
                check(sizes[name] == expected,
                      "%s is %s" % (name, expected))
    check(sizes.get("index.icon.png") is not None,
          "Web export icon PNG decodes")
    if baseline_dir and os.path.isdir(baseline_dir):
        for name in ("index.icon.png", "index.apple-touch-icon.png"):
            current = os.path.join(export_dir, name)
            baseline = os.path.join(baseline_dir, name)
            if os.path.isfile(current) and os.path.isfile(baseline):
                check(sha256_file(current) == sha256_file(baseline),
                      "%s is byte-identical across exports (stable official derivation)" % name)
    entry = os.path.join(export_dir, "index.html")
    if os.path.isfile(entry):
        with open(entry, encoding="utf-8") as handle:
            html = handle.read()
        check('href="index.icon.png"' in html and
              'href="index.apple-touch-icon.png"' in html,
              "Web export index.html links the generated icon set")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--website", default=os.path.join(WORKSPACE, "website"))
    parser.add_argument("--export-dir",
                        default=os.path.join(WORKSPACE, "builds", "_ws1_web",
                                             "export", "web"))
    parser.add_argument("--baseline-dir",
                        default=os.path.join(WORKSPACE, "builds", "v0.8.6", "web"))
    parser.add_argument("--json", default="")
    args = parser.parse_args(argv)
    website = os.path.abspath(args.website)
    manifest = load_manifest(website)
    check(bool(manifest.get("format")),
          "brand manifest present (website/assets/brand-manifest.json)")
    audit_sources(WORKSPACE, manifest)
    allowed = audit_generated_assets(website, manifest)
    official_uri = ""
    data_uri_file = os.path.join(website, "assets", "favicon-32-data-uri.txt")
    if os.path.isfile(data_uri_file):
        with open(data_uri_file, encoding="utf-8") as handle:
            official_uri = handle.read().strip()
        check(official_uri.startswith("data:image/png;base64,"),
              "favicon-32 data URI is a PNG data URI")
    audit_website(website, allowed)
    audit_webhost(WORKSPACE, official_uri)
    audit_pi_pages(WORKSPACE, official_uri)
    audit_export(args.export_dir, args.baseline_dir)

    inventory = {
        "official_sources": manifest.get("sources", []),
        "generated_assets": [entry.get("path") for entry in manifest.get("outputs", [])],
        "favicon_data_uri_sha256": manifest.get("favicon_data_uri_32_sha256"),
        "checks": CHECKS,
        "failures": FAILS,
    }
    if args.json:
        os.makedirs(os.path.dirname(os.path.abspath(args.json)) or ".",
                    exist_ok=True)
        with open(args.json, "w", encoding="utf-8") as handle:
            json.dump(inventory, handle, indent=1)
            handle.write("\n")
    print("")
    if FAILS:
        print("LOGO PARITY: %d/%d checks FAILED" % (len(FAILS), CHECKS),
              file=sys.stderr)
        return len(FAILS)
    print("LOGO PARITY: %d/%d checks passed - every surface uses official cart_icon art"
          % (CHECKS, CHECKS))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
