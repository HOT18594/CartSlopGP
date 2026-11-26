#!/usr/bin/env python3
"""Put the official Cart Slop GP brand mark on the Pi console/login pages.

The marketing site (``website/``), the ``/play`` launcher and its inline login /
missing-build pages (``pi_setup/cartslop-server/webhost.py``) already show the
official app icon derived from ``godot_project/assets/ui/cart_icon.png``. The
two standalone Pi pages served by ``cartslop_server.py`` -
``pi_setup/cartslop-server/console.html`` and ``login.html`` - are read from
disk and shipped verbatim, so they can only use the logo if it is embedded in
the page itself (the console listener serves no static asset routes, and its CSP
allows ``img-src 'self' data:``).

This tool owns that embedded block. It never invents artwork: the 32x32
palette-quantised PNG data URI comes from
``website/assets/favicon-32-data-uri.txt``, which is generated from the official
icon by ``website/tools/build_brand_assets.py`` and recorded in
``website/assets/brand-manifest.json``. The same URI must appear in webhost.py;
``--check`` proves all four copies agree.

Managed markup (idempotent):

* a ``<!-- cartslop:brand:begin/end -->`` head block with theme-color,
  favicon, apple-touch-icon, robots and OpenGraph/Twitter tags;
* the header ``<span class="mark">CS</span>`` placeholder replaced by
  ``<span class="mark"><img ...></span>`` (the official logo instead of the
  hand-typed initials);
* a tiny ``#cartslop-brand-style`` style block so the icon sits in the existing
  header slot without changing the page layout.

Usage (from the workspace root):
    python website/tools/sync_pi_pages.py --check    # verify only (default)
    python website/tools/sync_pi_pages.py --write    # apply the managed block

Exit code 0 = every surface matches the official art, 1 = a mismatch (the
messages name the file and what to run). ``--check`` is safe in CI; ``--write``
is deterministic, so running it twice produces byte-identical files.
"""
from __future__ import annotations

import argparse
import hashlib
import json
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
WEBSITE = os.path.dirname(HERE)
WORKSPACE = os.path.dirname(WEBSITE)
SERVER_DIR = os.path.join(WORKSPACE, "pi_setup", "cartslop-server")
MANIFEST = os.path.join(WEBSITE, "assets", "brand-manifest.json")
DATA_URI_FILE = os.path.join(WEBSITE, "assets", "favicon-32-data-uri.txt")
EMBED_PNG = os.path.join(WEBSITE, "assets", "favicon-embed.png")
WEBHOST = os.path.join(SERVER_DIR, "webhost.py")
TARGETS = (
    os.path.join(SERVER_DIR, "console.html"),
    os.path.join(SERVER_DIR, "login.html"),
)

MARK_BEGIN = "<!-- cartslop:brand:begin -->"
MARK_END = "<!-- cartslop:brand:end -->"
STYLE_ID = "cartslop-brand-style"
MARK_PLACEHOLDER = '<span class="mark">CS</span>'
DEFAULT_TERMINAL_COLOR = "#080808"

FAILS: list[str] = []
CHECKS = 0


def check(condition: bool, message: str) -> None:
    global CHECKS
    CHECKS += 1
    if condition:
        print("PASS: " + message)
    else:
        print("FAIL: " + message, file=sys.stderr)
        FAILS.append(message)


def sha256_bytes(payload: bytes) -> str:
    return hashlib.sha256(payload).hexdigest()


def rel(path: str) -> str:
    return os.path.relpath(path, WORKSPACE).replace("\\", "/")


def load_brand() -> tuple[str, dict]:
    """Return (data URI, manifest) after proving the URI belongs to the art."""
    manifest = None
    if os.path.isfile(MANIFEST):
        with open(MANIFEST, encoding="utf-8") as handle:
            manifest = json.load(handle)
    if not os.path.isfile(DATA_URI_FILE):
        raise SystemExit("missing %s - run python website/tools/"
                         "build_brand_assets.py" % rel(DATA_URI_FILE))
    with open(DATA_URI_FILE, encoding="utf-8") as handle:
        uri = handle.read().strip()
    if not re.match(r"^data:image/png;base64,[A-Za-z0-9+/=]+$", uri):
        raise SystemExit("%s does not hold a PNG data URI" % rel(DATA_URI_FILE))
    if manifest is not None:
        recorded = manifest.get("favicon_data_uri_32_sha256")
        if recorded != sha256_bytes(uri.encode("utf-8")):
            raise SystemExit(
                "%s does not match the hash in %s; regenerate the brand assets"
                % (rel(DATA_URI_FILE), rel(MANIFEST)))
    return uri, manifest or {}


def expected_block(uri: str, terminal_color: str) -> str:
    """The full managed head block, one line per tag, stable order."""
    return "\n".join([
        MARK_BEGIN,
        "<!-- Official app icon (godot_project/assets/ui/cart_icon.png) via "
        "website/tools/build_brand_assets.py;",
        "     synced by website/tools/sync_pi_pages.py. Do not edit by hand. -->",
        '<meta name="theme-color" content="%s">' % terminal_color,
        '<meta name="robots" content="noindex, nofollow">',
        '<link rel="icon" type="image/png" sizes="32x32" href="%s">' % uri,
        '<link rel="apple-touch-icon" href="%s">' % uri,
        '<meta property="og:type" content="website">',
        '<meta property="og:site_name" content="Cart Slop GP">',
        '<meta property="og:title" content="Cart Slop GP - Pi Console">',
        '<meta name="twitter:card" content="summary">',
        '<style id="%s">' % STYLE_ID,
        ".mark img{width:100%;height:100%;display:block;border-radius:5px}",
        ".mark{overflow:hidden;padding:0;background:transparent;border:0}",
        "</style>",
        MARK_END,
    ])


