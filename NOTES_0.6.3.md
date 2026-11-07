# Cart Slop GP 0.6.3 — notes (prepared, NOT released)

Status: **built locally, no tag, no GitHub release, no Pi mirror upload.**
The owner must approve the release; nothing has been pushed.

The locally prepared 0.7.0 label was never tagged or shipped. At the owner's
request the next patch is **0.6.3**, so all of the work below plus the menu /
animation pass ships under that number. See the 0.6.3 entry in `CHANGELOG.md`.

## What changed

### Skid marks in the race (root-cause fix)
- Meadow Loop's dirt road was a visual ribbon only. The kart physically drove
  on the ground box 4 cm lower, and the skid-trail raycasts painted marks at
  ground level — one centimetre or so UNDER the road texture, so nobody ever
  saw them in the race.
- `_build_track()` now also builds a `ConcavePolygonShape3D` from the road
  ribbon (`RoadCollision`, layer 1). Wheels rest on the visible dirt and the
  marks land on top of it. Verified with a real driving probe
  (`tools/skid_shot.tscn`, windowed): two parallel fading ribbons hug the road.
- The sandbox skid system was untouched; it already worked.

### Race identity: one car + tag colours
- In MINIGAMES sessions the host's vehicle is forced onto every peer:
  `grass_race._setup_multiplayer()` broadcasts `_net_force_race_vehicle`,
  `_net_race_ready` re-sends it to late/missed peers, and `_store_net_vehicle`
  applies host vehicles to the LOCAL cart via the new
  `CartPlayer.reapply_vehicle()` (pristine stats restore, so multipliers never
  stack). The off-track `_base_max_speed` is re-captured after the swap or
  the forced car silently reverts one frame later — that was a real bug the
  two-process test caught.
- Sandbox keeps per-peer vehicle choice.
- `GameSettings.player_tag_color` (hex, persisted). Lobby has 8 swatches.
  `Network.set_local_tag_color()` announces `_net_set_tag_color` (same relay
  pattern as names). Used on race + sandbox name labels, lobby list and the
  Tab list.

### Ping: ms + per-player table
- HUD line always shows ms; host shows `0 ms (host)`.
- Clients report RTT (`_net_report_ping`), host keeps `ping_table` and
  broadcasts `_net_ping_table`; lobby rows and the Tab list show it with
  green/amber/red colouring.
- Holding Tab (HUD `_unhandled_input`) opens the Minecraft-style list; rows
  rebuild at ~3 Hz while held.

### Floating carts fixed
- Remote ghosts have physics off and stayed at spawn height (race: 0.2 m,
  sandbox: 0.25 m); sandbox bots floated at 0.12 m forever. Race ghosts spawn
  at 0.05 (road top is 0.04), sandbox ghosts snap to a downward raycast
  (`driving_test._ground_height`), bots sit at 0.02.

### Update system (the greyed RESTART & UPDATE button)
- `update_checker.gd`: 600 s download budget; `_process` stall watchdog — if
  `get_downloaded_bytes()` stops moving for 20 s the request is detached
  (`HTTPRequest.cancel()` does not exist in Godot 4.7, and freeing it
  mid-flight can block the main loop on the thread join), its handler is
  disconnected, `timeout` is shortened so the engine ends the transfer, and
  `download_failed("stalled_connection")` is emitted. Partial files are
  deleted on any failure.
- `update_panel.gd`: self-heal loop — whenever the zip for the advertised
  version exists on disk and the dialog is not busy, it promotes to
  RESTART & UPDATE even if the finish signal was missed (hidden panel, scene
  change, freed instance).
- Verified headless with `tools/mock_update_server.py` +
  `tools/test_update_flow.tscn`: happy path reaches an enabled
  RESTART & UPDATE; the stall scenario recovers to TRY AGAIN in ~20 s.
- Known engine limit: the detached request's thread can stay blocked until
  the OS drops the dead connection, so *quitting the game* during that window
  can wait a bit. The dialog itself recovers immediately.

### Bug hunt / tests
- `test_car_collision.gd` was driving a cart into a ghost frozen mid-air
  (ghosts have no physics) and measured a free fall → FAIL since before
  0.6.2. The ghost now rests on the floor and the test PASSES.
- Full suite green: smoke_meadow_loop, vehicle_catalog, car_collision,
  car_collision_authority, pause_modes, ramp, loop_playback, update_panel,
  update_checker, update_extract, public_fallback.
- NEW `tools/test_sync_host|client(.gd/_driver.gd/.tscn)`: two headless
  processes over LAN — verifies forced race vehicle (client speed 19→18),
  tag colour relay both ways, ping table, scene readiness. Both peers PASS.
- Sandbox pair run through the LIVE Pi (host got code, client joined).

## Menu / animation / navigation pass (this session)

- `scripts/ui/ui_anim.gd` (`class_name UiAnim`) — shared eased fades, pops,
  slides, shakes and frame-rate independent damping. All tweens run while the
  tree is paused.
