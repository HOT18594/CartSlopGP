#!/usr/bin/env python3
"""Measure a staged Godot Web release: bytes, compression, pack composition, latency.

Produces the numbers that go into ``_audit/reports/ws1-web.md`` and lets a
reviewer re-run them. Three independent measurements:

1. **Download size** - every file in the export, its gzip/Brotli sibling size
   and ratio (read from a ``precompress_web.py`` JSON report, or measured here
   with gzip when no report is given). Totals and the first-load critical path
   (index.html + js + wasm + pck).
2. **What is in the pack** - ``index.pck`` is 120 MB; ``pck_stats.py`` is used
   to break it down by extension (textures, audio, scenes, ...) and count the
   editor sidecars that survive the export filter. If a second (older) export
   is given with ``--baseline-dir`` the two packs are compared.
3. **Serve path** - imports the real ``pi_setup/cartslop-server/webhost.py``,
   starts it on an ephemeral loopback port with the export as its web root and
   times ``/api/web/version``, the launcher entry HTML, the wasm and the 120 MB
   pck with and without ``Accept-Encoding``. This proves the version stamp and
   the pre-compressed siblings are actually served with the right headers
   (``Content-Encoding``, ``Cache-Control: no-store`` for the stamp, Vary).

Usage (from the workspace root):
    python web_deploy/scripts/measure_web_release.py \
        --export-dir builds/_ws1_web/export/web \
        --compression-report builds/_ws1_web/precompress-report.json \
        --baseline-dir builds/v0.8.6/web \
        --json builds/_ws1_web/measure-web.json \
        --markdown builds/_ws1_web/measure-web.md

Exit code 0 on success, 1 on a measurement failure (missing files, webhost
import error). The script never writes into the export directory.
"""
from __future__ import annotations

import argparse
import http.client
import importlib
import json
import os
import statistics
import sys
import threading
import time
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HERE = os.path.dirname(os.path.abspath(__file__))
sys.path.insert(0, HERE)
WORKSPACE = os.path.abspath(os.path.join(HERE, "..", ".."))
SERVER_DIR = os.path.join(WORKSPACE, "pi_setup", "cartslop-server")

import pck_stats  # noqa: E402  (same directory)

CRITICAL = ("index.html", "index.js", "index.wasm", "index.pck")


def human(value: float) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if value < 1024 or unit == "GB":
            return ("%d B" % int(value)) if unit == "B" else "%.2f %s" % (value, unit)
        value /= 1024.0
    return "%d B" % int(value)


def stamp_of(export_dir: str) -> dict:
    path = os.path.join(export_dir, "version.json")
    if not os.path.isfile(path):
        raise SystemExit("missing %s - stamp the export first "
                         "(pi_setup/sync_web_release.ps1)" % path)
    with open(path, encoding="utf-8") as handle:
        return json.load(handle)


def file_table(export_dir: str, report: dict | None) -> list[dict]:
    compressed = {}
    if report:
        for entry in report.get("files", []):
            compressed[entry["path"]] = entry
    rows = []
    for name in sorted(os.listdir(export_dir)):
        path = os.path.join(export_dir, name)
        if not os.path.isfile(path) or name.endswith((".gz", ".br")):
            continue
        raw = os.path.getsize(path)
        entry = compressed.get(name, {})
        gz = entry.get("gzip")
        br = entry.get("brotli")
        rows.append({
            "path": name,
            "raw": raw,
            "gzip": gz,
            "brotli": br,
            "gzip_ratio": (round(1.0 - gz / raw, 4)
                           if gz and raw else None),
            "brotli_ratio": (round(1.0 - br / raw, 4)
                             if br and raw else None),
        })
    return rows