def expected_logo_span(uri: str) -> str:
    return ('<span class="mark"><img src="%s" alt="Cart Slop GP" '
            'width="26" height="26"></span>' % uri)


def strip_managed(html: str) -> str:
    """Remove a previous managed block so a fresh one can be compared/written."""
    begin = html.find(MARK_BEGIN)
    if begin >= 0:
        end = html.find(MARK_END, begin)
        if end < 0:
            raise SystemExit("brand block has a begin marker but no end marker")
        tail = html[end + len(MARK_END):]
        # The renderer puts exactly one newline between the block and the next
        # line; drop a single one of ours so re-rendering is byte-identical
        # (idempotent --write) instead of accumulating blank lines.
        if tail.startswith("\r\n"):
            tail = tail[2:]
        elif tail.startswith("\n"):
            tail = tail[1:]
        html = html[:begin] + tail
    html = re.sub(r'<span class="mark"><img [^>]*></span>',
                  MARK_PLACEHOLDER, html)
    return html


def render(original: str, uri: str) -> str:
    """Return the target page text with exactly one managed block + logo."""
    if original.count(MARK_PLACEHOLDER) > 1:
        raise SystemExit("page has more than one '<span class=\"mark\">CS</span>'")
    block = expected_block(uri, DEFAULT_TERMINAL_COLOR)
    clean = strip_managed(original)
    head_end = clean.find("</head>")
    if head_end < 0:
        raise SystemExit("page has no </head>")
    stamped = clean[:head_end] + block + "\n" + clean[head_end:]
    if MARK_PLACEHOLDER in stamped:
        stamped = stamped.replace(MARK_PLACEHOLDER, expected_logo_span(uri), 1)
    return stamped


def verify_webhost(uri: str) -> None:
    if not os.path.isfile(WEBHOST):
        check(False, "%s exists" % rel(WEBHOST))
        return
    with open(WEBHOST, encoding="utf-8") as handle:
        source = handle.read()
    match = re.search(
        r'_BRAND_ICON_DATA_URI: str = \(\s*"(data:image/png;base64,[^"]+)"',
        source)
    check(bool(match), "webhost.py declares the embedded brand icon")
    if match:
        check(match.group(1) == uri,
              "webhost.py icon == website/assets/favicon-32-data-uri.txt")
    check('class="logo"' in source and "%%BRAND_ICON%%" in source,
          "webhost.py /play + login/missing pages render the brand <img>")
    check('rel="icon"' in source and 'rel="apple-touch-icon"' in source,
          "webhost.py pages link the favicon and apple-touch-icon")
    check('property="og:title"' in source and 'name="twitter:card"' in source,
          "webhost.py pages carry OpenGraph/Twitter meta")


def verify_target(path: str, uri: str, write: bool) -> None:
    name = rel(path)
    if not os.path.isfile(path):
        check(False, name + " exists")
        return
    with open(path, encoding="utf-8") as handle:
        original = handle.read()
    expected = render(original, uri)
    if write and expected != original:
        with open(path, "w", encoding="utf-8", newline="") as handle:
            handle.write(expected)
        print("WROTE: " + name)
    elif write:
        print("UNCHANGED: " + name)
    if write:
        with open(path, encoding="utf-8") as handle:
            original = handle.read()
        expected = render(original, uri)
    current = original
    check(current.count(MARK_BEGIN) == 1 and current.count(MARK_END) == 1,
          name + " has exactly one managed brand block")
    block = expected_block(uri, DEFAULT_TERMINAL_COLOR)
    check(block in current, name + " brand block is current (official icon URI)")
    check(current.count('rel="icon"') == 1 and
          current.count('rel="apple-touch-icon"') == 1,
          name + " links one favicon and one apple-touch-icon")
    check(current.count('<img src="%s"' % uri) == 1,
          name + " header shows the official logo <img>")
    check("CS</span>" not in current.replace("Cart Slop", ""),
          name + " no longer shows the hand-typed CS initials")
    check('property="og:title"' in current and 'name="twitter:card"' in current,
          name + " carries OpenGraph/Twitter meta")
    if not write and current != expected:
        check(False, name + " is not what sync_pi_pages.py --write would produce")
    elif not write:
        check(True, name + " is exactly what --write would produce")


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--write", action="store_true",
                        help="apply the managed block (default: check only)")
    parser.add_argument("--check", action="store_true",
                        help="verify only (this is the default; accepted for "
                             "symmetry with the other tools)")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args(argv)
    uri, manifest = load_brand()
    check(bool(manifest), "brand manifest is readable")
    png_ok = False
    if os.path.isfile(EMBED_PNG):
        with open(EMBED_PNG, "rb") as handle:
            payload = handle.read()
        png_ok = (payload.startswith(b"\x89PNG\r\n\x1a\n")
                  and ("data:image/png;base64,"
                       + _b64(payload)) == uri)
    check(png_ok, "favicon-embed.png is the PNG the data URI embeds")
    verify_webhost(uri)
    for target in TARGETS:
        verify_target(target, uri, args.write)
    print("")
    if FAILS:
        print("BRAND SYNC: %d/%d checks FAILED" % (len(FAILS), CHECKS),
              file=sys.stderr)
        return 1
    print("BRAND SYNC: %d/%d checks passed (%s)" % (CHECKS, CHECKS,
                                                    "written" if args.write
                                                    else "verified only"))
    return 0


def _b64(payload: bytes) -> str:
    import base64
    return base64.b64encode(payload).decode("ascii")


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
