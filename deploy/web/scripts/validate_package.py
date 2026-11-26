#!/usr/bin/env python3
"""Validate the web_deploy package without a Cloudflare account or network.

This is the "is the package deployable?" gate that can run on the dev PC:
it parses every config file the way the real tools would (JSON/JSONC, TOML),
checks the generated Cloudflare Pages files against the documented syntax and
the Cache-Control join pitfall, verifies the Worker parses as an ES module,
confirms the staged `dist/` layout matches the versioned architecture, and
scans the whole package for accidentally committed credentials.

Usage (from the workspace root):
    python web_deploy/scripts/validate_package.py [--stage-if-missing]

Exit code = number of failed checks. It never contacts Cloudflare and never
prints a token; a real deployment is a manual owner action (see README.md).
"""
from __future__ import annotations

import argparse
import json
import os
import re
import shutil
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
DEPLOY_ROOT = os.path.dirname(HERE)
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


def human(size: int) -> str:
    value = float(size)
    for unit in ("B", "KB", "MB", "GB"):
        if value < 1024 or unit == "GB":
            return ("%d B" % int(value)) if unit == "B" else "%.2f %s" % (value, unit)
        value /= 1024.0
    return "%d B" % int(value)


def strip_jsonc(text: str) -> str:
    """Remove // and /* */ comments plus trailing commas (JSONC -> JSON)."""
    output: list[str] = []
    index = 0
    length = len(text)
    in_string = False
    while index < length:
        char = text[index]
        if in_string:
            output.append(char)
            if char == "\\" and index + 1 < length:
                output.append(text[index + 1])
                index += 2
                continue
            if char == '"':
                in_string = False
            index += 1
            continue
        if char == '"':
            in_string = True
            output.append(char)
            index += 1
            continue
        if text.startswith("//", index):
            end = text.find("\n", index)
            index = length if end < 0 else end
            continue
        if text.startswith("/*", index):
            end = text.find("*/", index + 2)
            index = length if end < 0 else end + 2
            continue
        output.append(char)
        index += 1
    stripped = "".join(output)
    stripped = re.sub(r",\s*([}\]])", r"\1", stripped)
    return stripped


def load_json(path: str, jsonc: bool = False) -> dict | None:
    if not os.path.isfile(path):
        check(False, "config exists: " + os.path.relpath(path, DEPLOY_ROOT))
        return None
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    if jsonc:
        text = strip_jsonc(text)
    try:
        return json.loads(text)
    except json.JSONDecodeError as error:
        check(False, "config parses as JSON: %s (%s)"
              % (os.path.relpath(path, DEPLOY_ROOT), error))
        return None


def validate_configs() -> None:
    package = load_json(os.path.join(DEPLOY_ROOT, "package.json"))
    if package is not None:
        check(package.get("private") is True,
              "package.json is private (never published to npm)")
        scripts = package.get("scripts", {})
        for name in ("stage", "deploy:pages", "deploy:r2", "verify",
                     "test:parity"):
            check(name in scripts, "package.json exposes the '%s' script" % name)
        deps = package.get("devDependencies", {})
        check("wrangler" in deps, "package.json pins wrangler as a devDependency")

    pages = load_json(os.path.join(DEPLOY_ROOT, "wrangler.pages.jsonc"), jsonc=True)
    if pages is not None:
        check(pages.get("name") == "cartslop-play",
              "wrangler.pages.jsonc names the Pages project")
        check(pages.get("pages_build_output_dir") == "./dist",
              "wrangler.pages.jsonc points at ./dist")
        check(bool(re.fullmatch(r"\d{4}-\d{2}-\d{2}",
                                str(pages.get("compatibility_date", "")))),
              "wrangler.pages.jsonc sets a compatibility_date")

    r2 = load_json(os.path.join(DEPLOY_ROOT, "wrangler.r2.jsonc"), jsonc=True)
    if r2 is not None:
        check(r2.get("main") == "worker/index.js",
              "wrangler.r2.jsonc has a Worker entry point")
        bindings = r2.get("r2_buckets", [])
        check(bool(bindings) and bindings[0].get("binding") == "WEB_ASSETS",
              "wrangler.r2.jsonc binds the WEB_ASSETS R2 bucket")
        check(bindings and bindings[0].get("bucket_name") == "cartslop-web",
              "wrangler.r2.jsonc names the cartslop-web bucket")


