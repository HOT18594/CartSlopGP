# Changelog

All notable changes to Cart Slop GP. Format loosely follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/); versions follow SemVer.

## [0.5.0] - 2026-11-05

Meadow Loop, a real minigame grid, and a much more reliable multiplayer lobby.

### Added

- **MEADOW LOOP** — the first playable minigame: three laps of a winding 491 m
  dirt circuit through a dense grassy forest, with a 3-2-1-GO countdown, four
  boost pads, 34 pushable cones, checkpoint gates, lap times, place badges and
  a candy result card.
- **Waiting room** (`meadow_lobby.tscn`): live 3D preview, editable name,
  READY UP, rivals joining one by one and a start countdown.
- **Realistic PBR scenery**: ~387 procedural trees built from CC0 Poly Haven
  bark/leaf scans, tiled PBR ground, 5 scanned ground-cover models, wind and
  kart-bending foliage shaders, and heavy viewport settings for the race only.
- **Minigame grid** with generated preview cards for all five events; Meadow
  Loop is READY and the other four are marked COMING SOON. Includes a vehicle
  cycler and selected-event details.
- **AI carts in the sandbox** when the BOTS toggle is on, plus the self-hosted
  race rivals.
- **Multiplayer race support**: peers own their carts, stream position/yaw at
  20 Hz, exchange vehicle models, see name labels and are counted in the race
  position. Result cards hide RACE AGAIN (which would desync the field).
- **LAN code alongside the online code**, connection diagnostics for
  UPnP/CGNAT failures, and a visible warning when only a LAN route exists.
- Optional **PUBLIC IP** override remains for manual port-forwarding or a
  VPN/tunnel address.

### Changed

- PLAY now has SINGLE PLAYER / MULTIPLAYER tabs with shared BOTS controls.
- The multiplayer lobby switches between idle, host and client layouts instead
  of showing every control at once.
- Minigames are reached from PLAY again; the grid replaces the old options
  prototype and tournament placeholder.

### Fixed

- Online hosting could hang forever on a router that never answered UPnP. The
  host now gives discovery a hard 6 s budget, keeps loading in the background
  and upgrades the code if the mapping arrives later.
- The host no longer advertises a public IP as a joinable code when UPnP
  failed; it shows the LAN code plus a clear port-forward/CGNAT explanation.
- LAN IP selection skips VPN, Hyper-V, WSL, Docker and VirtualBox adapters.
- Joining now times out after 12 s with an actionable message instead of
  hanging on "Connecting...".
- Starting any scene while another transition was in flight is queued instead
  of silently dropped, and pause is cleared before every transition.
- Multiplayer Meadow Loop now actually shows the other players and their
  vehicle models instead of loading a solo scene.
- In 3+ player sessions, client names and cart positions were only sent to the
  host; the host now relays them so every client sees every player.
- Race result titles now reflect the finishing place instead of always saying
  YOU WIN, and the field size is no longer hard-coded to four.
- Race sync stops cleanly when the host leaves, instead of spamming RPC errors
  during the disconnect transition.
- The loading screen no longer spams an invalid-polygon error; the hills layer
  triangulates cleanly.
- Minigame vehicle choice now applies to the race without overwriting the
  saved sandbox choice.

## [0.4.2] - 2026-11-05

Menu polish across every screen.

### Changed

- Main-menu buttons (PLAY / SETTINGS / CHANGELOG / QUIT) now share the same
  80 px height, corner radius and spacing for a tidier stack.
- Hover animation is mouse-only: buttons bob, wobble and squish under the
  pointer, but a keyboard-focused button (including PLAY on boot) stays still.
- Candy styling and hover effects extended to the pause menu, SETTINGS
  (check-for-updates / back) and CHANGELOG back button; lobby, vehicle picker
  and update dialog already inherit it.
- Play menu hides its empty notice row, closing the awkward gap above BACK.

## [0.4.1] - 2026-11-05

Every vehicle now has its own personality - and the game has a changelog.

### Added

- **Per-vehicle physics**: each catalog entry has a real mass, top speed,
  engine power, grip and steering. Engine power is quoted at a 1.2 t reference,
  so the 3.2 t truck launches gently while the 1.15 t sports car is quick.
- **Momentum-based impacts**: hitting walls uses the vehicle's mass (light cart
  bounces and sheds speed; heavy truck ploughs on) and ramming props transfers
  proportionally more momentum from heavier vehicles. Camera shake scales down
  with weight.
- **Unique vehicle audio**: six distinct synthesized engine loops plus a
  shopping-cart wheel rattle (no engine), all pitch-shifted by speed. Generated
  by `tools/gen_vehicle_loops.py`; free CC0 source links in
  `docs/AUDIO_SOURCES.md`.
- **Per-vehicle smoke and skid marks**: sports car and truck produce the most
  smoke; skid width and rear track now match each vehicle (cart thin, truck
  wide).
- **CHANGELOG button** on the main menu with a scrollable history built from
  `CHANGELOG.md`, so every released version is listed in-game.

### Changed

- The speedometer dial rescales to the current vehicle's boosted top speed
  instead of clipping at 90 km/h.
