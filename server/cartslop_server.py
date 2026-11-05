#!/usr/bin/env python3
"""Cart Slop GP lobby + UDP relay for a Raspberry Pi.

HTTP console/API on TCP 42777, UDP discovery on 42778, and UDP relay ports
42800..42819 (one per lobby). Hosts run a normal ENet server on the LAN; the
Pi forwards each remote client to the host through a distinct upstream socket,
so ENet sees ordinary peers. UPnP opens the Pi's ports when the router allows.
"""
from __future__ import annotations

import json
import os
import re
import select
import shutil
import socket
import struct
import subprocess
import threading
import time
import urllib.request
import uuid
import secrets
import string
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

HTTP_PORT = int(os.environ.get("CARTSLOP_HTTP_PORT", "42777"))
DISCOVERY_PORT = int(os.environ.get("CARTSLOP_DISCOVERY_PORT", "42778"))
RELAY_BASE = int(os.environ.get("CARTSLOP_RELAY_BASE", "42800"))
RELAY_COUNT = int(os.environ.get("CARTSLOP_RELAY_COUNT", "20"))
TUNNEL_PORT = int(os.environ.get("CARTSLOP_TUNNEL_PORT", "42820"))
LOBBY_TTL = 75.0
CLIENT_TTL = 90.0
VERSION = "1.1.0"
ROOM_ALPHABET = "ABCDEFGHJKLMNPQRSTUVWXYZ23456789"
HERE = os.path.dirname(os.path.abspath(__file__))

LOCK = threading.Lock()
LOBBIES: dict[str, "Lobby"] = {}
USED_PORTS: set[int] = set()
ROOM_CODES: set[str] = set()
STARTED = time.time()
LAN_IP = "127.0.0.1"
PUBLIC_IP = ""
WAN_IP = ""
PUBLIC_LAST = 0.0
UPNP = {"available": False, "mapped": 0, "total": 0, "message": "checking"}
NATPMP = {"available": False, "mapped": 0, "total": 0, "message": "checking"}
EXTERNAL = {"checked": 0, "open": False, "message": "not checked"}
TUNNELS = {"active": 0, "port": TUNNEL_PORT}
TUNNEL_AVAILABLE = False
MAPPING_BUSY = False
MAPPING_LAST = 0.0
HAVE_UPNPC = shutil.which("upnpc") is not None
HAVE_NATPMPC = shutil.which("natpmpc") is not None


def detect_lan_ip() -> str:
    try:
        sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        sock.connect(("8.8.8.8", 80))
        address = sock.getsockname()[0]
        sock.close()
        return address
    except OSError:
        return "127.0.0.1"


def refresh_lan_ip() -> bool:
    """Re-detect the LAN address. The server may start before Wi-Fi is up."""
    global LAN_IP
    candidate = detect_lan_ip()
    if candidate and candidate != "127.0.0.1" and candidate != LAN_IP:
        LAN_IP = candidate
        print("LAN IP -> %s" % LAN_IP, flush=True)
        return True
    return False


def refresh_public_ip() -> str:
    global PUBLIC_IP, WAN_IP, PUBLIC_LAST
    urls = (
        "https://api.ipify.org",
        "https://ifconfig.me/ip",
        "https://icanhazip.com",
    )
    for url in urls:
        try:
            request = urllib.request.Request(
                url, headers={"User-Agent": "CartSlopPi/" + VERSION})
            with urllib.request.urlopen(request, timeout=4) as response:
                text = response.read().decode("ascii", "ignore").strip()
            if re.fullmatch(r"\d{1,3}(?:\.\d{1,3}){3}", text):
                PUBLIC_IP = text
                break
        except Exception:
            continue
    # The router's WAN address tells us whether a mapping can actually be
    # reached, even when the public-IP web services only see the ISP egress.
    if HAVE_UPNPC:
        ok, output = run_upnpc(["-s"])
        if ok:
            match = re.search(r"ExternalIPAddress\s*=\s*(\d{1,3}(?:\.\d{1,3}){3})", output)
            if match:
                WAN_IP = match.group(1)
                if not PUBLIC_IP:
                    PUBLIC_IP = WAN_IP
    PUBLIC_LAST = time.time()
    return PUBLIC_IP