class _Handler(BaseHTTPRequestHandler):
    auth_ok = True

    def _run(self, method: str) -> None:
        try:
            if not webhost.handle(self, method, self.path, self.auth_ok):
                self.send_error(404)
        except (BrokenPipeError, ConnectionResetError):
            self.close_connection = True

    def do_GET(self) -> None:
        self._run("GET")

    def do_HEAD(self) -> None:
        self._run("HEAD")

    def log_message(self, *_args) -> None:
        pass


webhost = None


def load_webhost(export_dir: str, version: str) -> None:
    os.environ["CARTSLOP_WEB_ROOT"] = os.path.abspath(export_dir)
    os.environ["CARTSLOP_GAME_VERSION"] = version
    os.environ.pop("CARTSLOP_WEB_BASE", None)
    global webhost
    if SERVER_DIR not in sys.path:
        sys.path.insert(0, SERVER_DIR)
    if "webhost" in sys.modules:
        webhost = importlib.reload(sys.modules["webhost"])
    else:
        import webhost as module  # noqa: PLC0415
        webhost = module


class Loopback:
    def __init__(self) -> None:
        self.server = ThreadingHTTPServer(("127.0.0.1", 0), _Handler)
        self.thread = threading.Thread(target=self.server.serve_forever,
                                       daemon=True)
        self.port = self.server.server_address[1]

    def __enter__(self):
        self.thread.start()
        return self

    def __exit__(self, *_exc):
        self.server.shutdown()
        self.server.server_close()

    def sample(self, path: str, accept_encoding: str = "") -> dict:
        started = time.perf_counter()
        connection = http.client.HTTPConnection("127.0.0.1", self.port,
                                                timeout=120)
        headers = {"Accept-Encoding": accept_encoding} if accept_encoding else {}
        connection.request("GET", path, headers=headers)
        response = connection.getresponse()
        response.read()
        total_ms = (time.perf_counter() - started) * 1000.0
        payload = response.getheader("Content-Length")
        return {
            "path": path,
            "accept_encoding": accept_encoding or "identity",
            "status": response.status,
            "bytes": int(payload) if payload and payload.isdigit() else None,
            "content_encoding": response.getheader("Content-Encoding") or "",
            "cache_control": response.getheader("Cache-Control") or "",
            "vary": response.getheader("Vary") or "",
            "total_ms": round(total_ms, 2),
        }