def validate_worker() -> None:
    node = shutil.which("node")
    worker = os.path.join(DEPLOY_ROOT, "worker", "index.js")
    if node is None:
        check(True, "Worker syntax (node not installed; skipped)")
        return
    if not os.path.isfile(worker):
        check(False, "worker/index.js exists")
        return
    result = subprocess.run([node, "--check", worker], capture_output=True,
                            text=True, cwd=DEPLOY_ROOT)
    check(result.returncode == 0,
          "worker/index.js passes node --check"
          + ("" if result.returncode == 0
             else ": " + result.stderr.strip()[:300]))


def parse_headers(path: str) -> list[dict]:
    """Parse a Cloudflare _headers file into [{'path','headers':[(n,v,detach)]}]."""
    blocks: list[dict] = []
    current: dict | None = None
    with open(path, encoding="utf-8") as handle:
        for raw in handle:
            line = raw.rstrip("\r\n")
            if not line.strip() or line.lstrip().startswith("#"):
                continue
            if not line.startswith((" ", "\t")):
                current = {"path": line.strip(), "headers": []}
                blocks.append(current)
                continue
            # `! Header-Name` (no value) removes a header set by earlier rules.
            detach_match = re.match(r"^\s+!\s*([A-Za-z0-9-]+)\s*$", line)
            if detach_match and current is not None:
                current["headers"].append((detach_match.group(1), "", True))
                continue
            match = re.match(r"^\s+([A-Za-z0-9-]+):\s+(.+)$", line)
            if current is None or match is None:
                continue
            current["headers"].append((match.group(1), match.group(2), False))
    return blocks


def _rule_matches(pattern: str, path: str) -> bool:
    """Cloudflare Pages header/redirect matching for the patterns this package uses."""
    if pattern == "/*":
        return True
    if pattern.endswith("/*"):
        return path.startswith(pattern[:-1])
    if pattern.endswith("*"):
        return path.startswith(pattern[:-1])
    if "%%" in pattern or "%%" in path:
        return False
    return pattern == path


def validate_headers(path: str, label: str) -> None:
    if not os.path.isfile(path):
        check(False, label + " exists")
        return
    blocks = parse_headers(path)
    check(len(blocks) > 0, label + " has URL rules")
    check(len(blocks) <= 100, label + " stays under the 100-rule Pages limit")
    paths = [block["path"] for block in blocks]
    check(len(paths) == len(set(paths)),
          label + " has no duplicate URL rules")
    check(any("game/*" in path or path == "/*" for path in paths),
          label + " has a broad rule for payloads")
    # The documented pitfall: two matching rules that both set Cache-Control are
    # joined with a comma and corrupt the directive. A narrower Cache-Control
    # rule only needs `! Cache-Control` when an earlier broad rule also sets
    # Cache-Control AND actually matches that path.
    cache_broad: list[str] = []
    for block in blocks:
        header_names = [name.lower() for name, _value, _detach in block["headers"]]
        has_cache = "cache-control" in header_names
        if not has_cache:
            continue
        detached = any(name.lower() == "cache-control" and detach
                       for name, _value, detach in block["headers"])
        earlier_broad_hits = [pattern for pattern in cache_broad
                              if _rule_matches(pattern, block["path"])]
        if earlier_broad_hits and not detached:
            check(False,
                  label + ": rule " + block["path"]
                  + " detaches Cache-Control before overriding " + earlier_broad_hits[0])
        elif earlier_broad_hits:
            check(True,
                  label + ": rule " + block["path"]
                  + " detaches Cache-Control before overriding " + earlier_broad_hits[0])
        if block["path"] in ("/*", "/game/*"):
            cache_broad.append(block["path"])
    immutable = [block for block in blocks
                 if block["path"] == "/game/*"
                 and any("immutable" in value for _n, value, _d in block["headers"])]
    check(bool(immutable), label + " makes /game/* immutable")
    no_store = [block for block in blocks
                if any("no-store" in value.lower()
                       for _n, value, _d in block["headers"])]
    check(any(block["path"].endswith("/index.html") for block in no_store),
          label + " marks the entry index.html no-store")
    check(any("version.json" in block["path"] for block in no_store),
          label + " marks version.json no-store")
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    if label.startswith("templates"):
        check("%%COOP_COEP%%" in text,
              label + " carries the generated COOP/COEP block placeholder")
    else:
        check("Cross-Origin-Opener-Policy" in text,
              label + " documents the conditional COOP header")
        check("Cross-Origin-Embedder-Policy" in text,
              label + " documents the conditional COEP header")