def check_external_port() -> None:
    """Ask a public checker whether the HTTP port is reachable."""
    global EXTERNAL
    if not PUBLIC_IP:
        EXTERNAL = {"checked": int(time.time()), "open": False,
                    "message": "public IP not detected"}
        return
    if _is_shared_address(PUBLIC_IP) or _is_private_address(PUBLIC_IP):
        EXTERNAL = {"checked": int(time.time()), "open": False,
                    "message": "carrier/private address - use a tunnel"}
        return
    url = ("https://api.networktools.dev/v1/port-test?port=%d&ip=%s"
           % (HTTP_PORT, PUBLIC_IP))
    try:
        request = urllib.request.Request(
            url, headers={"User-Agent": "CartSlopPi/" + VERSION})
        with urllib.request.urlopen(request, timeout=7) as response:
            payload = json.loads(response.read().decode("utf-8", "ignore"))
        opened = bool(payload.get("open", False))
        EXTERNAL = {
            "checked": int(time.time()),
            "open": opened,
            "message": "reachable from the internet" if opened
            else "TCP %d is not reachable - forward the ports or use a tunnel" % HTTP_PORT,
        }
    except Exception as error:
        EXTERNAL = {"checked": int(time.time()), "open": False,
                    "message": "check failed: %s" % str(error)[:80]}


def run_command(command: list[str], timeout: float = 6.0) -> tuple[bool, str]:
    try:
        result = subprocess.run(command, capture_output=True, text=True, timeout=timeout)
        return result.returncode == 0, (result.stdout or "") + (result.stderr or "")
    except Exception as error:
        return False, str(error)


def run_upnpc(args: list[str], timeout: float = 6.0) -> tuple[bool, str]:
    if not HAVE_UPNPC:
        return False, "upnpc not installed"
    return run_command(["upnpc", *args], timeout)


def map_upnp(port: int, protocol: str) -> bool:
    ok, _ = run_upnpc(["-a", LAN_IP, str(port), str(port), protocol])
    if ok:
        return True
    ok, _ = run_upnpc(["-a", LAN_IP, str(port), str(port), protocol, "CartSlopGP"])
    return ok


def map_natpmp(port: int, protocol: str) -> bool:
    """NAT-PMP fallback for routers that expose it instead of UPnP."""
    if not HAVE_NATPMPC:
        return False
    ok, output = run_command(
        ["natpmpc", "-a", str(port), str(port), protocol.lower(), "3600"], timeout=5)
    return ok and ("Mapped public port" in output or "public port" in output.lower())


def map_port(port: int, protocol: str) -> bool:
    if map_upnp(port, protocol):
        return True
    return map_natpmp(port, protocol)


def mapping_bootstrap() -> None:
    global UPNP, NATPMP, MAPPING_BUSY, MAPPING_LAST
    if MAPPING_BUSY:
        return
    MAPPING_BUSY = True
    try:
        ports = [(HTTP_PORT, "TCP"), (TUNNEL_PORT, "TCP")] \
            + [(RELAY_BASE + i, "UDP") for i in range(RELAY_COUNT)]
        upnp_mapped = 0
        natpmp_mapped = 0
        for port, protocol in ports:
            if map_upnp(port, protocol):
                upnp_mapped += 1
            elif map_natpmp(port, protocol):
                natpmp_mapped += 1
        UPNP = {
            "available": upnp_mapped > 0,
            "mapped": upnp_mapped,
            "total": len(ports),
            "message": "UPnP mapping complete" if upnp_mapped == len(ports)
            else ("UPnP partial" if upnp_mapped else "UPnP unavailable"),
        }
        NATPMP = {
            "available": natpmp_mapped > 0,
            "mapped": natpmp_mapped,
            "total": len(ports),
            "message": "NAT-PMP mapping complete" if natpmp_mapped == len(ports)
            else ("NAT-PMP partial" if natpmp_mapped else "NAT-PMP unavailable"),
        }
        MAPPING_LAST = time.time()
        if upnp_mapped + natpmp_mapped == 0:
            print("No automatic port mapping - forward TCP %d, TCP %d, and UDP %d-%d"
                  % (HTTP_PORT, TUNNEL_PORT, RELAY_BASE, RELAY_BASE + RELAY_COUNT - 1), flush=True)
    finally:
        MAPPING_BUSY = False


def upnp_bootstrap() -> None:
    mapping_bootstrap()


def ensure_port_mapped(port: int, protocol: str) -> None:
    def worker() -> None:
        if map_port(port, protocol):
            with LOCK:
                UPNP["mapped"] = min(int(UPNP.get("mapped", 0)) + 1, int(UPNP.get("total", 0)))
    threading.Thread(target=worker, daemon=True).start()


