#!/usr/bin/env python3
"""Report what is actually inside a Godot 4 PCK by extension and size.

The Web export ships ``index.pck`` (126 MB in 0.8.7), so "where did the download
go?" and "did the export preset actually stop packing editor-sidecar files?"
cannot be answered from file mtimes. This reads the pack's file table
(``GDPC`` header + per-file path/offset/size entries) and prints a composition
table plus, optionally, JSON for the release report.

It is deliberately read-only and defensive: a file whose table does not parse
makes the script fail with exit code 2 instead of inventing numbers (the caller
can fall back to the exporter's "Storing File:" log).

Usage:
    python scripts/pck_stats.py <index.pck> [--json out.json] [--top 15]
Exit codes: 0 parsed, 2 not a parseable Godot 4 pack, 1 I/O error.
"""
from __future__ import annotations

import argparse
import json
import os
import struct
import sys

MAGIC = b"GDPC"
# Header (Godot 4.x, pack format v3/v4):
#   magic u32, version u32, major u32, minor u32, patch u32, flags u32,
#   file_base u64, dir_offset u64           -> 40 bytes
# v2 instead has 16 * u32 reserved words after file_base and no dir_offset.
HEADER_FIXED = 4 + 4 + 4 + 4 + 4 + 4 + 8 + 8
PACK_DIR_ENCRYPTED = 1 << 0
PACK_FILE_REMOVAL = 1 << 5


class PckError(Exception):
    pass


def _read_pascal_string(data: bytes, offset: int) -> tuple[str, int]:
    """Godot stores paths as u32 byte-length + UTF-8 bytes (no padding)."""
    if offset + 4 > len(data):
        raise PckError("string length past end of pack")
    length = struct.unpack_from("<I", data, offset)[0]
    offset += 4
    if length == 0 or length > 4096:
        raise PckError("implausible path length %d" % length)
    if offset + length > len(data):
        raise PckError("path past end of pack")
    path = data[offset:offset + length].split(b"\x00", 1)[0]
    offset += length
    try:
        return path.decode("utf-8"), offset
    except UnicodeDecodeError as error:
        raise PckError("non-UTF-8 path: %s" % error) from error


def parse_pck(path: str) -> dict:
    size = os.path.getsize(path)
    with open(path, "rb") as handle:
        head = handle.read(HEADER_FIXED)
    if len(head) < HEADER_FIXED:
        raise PckError("pack shorter than the Godot header")
    if head[:4] != MAGIC:
        raise PckError("not a Godot pack (magic %r)" % head[:4])
    version, major, minor, patch, flags = struct.unpack_from("<IIIII", head, 4)
    file_base = struct.unpack_from("<Q", head, 24)[0]
    if version not in (2, 3, 4):
        raise PckError("unsupported pack format version %d" % version)
    if version in (3, 4):
        # v3/v4: the directory is at magic_start + dir_offset, not inline.
        dir_offset = struct.unpack_from("<Q", head, 32)[0]
        dir_start = dir_offset
    else:
        dir_start = HEADER_FIXED + 16 * 4
    if flags & PACK_DIR_ENCRYPTED:
        raise PckError("file table is encrypted")

    with open(path, "rb") as handle:
        handle.seek(dir_start)
        table = handle.read(min(size - dir_start, 64 * 1024 * 1024))
    if not table:
        raise PckError("directory table is empty")
    file_count = struct.unpack_from("<I", table, 0)[0]
    if file_count <= 0 or file_count > 2_000_000:
        raise PckError("implausible file count %d" % file_count)

    entries: list[dict] = []
    offset = 4
    total_bytes = 0
    for _index in range(file_count):
        name, offset = _read_pascal_string(table, offset)
        if offset + 8 + 8 + 16 + 4 > len(table):
            raise PckError("file entry past end of table")
        data_offset, data_size = struct.unpack_from("<QQ", table, offset)
        offset += 8 + 8
        digest = table[offset:offset + 16].hex()
        offset += 16
        entry_flags = struct.unpack_from("<I", table, offset)[0]
        offset += 4
        if data_size > size:
            raise PckError("file %s claims %d bytes in a %d-byte pack"
                           % (name, data_size, size))
        entries.append({"path": name, "offset": data_offset,
                        "size": data_size, "md5": digest,
                        "flags": entry_flags})
        total_bytes += data_size

    if entries and not sum(1 for e in entries
                           if "/" in e["path"] or "." in e["path"]):
        raise PckError("implausible paths in the table - parse is wrong")
    if total_bytes > size * 1.2:
        raise PckError("entry bytes exceed pack size - parse is wrong")
    return {
        "path": os.path.abspath(path),
        "bytes": size,
        "format": version,
        "engine": "%d.%d.%d" % (major, minor, patch),
        "flags": flags,
        "file_base": file_base,
        "file_count": file_count,
        "entry_bytes": total_bytes,
        "entries": entries,
    }


