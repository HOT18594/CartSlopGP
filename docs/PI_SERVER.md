# Cart Slop Pi server

A Raspberry Pi 4 (64-bit Raspberry Pi OS Lite, Trixie) runs the lobby and UDP
relay for the game. It starts on boot and needs no monitor.

## Ports

| Port | Protocol | Purpose |
| --- | --- | --- |
| 42777 | TCP | HTML console + lobby/API |
| 42778 | UDP | LAN discovery (`CARTSLOP_DISCOVER`) |
| 42800–42819 | UDP | One relay port per active lobby |

The server tries UPnP for these ports. If the router blocks UPnP, forward them
to the Pi's LAN address.

## Access

- Console: `http://cartslop.local:42777` (mDNS via Avahi), or
  `http://<pi-lan-ip>:42777`.
- SSH: `pi@cartslop.local` (password set during imaging).
- Server logs: `journalctl -u cartslop-server -f`.

## Relay model

The host PC runs a normal ENet server on the LAN. When hosting, the game
discovers the Pi, registers its local port and receives a public relay port.
The Pi forwards each remote client through a distinct upstream socket to the
host, so ENet sees ordinary peers. Friends connect to the Pi; the host needs no
port forwarding. The host must be reachable from the Pi (same home network).

## Install

The SD image is provisioned with `firstrun.sh`:

1. Set hostname `cartslop`, user `pi`, SSH.
2. Connect Wi-Fi with NetworkManager.
3. Copy `cartslop-server/` from the boot partition to `/opt/cartslop`.
4. Run `install.sh`: install `avahi-daemon`, `miniupnpc`, `iw`, write and enable
   `cartslop-server.service`, disable Wi-Fi power saving, then reboot.

After first boot the server is available on every boot via systemd.

## API

- `POST /api/register` `{name, local_port}`
- `POST /api/heartbeat` `{token}`
- `POST /api/unregister` `{token}`
- `GET /api/status`
- `GET /api/lobbies`
- `GET /api/events` (SSE)

## Troubleshooting

- **No console:** use the router's client list to find the Pi IP, then open
  `http://<ip>:42777`. Check `systemctl status cartslop-server` over SSH.
- **Host not registering:** both devices must be on the same LAN and UDP 42778
  must not be blocked by a firewall.
- **Internet friends cannot join:** check the console's UPnP status. Forward
  TCP 42777 and UDP 42800–42819, or use a VPN/tunnel and share the LAN code.
- **Wi-Fi drops:** use Ethernet or disable power saving (the installer adds
  `wifi-powersave-off.service`).