def read_int(path: str, default: int = 0) -> int:
    try:
        with open(path, "r", encoding="ascii") as handle:
            return int(handle.read().strip())
    except Exception:
        return default


def memory_info() -> dict:
    total = available = 0
    try:
        with open("/proc/meminfo", "r", encoding="ascii") as handle:
            for line in handle:
                if line.startswith("MemTotal:"):
                    total = int(line.split()[1]) * 1024
                elif line.startswith("MemAvailable:"):
                    available = int(line.split()[1]) * 1024
    except Exception:
        pass
    return {"total": total, "available": available, "used": max(total - available, 0)}


def uptime_seconds() -> float:
    try:
        with open("/proc/uptime", "r", encoding="ascii") as handle:
            return float(handle.read().split()[0])
    except Exception:
        return time.time() - STARTED


def sanitize_name(value: str) -> str:
    cleaned = re.sub(r"[^\x20-\x7E]", "", str(value or ""))[:28].strip()
    return cleaned or "HOST"


class Relay:
    def __init__(self, lobby: "Lobby") -> None:
        self.lobby = lobby
        self.port = lobby.relay_port
        self.host = (lobby.host_ip, lobby.host_port)
        self.socket = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        self.socket.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.socket.bind(("0.0.0.0", self.port))
        self.socket.setblocking(False)
        self.clients: dict[tuple[str, int], dict] = {}
        self.address_by_id: dict[int, tuple[str, int]] = {}
        self.next_id = 1
        self.tunnel: "TunnelLink | None" = None
        self.running = True
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()

    def _new_client(self, address: tuple[str, int], now: float) -> dict:
        client = {
            "last": now,
            "id": self.next_id,
            "queue": [],
            "sock": None,
        }
        self.next_id += 1
        with LOCK:
            self.clients[address] = client
            self.address_by_id[client["id"]] = address
            self.lobby.clients = len(self.clients)
        return client

    def _run(self) -> None:
        while self.running:
            with LOCK:
                items = list(self.clients.items())
                tunnel = self.tunnel
            sockets = [self.socket]
            if tunnel is None:
                sockets += [item[1]["sock"] for item in items if item[1].get("sock") is not None]
            try:
                readable, _, _ = select.select(sockets, [], [], 1.0)
            except (OSError, ValueError):
                break
            now = time.time()
            for sock in readable:
                if sock is self.socket:
                    try:
                        data, address = self.socket.recvfrom(65535)
                    except OSError:
                        continue
                    client = self.clients.get(address)
                    if client is None:
                        client = self._new_client(address, now)
                    client["last"] = now
                    if self.lobby.tunnel_token:
                        if self.tunnel is not None and self.tunnel.ready:
                            self.tunnel.send(client["id"], data)
                        else:
                            queue: list[bytes] = client["queue"]
                            if len(queue) < 256:
                                queue.append(data)
                        continue
                    upstream = client.get("sock")
                    if upstream is None:
                        upstream = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
                        upstream.setblocking(False)
                        try:
                            upstream.connect(self.host)
                        except OSError:
                            upstream.close()
                            continue
                        client["sock"] = upstream
                    try:
                        upstream.send(data)
                    except OSError:
                        pass
                else:
                    target = None
                    for address, client in list(self.clients.items()):
                        if client.get("sock") is sock:
                            target = address
                            break
                    if target is None:
                        continue
                    try:
                        data = sock.recv(65535)
                        self.socket.sendto(data, target)
                    except OSError:
                        pass
                    # stop() can clear the client table while this packet is
                    # in flight; do not key directly into it.
                    client = self.clients.get(target)
                    if client is not None:
                        client["last"] = now
            for address, client in list(self.clients.items()):
                if now - client["last"] > CLIENT_TTL:
                    try:
                        if client.get("sock") is not None:
                            client["sock"].close()
                    except OSError:
                        pass
                    with LOCK:
                        self.clients.pop(address, None)
                        self.address_by_id.pop(client.get("id", -1), None)
                        self.lobby.clients = len(self.clients)

    def from_tunnel(self, client_id: int, data: bytes) -> None:
        address = self.address_by_id.get(client_id)
        if address is None:
            return
        try:
            self.socket.sendto(data, address)
        except OSError:
            pass

    def attach_tunnel(self, link: "TunnelLink") -> None:
        with LOCK:
            self.tunnel = link
            items = list(self.clients.items())
        link.ready = True
        for address, client in items:
            for packet in client.get("queue", []):
                link.send(client["id"], packet)
            client["queue"] = []

    def detach_tunnel(self, link: "TunnelLink") -> None:
        with LOCK:
            if self.tunnel is link:
                self.tunnel = None

    def stop(self) -> None:
        self.running = False
        with LOCK:
            clients = list(self.clients.values())
            tunnel = self.tunnel
            self.clients.clear()
            self.address_by_id.clear()
            self.tunnel = None
        for client in clients:
            try:
                if client.get("sock") is not None:
                    client["sock"].close()
            except OSError:
                pass
        if tunnel is not None:
            tunnel.close()
        try:
            self.socket.close()
        except OSError:
            pass


