#!/usr/bin/env python3
"""Mock Cart Slop update mirror for the headless updater flow test.

Endpoints:
  /api/update?platform=windows        -> manifest JSON (version 9.9.9)
  /updates/CartSlopGP_v9.9.9_windows.zip   -> a small valid zip (happy path)
  /updates/CartSlopGP_stall_windows.zip    -> sends 1 KB then stalls forever
"""
import io
import json
import socketserver
import sys
import time
import zipfile
from http.server import BaseHTTPRequestHandler
from urllib.parse import urlparse, parse_qs

PORT = int(sys.argv[1]) if len(sys.argv) > 1 else 42999


def build_zip() -> bytes:
    buffer = io.BytesIO()
    with zipfile.ZipFile(buffer, "w", zipfile.ZIP_DEFLATED) as zf:
        zf.writestr("CartSlopGP.exe", b"MZ dummy executable for flow test")
        zf.writestr("version.txt", "9.9.9\n")
    return buffer.getvalue()


ZIP_BYTES = build_zip()


class Handler(BaseHTTPRequestHandler):
    def log_message(self, *args) -> None:
        pass

    def _send_json(self, payload: dict) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self) -> None:  # noqa: N802
        parsed = urlparse(self.path)
        query = parse_qs(parsed.query)
        if parsed.path == "/api/update":
            platform = (query.get("platform", [""])[0] or "").lower()
            if platform != "windows":
                self.send_response(404)
                self.end_headers()
                return
            self._send_json({
                "version": "9.9.9",
                "asset_name": "CartSlopGP_v9.9.9_windows.zip",
                "asset_path": "/updates/CartSlopGP_v9.9.9_windows.zip",
                "release_url": "http://127.0.0.1:%d/release" % PORT,
            })
            return
        if parsed.path == "/updates/CartSlopGP_v9.9.9_windows.zip":
            self.send_response(200)
            self.send_header("Content-Type", "application/zip")
            self.send_header("Content-Length", str(len(ZIP_BYTES)))
            self.end_headers()
            self.wfile.write(ZIP_BYTES)
            return
        if parsed.path == "/updates/CartSlopGP_stall_windows.zip":
            # Deliver one kilobyte, then go silent: exercises the stall
            # watchdog that used to leave the dialog on DOWNLOADING... forever.
            self.send_response(200)
            self.send_header("Content-Type", "application/zip")
            self.send_header("Content-Length", str(10 * 1024 * 1024))
            self.end_headers()
            try:
                self.wfile.write(b"\x50\x4b" + bytes(1022))
                self.wfile.flush()
            except OSError:
                return
            time.sleep(300)
            return
        self.send_response(404)
        self.end_headers()


class Server(socketserver.ThreadingTCPServer):
    allow_reuse_address = True


if __name__ == "__main__":
    with Server(("127.0.0.1", PORT), Handler) as httpd:
        print("mock update server on %d" % PORT, flush=True)
        httpd.serve_forever()
