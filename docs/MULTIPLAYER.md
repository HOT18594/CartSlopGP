# Multiplayer

Peer-to-peer, free, no account and no game server. Godot's high-level
multiplayer over **ENet (UDP)** connects the players directly.

## Flow

1. PLAY -> MULTIPLAYER. Set your name, pick LAN or ONLINE, then HOST A GAME.
2. **LAN**: the code uses the best physical network adapter and works on the
   same Wi-Fi (VPN/Hyper-V/WSL adapters are skipped).
   **ONLINE**: the host opens the first free UDP port in `8910..8949` and asks
   the router for a **UPnP** mapping. Discovery gets a hard **6 s** budget so a
   silent router can never hang the lobby; if the mapping arrives later the
   code upgrades automatically. If UPnP fails, the host keeps the LAN code and
   shows the public IP plus a port-forward/CGNAT explanation instead of
   advertising an unreachable address.
3. When a Cart Slop Pi answers, the lobby shows a **5-character room code**
   and lists the room in BROWSE. Without a Pi it falls back to a
   **14-character code**: four hex IP octets + two hex port bytes + a 2-hex
   checksum. A mistyped code fails immediately. A **LAN** row appears when
   hosting online so same-network players can always join.
4. Friends paste the code (or type `ip:port` / a tunnel hostname) into JOIN.
   Joining times out after 12 s with an actionable message. If LAN discovery
   finds nothing, the client probes the baked public Pi address
   (`68.204.45.1:42777`) before giving up.
5. The host chooses SANDBOX or MINIGAMES, optional bots, and presses START.
   Everyone gets the themed loading screen and the same scene. Late joiners
   are dropped straight in (the host re-sends the full session config).
6. The host and every client can open **VEHICLE** in the lobby (or the minigame
   screen) to pick a car with the full stat sheet. Each peer picks their own;
   the host relays vehicle ids so every cart looks right.

Names are limited to 16 printable characters and sanitised on both the sender
and the receiver; the host's list shows names and the client's ping. Names also
float above remote carts. ENet traffic is not encrypted - treat the code like a
room key and only share it with people you want in the session.

## What is networked

| Thing | Owner | Rate |
| --- | --- | --- |
| Cart transform (position + yaw) | each peer for its own cart | 20 Hz, unreliable |
| Remote carts | interpolated ghosts, no physics/camera | - |
| Props (cones, crates) | host simulates, broadcasts snapshots | 10 Hz, unreliable |
| Pushes from clients | client asks host, host applies the impulse | on contact |
| Vehicle choice | each peer announces its model id | on join / peer change |
| Race progress | each peer streams unwrapped lap distance | 20 Hz |
| Ping | client -> host -> client round trip | 2 s |

Remote carts are interpolated ghosts; each peer owns and simulates its own
cart. Car-to-car contacts are mass-aware: the local cart's move-and-slide sees
remote/bot/rival bodies and exchanges momentum using each vehicle's catalog
mass. Bots and race rivals receive a decaying bump offset. Props stay
host-authoritative. Traffic is roughly 8-10 KB/s per client.

## NAT / internet notes

- A Pi server is preferred. It gives short codes, room browsing, a TCP host
  tunnel around Windows Firewall, and UPnP/NAT-PMP on the Pi.
- If no Pi answers, UPnP on the host router is tried. If that fails too, the
  lobby keeps the LAN code and explains the **UDP port forward** needed to the
  host PC (the port is in the code).
- The baked public Pi fallback is `68.204.45.1:42777`. Forward TCP 42777,
  TCP 42820 and UDP 42800–42819 to the Pi and keep its LAN address reserved.
  Public IPs from home ISPs can change; use a DDNS hostname in ADVANCED if
  that happens.
- Carrier-grade NAT (some mobile / apartment ISPs) cannot be port-forwarded;
  the lobby detects a CGNAT external address and says so. Use Tailscale,
  ZeroTier or a UDP tunnel (playit.gg) instead, then share the LAN code or the
  tunnel `host:port`.
- Windows Firewall may ask to allow the game the first time you host: allow it
  for private networks (and public if you play over the internet).
- The host's public IP alone is never advertised as ready until a mapping or a
  manual PUBLIC IP was supplied.

## Limits

- 8 players (configurable in `scripts/net/network.gd`).
- Props are host-authoritative: a client's push is visible after a round trip
  (host applies it, snapshot comes back).
- No voice chat, no matchmaking, no reconnect after a drop (host or client
  returns to the lobby).
- The **Web** build cannot host or join: browsers cannot open UDP sockets. It
  is single-player only.

## Tests performed

Two headless processes on localhost:

- host + client connect via the generated code (12-31 ms ping),
- both load the sandbox, each spawns one remote cart,
- prop snapshots match between host and client,
- late join (client connecting after START) loads the sandbox and spawns ghosts,
- host quitting returns the client to the lobby with a message.
