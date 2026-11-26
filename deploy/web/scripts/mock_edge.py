#!/usr/bin/env python3
"""Local mock of the Cloudflare edge, for testing verify_deploy.ps1 offline.

``verify_deploy.ps1`` is an HTTPS client: it checks redirects, cache headers,
content types, compression negotiation and the version meta tag of a deployed
release. Without a Cloudflare account there is still value in running it, so
this script serves a staged ``dist/`` with the same contract the Worker / Pages
setup provides, on plain HTTP loopback:

* ``/``, ``/index.html``, ``/latest`` -> 302 to ``release.json.entry``;
* ``/version.json`` / ``/release.json`` -> ``no-store`` JSON;
* ``/game/.../index.html`` -> ``no-store`` text/html;
* other ``/game/*`` payloads -> ``immutable``, extension MIME, and the
  ``.br``/``.gz`` sibling when the client accepts it (``Content-Encoding``);
* security headers on everything; COOP/COEP only with ``--threaded``.

Usage:
    python scripts/mock_edge.py --root dist --port 8791 &
    powershell -File scripts/verify_deploy.ps1 -BaseUrl http://127.0.0.1:8791 -LocalDist dist

This is a developer tool, never a production server.
"""
from __future__ import annotations

import argparse
import json
import os
import sys
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

MIME = {
    ".html": "text/html; charset=utf-8",
    ".js": "text/javascript; charset=utf-8",
    ".wasm": "application/wasm",
    ".pck": "application/octet-stream",
    ".png": "image/png",
    ".json": "application/json",
    ".txt": "text/plain; charset=utf-8",
}
SECURITY = {
    "X-Content-Type-Options": "nosniff",
    "X-Frame-Options": "SAMEORIGIN",
    "Referrer-Policy": "strict-origin-when-cross-origin",
    "Permissions-Policy": "camera=(), microphone=(), geolocation=()",
}


class Edge(BaseHTTPRequestHandler):
    root = ""
    threaded = False

    def log_message(self, *_args):
        pass

    def _release(self) -> dict | None:
        path = os.path.join(self.root, "release.json")
        try:
            with open(path, encoding="utf-8") as handle:
                return json.load(handle)
        except (OSError, ValueError):
            return None

    def _send(self, status: int, body: bytes, headers: dict, head_only: bool):
        self.send_response(status)
        payload = dict(SECURITY)
        payload.update(headers)
        if self.threaded:
            payload["Cross-Origin-Opener-Policy"] = "same-origin"
            payload["Cross-Origin-Embedder-Policy"] = "require-corp"
            payload["Cross-Origin-Resource-Policy"] = "same-origin"
        payload["Content-Length"] = str(len(body))
        for name, value in payload.items():
            self.send_header(name, value)
        self.end_headers()
        if not head_only:
            self.wfile.write(body)

    def do_GET(self):  # noqa: N802 - BaseHTTPRequestHandler API
        self._serve(head_only=False)

    def do_HEAD(self):  # noqa: N802
        self._serve(head_only=True)

    def _serve(self, head_only: bool) -> None:
        path = self.path.split("?", 1)[0]
        release = self._release()
        if path in ("/", "/index.html", "/latest", "/latest/"):
            if not release or not release.get("entry"):
                self._send(503, b"no release", {"Cache-Control": "no-store"}, head_only)
                return
            self._send(302, b"", {"Location": release["entry"],
                                  "Cache-Control": "no-store"}, head_only)
            return
        if path in ("/version.json", "/release.json"):
            local = os.path.join(self.root, path.lstrip("/"))
            try:
                with open(local, "rb") as handle:
                    body = handle.read()
            except OSError:
                self._send(503, b"missing", {"Cache-Control": "no-store"}, head_only)
                return
            self._send(200, body, {"Content-Type": "application/json",
                                   "Cache-Control": "no-store, must-revalidate",
                                   "Access-Control-Allow-Origin": "*"}, head_only)
            return
        if not path.startswith("/game/"):
            self._send(404, b"not found", {"Cache-Control": "no-store"}, head_only)
            return
        relative = path.lstrip("/")
        local = os.path.join(self.root, relative.replace("/", os.sep))
        accept = (self.headers.get("Accept-Encoding") or "").lower()
        encoding = ""
        for suffix, coding in ((".br", "br"), (".gz", "gzip")):
            if coding in accept and os.path.isfile(local + suffix):
                local = local + suffix
                encoding = coding
                break
        if not os.path.isfile(local):
            self._send(404, b"not found", {"Cache-Control": "no-store"}, head_only)
            return
        extension = os.path.splitext(relative)[1].lower()
        headers = {
            "Content-Type": MIME.get(extension, "application/octet-stream"),
            "Cache-Control": ("no-store, must-revalidate"
                              if relative.endswith("/index.html")
                              else "public, max-age=31536000, immutable"),
            "Vary": "Accept-Encoding",
        }
        if encoding:
            headers["Content-Encoding"] = encoding
        with open(local, "rb") as handle:
            self._send(200, handle.read(), headers, head_only)


def main(argv: list[str]) -> int:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--root", required=True)
    parser.add_argument("--port", type=int, default=8791)
    parser.add_argument("--threaded", action="store_true")
    args = parser.parse_args(argv)
    root = os.path.abspath(args.root)
    if not os.path.isfile(os.path.join(root, "release.json")):
        print("mock_edge: %s has no release.json (stage first)" % root,
              file=sys.stderr)
        return 1
    Edge.root = root
    Edge.threaded = args.threaded
    server = ThreadingHTTPServer(("127.0.0.1", args.port), Edge)
    print("mock edge serving %s on http://127.0.0.1:%d (Ctrl+C to stop)"
          % (root, args.port), flush=True)
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    finally:
        server.server_close()
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
