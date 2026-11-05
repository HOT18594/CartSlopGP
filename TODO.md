# Cart Slop GP TODO

Updated: 2026-11-05

## Pi server

- [x] Download/verify Raspberry Pi OS Lite 64-bit (Trixie, 2026-10-06)
- [x] Build lobby + UDP relay server (`server/cartslop_server.py`)
- [x] HTML console with live status and lobby list (`server/console.html`)
- [x] Short 5-character room codes + `/api/room/<code>`
- [x] Game discovers server by UDP, registers, heartbeats, unregisters
- [x] Relay tested end-to-end locally (host game → Pi relay → client)
- [x] Flash SD image with first-boot provisioning (`pi_setup/`)
- [ ] First boot on the physical Pi 4 — **waiting for SD to be inserted**
- [ ] Verify `cartslop.local:42777` from the Windows PC
- [ ] Verify game → Pi registration and a real second-device join
- [ ] Verify UPnP mappings / internet join; document port-forward fallback
- [ ] Add server-side lobby update mirror (`/updates/`) if GitHub-only is not enough

## Multiplayer

- [x] Client names and cart positions relayed for 3+ players
- [x] Multiplayer Meadow Loop with remote carts, names and standings
- [x] Short room-code join + lobby BROWSE list
- [ ] Internet short-code lookup (needs a public server URL field or tunnel)
- [ ] Full server-authoritative vehicle collisions (currently each client
      resolves its own cart against ghost bodies; bots/remotes block locally)
- [ ] Host migration/reconnect after a drop

## Gameplay / content

- [x] Per-vehicle mass/top speed/engine/skid/smoke
- [x] Meadow Loop 3-lap race + waiting room
- [x] Sandbox AI bots (moving collision bodies)
- [x] Bots/remote carts/rivals block the local cart (layer 8)
- [ ] More minigames (slalom, crates, drift, boost)
- [ ] Better race rivals/bot AI and server-owned bot state
- [ ] Vehicle-vs-vehicle collision feedback (sound/sparks)

## UI

- [x] Pill cyclers for BOTS (NO BOTS → 1…5), GAME and LAN/ONLINE
- [x] Compact PLAY and lobby layouts; ADVANCED public-IP toggle
- [x] Minigame preview grid
- [ ] Race result leaderboard for all peers
- [ ] In-game server status / room browser polish
- [ ] Controller navigation audit

## Updates / builds

- [x] GitHub updater with progress and restart-to-install
- [x] macOS ad-hoc re-sign after replacing the .app
- [ ] Release v0.5.1 builds for Windows/macOS/Linux/Web
- [ ] Verify updater from v0.5.0 → v0.5.1 on each desktop platform
- [ ] Optional Pi update mirror + release automation

## Music

- [x] `menu_loop.mp3`, `sandbox_loop.mp3`, `race_loop.mp3` moved into the project
- [ ] Import MP3s in Godot and verify loops/volume in each state

## Housekeeping

- [ ] Remove dev-only screenshot/probe scenes from exported builds (optional)
- [ ] Update `docs/MULTIPLAYER.md` and `docs/PI_SERVER.md` after live Pi test
- [ ] Keep README screenshots/current version in sync
