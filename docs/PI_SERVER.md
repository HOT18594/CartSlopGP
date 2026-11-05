# Cart Slop Pi server

A Raspberry Pi 4 (64-bit Raspberry Pi OS Lite, Trixie) runs the lobby and UDP
relay for the game. It starts on boot and needs no monitor.

## Ports

| Port | Protocol | Purpose |
| --- | --- | --- |
| 42777 | TCP | HTML console + lobby/API |
| 42778 | UDP | LAN discovery (`CARTSLOP_DISCOVER`) |
| 42800–42819 | UDP | One relay port per active lobby |
| 42820 | TCP | Host TCP tunnel (outbound from the host game) |

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
port forwarding.

Newer game builds also open a **TCP tunnel** from the host to the Pi. The host
connects outward to TCP 42820, and a local loopback proxy gives every remote
client its own ENet peer. This works even when Windows Firewall blocks inbound
UDP for the exported game, which is the normal Public-network default. The Pi
still exposes the UDP relay port to friends; the host side is outbound only.

## Internet join

1. Host a game on the PC. The game registers with the Pi and gets a 5-character
   room code.
2. Open the console on the PC (`http://cartslop.local:42777`) and use
   **PUBLIC** in the lobby row. That copies the 14-character public code
   (`public-ip:relay-port`).
3. Send that public code to the friend. They paste it into JOIN. No server
   address or account is needed.
4. Newer builds also accept the 5-character room code after the public Pi
   address is entered in the optional **SERVER** field.

The Pi opens its ports automatically with UPnP first and NAT-PMP second. If the
console says **INTERNET: not reachable**, either forward TCP 42777 and UDP
42800–42819 to the Pi's LAN address, or the ISP is using carrier-grade NAT and
a UDP tunnel is required. The console lists the exact ports and the public IP.

## Install

The SD image is provisioned with `firstrun.sh` plus a permanent watchdog:

1. `firstrun.sh` runs once from the kernel command line. It sets hostname
   `cartslop`, user `pi`, SSH, stages `/opt/cartslop`, installs
   `cartslop-connect.service`, removes the kernel hook and reboots.
2. On the next boot `cartslop-connect.sh` starts after NetworkManager. It
   retries `blue24` (fallback `blue21`) on 2.4 GHz and 5 GHz with WPA2 and WPA3,
   logs to `/boot/firmware/cartslop-connect.log`, and starts
   `cartslop-server.service` as soon as the Pi has a non-link-local address.
3. Once online it installs `avahi-daemon`, `miniupnpc`, `iw` and
   `openssh-server`, then writes `/boot/firmware/CART_SLOP_WIFI_OK.txt`.

The watchdog keeps running, so a dropped Wi-Fi link is retried automatically.
`install.sh` remains available for manual reinstall/repair.

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
  TCP 42777, TCP 42820 and UDP 42800–42819, or use a VPN/tunnel and share the
  LAN code. The console's INTERNET card tests TCP 42777 from outside.
- **Wi-Fi drops:** use Ethernet or disable power saving (the installer adds
  `wifi-powersave-off.service`).
- **Pi never appears:** put the SD card back in the PC and read
  `/boot/firmware/cartslop-connect.log`. It records `nmcli` scan results,
  `rfkill`, association attempts and the chosen IP. The first boot also writes
  `/boot/firmware/cartslop-firstboot.log`.
