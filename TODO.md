# Cart Slop GP TODO

Updated: 2026-11-06 (v0.7.0 prepared locally; NOT released yet)

## Pi server

- [x] Download/verify Raspberry Pi OS Lite 64-bit (Trixie, 2026-10-06)
- [x] Build lobby + UDP relay server (`server/cartslop_server.py`)
- [x] HTML console with live status and lobby list (`server/console.html`)
- [x] Short 5-character room codes + `/api/room/<code>`
- [x] Game discovers server by UDP, registers, heartbeats, unregisters
- [x] Relay tested end-to-end locally (host game → Pi relay → client)
- [x] Flash SD image with first-boot provisioning (`pi_setup/`)
- [x] Confirm the physical Pi booted the new image: `firstrun.log` shows
      Debian 13 (trixie), Python 3.13.5, 2026-10-06 kernel files
- [x] Diagnose first-boot Wi-Fi failure: old script called `nmcli` before
      NetworkManager was running, so it never associated
- [x] Replace one-shot firstrun with a `cartslop-connect` watchdog that starts
      after NetworkManager, retries `blue24`/`blue21` (WPA2 + WPA3), logs to
      the boot partition, and starts the server once an address exists
- [x] Install a passwordless SSH key on the card (`pi_setup/pi_ssh_key`)
- [x] Boot the Pi with the updated card and verify `cartslop.local:42777`
      (live at 192.168.1.22; server + Wi-Fi watchdog enabled)
- [x] Verify game → Pi registration and a join through the Pi
      (host/client + Meadow Loop race, LAN and public relay)
- [ ] Verify a real second physical device (school/Mac/Linux) joins
- [x] Verify UPnP mappings / internet join; document port-forward fallback
      (22/22 ports mapped, external check OPEN)
- [x] Fixed LAN address `192.168.1.22` with DHCP fallback
- [ ] Add a router DHCP reservation for the Pi's MAC
- [x] Baked public Pi fallback (`68.204.45.1:42777`) and LAN-first discovery
- [ ] Confirm public IP is still current / add DDNS hostname if ISP changes
- [x] Server-side update mirror (`/updates/`) with 0.6.1 Windows zip
- [x] Room state in the server (`lobby` / `playing` / `finished`); pause is client-only
- [x] Nightly service window 00:15-07:15 America/New_York with persistent timers
- [x] Pi timezone/NTP corrected; no RTC wake, so Pi stays powered
- [ ] Add a heatsink/fan before sustained 24/7 load
- [ ] Optional: wire the Pi to Ethernet for lower relay jitter

## Multiplayer

- [x] Client names and cart positions relayed for 3+ players
- [x] Multiplayer Meadow Loop with remote carts, names and standings
- [x] Short room-code join + lobby BROWSE list
- [x] Short-code-only join through the Pi (no IP, port, hostname or 14-character code)
- [x] Host TCP tunnel end-to-end: local Pi server, host ENet, client ENet join
- [x] Host TCP tunnel (TCP 42820) around Windows Firewall inbound blocks
- [x] UPnP + NAT-PMP automatic mapping and public reachability check
- [x] LAN host advertises itself; nearby clients see a room card, no IP
- [x] Race car chosen by the host for everyone; only name tags differ
- [x] Name tag colours (lobby swatches, synced, on carts/lists/Tab panel)
- [x] Hold-Tab Minecraft-style player list with per-player ping
- [x] Ghost carts and bots spawn snapped to the ground (no more hovering)
- [x] Host-authoritative two-body car collisions in sandbox and race (mass,
      restitution, friction, delta-v to both owners)
- [ ] Full server-authoritative vehicle physics (impulses are host-side;
      each peer still simulates its own cart)
- [ ] Host migration/reconnect after a drop

## Gameplay / content

- [x] Per-vehicle mass/top speed/engine/skid/smoke
- [x] Meadow Loop 3-lap race + waiting room
- [x] Sandbox AI bots (moving collision bodies)
- [x] Bots/remote carts/rivals block the local cart (layer 8)
- [x] Skid marks visible on the Meadow Loop dirt road (road collision added)
- [ ] More minigames (add to the screen only when the scene is playable)
- [ ] Better race rivals/bot AI and server-owned bot state
- [ ] Vehicle-vs-vehicle collision feedback (sound/sparks)

## UI

- [x] Pill cyclers for BOTS (NO BOTS → 1…5), GAME and LAN/ONLINE
- [x] Compact PLAY menu; one MULTIPLAYER LOBBY entry
- [x] Fall Guys-style lobby: LAN/Pi host cards, 5-letter code, room lists
- [x] Minigame screen lists only playable events with real previews
- [x] Removed invented COMING SOON cards and illustrated placeholders
- [x] Shared UI kit: one action-button height and type scale on every screen
- [x] Lobby map selector sets the map and returns; host starts from lobby
- [x] Solo minigames skip the waiting room; countdown runs after the race loads
- [x] Mass-aware car-to-car collisions for remotes, bots and rivals
- [x] Multiplayer result card shows BACK TO LOBBY, not RACE AGAIN/HUB
- [x] Shared vector cart art (menu, loading, boot splash, icon)
- [x] SLOP drips anchored to the actual letters
- [x] Scene fade transitions and a fuller loading scene
- [x] Button labels explicitly centred and vertically padded symmetrically
- [x] Full vehicle stat sheet in solo, lobby and minigame picker
- [x] Meadow Loop hills, denser PBR forest, kicker ramps and visible boost pads
- [x] Race HUD simplified; sector labels and icon clutter removed
- [x] Countdown / lap / finish / ambience / impact / UI sounds
- [x] Baked public Pi fallback after LAN discovery
- [ ] Race result leaderboard for all peers
- [x] Server online/offline pill gate; LAN and online room lists
- [x] Multiplayer Esc menu keeps the world running; single-player pauses
- [ ] Controller navigation audit

## Updates / builds

- [x] GitHub updater with progress and restart-to-install
- [x] macOS ad-hoc re-sign after replacing the .app
- [x] Release v0.6.0 builds for Windows/macOS/Linux/Web
- [x] Auto-check, auto-surface, auto-download update
- [x] RESTART & UPDATE prompt; install and relaunch without unzipping
- [x] Pi update manifest endpoint (`/api/update`) with GitHub fallback
- [x] Verify updater zip extraction and Pi manifest lookup
- [x] Stall watchdog + self-healing update dialog (v0.7.0); verified with a
      mock mirror (happy path + stalled connection)
- [ ] Verify the final file swap on each desktop platform
- [ ] Optional automated copy of release assets to the Pi mirror

## Music

- [x] `menu_loop.mp3`, `sandbox_loop.mp3`, `race_loop.mp3` moved into the project
- [ ] Import MP3s in Godot and verify loops/volume in each state

## Housekeeping

- [ ] Remove dev-only screenshot/probe scenes from exported builds (optional)
- [ ] Update `docs/MULTIPLAYER.md` and `docs/PI_SERVER.md` after live Pi test
- [ ] Keep README screenshots/current version in sync
