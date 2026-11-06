# Multiplayer

Two ways to start a world, and no other:

1. **HOST LAN ROOM** - this PC is the ENet server. It advertises a room on
   UDP 42779. Players on the same Wi-Fi press **FIND LAN ROOMS** and pick the
   card. No internet, no Pi and no code.
2. **HOST ONLINE** - the Cart Slop Pi allocates a **5-letter room code** and
   relays the session through its TCP tunnel. Friends type that code under
   **JOIN A ROOM**. The Pi is the only online room service.

The lobby shows **PI SERVER ONLINE/OFFLINE** and disables online controls when
the server cannot be reached. There is no IP address, port, hostname, UPnP or
hand-built address code in the join path; a 14-character code is rejected.

The host chooses SANDBOX or MINIGAMES, optional bots, and presses START.
Everyone gets the themed loading screen and the same scene. Late joiners are
dropped straight in (the host re-sends the full session config), unless the
room state is already `playing` or `finished`.

The host and every client can open **VEHICLE** in the lobby (or the minigame
screen) to pick a car with the full stat sheet. Each peer picks their own;
the host relays vehicle ids so every cart looks right.

Pausing in multiplayer opens the menu but does **not** pause the tree or the
server; the world keeps running. Single-player still pauses.

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
| Car-to-car collisions | host resolves and sends impulses to both owners | on contact |
| Race countdown | host starts after every peer confirms the scene | once |
| Ping | client -> host -> client round trip | 2 s |

Remote carts are interpolated ghosts; each peer owns and simulates its own
cart. Car-to-car contacts are mass-aware: the local cart's move-and-slide sees
remote/bot/rival bodies and exchanges momentum using each vehicle's catalog
mass. Bots and race rivals receive a decaying bump offset. Props stay
host-authoritative. Traffic is roughly 8-10 KB/s per client.

## NAT / internet notes

- Online rooms always go through the Pi. It provides short codes, room
  browsing, the TCP host tunnel around Windows Firewall, and UPnP/NAT-PMP on
  the Pi itself.
- The baked Pi address is `68.204.45.1:42777`. Forward TCP 42777, TCP 42820
  and UDP 42800-42819 to the Pi and keep its LAN address reserved.
- Public IPs from home ISPs can change. Update `DEFAULT_RELAY_SERVER` in
  `scripts/net/network.gd` if that happens; no address is entered in the UI.
- School networks that block outbound UDP can load the HTTP console but cannot
  relay a race.
- LAN hosting needs no router configuration. Windows Firewall may ask to allow
  the game on private networks the first time you host.

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