def validate_redirects(path: str, label: str) -> None:
    if not os.path.isfile(path):
        check(False, label + " exists")
        return
    with open(path, encoding="utf-8") as handle:
        text = handle.read()
    # Validate the template's semantics by filling its placeholders with a
    # representative release path before parsing.
    text = text.replace("%%RELEASE_DIR%%", "/game/0.0.0/000000000000")
    text = text.replace("%%FLAT_REDIRECTS%%",
                        "/index.js /game/0.0.0/000000000000/index.js 301")
    sources: set[str] = set()
    dynamic_seen = False
    static_count = 0
    redirects: list[tuple[str, str, int]] = []
    for line_no, raw in enumerate(text.splitlines(), 1):
        line = raw.strip()
        if not line or line.startswith("#"):
            continue
        parts = line.split()
        check(len(parts) in (2, 3), label + " line %d has source [dest] [code]" % line_no)
        if len(parts) < 2:
            continue
        source, destination = parts[0], parts[1]
        code = int(parts[2]) if len(parts) == 3 else 302
        check(code in (200, 301, 302, 303, 307, 308),
              label + " line %d uses a supported status (%d)" % (line_no, code))
        check(source.count("*") <= 1 and destination.count("*") <= 1,
              label + " line %d has at most one splat" % line_no)
        check(source not in sources,
              label + " line %d does not duplicate a source" % line_no)
        sources.add(source)
        if "*" in source or ":" in source:
            dynamic_seen = True
        else:
            check(not dynamic_seen,
                  label + " line %d keeps static rules before dynamic ones" % line_no)
            static_count += 1
        redirects.append((source, destination, code))
    check(static_count > 0, label + " has static redirects")
    root = [entry for entry in redirects if entry[0] == "/"]
    check(bool(root), label + " redirects / to the release entry")
    if root:
        target = root[0][1]
        check(("/game/" in target or "%%RELEASE_DIR%%" in target)
              and target.endswith("/index.html"),
              label + " root redirect targets the versioned index.html")
        check(root[0][2] == 302, label + " root redirect is 302 (target changes per release)")


def validate_stage() -> None:
    dist = os.path.join(DEPLOY_ROOT, "dist")
    if not os.path.isdir(dist):
        check(False, "dist/ is staged (run scripts/stage_release.ps1)")
        return
    release_path = os.path.join(dist, "release.json")
    if not os.path.isfile(release_path):
        check(False, "dist/release.json exists")
        return
    with open(release_path, encoding="utf-8") as handle:
        release = json.load(handle)
    check(release.get("schema") == "cartslop.web_hosting/1",
          "dist/release.json has the hosting schema")
    version = str(release.get("game_version", ""))
    build_id = str(release.get("build_id", ""))
    release_dir = os.path.join(dist, "game", version, build_id[:12])
    check(len(build_id) == 64 and os.path.isdir(release_dir),
          "dist release lives under /game/<version>/<build-id>/")
    for name in ("index.html", "index.js", "index.wasm", "index.pck"):
        check(os.path.isfile(os.path.join(release_dir, name)),
              "dist release ships " + name)
    check(os.path.isfile(os.path.join(release_dir, "version.json")),
          "dist release keeps its own version.json")
    root_stamp = os.path.join(dist, "version.json")
    check(os.path.isfile(root_stamp), "dist/version.json pointer exists")
    if os.path.isfile(root_stamp):
        with open(root_stamp, encoding="utf-8") as handle:
            stamp = json.load(handle)
        check(str(stamp.get("build_id")) == build_id,
              "dist/version.json matches release.json build id")
    # Cloudflare Pages' documented 25 MiB per-asset limit decides which host can
    # serve this build; the stager records the answer in release.json and the
    # upload script refuses accordingly.
    limit = int(release.get("pages_limit_bytes", 0))
    check(limit == 25 * 1024 * 1024,
          "release.json records the Cloudflare Pages 25 MiB asset limit")
    check(isinstance(release.get("pages_compatible"), bool),
          "release.json records pages_compatible")
    largest = 0
    for name in os.listdir(release_dir):
        path = os.path.join(release_dir, name)
        if os.path.isfile(path):
            largest = max(largest, os.path.getsize(path))
    check(int(release.get("largest_file_bytes", -1)) == largest,
          "release.json reports the real largest file size")
    expected_compatible = largest <= limit
    check(bool(release.get("pages_compatible")) == expected_compatible,
          "pages_compatible matches the 25 MiB limit (largest file %s)"
          % human(largest))
    validate_headers(os.path.join(dist, "_headers"), "dist/_headers")
    validate_redirects(os.path.join(dist, "_redirects"), "dist/_redirects")
    check(os.path.isfile(os.path.join(dist, "robots.txt")),
          "dist/robots.txt exists")