class TunnelLink:
    """One TCP tunnel from a host game to the Pi.

    The host opens this connection outward, so it works even when the host's
    Windows firewall blocks inbound UDP. Client packets are framed as
    ``[client_id u32][length u32][payload]``.
    """

    def __init__(self, sock: socket.socket, lobby: "Lobby") -> None:
        self.sock = sock
        self.lobby = lobby
        self.ready = False
        self.running = True
        self.write_lock = threading.Lock()
        self.thread = threading.Thread(target=self._read_loop, daemon=True)
        self.thread.start()

    def send(self, client_id: int, data: bytes) -> None:
        if not self.running:
            return
        frame = struct.pack("!II", int(client_id), len(data)) + data
        with self.write_lock:
            try:
                self.sock.sendall(frame)
            except OSError:
                self.close()

    def _read_exact(self, count: int) -> bytes | None:
        chunks = bytearray()
        while len(chunks) < count and self.running:
            try:
                part = self.sock.recv(count - len(chunks))
            except OSError:
                return None
            if not part:
                return None
            chunks.extend(part)
        return bytes(chunks) if len(chunks) == count else None

    def _read_loop(self) -> None:
        try:
            while self.running:
                header = self._read_exact(8)
                if header is None:
                    break
                client_id, length = struct.unpack("!II", header)
                if length > 65535:
                    break
                payload = self._read_exact(length)
                if payload is None:
                    break
                self.lobby.relay.from_tunnel(client_id, payload)
        finally:
            self.close()

    def close(self) -> None:
        if not self.running:
            return
        self.running = False
        self.ready = False
        self.lobby.relay.detach_tunnel(self)
        try:
            self.sock.close()
        except OSError:
            pass
        with LOCK:
            TUNNELS["active"] = max(0, int(TUNNELS.get("active", 0)) - 1)


class TunnelServer:
    def __init__(self) -> None:
        global TUNNEL_AVAILABLE
        self.sock = socket.socket(socket.AF_INET, socket.SOCK_STREAM)
        self.sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        self.sock.bind(("0.0.0.0", TUNNEL_PORT))
        self.sock.listen(16)
        TUNNEL_AVAILABLE = True
        self.thread = threading.Thread(target=self._run, daemon=True)
        self.thread.start()

    def _run(self) -> None:
        while True:
            try:
                conn, _ = self.sock.accept()
            except OSError:
                return
            threading.Thread(target=self._handle, args=(conn,), daemon=True).start()

    def _handle(self, conn: socket.socket) -> None:
        lobby: Lobby | None = None
        try:
            conn.settimeout(6.0)
            line = b""
            while len(line) < 128:
                byte = conn.recv(1)
                if not byte:
                    return
                if byte == b"\n":
                    break
                line += byte
            text = line.decode("ascii", "ignore").strip()
            if not text.startswith("TOKEN "):
                conn.sendall(b"ERR\n")
                return
            token = text[6:].strip()
            with LOCK:
                lobby = next((item for item in LOBBIES.values()
                              if item.tunnel_token and item.tunnel_token == token), None)
            if lobby is None:
                conn.sendall(b"ERR\n")
                return
            conn.settimeout(None)
            conn.sendall(b"OK\n")
            link = TunnelLink(conn, lobby)
            with LOCK:
                TUNNELS["active"] = int(TUNNELS.get("active", 0)) + 1
            lobby.relay.attach_tunnel(link)
        except Exception:
            try:
                conn.close()
            except OSError:
                pass


