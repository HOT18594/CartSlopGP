# Cart Slop GP Pi server

Runs headless on a Raspberry Pi 4 (64-bit Raspberry Pi OS Lite, Trixie).

## Ports

| Port | Protocol | Purpose |
| --- | --- | --- |
| 42777 | TCP | HTML console + lobby/API |
| 42778 | UDP | LAN discovery (`CARTSLOP_DISCOVER`) |
| 42800–42819 | UDP | One relay port per active lobby |

The Pi maps these with UPnP on boot. If the router blocks UPnP, forward them
manually to the Pi's LAN address.

## Console

`http://cartslop.local:42777` (or `http://<pi-lan-ip>:42777`).

Shows server health, UPnP status, active lobbies, and a ready-to-copy join code
for each lobby.

## Relay model

The host PC keeps running a normal ENet server on the LAN. On hosting, the game
registers `local_port` with the Pi. The Pi opens a public UDP relay port and
forwards each remote client through a distinct upstream socket to the host, so
ENet sees ordinary peers. Friends connect to the Pi; the host needs no port
forwarding.

This requires the host PC to be reachable from the Pi (same home network). If
the host is elsewhere, use the direct host mode instead.

## API

- `POST /api/register` `{name, local_port}` → `{token, relay_port, lan_host, public_host, http_port}`
- `POST /api/heartbeat` `{token}`
- `POST /api/unregister` `{token}`
- `GET /api/status`
- `GET /api/lobbies`
- `GET /api/events` (SSE)

## Run manually

```bash
python3 /opt/cartslop/cartslop_server.py
```

Logs: `journalctl -u cartslop-server -f`