def scan_for_secrets() -> None:
    patterns = {
        "API token assignment": re.compile(r"CLOUDFLARE_API_TOKEN\s*=\s*\S+"),
        "Bearer token": re.compile(r"Bearer\s+[A-Za-z0-9._-]{20,}"),
        "private key block": re.compile(r"-----BEGIN [A-Z ]*PRIVATE KEY-----"),
        "AWS-style key": re.compile(r"AKIA[0-9A-Z]{16}"),
    }
    hits: list[str] = []
    for directory, subdirs, names in os.walk(DEPLOY_ROOT):
        subdirs[:] = [name for name in subdirs
                      if name not in ("node_modules", "dist", ".wrangler",
                                      "__pycache__")]
        for name in names:
            if not name.endswith((".md", ".ps1", ".py", ".js", ".mjs",
                                  ".json", ".jsonc", ".toml", ".txt")):
                continue
            path = os.path.join(directory, name)
            try:
                with open(path, encoding="utf-8", errors="replace") as handle:
                    text = handle.read()
            except OSError:
                continue
            for label, pattern in patterns.items():
                for match in pattern.finditer(text):
                    # Documentation placeholders like "<token>" are fine.
                    value = match.group(0)
                    if "<" in value or "..." in value or "example" in value.lower():
                        continue
                    hits.append("%s in %s" % (label, os.path.relpath(path, DEPLOY_ROOT)))
    check(not hits, "no credentials in the package"
          + (": " + "; ".join(hits[:3]) if hits else ""))
    check(not os.path.isfile(os.path.join(DEPLOY_ROOT, ".dev.vars")),
          "no .dev.vars credentials file")


def validate_readme() -> None:
    path = os.path.join(DEPLOY_ROOT, "README.md")
    if not os.path.isfile(path):
        check(False, "web_deploy/README.md exists")
        return
    with open(path, encoding="utf-8") as handle:
        text = handle.read().lower()
    for needle, label in (
            ("cloudflare", "Cloudflare"),
            ("api token", "API token"),
            ("pages project", "Pages project"),
            ("r2 bucket", "R2 bucket"),
            ("custom domain", "custom domain"),
            ("dns", "DNS"),
            ("coop", "COOP documentation"),
            ("coep", "COEP documentation"),
            ("manual", "manual approval note"),
            ("rollback", "rollback steps"),
            ("25 mib", "the Cloudflare Pages 25 MiB per-asset limit"),
            ("upload_r2", "the R2 + Worker deploy path")):
        check(needle in text, "README documents " + label)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--stage-if-missing", action="store_true",
                        help="informational only; staging is done by the "
                             "PowerShell script")
    parser.parse_args(argv)
    validate_configs()
    validate_worker()
    validate_headers(os.path.join(DEPLOY_ROOT, "templates", "_headers"),
                     "templates/_headers")
    validate_redirects(os.path.join(DEPLOY_ROOT, "templates", "_redirects"),
                       "templates/_redirects")
    validate_stage()
    scan_for_secrets()
    validate_readme()
    print("")
    if FAILS:
        print("WEB DEPLOY PACKAGE: %d/%d checks FAILED" % (len(FAILS), CHECKS),
              file=sys.stderr)
        return len(FAILS)
    print("WEB DEPLOY PACKAGE: %d/%d checks passed" % (CHECKS, CHECKS))
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