def composition(parsed: dict, top: int = 15) -> dict:
    by_ext: dict[str, dict] = {}
    for entry in parsed["entries"]:
        name = entry["path"]
        base = name.rsplit("/", 1)[-1]
        if "." in base:
            ext = "." + base.rsplit(".", 1)[-1].lower()
        else:
            ext = "<none>"
        bucket = by_ext.setdefault(ext, {"count": 0, "bytes": 0})
        bucket["count"] += 1
        bucket["bytes"] += entry["size"]
    ordered = sorted(by_ext.items(), key=lambda item: -item[1]["bytes"])
    summary = {
        "pack_bytes": parsed["bytes"],
        "entry_bytes": parsed["entry_bytes"],
        "file_count": parsed["file_count"],
        "by_extension": [
            {"extension": ext, "count": info["count"], "bytes": info["bytes"],
             "percent": round(100.0 * info["bytes"] / parsed["bytes"], 2)
             if parsed["bytes"] else 0.0}
            for ext, info in ordered
        ],
        "top_files": [
            {"path": entry["path"], "bytes": entry["size"]}
            for entry in sorted(parsed["entries"],
                                key=lambda e: -e["size"])[:top]
        ],
        "editor_sidecars": {
            "import_files": sum(1 for e in parsed["entries"]
                                if e["path"].endswith(".import")),
            "godot_dir_files": sum(1 for e in parsed["entries"]
                                   if e["path"].startswith(".godot/")),
            "imported_textures": sum(1 for e in parsed["entries"]
                                     if ".godot/imported/" in e["path"]),
        },
    }
    return summary


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("pck")
    parser.add_argument("--json", default="")
    parser.add_argument("--top", type=int, default=15)
    parser.add_argument("--quiet", action="store_true")
    args = parser.parse_args(argv)
    try:
        parsed = parse_pck(args.pck)
    except OSError as error:
        print("pck_stats: %s" % error, file=sys.stderr)
        return 1
    except PckError as error:
        print("pck_stats: cannot parse %s: %s" % (args.pck, error),
              file=sys.stderr)
        return 2
    summary = composition(parsed, args.top)
    if not args.quiet:
        print("pack %s: %.1f MB, %d files, engine %s"
              % (os.path.basename(args.pck), parsed["bytes"] / 1048576.0,
                 parsed["file_count"], parsed["engine"]))
        print("  %-14s %8s %14s %7s" % ("extension", "files", "bytes", "%"))
        for row in summary["by_extension"]:
            print("  %-14s %8d %14s %6.1f%%"
                  % (row["extension"], row["count"],
                     _human(row["bytes"]), row["percent"]))
        sidecars = summary["editor_sidecars"]
        print("  editor sidecars: .import=%d .godot/=%d imported=%d"
              % (sidecars["import_files"], sidecars["godot_dir_files"],
                 sidecars["imported_textures"]))
    if args.json:
        os.makedirs(os.path.dirname(os.path.abspath(args.json)) or ".",
                    exist_ok=True)
        with open(args.json, "w", encoding="utf-8") as handle:
            json.dump(summary, handle, indent=1)
            handle.write("\n")
    return 0


def _human(size: int) -> str:
    value = float(size)
    for unit in ("B", "KB", "MB", "GB"):
        if value < 1024 or unit == "GB":
            return ("%d B" % int(value)) if unit == "B" else "%.2f %s" % (value, unit)
        value /= 1024.0
    return "%d B" % int(value)


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
