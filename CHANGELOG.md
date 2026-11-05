# Changelog

All notable changes to Cart Slop GP. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow SemVer.

## [0.2.0] - 2026-11-05

Peer-to-peer multiplayer.

### Added

- **Host / join over the internet** with a 12-character join code (ENet over
  UDP, no account or server). Hosting opens a port, asks the router for a UPnP
  mapping and falls back to a public-IP lookup; the lobby shows the code, a
  copy button, the player list and a measured ping.
- **Lobby screen** (`lobby_menu`) reachable from HOST GAME / JOIN GAME, with a
  paste-code field that also accepts `ip:port`.
- **Shared sandbox**: every peer drives its own cart (position streamed at
  20 Hz and interpolated on the other clients), the host simulates props and
  broadcasts snapshots at 10 Hz, and client pushes are forwarded to the host.
- Late join: connecting while a session is running drops you into the sandbox
  with the existing players.
- Per-player vehicle choice is synced to the ghosts.
- `Network` autoload with join-code encode/decode, ping measurement and clean
  disconnect handling.

### Changed

- Pause -> QUIT TO MENU leaves the session.
- The HOST/JOIN notice on the play screen is gone; those buttons open the lobby.

## [0.1.1] - 2026-11-05

Playtest pass: vehicle feel, arena rebuild, UI polish and audit fixes.

### Added

- Vehicle picker after SANDBOX: shopping cart (default), sedan, sports car,
  taxi, van, box truck, police cruiser, with a spinning 3D preview.
- Planned sandbox arena (`tools/build_arena.py` + `docs/ARENA_LAYOUT.md`):
  140 x 140 m, start straight with speed bumps, jump + landing, drift ring,
  slalom, cone field, crate wall, bowl and cliff jump.

### Fixed

- Kenney vehicles drove backwards (180 degree yaw error); the shopping cart was
  the only one facing correctly.
- Boost pads never fired: the Area3D masked layer 1 while the kart is layer 2.
- Props could stop or launch the kart; they now sit on their own layer and are
  popped by a push sensor, with a horizontal speed clamp as a safety net.
- Cliff ramp/platform had a 0.2 m lip that trapped the kart.
- Crate stack was unsupported and collapsed at spawn.
- Coplanar track decals z-fought; decal heights are staggered.
- Smoke particles: emission box moved onto the process material, orbit and
  turbulence property names corrected (settings were silently ignored).
- Update installer wrote a `user://` path into `update_install.bat`; it now
  gets a globalised Windows path.
- A finished update download is remembered across restarts, and zip extraction
  rejects `..`/absolute entries.
- SFX volume now controls gameplay audio, not just the menu click.
- Holding boost on an empty tank no longer micro-pulses the FOV and boost sound.

### Changed

- Camera: smooth layered-sine shake, softer impact/landing trauma, corner
  banking, vertical lag on jumps.
- HUD shrunk (~40% smaller) and tilted; menu/panel spacing made consistent.

## [0.1.0] - 2026-11-04

First tagged prototype build: playable driving sandbox plus the full menu/shell layer.

### Added

- **Main menu** (`scenes/ui/main_menu.tscn`): PLAY, SETTINGS, QUIT, disabled HOST/JOIN
  placeholders, version label, update badge.
- **HUD** (`scenes/ui/hud.tscn`): speed readout, boost bar, drive-state label
  (DRIVING / AIRBORNE / CRASHED / RECOVERY), controls hint.
- **Pause menu** (Esc during driving) and **Settings** (master/SFX volume, fullscreen,
  custom cursor toggle).
- **Custom cursor** (`scenes/ui/cursor_controller.tscn`): OS pointer hidden in menus,
  idle/hover/click states, tween pop on click, exported scale and pop strength.
- **Theme** (`assets/ui/theme.tres`) and Fredoka font for menus/HUD.
- **Update checker** autoload: silent GitHub release check, in-menu update badge,
  browser/download/.bat-install tiers, `user://updates/` staging.
