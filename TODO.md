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
- [x] Confirm the physical Pi booted the new image: `firstrun.log` shows
      Debian 13 (trixie), Python 3.13.5, 2026-10-06 kernel files
- [x] Diagnose first-boot Wi-Fi failure: old script called `nmcli` before
      NetworkManager was running, so it never associated
- [x] Replace one-shot firstrun with a `cartslop-connect` watchdog that starts
      after NetworkManager, retries `blue24`/`blue21` (WPA2 + WPA3), logs to
      the boot partition, and starts the server once an address exists
- [x] Install a passwordless SSH key on the card (`pi_setup/pi_ssh_key`)
- [ ] Reboot the Pi with the updated card and verify `cartslop.local:42777`
- [ ] Verify game → Pi registration and a real second-device join
- [ ] Verify UPnP mappings / internet join; document port-forward fallback
- [ ] Add server-side lobby update mirror (`/updates/`) if GitHub-only is not enough

## Multiplayer

- [x] Client names and cart positions relayed for 3+ players
- [x] Multiplayer Meadow Loop with remote carts, names and standings
- [x] Short room-code join + lobby BROWSE list
- [x] Internet short-code lookup (optional SERVER field) + public 14-character code
- [x] Host TCP tunnel end-to-end: local Pi server, host ENet, client ENet join
- [x] Host TCP tunnel (TCP 42820) around Windows Firewall inbound blocks
- [x] UPnP + NAT-PMP automatic mapping and public reachability check
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
- [x] Release v0.5.2 builds for Windows/macOS/Linux/Web
- [x] Verify GitHub latest release and platform asset names (v0.5.2)
- [ ] Verify updater download/install on each desktop platform
- [ ] Optional Pi update mirror + release automation

## Music

- [x] `menu_loop.mp3`, `sandbox_loop.mp3`, `race_loop.mp3` moved into the project
- [ ] Import MP3s in Godot and verify loops/volume in each state

## Housekeeping

- [ ] Remove dev-only screenshot/probe scenes from exported builds (optional)
- [ ] Update `docs/MULTIPLAYER.md` and `docs/PI_SERVER.md` after live Pi test
- [ ] Keep README screenshots/current version in sync
