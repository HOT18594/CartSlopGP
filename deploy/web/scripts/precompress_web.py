#!/usr/bin/env python3
"""Pre-compress a staged Godot Web release for static hosting (gzip + Brotli).

The Godot exporter writes ``index.wasm`` / ``index.pck`` / ``index.js``
uncompressed. Cloudflare Pages serves Brotli automatically, but the R2 + Worker
path in this package (and any plain object store / CDN) needs the encoded
siblings at known keys, because compressing a 120 MB ``.pck`` per request is
exactly the CPU spike we are trying to avoid. This script writes
``<file>.gz`` and ``<file>.br`` next to their source, atomically, and a JSON
report with the measured ratio of every file (the same report feeds
``_audit/reports/ws1-web.md``).

Brotli is optional: it uses the Python ``brotli`` module when installed, else
the bundled ``brotli_compress.mjs`` Node helper (Node >= 18), else it skips
``.br`` with a warning. gzip always works with the standard library.

Usage:
    python scripts/precompress_web.py dist [options]

    dist                 staged release directory (contains game/<version>/...)
    --gzip-level N       gzip level 1-9 (default 9; done once at staging time)
    --brotli-quality N   Brotli quality 1-11 (default 9)
    --no-brotli          skip .br siblings
    --min-size BYTES     skip files smaller than this (default 1024)
    --min-gain FRACTION  delete a sibling that saves less than this (0.03)
    --prune             delete stale .gz/.br siblings whose source is gone
    --report PATH        write the per-file JSON report
    --quiet             only the summary line

Exit code 0 on success (including "nothing to do"), 1 on an I/O or
decompression self-check failure. Idempotent: rerunning skips fresh siblings
whose mtime is newer than the source.
"""
from __future__ import annotations

import argparse
import json
import os
import shutil
import subprocess
import sys
import time
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
NODE_HELPER = os.path.join(HERE, "brotli_compress.mjs")
CHUNK = 1024 * 1024
EXTENSIONS = (".wasm", ".pck", ".js", ".mjs", ".json", ".html", ".css", ".data")


def human(size: float) -> str:
    for unit in ("B", "KB", "MB", "GB"):
        if size < 1024 or unit == "GB":
            return ("%d B" % int(size)) if unit == "B" else "%.2f %s" % (size, unit)
        size /= 1024.0
    return "%d B" % int(size)


def candidates(root: str, min_size: int) -> list[str]:
    found: list[str] = []
    for directory, _subdirs, names in os.walk(root):
        for name in sorted(names):
            if name.endswith((".gz", ".br", ".tmp")):
                continue
            if not name.lower().endswith(EXTENSIONS):
                continue
            path = os.path.join(directory, name)
            try:
                if os.path.isfile(path) and os.path.getsize(path) >= min_size:
                    found.append(path)
            except OSError:
                continue
    return found


def fresh(source: str, sibling: str, min_gain: float) -> bool:
    try:
        src = os.stat(source)
        dst = os.stat(sibling)
    except OSError:
        return False
    return (dst.st_size > 0
            and dst.st_mtime_ns >= src.st_mtime_ns
            and dst.st_size <= src.st_size * (1.0 - min_gain))


def atomic_write(path: str, writer) -> None:
    tmp = path + ".tmp.%d" % os.getpid()
    try:
        with open(tmp, "wb") as handle:
            writer(handle)
            handle.flush()
            os.fsync(handle.fileno())
        os.replace(tmp, path)
    finally:
        if os.path.exists(tmp):
            try:
                os.unlink(tmp)
            except OSError:
                pass


def gzip_file(source: str, destination: str, level: int) -> None:
    import gzip

    def writer(handle) -> None:
        with gzip.GzipFile(filename="", mode="wb", fileobj=handle,
                           compresslevel=level, mtime=0) as gz:
            with open(source, "rb") as raw:
                while True:
                    chunk = raw.read(CHUNK)
                    if not chunk:
                        break
                    gz.write(chunk)
    atomic_write(destination, writer)


class Brotli:
    """Brotli encoder: Python module, else the bundled Node helper, else None."""

    def __init__(self, quality: int) -> None:
        self.quality = quality
        self.mode = "none"
        try:
            import brotli  # noqa: F401
            self._module = brotli
            self.mode = "python"
        except ImportError:
            self._module = None
            if shutil.which("node") and os.path.isfile(NODE_HELPER):
                self.mode = "node"

    def available(self) -> bool:
        return self.mode != "none"

    def compress(self, source: str, destination: str) -> None:
        if self.mode == "python":
            compressor_cls = self._module.Compressor

            def writer(handle) -> None:
                compressor = compressor_cls(quality=self.quality)
                with open(source, "rb") as raw:
                    while True:
                        chunk = raw.read(CHUNK)
                        if not chunk:
                            break
                        piece = compressor.process(chunk)
                        if piece:
                            handle.write(piece)
                tail = compressor.finish()
                if tail:
                    handle.write(tail)
            atomic_write(destination, writer)
            return
        tmp = destination + ".tmp.%d" % os.getpid()
        try:
            result = subprocess.run(
                ["node", NODE_HELPER, source, tmp, str(self.quality)],
                capture_output=True, text=True, timeout=600)
            if result.returncode != 0:
                raise OSError(result.stderr.strip() or "node brotli failed")
            os.replace(tmp, destination)
        finally:
            if os.path.exists(tmp):
                try:
                    os.unlink(tmp)
                except OSError:
                    pass