class Lobby:
    def __init__(self, token: str, room_code: str, name: str, host_ip: str, host_port: int, relay_port: int,
                 tunnel_token: str = "") -> None:
        self.token = token
        self.room_code = room_code
        self.name = name
        self.host_ip = host_ip
        self.host_port = host_port
        self.relay_port = relay_port
        self.tunnel_token = tunnel_token
        self.created = time.time()
        self.last_seen = time.time()
        self.clients = 0
        self.relay = Relay(self)

    def snapshot(self, include_private: bool = False) -> dict:
        data = {
            "name": self.name,
            "room_code": self.room_code,
            "relay_port": self.relay_port,
            "players": max(self.clients, 1),
            "age": int(time.time() - self.created),
            "lan_host": LAN_IP,
            "public_host": PUBLIC_IP,
            "http_port": HTTP_PORT,
            "tunnel": bool(self.tunnel_token),
            "tunnel_active": bool(self.relay.tunnel and self.relay.tunnel.ready),
        }
        if include_private:
            data["host_ip"] = self.host_ip
            data["host_port"] = self.host_port
            data["token"] = self.token
            data["tunnel_token"] = self.tunnel_token
            data["tunnel_port"] = TUNNEL_PORT
        return data

    def stop(self) -> None:
        self.relay.stop()
        with LOCK:
            USED_PORTS.discard(self.relay_port)
            ROOM_CODES.discard(self.room_code)
            LOBBIES.pop(self.token, None)


def allocate_room_code() -> str:
    with LOCK:
        for _ in range(1000):
            code = "".join(secrets.choice(ROOM_ALPHABET) for _ in range(5))
            if code not in ROOM_CODES:
                ROOM_CODES.add(code)
                return code
    return ""


def find_lobby_by_code(code: str) -> "Lobby | None":
    normalized = re.sub(r"[^A-Z0-9]", "", str(code).upper())
    with LOCK:
        for lobby in LOBBIES.values():
            if lobby.room_code == normalized:
                return lobby
    return None


def allocate_relay_port() -> int | None:
    with LOCK:
        for offset in range(RELAY_COUNT):
            port = RELAY_BASE + offset
            if port not in USED_PORTS:
                USED_PORTS.add(port)
                return port
    return None


def expire_lobbies() -> None:
    now = time.time()
    with LOCK:
        expired = [lobby for lobby in LOBBIES.values() if now - lobby.last_seen > LOBBY_TTL]
    for lobby in expired:
        lobby.stop()


def _is_shared_address(address: str) -> bool:
    """True for RFC 6598 carrier-grade NAT (100.64.0.0/10)."""
    if not re.fullmatch(r"100\.(\d{1,3})\.\d{1,3}\.\d{1,3}", address or ""):
        return False
    return 64 <= int(address.split(".")[1]) <= 127


def _same_subnet_24(left: str, right: str) -> bool:
    if not re.fullmatch(r"\d{1,3}(?:\.\d{1,3}){3}", left or "") \
            or not re.fullmatch(r"\d{1,3}(?:\.\d{1,3}){3}", right or ""):
        return False
    return left.rsplit(".", 1)[0] == right.rsplit(".", 1)[0]


def _is_private_address(address: str) -> bool:
    if not re.fullmatch(r"\d{1,3}(?:\.\d{1,3}){3}", address or ""):
        return False
    first, second = (int(part) for part in address.split(".")[:2])
    return first == 10 or (first == 172 and 16 <= second <= 31) \
        or (first == 192 and second == 168) or first == 127


def status_snapshot() -> dict:
    with LOCK:
        lobbies = [lobby.snapshot() for lobby in LOBBIES.values()]
    return {
        "server": "cartslop",
        "version": VERSION,
        "hostname": socket.gethostname(),
        "lan_ip": LAN_IP,
        "public_ip": PUBLIC_IP,
        "wan_ip": WAN_IP,
        "http_port": HTTP_PORT,
        "discovery_port": DISCOVERY_PORT,
        "relay_base": RELAY_BASE,
        "relay_count": RELAY_COUNT,
        "upnp": dict(UPNP),
        "natpmp": dict(NATPMP),
        "external": dict(EXTERNAL),
        "tunnels": dict(TUNNELS),
        "mapping_ready": bool(UPNP.get("available") or NATPMP.get("available")),
        "cgnat": _is_shared_address(WAN_IP) or _is_shared_address(PUBLIC_IP)
                  or _is_private_address(WAN_IP),
        "uptime": int(uptime_seconds()),
        "load": list(os.getloadavg()) if hasattr(os, "getloadavg") else [],
        "cpu_temp": read_int("/sys/class/thermal/thermal_zone0/temp") / 1000.0,
        "memory": memory_info(),
        "lobbies": lobbies,
        "lobby_count": len(lobbies),
    }