- Windows export preset and `builds/v0.1.0/` packaging.
- `version.txt`, `CHANGELOG.md`, `README.md`, `docs/RELEASE_WORKFLOW.md`.

### Fixed

- Boost pads were inert: their Area3D masked layer 1 while the kart is layer 2.
- Props now live on their own layer with a push sensor, so they pop away
  instead of blocking or launching the kart; a horizontal speed clamp is a
  safety net.
- Cliff ramp/platform lip removed; the route is drivable.
- Crate stack is supported (two rows of five) and no longer collapses at spawn.
- Coplanar track decals staggered to stop z-fighting.
- Particle sheet: emission box moved to the process material, orbit/turbulence
  property names corrected.
- An empty boost tank no longer micro-pulses while the button is held.
- Camera banks into corners instead of outward.
- Update installer wrote a `user://` path into `update_install.bat`, so the
  batch could never copy files. It now gets a globalised Windows path.
- A finished download is remembered across restarts (and no longer resets to
  "update available" when the menu reloads), so "RESTART TO INSTALL" works.
- SFX volume now actually controls gameplay audio: engine, skid, impacts,
  landing and boost players are routed to the SFX bus.
- Zip extraction rejects `..`/absolute entries (zip-slip) and a failed download
  request no longer leaks an HTTPRequest.

### Changed

- **Vehicle selector**: SANDBOX now opens `vehicle_select` with a spinning 3D
  preview - shopping cart (default), sedan, sports car, taxi, van, box truck and
  police cruiser. The choice is saved in `user://settings.cfg` and applied when
  the sandbox cart spawns. The minigame buggy is intentionally not listed.
- **Menu flow**: PLAY now opens a mode-select screen (`play_menu`) with
  SANDBOX / HOST / JOIN / BACK. Sandbox loads the driving test; host and join
  show a "multiplayer coming" notice. HOST/JOIN were removed from the main menu
  and the title is a single playful `CART SLOP GP` line.
- **HUD** made compact (about 40% smaller footprint) and tilted for personality:
  smaller speedometer, boost meter and state pill, thinner hint text.
- **Track dressing**: new animated chevron boost pad (shader), checkered start
  line, palette-matched lane / landing / brake / drift pads, navy ramps.
- **Props** are much lighter: cones 1.5 -> 0.35 kg, crates 3.0 -> 0.8 kg, they pop
  upward and spin, and knocking them no longer slows the kart. Rollers are now
  low ramps you can drive over.
- **Main menu art** rebuilt to match the supplied mockup: vector SlopMart
  parking-lot backdrop (sky, clouds, store, carts, lamps, lot lines), layered
  `CART / SLOP / GP` title with paint drips and a waving checkered flag, and
  candy buttons (yellow PLAY, blue SETTINGS, red QUIT) with thick outlines,
  hard shadows and a gloss highlight.
- **HUD** rebuilt in the same sticker style: round speedometer with needle and
  colour sweep, segmented boost bar with a lightning bolt, cream state pill and
  outlined hint text. Race position (`1st`) and lap (`LAP 1 / 3`) pills are
  included but hidden by default - they are for race-style minigames
  (`set_race_position()`, `set_lap()` or the `show_*` exports).
- **Smoke** (`assets/textures/smoke_sheet.png`, `scenes/feedback/cart_feedback.tscn`):
  replaced the old sheet (16 thin crescent frames that looked like boomerangs) with a
  soft 4x4 billowing puff sheet generated by `tools/gen_smoke_sheet.py`. Drift smoke now
  uses world-space particles (`local_coords = false`), gentler upward drift, less
  turbulence and depth-sorted billboards; landing/crash bursts softened to match.
- Main scene switched from the driving test to the main menu.

### Known limitations

- No multiplayer, laps, or track art yet (HOST/JOIN are placeholders).
- Update support covers Windows .exe builds only.