- `scripts/ui/menu_nav.gd` (`MenuNav` autoload) — owns arrow / WASD / d-pad
  focus for every screen. Discovers the active scope through the `nav_scope`
  group, builds a geometry-aware focus map, installs explicit
  `focus_neighbor_*` and `focus_next/previous` paths, wraps at edges, keeps
  focus out of hidden panels, scrolls dynamic room lists into view and never
  consumes letters typed into a LineEdit.
- `candy_button.gd` — focus now animates like hover with visible selector
  chevrons; `ui_kit.gd` installs a uniform yellow focus ring on every button.
- `pill_cycler.step()` lets left/right cycle BOTS / MODE in place.
- `changelog_panel` — anchored full-height panel, scrollable text, line-budget
  pagination (165 lines/page), flush-left bullets that fold markdown wraps.
- `loading_screen` / `scene_loader` — redesigned progress card with 10 visible
  sections, cart at the fill head, damped fill and a fixed big percentage.
- `stat_bar.gd` + `vehicle_catalog.stats_for/stat_ranges/stat_ratio` —
  10-block relative bars, no raw numbers, aligned two-column sheet.
- `lobby_menu` — final pass is ONE centred column (900 px body): compact
  profile row, numbered HOST / JOIN button groups, one room card, host
  settings, START and LEAVE ROOM. No coloured accent bars on cards, no
  HOW IT WORKS / CONTROLS filler, no permanent keyboard hint. Error label is
  hidden unless there is a message.
- `scenes/ui/room_browser.tscn` + `scripts/ui/room_browser.gd` — modal popup
  with a search field (filters host name / room code locally), REFRESH and a
  scrollable result list. Opened by both FIND LAN ROOMS and BROWSE ONLINE
  ROOMS; emits `room_selected(room)` back to the lobby. Registers in the
  `nav_scope` group so arrow-key focus stays inside the popup.
- Left/right screen actions: `play_menu`, `vehicle_select`, `changelog_panel`.

## Final pass (this session, part 2)

### macOS updater fix (answer: unsigned Mac DOES update with one click now)
The old `_install_macos()` returned before `get_tree().quit()`, so the shell
script sat in `while kill -0 $PID` forever and RESTART & UPDATE did nothing.
Fixed plus three more real bugs:
- `ZIPReader` recreates files as 0644, so the copied `.app` had no executable
  bit. The installer now runs `chmod +x "$APP/Contents/MacOS/"*`.
- `rm -rf "$APP"` with no backup could leave the player with no app. Now the
  old bundle is moved aside, the new one is copied, and a failed launch rolls
  back to the previous build.
- Re-signs ad-hoc only when `codesign --verify` fails, clears Gatekeeper
  quarantine, and uses `open -n` for a fresh instance.
- A write-probe detects a read-only location before quitting; the dialog then
  shows a specific message and opens the release page instead of lying.
Godot exports are ad-hoc signed (`codesign/codesign=1`, empty identity), not
notarized. Replacing a Developer ID signature with an ad-hoc one still launches
after quarantine is cleared, but macOS may re-ask for TCC permissions.
New test: `tools/test_macos_update.gd` validates the generated script on Windows.

### UI
- `loading_screen.gd` — the dark card is GONE. Bar, percent, message and tip
  sit directly on the SlopMart illustration with a soft gradient scrim and
  font outlines for contrast. Added animated road dashes above the bar.
- `candy_button.gd` / `play_card.gd` — focus chevrons now point inward `>  <`.
- `scripts/ui/play_card.gd` + `play_menu.gd` — PLAY is a picker with two large
  square icon cards (one cart / two carts), labels drawn underneath and one
  full-width BACK bar. Each card opens its own state; BACK returns to the picker.
- `CHANGELOG.md` — rewritten as short casual player notes, no em-dashes, no dev
  detail. Still uses `## [version] - date` so the in-game pager works.
- `grass_race.gd` — start gantry is now a real F1 two-row, ten-lamp rig. One
  column (two lamps) lights per beat, so two dots at once is intentional.
  Sequence 0, 2, 4, 6 red, all ten green on GO. Documented in MEADOW_LOOP.md.

### Docs
- `README.md` — full setup guide: install per platform, macOS Gatekeeper and
  unsigned/self-update behaviour, controls, single player, vehicles, minigames,
  LAN and online multiplayer step by step, Pi ports, troubleshooting, updater
  publishing checklist, dev setup, exports and tests.
- `docs/AI_ART_PROMPTS.md` — rewritten at the owner's request as a small
  curated set of 7 general, copy-paste-ready game background prompts. One
  shared style and palette, one shared "never" list, no screen-specific
  filenames, dimensions or integration spec.

## Screen logic cleanup (this session, part 4)

- `play_menu.gd` — MULTIPLAYER card now goes STRAIGHT to `lobby_menu.tscn`.
  Removed the redundant "multi" state and its OPEN MULTIPLAYER LOBBY button.
  Only two states remain: picker and single.