def serve_bench(export_dir: str, version: str, samples: int) -> dict:
    load_webhost(export_dir, version)
    bench: dict = {"samples": samples, "routes": []}
    plans = [
        ("/api/web/version", "", samples * 3),
        ("/game/index.html", "", samples * 3),
        ("/game/version.json", "", samples * 2),
        ("/game/index.js", "gzip, br", samples * 2),
        ("/game/index.wasm", "gzip", max(2, samples // 2)),
        ("/game/index.wasm", "br", max(2, samples // 2)),
        ("/game/index.pck", "br", max(2, samples // 2)),
    ]
    with Loopback() as server:
        for path, encoding, count in plans:
            results = [server.sample(path, encoding) for _index in range(count)]
            ok = [r for r in results if r["status"] == 200]
            entry = {
                "path": path,
                "accept_encoding": encoding or "identity",
                "requests": count,
                "statuses": sorted({r["status"] for r in results}),
                "content_encoding": sorted({r["content_encoding"] for r in results}),
                "cache_control": sorted({r["cache_control"] for r in results}),
                "vary": sorted({r["vary"] for r in results}),
                "bytes": sorted({r["bytes"] for r in results if r["bytes"]}),
                "median_ms": round(statistics.median(
                    [r["total_ms"] for r in ok]), 2) if ok else None,
                "p95_ms": round(sorted(r["total_ms"] for r in ok)[
                    max(0, int(0.95 * len(ok)) - 1)], 2) if ok else None,
                "min_ms": round(min(r["total_ms"] for r in ok), 2) if ok else None,
            }
            bench["routes"].append(entry)
    return bench


def pck_measure(export_dir: str) -> dict | None:
    path = os.path.join(export_dir, "index.pck")
    if not os.path.isfile(path):
        return None
    try:
        parsed = pck_stats.parse_pck(path)
        return pck_stats.composition(parsed)
    except (OSError, pck_stats.PckError) as error:
        print("measure: pck_stats failed: %s" % error, file=sys.stderr)
        return None


def baseline_measure(directory: str | None) -> dict | None:
    if not directory or not os.path.isdir(directory):
        return None
    files = {}
    for name in sorted(os.listdir(directory)):
        path = os.path.join(directory, name)
        if os.path.isfile(path):
            files[name] = os.path.getsize(path)
    result = {"dir": os.path.abspath(directory), "file_count": len(files),
              "bytes": sum(files.values()), "files": files}
    result["pck"] = pck_measure(directory)
    return result


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--export-dir", required=True)
    parser.add_argument("--compression-report", default="")
    parser.add_argument("--baseline-dir", default="")
    parser.add_argument("--sample-count", type=int, default=5)
    parser.add_argument("--no-serve", action="store_true")
    parser.add_argument("--json", default="")
    parser.add_argument("--markdown", default="")
    args = parser.parse_args(argv)
    export_dir = os.path.abspath(args.export_dir)
    if not os.path.isdir(export_dir):
        print("measure: %s is not a directory" % export_dir, file=sys.stderr)
        return 1
    stamp = stamp_of(export_dir)
    report = None
    if args.compression_report:
        with open(args.compression_report, encoding="utf-8") as handle:
            report = json.load(handle)
    rows = file_table(export_dir, report)
    missing = [name for name in CRITICAL
               if not os.path.isfile(os.path.join(export_dir, name))]
    if missing:
        print("measure: export is missing %s" % ", ".join(missing),
              file=sys.stderr)
        return 1
    critical = [row for row in rows if row["path"] in CRITICAL]
    result: dict = {
        "generated_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "export_dir": export_dir,
        "stamp": {"game_version": stamp.get("game_version"),
                  "engine_version": stamp.get("engine_version"),
                  "build_id": stamp.get("build_id"),
                  "built_utc": stamp.get("built_utc")},
        "files": rows,
        "totals": {
            "bytes": sum(row["raw"] for row in rows),
            "file_count": len(rows),
        },
        "critical_path": {
            "bytes": sum(row["raw"] for row in critical),
            "gzip_bytes": sum(row["gzip"] or row["raw"] for row in critical),
            "brotli_bytes": sum(row["brotli"] or row["raw"] for row in critical),
            "files": [row["path"] for row in critical],
        },
        "pck": pck_measure(export_dir),
        "baseline": baseline_measure(args.baseline_dir),
    }
    if report:
        result["compression_encoder"] = report.get("brotli_encoder")
    if not args.no_serve:
        try:
            result["serve"] = serve_bench(export_dir,
                                          str(stamp.get("game_version") or ""),
                                          args.sample_count)
        except Exception as error:  # noqa: BLE001 - report, do not hide
            result["serve"] = {"error": str(error)}
            print("measure: serve benchmark failed: %s" % error,
                  file=sys.stderr)
    if args.json:
        os.makedirs(os.path.dirname(os.path.abspath(args.json)) or ".",
                    exist_ok=True)
        with open(args.json, "w", encoding="utf-8") as handle:
            json.dump(result, handle, indent=1)
            handle.write("\n")
    markdown = render_markdown(result)
    if args.markdown:
        os.makedirs(os.path.dirname(os.path.abspath(args.markdown)) or ".",
                    exist_ok=True)
        with open(args.markdown, "w", encoding="utf-8") as handle:
            handle.write(markdown)
    print(markdown)
    return 0


def render_markdown(result: dict) -> str:
    stamp = result["stamp"]
    lines = [
        "# Cart Slop GP Web release measurements",
        "",
        "- export: `%s`" % result["export_dir"],
        "- stamp: v%s, engine %s, build `%s`, built %s"
        % (stamp.get("game_version"), stamp.get("engine_version"),
           str(stamp.get("build_id"))[:12], stamp.get("built_utc")),
        "",
        "## Download size (per file, compressed once at staging time)",
        "",
        "| file | raw | gzip | br | gzip saved | br saved |",
        "| --- | ---: | ---: | ---: | ---: | ---: |",
    ]
    for row in result["files"]:
        lines.append("| `%s` | %s | %s | %s | %s | %s |" % (
            row["path"], human(row["raw"]),
            human(row["gzip"]) if row["gzip"] else "-",
            human(row["brotli"]) if row["brotli"] else "-",
            ("%.1f %%" % (100 * row["gzip_ratio"])) if row["gzip_ratio"] else "-",
            ("%.1f %%" % (100 * row["brotli_ratio"]))
            if row["brotli_ratio"] else "-"))
    totals = result["totals"]
    critical = result["critical_path"]
    lines += [
        "",
        "- all files: %d files, %s raw" % (totals["file_count"],
                                           human(totals["bytes"])),
        "- first load (html+js+wasm+pck): %s raw, %s gzip, %s brotli"
        % (human(critical["bytes"]), human(critical["gzip_bytes"]),
           human(critical["brotli_bytes"])),
        "",
        "## Pack composition (index.pck)",
        "",
    ]
    pck = result.get("pck")
    if pck:
        lines += ["| extension | files | bytes | % of pack |",
                  "| --- | ---: | ---: | ---: |"]
        for row in pck["by_extension"]:
            lines.append("| `%s` | %d | %s | %.2f %% |"
                         % (row["extension"], row["count"],
                            human(row["bytes"]), row["percent"]))
        sidecars = pck["editor_sidecars"]
        lines += ["", "editor-only sidecars still packed: `*.import` %d, "
                       "`.godot/` %d, imported %d"
                  % (sidecars["import_files"], sidecars["godot_dir_files"],
                     sidecars["imported_textures"])]
    baseline = result.get("baseline")
    if baseline:
        lines += ["", "### Baseline comparison (`%s`)" % baseline["dir"], ""]
        lines += ["| metric | baseline | current | delta |",
                  "| --- | ---: | ---: | ---: |"]
        lines.append("| files | %d | %d | %+d |"
                     % (baseline["file_count"], totals["file_count"],
                        totals["file_count"] - baseline["file_count"]))
        lines.append("| bytes | %s | %s | %+d |"
                     % (human(baseline["bytes"]), human(totals["bytes"]),
                        totals["bytes"] - baseline["bytes"]))
        if baseline.get("pck") and pck:
            b_pack = baseline["pck"]
            lines.append("| pck files | %d | %d | %+d |"
                         % (b_pack["file_count"], pck["file_count"],
                            pck["file_count"] - b_pack["file_count"]))
            b_import = b_pack["editor_sidecars"]["import_files"]
            lines.append("| pck `*.import` sidecars | %d | %d | %+d |"
                         % (b_import, pck["editor_sidecars"]["import_files"],
                            pck["editor_sidecars"]["import_files"] - b_import))
    serve = result.get("serve")
    if serve and "routes" in serve:
        lines += ["", "## Local serve path (`pi_setup/cartslop-server/webhost.py`)", "",
                  "| request | accept-encoding | status | bytes | CE | cache-control | median ms | p95 ms |",
                  "| --- | --- | ---: | ---: | --- | --- | ---: | ---: |"]
        for route in serve["routes"]:
            lines.append("| `%s` | %s | %s | %s | %s | %s | %s | %s |" % (
                route["path"], route["accept_encoding"],
                ",".join(str(s) for s in route["statuses"]),
                human(route["bytes"][0]) if route["bytes"] else "-",
                ",".join(route["content_encoding"]) or "-",
                "; ".join(route["cache_control"]) or "-",
                route["median_ms"], route["p95_ms"]))
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