def verify_gzip(source: str, compressed: str) -> bool:
    """First-chunk round-trip check; a bad write shows up immediately.

    A full decompress would double the staging cost, so only the start of the
    stream is decoded. ``zlib.decompressobj`` is used instead of
    ``gzip.decompress`` because the latter raises EOFError on any stream that
    is not complete within the buffer - which is every large file (the 106 MB
    ``index.pck.gz``) and made this check reject good output.
    """
    try:
        with open(source, "rb") as handle:
            expected = handle.read(65536)
        with open(compressed, "rb") as handle:
            payload = handle.read(CHUNK)
        decompressor = zlib.decompressobj(16 + zlib.MAX_WBITS)
        decoded = decompressor.decompress(payload, len(expected))
        return decoded[:65536] == expected[:65536] and len(decoded) > 0
    except (OSError, EOFError, zlib.error):
        return False


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("root")
    parser.add_argument("--gzip-level", type=int, default=9)
    parser.add_argument("--brotli-quality", type=int, default=9)
    parser.add_argument("--no-brotli", action="store_true")
    parser.add_argument("--min-size", type=int, default=1024)
    parser.add_argument("--min-gain", type=float, default=0.03)
    parser.add_argument("--prune", action="store_true")
    parser.add_argument("--report", default="")
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args(argv)

    root = os.path.abspath(args.root)
    if not os.path.isdir(root):
        print("precompress: %s is not a directory" % root, file=sys.stderr)
        return 1
    brotli = Brotli(max(1, min(11, args.brotli_quality)))
    if not args.no_brotli and not brotli.available():
        print("precompress: no Brotli encoder (install the Python 'brotli' "
              "module or Node.js); writing gzip only", file=sys.stderr)
    if args.no_brotli:
        brotli.mode = "none"

    files = candidates(root, args.min_size)
    report: dict = {
        "root": root,
        "generated_utc": time.strftime("%Y-%m-%dT%H:%M:%SZ", time.gmtime()),
        "gzip_level": args.gzip_level,
        "brotli_quality": args.brotli_quality if brotli.mode != "none" else None,
        "brotli_encoder": brotli.mode,
        "min_gain": args.min_gain,
        "files": [],
        "totals": {"raw": 0, "gzip": 0, "brotli": 0},
    }
    failures = 0
    skipped = 0
    wrote = 0
    started = time.monotonic()
    for source in files:
        relative = os.path.relpath(source, root).replace("\\", "/")
        raw = os.path.getsize(source)
        entry = {"path": relative, "raw": raw, "gzip": None, "brotli": None,
                 "gzip_encoding": None, "brotli_encoding": None}
        gz_path = source + ".gz"
        br_path = source + ".br"
        for coding, path in (("gzip", gz_path), ("brotli", br_path)):
            if coding == "brotli" and brotli.mode == "none":
                continue
            if fresh(source, path, args.min_gain):
                size = os.path.getsize(path)
                if size <= raw * (1.0 - args.min_gain):
                    entry[coding] = size
                    skipped += 1
                    continue
                os.unlink(path)
            try:
                if coding == "gzip":
                    gzip_file(source, path, args.gzip_level)
                else:
                    brotli.compress(source, path)
            except (OSError, ImportError, zlib.error) as error:
                failures += 1
                print("  FAIL %-48s %s: %s" % (relative, coding, error),
                      file=sys.stderr)
                continue
            size = os.path.getsize(path)
            if size <= raw * (1.0 - args.min_gain):
                entry[coding] = size
                wrote += 1
                if coding == "gzip" and not verify_gzip(source, path):
                    os.unlink(path)
                    entry[coding] = None
                    failures += 1
                    print("  FAIL %-48s gzip self-check" % relative,
                          file=sys.stderr)
            else:
                os.unlink(path)
        report["files"].append(entry)
        report["totals"]["raw"] += raw
        report["totals"]["gzip"] += entry["gzip"] or raw
        report["totals"]["brotli"] += entry["brotli"] or raw
        if not args.quiet and entry["gzip"]:
            print("  %-52s %10s -> gz %10s / br %10s" % (
                relative, human(raw), human(entry["gzip"] or raw),
                human(entry["brotli"] or raw)))

    if args.prune:
        pruned = 0
        for directory, _subdirs, names in os.walk(root):
            for name in names:
                if not name.endswith((".gz", ".br")):
                    continue
                sibling = os.path.join(directory, name)
                source = sibling[:-3]
                if not os.path.isfile(source) or \
                        (os.path.getsize(sibling) >
                         os.path.getsize(source) * (1.0 - args.min_gain)):
                    try:
                        os.unlink(sibling)
                        pruned += 1
                    except OSError:
                        pass
        report["pruned"] = pruned

    if args.report:
        os.makedirs(os.path.dirname(os.path.abspath(args.report)) or ".",
                    exist_ok=True)
        with open(args.report, "w", encoding="utf-8") as handle:
            json.dump(report, handle, indent=1)
            handle.write("\n")
    raw = report["totals"]["raw"]
    best = report["totals"]["brotli"]
    saved = 100.0 * (raw - best) / raw if raw else 0.0
    print("precompress: %d file(s), raw %s -> best %s (-%.1f %%), %d wrote, "
          "%d skipped, %d failed, %.1f s" % (
              len(report["files"]), human(raw), human(best), saved, wrote,
              skipped, failures, time.monotonic() - started))
    return 0 if failures == 0 else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