- `minigames_menu.gd` — when opened from the lobby (`Network.is_session_active()`)
  it is a map picker: title becomes CHOOSE A MAP and the VEHICLE button is
  hidden. Solo play still shows it. Vehicle choice for multiplayer lives in
  HOST SETTINGS only. Lobby's `_on_choose_map` now loads with the
  "CHOOSE A MAP" title.
- `lobby_menu.gd` / `.tscn` — room card is now TWO COLUMNS: code caption,
  code, COPY CODE / LEAVE ROOM and the share hint on the left; PLAYERS header
  and list on the right, separated by a thin divider.
- Removed the PI SERVER ONLINE / OFFLINE pill completely. Online shows nothing.
  Offline shows one plain line: "Game server is down. Try again later."
  `_server_checked` prevents a false error flash before the probe finishes;
  `_refresh_status()` preserves real join/host errors and re-applies the
  server-down line across state changes. All three old "Cart Slop server is
  offline" strings now use the single `SERVER_DOWN` constant.
- Room hints shortened ("Share this code with your friends.").
- `README.md` multiplayer section and troubleshooting table updated.
- `CHANGELOG.md` 0.6.3 entry updated. Still 0.6.3, no release.
- `tools/ui_pass_check.gd` now asserts: no ServerPill node, status only shows
  a plain error, code/players in different parent columns, no `_on_multi`
  method, and that the MULTIPLAYER card navigates to the lobby directly.

## Final 0.6.3 pass (art, layout, updater, release)

### Artwork (5 supplied images, not 6)
Owner supplied 5 `.webp` files in the OS Downloads folder. Converted to
optimised PNG and copied into `assets/ui/art/`:
`bg_parking.png` (menu + loading), `scene_track_aerial.png`, `scene_road.png`,
`scene_arena.png`, `scene_finish.png` (game selector slideshow). Renamed
originals are archived in `downloads/ai_art/`.
- New `scripts/ui/art_backdrop.gd`: full-bleed `TextureRect` layers with an
  optional crossfade slideshow. IMPORTANT: explicit parent-size fitting in
  `_process`; `set_anchors_preset(PRESET_FULL_RECT)` alone left the node at
  0x0 when parented to a plain Control (not a Container).
- `menu_background.gd` uses `bg_parking.png` and skips the vector drawing when
  the image loads; vector art remains the fallback.
- `loading_screen.gd` aspect-covers `bg_parking.png` via `draw_texture_rect`.
  Scrim rewritten to 80 exact-height bands (28 overlapping +1 bands produced
  visible horizontal stripes over flat art).
- `minigames_menu.gd` preview is a 4-image crossfade gallery led by the aerial
  dirt-track shot; single static `meadow_loop.png` removed.
- `export_presets.cfg` include_filter now lists `assets/ui/art/*.png`.

### Layout
Every panel shrunk so the artwork shows around it: main 560->450, play 780->680,
minigames 1080->880, vehicle 780->700, settings 640->540, update 600->520,
pause 460->420, room browser 780x500->700x460, changelog anchors 0.07..0.93 ->
0.15..0.85, lobby margins 48->130 and body 900->760. Lobby/play/minigames/
vehicle buttons switched from EXPAND_FILL to fixed widths + SHRINK_CENTER with
centered rows. Lobby step labels centered to match.

### Updater
`chmod -R u+rwX "$APP"` removed from the macOS installer. It rewrote sealed
resource modes, invalidated the ad-hoc signature and forced a re-sign on every
update. Now only `Contents/MacOS/*` is made executable, `codesign --verify
--deep` runs first (no `--strict`, which ad-hoc bundles fail), and re-signing
only happens when verification actually fails. Test updated accordingly.

### Bug hunt
- `tools/test_join_started.gd` was a live-server test that reported FAIL when
  `CODE` was unset. Now prints SKIP and exits 0.
- Audited all scripts: no `get_meta(key, null)` calls left (Godot 4.7 errors
  on those), no missing UiAnim preloads, no TODO/FIXME left in scripts.
- Ran the whole offline headless battery plus windowed UI renders. All green.

## Release checklist (DONE 2026-11-06)
1. Commit + tag `v0.6.3`, push.
2. Export all four platforms into `builds/v0.6.3/`, zip, `gh release create`.
3. Upload the Windows zip to the Pi mirror + bump
   `pi_setup/cartslop-server/updates/manifest.json` (version 0.6.3).
4. Old build should offer the update automatically.

## Shipped

- Commits `f03f444` (release) and `89893d9` (updater arbitration), pushed to
  `origin/main`. Tag `v0.6.3` force-moved onto `89893d9` after the last fix.
- GitHub release: https://github.com/HOT18594/CartSlopGP/releases/tag/v0.6.3
  with all four zips. Assets rebuilt and re-uploaded after the final updater
  change so binaries match HEAD.
- Live check: `LIVE status=up_to_date local=0.6.3 latest=0.6.3
  asset=CartSlopGP_v0.6.3_windows.zip asset_url=true`.
- Working tree clean at handoff time.
