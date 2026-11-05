# Multiplayer

Peer-to-peer, free, no account and no game server. Godot's high-level
multiplayer over **ENet (UDP)** connects the players directly.

## Flow

1. PLAY -> HOST GAME.
2. The host opens the first free UDP port in `8910..8949`, asks the router for
   a **UPnP** mapping (1.5 s budget) and resolves a public IP (UPnP external
   address, otherwise `api.ipify.org` for 4 s).
3. The lobby shows a **12-character code**: four hex IP octets + two hex port
   bytes. Example: `C0A8010422CE` -> `192.168.1.4:8910`.
4. Friends paste the code (or type `ip:port`) into JOIN GAME.
5. The host presses START SANDBOX; everyone loads the same scene. Late joiners
   are dropped straight into the running sandbox.

## What is networked

| Thing | Owner | Rate |
| --- | --- | --- |
| Cart transform (position + yaw) | each peer for its own cart | 20 Hz, unreliable |
| Remote carts | interpolated ghosts, no physics/camera | - |
| Props (cones, crates) | host simulates, broadcasts snapshots | 10 Hz, unreliable |
| Pushes from clients | client asks host, host applies the impulse | on contact |
| Vehicle choice | each peer announces its model id | on join / peer change |
| Ping | client -> host -> client round trip | 2 s |

Remote carts and props are visual only; the local cart is always the one you
drive, so collisions between players are not simulated (they pass through each
other). That keeps the session cheap: roughly 8-10 KB/s per client.

## NAT / internet notes

- UPnP works on many home routers. If the router has it disabled, the code
  falls back to the LAN address and internet play needs a **UDP port forward**
  to the host's machine (the port is in the code).
- Carrier-grade NAT (some mobile / apartment ISPs) cannot be port-forwarded;
  use a VPN with a public address or play on the same network.
- Windows Firewall may ask to allow the game the first time you host: allow it
  for private networks (and public if you play over the internet).

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