- Vehicle picker/README now document the weight and top-speed differences.

### Fixed

- Skid trails for wide vehicles were both offset to the same side and merged
  into one thick mark; they now keep their left/right wheel sides.
- The update badge never appeared on the first menu load: the 3-argument
  `update_available` signal was connected to a 1-argument handler.
- The update dialog could not be dismissed once an update was ready; Escape
  now closes it, release notes close it after opening, and "no matching build"
  opens the download page instead of getting stuck on "DOWNLOADING".
- Changing scenes while paused (host start / host quit) carried the pause flag
  into the new menu, freezing it. Transitions always unpause first.
- The loading overlay hid the custom cursor and let clicks reach the menu
  behind it; it now blocks input and draws the cursor above the overlay.
- Lobby could START before hosting finished, and a failed host left a fake
  code panel; buttons wait for `host_started`, failures reset the panel, and
  BACK cancels an in-flight host instead of leaking a server.
- Tab focus could escape update/settings/changelog overlays; focus now loops
  inside each overlay and closing pause clears an open settings panel.
- Tournament dropdowns overwrote Free Play settings with the wrong widgets.
- Vehicle select had no working buttons if the catalog was empty.
- The loading screen kept redrawing while hidden and skipped the first tip.
- Remote peers could keep the wrong vehicle model when joining mid-game; the
  sandbox now exchanges a full vehicle map when each peer enters the scene.
- Skid ribbons joined separate drifts with a stripe across the map; strips now
  break into segments that fade independently.
- Navigation requested during a transition was silently dropped, which could
  desync host/client scene loads; it is queued instead.
- Reset in multiplayer respawned on the single-player marker and snapped
  host-owned props around; it now uses the network spawn and leaves props to
  the host.
- Crashed/recovering carts kept emitting drift smoke and skid marks.
- Knocked-over props stayed upright on clients; full rotation is replicated.
- Client pushes applied impulses to frozen props and the host ignored spin;
  clients now only request, and the host validates and applies the kick.
- Ghost carts ran smoke/skid/audio logic and could briefly steal the camera.
- UPnP mappings are now time-limited instead of permanent.
- Download progress no longer jumps to 100% when the CDN omits Content-Length,
  and old update zips are pruned.
- Guarded divide-by-zero on designer-exposed speed/recovery values.

## [0.4.0] - 2026-11-05

Playtest polish: real skid marks, music, a complete update flow and a quieter
loading policy.

### Added

- **Tyre skid marks** (`scripts/feedback/skid_trail.gd`): one world-space
  ribbon per rear wheel while drifting/handbraking. Marks hug ramps via ground
  raycasts, break on jumps, never z-fight, and fade out over 6 seconds.
- **Music system** (`Music` autoload): crossfades a menu bed and a sandbox bed,
  loops MP3s, and silently skips missing files. Drop-in folder
  `assets/audio/music/` with exact filenames and Suno prompt guide.
- **Update progress UI**: real download percentage and MB counter, plus
  **RESTART TO INSTALL** once complete; reopening the panel while a download
  runs shows live progress. Failed downloads now offer the release page.
- **SETTINGS → CHECK FOR UPDATES** with online/up-to-date/offline feedback.
- **Async hosting**: the loading overlay animates while the port and UPnP
  mapping are prepared; the lobby no longer freezes.
- Easy player-facing download/play instructions in `README.md`.

### Changed

- The loading screen is only used for long transitions (entering the 3D arena,
  starting a network session); quick menu hops are instant again.
- **Minigames are removed from the UI** for now; the scene is kept for the
  future scrollable preview grid. PLAY offers SANDBOX and MULTIPLAYER only.
- Updater now selects the release zip for the **running platform** instead of
  always preferring the Windows build.

### Fixed

- Update panel could not reopen cleanly mid-download and its secondary button
  closed the dialog after a failed download instead of opening the release page.
- macOS/Linux clients could previously download the Windows update package.

## [0.3.0] - 2026-11-05

Profiles, online play, loading screens and the minigames hub.

### Added

- **Player names**: up to 16 printable characters, sanitised on send and
  receive, persisted, shown in the lobby and floating above remote carts.
- **LAN / ONLINE switch** in the lobby. Online uses UPnP or a public IP with an
  optional manual PUBLIC IP override; LAN uses the local address.
- **Checksummed 14-character join codes** - typos are rejected before connecting.
- **Themed loading screens** for every scene transition (cart driving along a
  road with the real progress) plus a branded boot splash.
- **Minigames hub** (`minigames_menu`): Free Play cards with per-game options
  (difficulty, rounds, vehicle) and a Tournament setup prototype; options are
  persisted. All minigames are solo and marked COMING SOON.
- PLAY now offers SANDBOX / MULTIPLAYER / MINIGAMES.

### Fixed

- Join-code decoding loop included the checksum byte, rejecting valid codes.

## [0.2.1] - 2026-11-05

- Auto-install is Windows-only now: macOS and Linux update badges open the
  release page instead of handing a .bat to a missing cmd.exe.
- Multi-platform release assets (Windows, macOS, Linux, Web).

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