class Handler(BaseHTTPRequestHandler):
    server_version = "CartSlopPi/" + VERSION

    def log_message(self, fmt: str, *args) -> None:
        print("%s - %s" % (self.address_string(), fmt % args), flush=True)

    def _cors(self) -> None:
        self.send_header("Access-Control-Allow-Origin", "*")
        self.send_header("Access-Control-Allow-Headers", "Content-Type")
        self.send_header("Access-Control-Allow-Methods", "GET, POST, OPTIONS")

    def _json(self, payload: dict, status: int = 200) -> None:
        body = json.dumps(payload).encode("utf-8")
        self.send_response(status)
        self.send_header("Content-Type", "application/json; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self.send_header("Cache-Control", "no-store")
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def _body(self) -> dict:
        try:
            length = int(self.headers.get("Content-Length", "0"))
            return json.loads(self.rfile.read(length).decode("utf-8")) if length else {}
        except Exception:
            return {}

    def do_OPTIONS(self) -> None:
        self.send_response(204)
        self._cors()
        self.end_headers()

    def do_GET(self) -> None:
        path = self.path.split("?", 1)[0]
        if path in ("/", "/index.html"):
            self._serve_console()
        elif path == "/api/status":
            self._json(status_snapshot())
        elif path == "/api/lobbies":
            with LOCK:
                lobbies = [lobby.snapshot() for lobby in LOBBIES.values()]
            self._json({"lobbies": lobbies})
        elif path.startswith("/api/room/"):
            code = path.rsplit("/", 1)[-1]
            lobby = find_lobby_by_code(code)
            if lobby is None:
                self._json({"error": "room not found"}, 404)
            else:
                self._json(lobby.snapshot())
        elif path == "/api/events":
            self._sse()
        elif path == "/favicon.ico":
            self.send_response(204)
            self.end_headers()
        else:
            self._json({"error": "not found"}, 404)

    def do_POST(self) -> None:
        path = self.path.split("?", 1)[0]
        data = self._body()
        if path == "/api/register":
            self._register(data)
        elif path == "/api/heartbeat":
            self._heartbeat(data)
        elif path == "/api/unregister":
            self._unregister(data)
        else:
            self._json({"error": "not found"}, 404)

    def _register(self, data: dict) -> None:
        try:
            host_port = int(data.get("local_port", 0))
        except Exception:
            host_port = 0
        if host_port < 1024 or host_port > 65535:
            self._json({"error": "local_port must be 1024..65535"}, 400)
            return
        relay_port = allocate_relay_port()
        if relay_port is None:
            self._json({"error": "all relay ports are busy"}, 503)
            return
        token = uuid.uuid4().hex
        room_code = allocate_room_code()
        if room_code == "":
            with LOCK:
                USED_PORTS.discard(relay_port)
            self._json({"error": "could not allocate room code"}, 503)
            return
        name = sanitize_name(data.get("name", ""))
        host_ip = self.client_address[0]
        # VPN/Cloudflare-WARP clients can make the TCP source address look
        # like a virtual adapter. Prefer the host's explicitly reported LAN
        # address when it is a normal private IPv4 address.
        reported_ip = str(data.get("local_ip", "")).strip()
        if _is_private_address(reported_ip) and not _is_shared_address(reported_ip) \
                and not reported_ip.startswith("127.") \
                and _same_subnet_24(reported_ip, LAN_IP):
            host_ip = reported_ip
        tunnel_requested = bool(data.get("tunnel", False)) and TUNNEL_AVAILABLE
        tunnel_token = secrets.token_hex(16) if tunnel_requested else ""
        try:
            lobby = Lobby(token, room_code, name, host_ip, host_port, relay_port, tunnel_token)
        except OSError as error:
            with LOCK:
                USED_PORTS.discard(relay_port)
                ROOM_CODES.discard(room_code)
            print("relay bind failed:", error, flush=True)
            self._json({"error": "relay port unavailable"}, 503)
            return
        with LOCK:
            LOBBIES[token] = lobby
        ensure_port_mapped(relay_port, "UDP")
        if not PUBLIC_IP:
            refresh_public_ip()
        print("LOBBY OPEN %s %s:%d -> relay %d code %s" % (name, host_ip, host_port, relay_port, room_code), flush=True)
        self._json({
            "token": token,
            "room_code": room_code,
            "relay_port": relay_port,
            "lan_host": LAN_IP,
            "public_host": PUBLIC_IP,
            "http_port": HTTP_PORT,
            "tunnel": bool(tunnel_token),
            "tunnel_token": tunnel_token,
            "tunnel_port": TUNNEL_PORT,
            "expires_in": int(LOBBY_TTL),
        })

    def _heartbeat(self, data: dict) -> None:
        token = str(data.get("token", ""))
        with LOCK:
            lobby = LOBBIES.get(token)
        if lobby is None:
            self._json({"error": "unknown lobby"}, 404)
            return
        lobby.last_seen = time.time()
        self._json({"ok": True, "expires_in": int(LOBBY_TTL)})

    def _unregister(self, data: dict) -> None:
        token = str(data.get("token", ""))
        with LOCK:
            lobby = LOBBIES.get(token)
        if lobby is not None:
            lobby.stop()
        self._json({"ok": True})

    def _serve_console(self) -> None:
        try:
            with open(os.path.join(HERE, "console.html"), "rb") as handle:
                body = handle.read()
        except OSError:
            body = b"<h1>console.html missing</h1>"
        self.send_response(200)
        self.send_header("Content-Type", "text/html; charset=utf-8")
        self.send_header("Content-Length", str(len(body)))
        self._cors()
        self.end_headers()
        self.wfile.write(body)

    def _sse(self) -> None:
        self.send_response(200)
        self.send_header("Content-Type", "text/event-stream")
        self.send_header("Cache-Control", "no-cache")
        self.send_header("Connection", "keep-alive")
        self._cors()
        self.end_headers()
        try:
            while True:
                payload = json.dumps(status_snapshot())
                self.wfile.write(("data: %s\n\n" % payload).encode("utf-8"))
                self.wfile.flush()
                time.sleep(2.0)
        except (BrokenPipeError, ConnectionResetError, OSError):
            return


def discovery_loop() -> None:
    sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
    sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    try:
        sock.bind(("0.0.0.0", DISCOVERY_PORT))
    except OSError as error:
        print("discovery bind failed:", error, flush=True)
        return
    while True:
        try:
            data, address = sock.recvfrom(2048)
        except OSError:
            continue
        if data.strip().upper().startswith(b"CARTSLOP_DISCOVER"):
            reply = json.dumps({
                "service": "cartslop",
                "version": VERSION,
                "http_port": HTTP_PORT,
                "lan_ip": LAN_IP,
                "hostname": socket.gethostname(),
            }).encode("utf-8")
            try:
                sock.sendto(reply, address)
            except OSError:
                pass


def maintenance_loop() -> None:
    while True:
        time.sleep(10)
        expire_lobbies()
        if refresh_lan_ip():
            # Wi-Fi/Ethernet appeared or changed after startup: refresh the
            # advertised LAN address and redo the router mappings.
            threading.Thread(target=mapping_bootstrap, daemon=True).start()
        if time.time() - PUBLIC_LAST > 300:
            refresh_public_ip()
        if time.time() - int(EXTERNAL.get("checked", 0)) > 300:
            check_external_port()
        if MAPPING_LAST > 0 and time.time() - MAPPING_LAST > 1800:
            threading.Thread(target=mapping_bootstrap, daemon=True).start()


def main() -> None:
    global LAN_IP
    LAN_IP = detect_lan_ip()
    refresh_public_ip()
    print("Cart Slop server %s on %s, HTTP %d, relay %d-%d"
          % (VERSION, LAN_IP, HTTP_PORT, RELAY_BASE, RELAY_BASE + RELAY_COUNT - 1), flush=True)
    threading.Thread(target=discovery_loop, daemon=True).start()
    try:
        TunnelServer()
    except OSError as error:
        print("tunnel bind failed:", error, flush=True)
    threading.Thread(target=upnp_bootstrap, daemon=True).start()
    threading.Thread(target=maintenance_loop, daemon=True).start()
    server = ThreadingHTTPServer(("0.0.0.0", HTTP_PORT), Handler)
    server.daemon_threads = True
    server.serve_forever()


if __name__ == "__main__":
    main()
