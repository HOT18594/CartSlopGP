# Quality of Life, Feel and Clarity Backlog — v0.8.7+

A prioritised, code-grounded backlog of quality-of-life, gameplay-feel,
perceived-speed and player-clarity improvements for the releases after v0.8.6.
Produced read-only against the v0.8.6 tree. **Status note (v0.8.7 Phase 2):**
several of the top items are now implemented — gamepad scoreboard (Q01),
Web-build gating (Q05), solo focus-loss auto-pause (Q04), lobby ready/presence
gate (Q11), and the loading/sync clarity work (Q03/Q09 partially). The entries
below are kept as the original review record; check `CHANGELOG.md` and
`docs/Future To Do's.md` for current status.

## How this was built

- Read the project docs (`AGENTS.md`, `docs/ARCHITECTURE.md`,
  `docs/MAINTENANCE.md`), the v0.8.0–v0.8.6 `CHANGELOG.md` sections and the
  workspace notes (`docs/Future To Do's.md`, `docs/NOTES_NETWORK_VEHICLES.md`).
- Read the actual code paths behind each flow: menus and modals, lobby and room
  browser, HUD, all four match scenes, pause/settings/update/changelog, input
  setup, settings persistence, audio, the scene loader and the multiplayer
  layer. Line numbers below are from this tree (v0.8.6) and will drift as files
  change.
- Ran the headless boot check (`--quit-after 120`, exit 0) and a throwaway
  headless HUD probe at the settings maximum `hud_scale = 1.5` (13-entry
  standings: no gauge overlap, no cluster outside 1280×720). The probe was
  deleted; no project file was touched. That probe was worth doing: the 1.5×
  maximum that `settings_menu` offers is not covered by `hud_smoke.gd`
  (which stops at 1.35×), and it currently holds.
- **Not** done: no windowed playtest, no capture of the live UI, no live
  multiplayer session. Claims are from code and the shipped test harness.

Paths are relative to `godot_project/` unless prefixed `workspace:`.

### Scales

| Effort | Meaning |
| --- | --- |
| **S** | Under one day; one or two files; no new state or protocol. |
| **M** | One to three days; new persisted state, a new panel, or a protocol/format addition. |
| **L** | A week or more; new subsystem, cross-cutting input/protocol work, or real render cost. |

**Priority:** P0 = a shipped control/flow misleads or blocks a common player
today. P1 = high-impact clarity, feel or retention. P2 = a good addition worth
scheduling. P3 = a large or speculative bet.

### What this list deliberately does not repeat

Already shipped in 0.8.x, so **not** proposed again: the slanted dark-glass UI
and end-screen rebuild (0.8.6), host rematch buttons, the paint shop and vehicle
sync, `PICK OWN`/`SHARED`, master/music/SFX volumes, boost/drift hold-vs-toggle,
reduce motion, HUD scale, stick deadzone, quality presets, dynamic resolution,
room code entry/copy, lobby ping, HUD ping, the Tab scoreboard, R reset,
wrong-way banner, lap pips and lap/best-lap readouts, finish fanfare, the
in-game changelog viewer, and the SHA-256 verified desktop updater.

End-screen **layout** is owned by the concurrent UI workstream; items below ask
for **content and behaviour** (data, gating, status text) and note where the
layout team should implement the visual part. Networking state ownership is
called out where a fix crosses into the multiplayer workstream.

The two items already listed as open in `workspace:docs/Future To Do's.md`
(ghost lap, split-screen) are included only with a concrete design, in
[P3](#p3--big-bets).

## Summary — top 15

| ID | Item | Pri | Effort | Player impact |
| --- | --- | --- | --- | --- |
| Q02 | On-screen prompts teach keyboard keys to gamepad players | P0 | S | Pad players are told to press keys they are not using |
| Q01 | Gamepad cannot open the scoreboard at all | P0 | S | A documented control does nothing |
| Q03 | "Waiting for players" has no count or names | P0 | S | A normal start looks like a freeze |
| Q04 | Solo race keeps running when the window loses focus | P0 | S | Alt-tab loses the race |
| Q05 | Web build offers multiplayer/quit it cannot serve | P0 | S | Dead-end menus on a supported platform |
| Q06 | No first-run setup, controls screen or first-race hints | P1 | M | New players get no controls help beyond loading tips |
| Q09 | RACE AGAIN rebuilds the whole circuit (~3.7 s+) | P1 | M | The retry loop — the core skill loop — has a loading screen |
| Q08 | Best laps are never saved (README says they are) | P1 | M | No personal bests, no reason to return solo |
| Q11 | Lobby has no ready state; host can launch while a client is in the garage | P1 | M | Host starts a match the client never sees |
| Q07 | No control remapping | P1 | L | Accessibility and keyboard-layout blockers |
| Q10 | Results show "—" for every rival's total/best | P1 | M | The results table can't answer "how close was it?" |
| Q12 | Reduce motion misses the big hazard flashes | P1 | S | Photosensitivity risk in two modes |
| Q13 | Colour is the only cue for several states | P1 | M | Colourblind players lose lap/ping/team distinctions |
| Q14 | No minimap or within-lap progress cue | P1 | M | Easy to lose track of where you are on 1 km circuits |
| Q17 | Pause has no restart / return-to-lobby | P1 | S | A bad start needs a full reload or a room exit |

---

## P0 — fix first

These are small, clearly wrong, and hit common flows. They are all safe to do
without waiting for design sign-off.

### Q01 · The gamepad cannot open the scoreboard

- **Player problem:** `Tab` opens the in-match scoreboard on keyboard, and the
  README promises the same on a controller (`Select / View`), but no joypad
  button is bound anywhere. Pad-only players have no scoreboard, and it is the
  only in-match place that shows per-player ping.
- **Evidence:** `README.md:117` documents `Select / View`. The HUD handles Tab
  as a raw key event only: `scripts/hud.gd:2029-2037` (`if key == null: return`,
  then `KEY_TAB`). `scripts/systems/input_setup.gd:13-42` adds the joypad
  bindings for driving and menus but has no `scoreboard` action; `project.godot`
  has no such action either.
- **Proposal:** add a `scoreboard` InputMap action (Tab plus gamepad
  Back/Select), handle it with `Input.is_action_pressed()` in `hud.gd` so it
  works for any device, and list it in the eventual CONTROLS screen (Q07).
- **Effort:** S. **Priority:** P0.
- **Risk / dependencies:** none technically. Keep the hold behaviour and the
  `ui_accept`-style routing intact; `hud.gd` is a shared file — coordinate the
  exact hunk with the multiplayer workstream (they read standings data from it).
- **Acceptance sketch:** in a solo race and a LAN race, holding gamepad
  Select/View shows the scoreboard and releasing hides it; Tab unchanged;
  `hud_smoke.gd` asserts `InputMap.has_action("scoreboard")` and that the action
  has both a key and a joypad event.

### Q02 · Prompts and the ability dock speak keyboard only

- **Player problem:** the party-mode dock renders a hard-coded `[E]` keycap and
  a keyboard-only controls strip even on a controller. In Deliver the crate
  load is bound to the pad's left shoulder (`JOY_BUTTON_LEFT_SHOULDER`) but the
  prompt reads `HOLD [E] TO LOAD`, because the key-name helper returns the first
  keyboard event. Pad players are told to press a key on a device they are not
  using, and the actual LB binding is documented nowhere.
- **Evidence:** `scripts/ui/ability_dock.gd:17` (`key_text = "E"`) and `:22`
  (default `WASD DRIVE · SPACE DRIFT · SHIFT BOOST · E SLAM`); set in
  `scripts/minigames/knockout.gd:2276` and
  `scripts/minigames/bomb_tag.gd:2746`; Deliver's keyboard-only strip at
  `scripts/minigames/cargo_rush.gd:2798-2809`. The pad binding is added at
  `scripts/minigames/cargo_rush.gd:543-546`, but `_interact_key_name()`
  (`:549-558`) returns the first `InputEventKey`, so the HUD always prints `E`.
- **Proposal:** track the last input device in a tiny autoload helper (listen
  for `InputEventJoypadButton`/`InputEventJoypadMotion` vs key/mouse), and make
  prompts device-aware: keyboard shows `E`/`SHIFT`/`SPACE`, gamepad shows
  `B`/`LB`/`A` glyphs. Reword the dock strip per device (e.g.
  `STICK DRIVE · A DRIFT · X BOOST · B SLAM`). Also make the README's control
  table state the Deliver shoulder binding explicitly.
- **Effort:** S. **Priority:** P0.
- **Risk / dependencies:** `ability_dock.gd` and the mode HUDs are UI-team
  files; this is a text/input-source change, not a restyle. Keep the keycap
  node able to render two-character glyphs without clipping (it auto-fits
  already).
- **Acceptance sketch:** with only a gamepad touched since the last screen,
  every in-match prompt shows pad glyphs and never a keyboard letter; with
  keyboard/mouse, nothing changes; the Deliver prompt names the shoulder button;
  no prompt clips at 1280×720 or 960×540.

### Q03 · "Waiting for players" is an unexplained countdown

- **Player problem:** after the loading screen, every player (host included)
  sees a giant `WAITING` label while the room waits for scene-ready peers for up
  to 8 s with no count, names, or progress. A normal join looks like a hang, and
  when the 8-second fail-safe fires the countdown starts with no explanation
  that players were left behind.
- **Evidence:** `scripts/minigames/grass_race.gd:416-418` sets
  `_countdown_label.text = "WAITING"`. The wait itself is at
  `scripts/minigames/grass_race.gd:3728-3744`:
  `all_ready or _wait_elapsed >= 8.0` then `_begin_race_countdown()`, with no HUD
  update in between. The data needed is already there:
  `scripts/net/network.gd:218` (`scene_ready_peers`), `:486-492`
  (`is_scene_ready`), and the loading screen already says
  "Syncing players..." (`scripts/net/network.gd:3825`).
- **Proposal:** replace `WAITING` with a labelled status card:
  `WAITING FOR PLAYERS  3/5` plus the names of peers not yet ready (or
  `STARTING: 2 STILL LOADING`), and a one-line hint that the host's 8 s fail-safe
  will start without them if they don't arrive. Reuse the countdown label area
  (no new layout).
- **Effort:** S. **Priority:** P0.
- **Risk / dependencies:** reads network state only; multiplayer workstream owns
  `network.gd`, so do not change the wait policy here. The same status line
  should be reused by the other three match scenes (they have a shorter or
  implicit wait).
- **Acceptance sketch:** a two-process LAN race with one client deliberately
  delayed shows `WAITING FOR PLAYERS 1/2` then the countdown; when the 8 s
  fail-safe fires the message changes to `STARTING WITHOUT 1 PLAYER` for one
  beat; no change to solo.

### Q04 · Solo play keeps racing when the window loses focus

- **Player problem:** alt-tabbing, clicking another window, or the OS swallowing
  focus during a solo race does not pause the race. The player comes back to a
  finished or badly placed run through no input of their own. This is a
  Windows/macOS/Linux papercut that costs races.
- **Evidence:** there is no `NOTIFICATION_APPLICATION_FOCUS_OUT`/
  `FOCUS_IN` handling anywhere in `scripts/` (searched). The pause menu opens
  only from the pause/cancel action (`scripts/ui/pause_menu.gd:140-152`), and
  `GameSettings` only handles close/pause notifications to flush a save
  (`scripts/systems/game_settings.gd:186-192`).
- **Proposal:** in the solo race scene only, auto-open the existing pause menu
  on focus-out (or after a short grace period so a quick alt-tab doesn't stop
  you). Never auto-pause a multiplayer session (the world is shared); instead
  show a small "window unfocused" badge in multiplayer. Add a
  `pause_on_focus_loss` setting (default ON) next to the existing toggles.
- **Effort:** S. **Priority:** P0.
- **Risk / dependencies:** must not fire during `SceneLoader` transitions,
  while a modal is open, or when the game is already finished; guard with
  `SceneLoader.is_busy()` and `_phase`. Web is complicated (tab hidden), so
  scope the first pass to desktop.
- **Acceptance sketch:** a solo race pauses within ~0.4 s of focus loss with the
  standard pause panel, and resumes on return; a multiplayer race keeps running
  and shows the badge; toggling the setting off restores today's behaviour.

### Q05 · The web build offers flows it cannot serve

- **Player problem:** the browser build ships the full main menu. MULTIPLAYER
  leads to a lobby whose host/join paths create `ENetMultiplayerPeer`s, which
  browser exports cannot use; the failure is a generic join error after a long
  wait rather than "this is desktop-only". `QUIT` calls `get_tree().quit()`,
  which cannot close a browser tab — it stops the page instead. `UPDATE` says
  "Up to date" no matter how old the served build is. The README already states
  the web build is solo-only, so the UI is the part that is wrong.
- **Evidence:** `README.md:93` (web = solo modes only). No web guard in
  `scripts/ui/main_menu.gd:821-823` (MULTIPLAYER), `:856-857` (QUIT), or
  `scripts/ui/lobby_menu.gd:224-258`. Transport creation:
  `scripts/net/network.gd:2483-2492` (`ENetMultiplayerPeer.create_server`) and
  `:3396-3404` (`create_client`). Update check short-circuits to
  `"up_to_date"` on web (`scripts/systems/update_checker.gd:211-221`), and the
  update panel is desktop-only (`scripts/ui/update_panel.gd:62-65`).
- **Proposal:** on `OS.has_feature("web")`: disable/replace the MULTIPLAYER tile
  with "MULTIPLAYER NEEDS THE DESKTOP DOWNLOAD" (release link), hide QUIT or
  relabel it "CLOSE TAB", and on web change the update row to "THIS IS THE
  LATEST WEB BUILD — REFRESH TO UPDATE" with a reload button. Keep the existing
  solo flow untouched.
- **Effort:** S. **Priority:** P0.
- **Risk / dependencies:** platform gating in menus is UI-team scope; the read
  is a single `OS.has_feature` check. Do not disable the browser build's
  LAN-direct path: it is unused because ENet cannot exist there.
- **Acceptance sketch:** the web export's main menu has no MULTIPLAYER or QUIT
  entry points and explains why; desktop builds are unchanged; a `--headless`
  run with `CARTSLOP_FORCE_WEB_QUALITY` is not affected (that env only changes
  rendering).

---

## P1 — high impact

### Q06 · No first-run setup, no controls screen, no first-race hints

- **Player problem:** a brand-new player lands on a bare hub with SOLO /
  MULTIPLAYER / GARAGE and five mode cards. Nothing explains that Space is the
  hop-drift, Shift is boost, E is the mode action, R resets the cart, or how
  drifting tiers work. The only in-game control teaching is five lines of
  loading-screen tips plus the party-mode dock strip; the HUD even keeps a
  `HintLabel` node that no code ever fills in.
- **Evidence:** the hub is built from buttons and cards only
  (`scripts/ui/main_menu.gd:583-780`); no first-run/onboarding code exists
  (searched: `first_run`, `onboard`, `tutorial`, `HOW TO` have no hits outside
  a comment). The only control text lives in the loading tips:
  `scripts/ui/loading_screen.gd:75-81`. The HUD hint label is declared and
  hidden at `scripts/hud.gd:43`, `:336-338` and never assigned. The settings
  sections are AUDIO/VIDEO/GAMEPLAY/ACCESSIBILITY/UPDATES only
  (`scripts/ui/settings_menu.gd:17`), with no CONTROLS page.
- **Proposal:** three small pieces, one shared flag in `settings.cfg`
  (`onboarded = true`):
  1. First launch only: a "PADDOCK BRIEFING" card offering driver name/tag
     colour, control scheme summary (keyboard + gamepad), boost/drift
     hold-vs-toggle, and HUD scale. Skip is allowed and re-openable later.
  2. A permanent CONTROLS page (in settings) rendering the lab-verified binding
     table from the InputMap — double duty as the reference screen for Q07.
  3. First N solo races (default 3, then never again): a fading bottom hint
     strip using the existing `HintLabel`, showing only the three most useful
     actions for the current mode. Respect `reduce_motion` for its fade.
- **Effort:** M. **Priority:** P1.
- **Risk / dependencies:** adds one settings key (bump `SETTINGS_VERSION` per
  `scripts/systems/game_settings.gd:19-28` pattern). UI-team scope for the
  panels. The control table must be generated from InputMap once Q07 exists, so
  build the table reader first and let the screen follow.
- **Acceptance sketch:** with a fresh `user://`, the briefing appears exactly
  once and the first three solo races show the hint strip; a returning save does
  not; CONTROLS opens from the main menu and pause menu and matches live
  bindings; the flag survives a settings reset only if the player chooses so
  (state it in the reset copy).

### Q07 · No control remapping

- **Player problem:** all keyboard/gamepad bindings are hard-coded at startup.
  A player on a non-QWERTY layout (the bindings are physical keycodes, so AZERTY
  WASD is offset), a left-handed player, a one-hand player, or anyone whose
  controller labels differ cannot change a single binding. This is the single
  largest accessibility gap in the game.
- **Evidence:** `scripts/systems/input_setup.gd:1-85` adds all joypad and
  one-hand keyboard events in code with no persistence or UI; the base bindings
  are static `Object(...)` InputEvent literals in `project.godot:44-90`; no
  settings section or file stores overrides. The README's control table
  (`README.md:103-119`) is the only place a player can even read the defaults
  in full.
- **Proposal:** a CONTROLS settings page (shared with Q06) with one row per
  gameplay action (accelerate, brake, steer L/R, handbrake/drift, boost,
  action/surge, horn, reset, scoreboard, pause), primary + secondary binding,
  "press a key/button" capture, conflict detection, and RESET ALL. Persist
  overrides to `user://controls.cfg` and re-apply them after InputSetup on
  boot; keep menu navigation out of scope (fixed).
- **Effort:** L. **Priority:** P1.
- **Risk / dependencies:** medium: physical vs unicode keycodes, axis/trigger
  capture, and the need to never let a player remove the last way to open the
  pause menu. Menu navigation (`ui_*`) stays fixed in v1. Coordinate UI shape
  with the UI workstream. Must be smoke-testable headless (apply overrides, read
  back the InputMap).
- **Acceptance sketch:** rebind accelerate from `W` to a pad trigger and from
  `Shift` to `Q`; both persist across restart; conflicting binding shows a
  warning and requires replace; RESET ALL restores defaults; a headless test
  applies an override map and asserts the InputMap and the settings file agree.

### Q08 · Best laps are never saved, although the README says they are

- **Player problem:** there is no personal best anywhere: closing the game
  forgets every lap. Solo has no long-term goal and map cards can only show a
  description, never "your best". This is the cheapest retention hook the game
  is missing, and it also fixes a documentation claim.
- **Evidence:** `README.md:96` says "Local settings and lap records are stored
  in..." but the only writes to `user://` are settings and the updater
  (`scripts/systems/game_settings.gd:8`, `scripts/systems/update_checker.gd:17-21`;
  no other `FileAccess`/`ConfigFile` writer exists outside tests/tools). Best
  lap is per-race only: `scripts/minigames/grass_race.gd:2992-3007`
  (`_best_lap_time()` over `_lap_times`) and the lap toast at
  `:4481-4517`. Map cards show only name/description/lap length/climb
  (`scripts/ui/minigames_menu.gd:851-946`).
- **Proposal:** a tiny persisted record store (`user://records.cfg`, per map +
  vehicle: best lap, best total, clean lap count), written atomically like
  settings, tolerant of corruption (same pattern as
  `settings.corrupt.cfg`). Surface it as: `BEST` on the HUD baseline when the
  current session has no faster lap (`REC` marker instead of blank), `NEW
  PERSONAL BEST` stamp on the result card, and a `YOUR BEST 1:02.345` line on
  each map card. Records are local-only; multiplayer results never write
  another player's record.
- **Effort:** M. **Priority:** P1.
- **Risk / dependencies:** no network change; solo/offline only, which keeps it
  out of the multiplayer workstream. Add a version/hash guard so a changed
  physics/track later does not silently keep unfair records (schema has a
  `track_hash` field, invalidate on change). UI-team owns where the map-card
  line sits.
- **Acceptance sketch:** set a best lap, quit, relaunch, and see it on the map
  card and as the HUD baseline; beat it and get a stamp; corrupt the file and
  the game boots with no records instead of crashing; a headless test round-trips
  a record through save/load.

### Q09 · RACE AGAIN rebuilds the whole circuit instead of restarting it

- **Player problem:** the retry loop is the core loop of an arcade racer, and
  today it costs a full teardown and rebuild: solo RACE AGAIN calls
  `SceneLoader.go_to(RACE_SCENE, ...)`, and the race scene is in the heavy
  overlay list (the loader's own comment measures Meadow Loop at ~3.7 s on the
  dev machine before the 0.8.6 Glacier rebuild; Glacier is now larger). Party
  modes do the same. Every restart is a loading screen, every rematch is a
  re-download of the world for every peer.
- **Evidence:** `scripts/minigames/grass_race.gd:4652-4657`
  (`_on_race_again` → `SceneLoader.go_to`); compare party modes:
  `scripts/minigames/knockout.gd:2549-2554`,
  `scripts/minigames/bomb_tag.gd:3276-3281`,
  `scripts/minigames/cargo_rush.gd:3932-3937`. `OVERLAY_SCENES` includes all
  five match scenes (`scripts/systems/scene_loader.gd:23-30`), and `MIN_SHOW`
  forces at least 0.25 s even for a fast load (`:10`). The reset machinery
  already exists for multiplayer re-sync: `_reset_race_progress(force)`
  (`scripts/minigames/grass_race.gd:3802-3855`).
- **Proposal:** implement an in-place restart path: reset race state (laps,
  lap times, sector flags, finish flags, rivals, effects, camera, HUD), re-place
  carts at the grid, and start the countdown without rebuilding the map. Use the
  full scene reload only when the player changes track or vehicle. For party
  modes, reset scores/round/phase in place. Keep a "Restarting..." one-beat
  overlay so the transition still reads intentionally.
- **Effort:** M. **Priority:** P1.
- **Risk / dependencies:** medium: state-reset bugs are easy (stale callouts,
  stale standings rows, effects, server-race ids). The groundwork is already
  used by the multiplayer re-join path, so lean on it and add a headless
  "restart twice" assertion. Do not change map-building ownership; this is a
  mode-scene change (multiplayer workstream owns those files, so land it there
  or coordinate).
- **Acceptance sketch:** RACE AGAIN in solo reaches the countdown in under
  ~0.5 s with the same track; all lap times/state cleared; in multiplayer, host
  RACE AGAIN still syncs every client (existing network start path), but no
  client rebuilds the 3D world unless the map changed.

### Q10 · Multiplayer results can't show rivals' total or best lap

- **Player problem:** after an online race the standings table is half empty:
  every remote player's `TOTAL` and `BEST` columns are `—`, and there is no
  fastest-lap award. The one screen that should settle "how close was it" gives
  the player data only for their own kart. (The local estimate is honest about
  it in code — that honesty is the point of the fix.)
- **Evidence:** `scripts/minigames/grass_race.gd:2534-2538`: "Remote peers do
  not replicate lap times, so their total/best stay '—' and the gap is the real
  track distance behind the leader". The remote stream carries position/yaw/
  progress/velocity only (`_net_race_cart_state` and `_broadcast_race_state`,
  `:3262-3275`, `:3411-3451`); the server race path reports laps only for the
  local player (`_report_server_lap_async`, `:4360-4379`).
- **Proposal:** include completed lap splits in the finish/state packet (a
  small `PackedFloat32Array` or `PackedInt32Array`, e.g. up to 9 entries of
  milliseconds, sent once on finish and again for late joiners; the existing
  batched state stream can carry a capped version). Fill `TOTAL`/`BEST` for
  every row and mark the fastest race lap. Keep an "old peer" fallback:
  missing laps still render `—`, never a fabricated time.
- **Effort:** M. **Priority:** P1.
- **Risk / dependencies:** network protocol + standings ownership is the
  multiplayer workstream; this document specifies the content contract only.
  Must stay backward compatible with 0.8.6 peers (extra fields ignored).
  Layout/content split with the UI workstream: they place the fastest-lap mark,
  the data comes from here.
- **Acceptance sketch:** two-process race shows both drivers' totals/bests and
  a fastest-lap marker; a peer with no lap data still shows `—` and no error;
  `mode_rules_smoke` or a new headless assertion checks the finish packet parse.

### Q11 · The lobby has no ready state and can launch past a client

- **Player problem:** the host can press START MATCH while another player is in
  the Garage, changing maps, or still loading the lobby from the room browser.
  From the host's side there is no signal that someone is away; from the
  client's side the match can start without them (they then see the scene-load
  path or the WAITING state). There is also no "everyone ready" moment at all.
- **Evidence:** `scripts/ui/lobby_menu.gd:1992-1999` (`_on_start_pressed`)
  checks only `Network.is_host` and immediately applies config and starts.
  Player rows render name/car/ping only (`:2013-2103`); no ready/presence state
  is exchanged. A client can leave the lobby for the Garage at
  `:1981-1989` (`_on_change_vehicle`). The client's own view just says
  `WAITING FOR HOST...` (`:1058-1064`).
- **Proposal:** add a lightweight presence + ready state: clients auto-ready in
  the lobby, go not-ready while in the Garage/changing map; the START button is
  disabled unless every connected player is in the lobby and ready (with a
  tooltip naming who is away), and a host press when all-ready starts a short
  room countdown ("STARTING IN 3"). Let the host override with a second press
  ("START ANYWAY" confirm) so a stuck client can't hold the room hostage.
- **Effort:** M. **Priority:** P1.
- **Risk / dependencies:** multiplayer session state (workstream-owned);
  network additions must be tolerant of old peers (treat unknown as ready but
  warn). UI-team implements the row state and button styling.
- **Acceptance sketch:** a client in the Garage turns its row amber and the
  host's START is disabled with "WAITING FOR 1 PLAYER"; both ready → 3-2-1 room
  countdown then match; host can override after a confirm; headless test covers
  the gating predicate.

### Q12 · Reduce motion misses the big hazard flashes

- **Player problem:** the game already has a solid reduce-motion switch that
  damps camera shake/roll/FOV, HUD speed lines and the wrong-way banner — but
  the largest luminance flashes in the game are not gated: Knockout's collapsing
  sector strobes and Blast Tag's fuse/status plates pulse between bright colours
  at ~2 Hz, large and unavoidable. For a photosensitive player this is
  worse than any camera motion.
- **Evidence:** the correct pattern exists: `scripts/hud.gd:1359-1373` holds a
  steady red/yellow wrong-way plate when `GameSettings.reduce_motion` is on.
  Ungated: `scripts/minigames/knockout.gd:734-750` (sector warning material
  lerps amber↔red at `rate 9.5 / 13.0`), and
  `scripts/minigames/bomb_tag.gd:2912-2943` (`flash = sin(_visual_time * 14.0)`
  flips fuse/status plate fill red↔pink). `cargo_rush.gd:2480-2487` is a single
  red→white fade rather than a strobe, so it is acceptable.
- **Proposal:** add a shared `Fx.flash_allowed()` helper (reads
  `GameSettings.reduce_motion`; optionally a separate `reduce_flashing` under
  ACCESSIBILITY if the owner wants a distinct switch). When it returns false,
  hold the hazard at one high-contrast colour and move the urgency into text
  (`⚠ DROPPING`) and scale/pop animations that are already damped, instead of
  luminance blinking. Apply to Knockout sectors and Blast Tag plates first,
  then sweep for any remaining `sin(...) > 0` colour flip.
- **Effort:** S. **Priority:** P1.
- **Risk / dependencies:** none to gameplay; colour choice must stay legible
  for colourblind players (Q13). Keep the default (reduce_motion off) exactly
  as today.
- **Acceptance sketch:** with reduce motion on, no in-match material/plate
  flips between two colours faster than 1 Hz; warnings remain obvious in a
  screenshot/video; with it off, behaviour is unchanged; grep-able helper is the
  only place the decision is made.

### Q13 · Colour is the only cue for several states

- **Player problem:** several meanings are carried by hue alone: lap-delta
  faster/slower is green/red text, ping quality is green/yellow, team identity
  in Deliver is blue/red, and player tag identity is an 8-swatch palette. For
  red-green colourblind players the lap delta and ping states collapse into
  "some colour", and team identity is the main trust cue in a 2-team mode.
- **Evidence:** lap deltas coloured green/red at
  `scripts/minigames/grass_race.gd:3043-3049` and the live HUD's delta badge
  (`scripts/hud.gd` `_refresh_lap_readout`, `:1272-1313`); ping thresholds in
  `scripts/hud.gd:1884-1890` (`_ping_color`) and room rows
  `scripts/ui/room_browser.gd:454-464` (green under 80 ms, else yellow); team
  colours `scripts/minigames/cargo_rush.gd:229` (`[UiPalette.BLUE,
  UiPalette.RED]`); tag palette `scripts/ui/lobby_menu.gd:53-60`.
- **Proposal:** a COLOUR BLIND setting under ACCESSIBILITY with two axes:
  (a) an alternate semantic palette (blue/orange instead of green/red, with a
  brighter team pair), and (b) redundant glyphs — `+`/`−` on every lap delta,
  `▲`/`▼` in standings for position change, a small square/triangle marker on
  team plates and car name tags, and a word (`GOOD`/`FAIR`/`POOR`) beside ping.
  Theme through the shared `UiPalette`/`UiKit` tokens rather than per-screen
  colours.
- **Effort:** M. **Priority:** P1.
- **Risk / dependencies:** UI-team owns the palette primitives; this is a
  token-set plus per-screen glyph addition. Verify against the darkest end
  screens (standings already use plates). A headless screenshot-free check can
  at least assert the palette switch is read by the HUD.
- **Acceptance sketch:** with the setting on, a grayscale screenshot of the
  results table still distinguishes gain/loss and the fastest lap; team pods in
  Deliver keep distinct shapes; ping reads as words; nothing regresses with the
  setting off.

### Q14 · No minimap, and no within-lap progress cue

- **Player problem:** circuits are 857 m to ~1.8 km with elevation, splits and
  two chasm jumps; the HUD shows lap count and completed-lap pips but nothing
  about where you are on the current lap or where the field is. Players who
  spin out or land a jump badly cannot orient themselves without driving on, and
  the live standings gaps (metres) require knowing the track shape.
- **Evidence:** the HUD has no minimap: its built cluster list is the state
  plate, dial, net block, scoreboard, race plaque, standings, gear/drift/wrong-way
  badges, callout and boost header (`scripts/hud.gd:342-358`); lap pips show
  completed laps only (`_lap_pips_for`/`_update_lap_pips`, `:819-855`). The
  centreline the minimap needs is already available as `_track_points`
  (`scripts/minigames/grass_race.gd:365-367`), and sector gates already flash on
  crossing (`_flash_gate`, `:1824-1845`).
- **Proposal:** a corner minimap drawn with `draw_polyline` from the spline (no
  texture, ~1 KB of points): rotated-to-north or fixed orientation, player dot
  with heading wedge, rival/ghost dots at reduced opacity, finish line tick and
  four sector ticks. Hide below 960×540 and offer a HUD option `MINIMAP: ON/OFF`
  (default ON for racing, and inside the HUD-scale system so it never overlaps
  the race plaque or standings). Add a thin per-lap progress bar to the race
  plaque using the same unwrapped distance.
- **Effort:** M. **Priority:** P1.
- **Risk / dependencies:** HUD layout is shared with the UI workstream and
  covered by `hud_smoke.gd` bounds checks; add the new cluster to that test at
  720p/540p and 1.5× scale (the probe above shows the current clusters pass at
  1.5×). Keep it cheap: no per-frame node churn, redraw only when a dot moves a
  pixel.
- **Acceptance sketch:** minimap fits inside the viewport at every HUD scale and
  resolution the settings offer; player dot matches the spline position within
  one lattice cell; four sector ticks light as the player crosses gates; no
  measurable frame-time change on a 1280×720 headless run.

### Q15 · Finishers have no way to watch the rest of the race

- **Player problem:** in multiplayer racing, crossing the line freezes your cart
  and covers the screen with the result card — while up to seven other karts are
  still racing. You cannot see the fights you just caused, the finish order
  settling, or your friend grabbing the last podium spot. Knockout already has
  an elegant spectator camera for eliminated players; racing has no equivalent.
- **Evidence:** on finish the local cart is frozen and collision-disabled
  (`scripts/minigames/grass_race.gd:4528-4535`) and the result card is a
  full-screen `Control` with art/dim/panel (`_result_root`, `:2358-2394`,
  shown at `:4584`). The ready-made pattern lives in
  `scripts/minigames/knockout.gd:1965-1984`: `_tick_spectator_camera` orbits the
  alive field and labels itself `ELIMINATED · SPECTATING (n ALIVE)`.
- **Proposal:** after the local finish, keep the world visible and attach a
  spectator camera that cycles remaining racers (or orbits the pack). Put the
  result card on the left or make it compact/transparent enough to see the
  action, with a `SPECTATING` tab; the "WAITING FOR n PLAYERS" banner already
  gives the reason. On the project's mobile renderer this is one camera + one
  orbit, no new render target.
- **Effort:** M. **Priority:** P1.
- **Risk / dependencies:** camera/state work in the race scene (multiplayer
  workstream owns it); layout is UI-team. Must not break the result-card
  navigation scope or pause interactions. Do not spectate in a way that leaks
  remote positions in a way the netcode doesn't already stream (it streams all
  carts).
- **Acceptance sketch:** finishing 3rd of 8 keeps the remaining karts visible
  and animating until all cross; `SPECTATING 5 RACERS` label; pause still opens
  the menu; the result card remains fully legible; no change to solo.

### Q16 · Connection transparency is thin, and the relay setting is unreachable

- **Player problem:** the HUD says `SERVER 43 MS`, the lobby says `43 ms`, but
  the game never explains whether that is the relay, the host, or the server.
  Jitter is measured and exposed as a signal and then never shown anywhere. If
  the baked relay is unreachable (ISP address changed, remote region) there is
  no supported way to point the game elsewhere: `GameSettings.relay_server`
  exists, is validated, and is saved — but no screen writes it. The old notes
  even describe a MULTIPLAYER → ADVANCED entry that no longer exists.
- **Evidence:** `scripts/net/network.gd:30` (`relay_metrics_changed(rtt_ms,
  jitter_ms)`), `:204-205` (`relay_rtt_ms`/`relay_jitter_ms`), `:2014-2020`
  (emit on change) — no UI connects to this signal (only `latency_changed` is
  connected, in `scripts/ui/lobby_menu.gd:243`). HUD label built at
  `scripts/hud.gd:1693-1719`; lobby ping text at
  `scripts/ui/lobby_menu.gd:2082-2094`. Relay setting exists at
  `scripts/systems/game_settings.gd:139,469-477` and
  `scripts/net/network.gd:2980-2988`, but a grep across `scripts/ui/**` shows no
  writer. `workspace:docs/NOTES_NETWORK_VEHICLES.md:71` documents the removed
  ADVANCED screen.
- **Proposal:** a CONNECTION strip in the multiplayer lobby (and a section in
  settings): current server address, a validated custom relay field with TEST
  (reuse `Network.probe_server()`), and a live chip `LAN DIRECT` / `RELAY 24 ms
  ± 8` / `RELAY —`, using the existing RTT/jitter signals. Rename the HUD label
  to `RELAY` or `LAN` explicitly. When jitter or the RTT EMA crosses a bad
  threshold, show `UNSTABLE CONNECTION` with a tooltip ("positions may jump") —
  never block play.
- **Effort:** M. **Priority:** P1.
- **Risk / dependencies:** prefer read-only UI over server changes; custom
  relay is a settings/session concern owned by the multiplayer workstream. No
  new protocol needed. Keep the macOS LAN-permission hint (already shipped)
  visible in the same strip.
- **Acceptance sketch:** the lobby shows the relay RTT and jitter and changes to
  `LAN DIRECT` for a LAN room; entering a valid relay address and pressing TEST
  reports reachable/unreachable and is used by the next hosted room; a stale
  public IP produces a readable error with the custom field available;
  `net_mac_smoke.gd` still passes.

### Q17 · Pause can't restart a race or leave a match politely

- **Player problem:** the pause menu offers only RESUME / SETTINGS / QUIT. In
  solo, a bad first corner means the only way to restart is to finish the race
  (or quit to the main menu and rebuild the mode flow). In multiplayer, a client
  who wants out of the match can only QUIT, which leaves the room entirely; the
  host gets a confirm because quitting closes the room, but there is no
  "return to lobby together".
- **Evidence:** the panel is exactly three buttons (`scripts/ui/pause_menu.gd:20-23`)
  and `QUIT` calls `Network.leave()` before going to the main menu
  (`:212-233`); the host warning is `QUIT_WARNING` (`:15`). The match scenes
  already have the "back to lobby" behaviour on their result cards
  (`scripts/minigames/grass_race.gd:2505-2511`,
  `scripts/minigames/cargo_rush.gd:3940-3944`,
  `Network.return_to_lobby_keep_session()` in `scripts/net/network.gd:3835`).
- **Proposal:** add context-aware pause actions: solo → `RESTART RACE` (the
  in-place restart from Q09) and `BACK TO MODES`; multiplayer host → `END MATCH
  + LOBBY`; multiplayer client → `LEAVE MATCH + STAY IN ROOM` (uses the
  existing keep-session return) and a clearly separated `LEAVE ROOM`. Keep QUIT
  as the destructive last option with its current confirmation.
- **Effort:** S. **Priority:** P1.
- **Risk / dependencies:** multiplayer teardown must use the existing lobby
  return path, not a new one; the result cards already prove it works.
  Coordinate with the multiplayer workstream (host end-match semantics) and the
  UI workstream (button layout).
- **Acceptance sketch:** solo pause → RESTART lands on the countdown in <0.5 s;
  host pause → END MATCH returns every peer to the room lobby with the session
  intact; client pause → LEAVE MATCH returns to the lobby and the host sees the
  slot reopen; no orphaned server room after any of these.

### Q18 · A host disconnect mid-match dumps clients into an empty lobby

- **Player problem:** if the host closes the game mid-match, every client is
  force-loaded into a freshly constructed lobby scene with no explanation and no
  result. The race (or party match) vanishes, the local standings are lost, and
  the new lobby may not even show why they are there. 0.8.3 deliberately taught
  the party modes to "conclude locally from current standings"; the hard
  disconnect path bypasses that.
- **Evidence:** `scripts/net/network.gd:4081-4092`: on
  `server_disconnected` it calls `leave()` and, for clients, immediately
  `SceneLoader.go_to(LOBBY_SCENE, "SESSION ENDED", "The host disconnected.")`.
  Only the lobby listens to `session_ended`
  (`scripts/ui/lobby_menu.gd:244, 1837`); the match scenes do not, so they are
  torn down before they can conclude. The 0.8.3 behaviour is described in
  `CHANGELOG.md:86-87`.
- **Proposal:** when the disconnect happens while a match scene is current, do
  not hard-swap: let the match scene freeze into its result card with the
  standings it has, shown under a modal `HOST DISCONNECTED — FINAL LOCAL
  STANDINGS` with `BACK TO LOBBY` / `MAIN MENU`. The lobby swap becomes the
  fallback only when there is no match scene to preserve.
- **Effort:** M. **Priority:** P1.
- **Risk / dependencies:** network-lifecycle ownership; the match scenes must be
  tolerant of a dead multiplayer peer when showing/finishing. Gate behind a
  `Network.is_session_active()` check that is already false after `leave()` —
  needs a small explicit "disconnected" path rather than a scene change.
  Coordinate with the multiplayer workstream; add a headless test that emits the
  disconnect while a stub match scene is current.
- **Acceptance sketch:** killing a host process mid-race leaves clients on a
  readable result screen with their final positions and two exits; no fresh
  lobby appears first; solo and normal lobby exits are unchanged.

---

## P2 — additions worth scheduling

### Q19 · The Garage explains tuning with bars but not numbers

- **Player problem:** the racing tune screen shows four bars, a `TUNE POINTS:
  12` badge and +/− buttons, but never says what a point does. A player cannot
  tell that top speed is +0.45 m/s per point, that weight is ballast in kg, or
  whether their build is faster than stock. There is also no reset-to-balanced,
  so an experiment must be undone by hand.
- **Evidence:** `scripts/ui/vehicle_select.gd:24-37` (stat labels only),
  `:1108-1120` (points badge, bars, +/− enable rules); allocation limits in
  `scripts/vehicles/vehicle_catalog.gd:21-50` (12 points, 6 max per stat,
  per-point effect constants `RACING_SPEED_PER_POINT` etc.); no reset control
  exists in the file.
- **Proposal:** a compact per-stat readout (`SPEED 27.0 m/s · +1 PT = +0.45`),
  a `STOCK ↔ BUILD` comparison arrow or delta chip, a one-line explainer for
  weight ("heavier: slower launch, harder shoves"), and `RESET TUNE` to the
  balanced 3/3/3/3 default. Optionally a `TEST IN SANDBOX` shortcut so a build
  can be felt immediately.
- **Effort:** M. **Priority:** P2.
- **Risk / dependencies:** UI-team screen; values come straight from the
  catalog constants, so no duplicated tuning numbers. Keep the bars — this adds
  a readout, not a redesign.
- **Acceptance sketch:** every stat shows the composed value and the per-point
  effect; RESET TUNE restores 3/3/3/3 and the composed numbers match the stock
  catalog entry within rounding; the screen still fits 960×540.

### Q20 · Match length is fixed and one saved setting is dead

- **Player problem:** every race is exactly 3 laps, every Deliver/Blast Tag
  match exactly 120 s, every Knockout match exactly 3 rounds. There is no way
  to play a 1-lap quick race or a 5-lap endurance run. Meanwhile
  `minigame_rounds` is saved to disk and settable through the vehicle picker,
  but no mode reads it — a configuration that does nothing.
- **Evidence:** `scripts/minigames/grass_race.gd:87-88` (`TOTAL_LAPS = 3`) with
  an environment override only for tests (`:368-370`); Deliver
  `scripts/minigames/cargo_rush.gd:65` (`MATCH_SECONDS = 120.0`) and
  `:68` (`BASE_TARGET = 8`); Blast Tag `scripts/minigames/bomb_tag.gd:58`;
  Knockout `scripts/minigames/knockout.gd:48` and env-only override `:488-494`.
  `minigame_rounds` is declared/saved in `scripts/systems/game_settings.gd:97,
  443-445, 924, 1055`; the only other writer is
  `scripts/ui/vehicle_select.gd:1147-1148`, and grep finds no reader.
- **Proposal:** a small SOLO OPTIONS block on the mode selector (or on the map
  card): `LAPS 1/2/3/5` for racing, `MATCH 60/120/180 s` + `TARGET 6/8/10` for
  Deliver/Blast Tag, `ROUNDS 1/3/5` for Knockout. Persist in settings per mode.
  For multiplayer, the host already owns the session config, so expose the same
  values in the room lobby and send them through the existing config RPC (or
  defer multiplayer to a follow-up). Either wire the dead `minigame_rounds` or
  remove it.
- **Effort:** M. **Priority:** P2.
- **Risk / dependencies:** multiplayer variants need a protocol/config field
  (multiplayer workstream); start solo-only to keep it one file plus settings.
  Result/standings code already reads `_total_laps`, so no scoring change.
- **Acceptance sketch:** a 2-lap solo race starts with `LAP 1/2` and finishes
  after 2 valid laps; a 60 s Deliver match ends at the horn; the chosen values
  persist; multiplayer keeps 3 laps until the host-option path ships.

### Q21 · The update flow nags on every launch and can't be snoozed

- **Player problem:** when an update exists, the dialog auto-opens on every
  launch and the only alternative to updating is LATER, which is not
  remembered. There is no "skip this version", no automatic update-check switch
  in the UI (the code has an export for it that nothing edits), and no in-game
  "what's new" for the version being offered — the changelog viewer exists but
  is not linked to the update.
- **Evidence:** `scripts/ui/main_menu.gd:869-877` auto-opens the panel once per
  run (`_update_auto_opened` is per menu instance) whenever an update is found;
  `scripts/ui/update_panel.gd:99-106` offers only DOWNLOAD UPDATE / LATER.
  `enable_update_checks` is a code export (`scripts/systems/update_checker.gd:29`,
  used at `:222`) with no settings control (`scripts/ui/settings_menu.gd:414-427`
  has one CHECK button). The changelog panel already parses releases
  (`scripts/ui/changelog_panel.gd:77-87, 223-273`).
- **Proposal:** add `SKIP THIS VERSION` (persisted), `WHAT'S NEW` opening the
  changelog at the offered version, an `AUTOMATIC UPDATE CHECKS` toggle in
  UPDATES, and a background auto-download option (start the download silently on
  the menu, show a small progress chip, let the player install when ready).
- **Effort:** S. **Priority:** P2.
- **Risk / dependencies:** settings schema plus updater call sites; no protocol
  change. Keep web behaviour as Q05 describes.
- **Acceptance sketch:** skipping v0.8.7 stops the dialog for that version only;
  the toggle disables the automatic menu check but keeps the manual button;
  WHAT'S NEW shows the v0.8.7 section live from the bundled changelog.

### Q22 · No quick mute and no separate engine mix

- **Player problem:** engines are a large, constant part of the soundscape and
  the only control is the global SFX slider; there is no one-key mute for a
  moment (stream, call, sleeping child) and no way to keep UI/impact feedback
  while taming the engine drone. The pause menu has no audio shortcut, so a loud
  moment forces pause → settings → slider → back.
- **Evidence:** audio settings are master/music/SFX only
  (`scripts/ui/settings_menu.gd:356-365`, `scripts/systems/game_settings.gd:61-63`);
  the pause menu is RESUME/SETTINGS/QUIT only (`scripts/ui/pause_menu.gd:20-23`);
  no mute action is bound anywhere (searched `mute`), and engine audio is on the
  SFX bus (`scripts/feedback/cart_feedback.gd` engine players, SFX bus).
- **Proposal:** `M` toggles mute (with a brief HUD badge and remembered state),
  a `MUTE WHEN UNFOCUSED` option (pairs with Q04), and either an `ENGINE`
  sub-slider by routing engine loops to their own bus or a simpler
  `ENGINE VOLUME 0–100` applied to the feedback rigs. Add a small volume row to
  the pause panel.
- **Effort:** S. **Priority:** P2.
- **Risk / dependencies:** new audio bus changes mix levels — tune by ear, not
  by guess. The audio mix is shared with the feedback rigs; coordinate with the
  workstream owning `scripts/feedback/**`.
- **Acceptance sketch:** M toggles mute in any screen and survives a restart;
  the engine slider changes engine loudness without changing impacts/menu
  clicks; unfocused mute works only when enabled.

### Q23 · Settings are only reachable from the main menu and pause

- **Player problem:** a player who wants to change volume, HUD scale or quality
  while in the lobby, mode selector, garage or room browser has to back all the
  way out to the main menu. In a live lobby that can mean leaving the room.
- **Evidence:** `SettingsMenu` is instantiated only in `scenes/ui/main_menu.tscn`
  and `scenes/ui/pause_menu.tscn` (grep across `scenes/`); the lobby
  (`scripts/ui/lobby_menu.gd`), mode selector (`scripts/ui/minigames_menu.gd`)
  and garage (`scripts/ui/vehicle_select.gd`) have no settings entry.
- **Proposal:** promote the settings overlay to a global overlay (or add it to
  the lobby/garage/mode-select scenes) opened by a gear/`F10` shortcut and a
  visible button. At minimum expose AUDIO + HUD SCALE there; UPDATES can stay
  main-menu-only.
- **Effort:** M. **Priority:** P2.
- **Risk / dependencies:** UI-team owns the overlay placement; ensure ESC
  stacking still closes only the top panel and `MenuNav` scopes stay correct
  (the pause menu already nests settings, so the pattern exists).
- **Acceptance sketch:** volume can be changed from the room lobby and garage
  and ESC backs out one layer; no focus escapes behind the overlay in any
  screen; wireframe/mouse navigation unchanged.

### Q24 · The room browser rarely refreshes and hides rooms silently

- **Player problem:** the browser scans once on open and then only when REFRESH
  is pressed; rooms fill and start while the list is stale. It also silently
  drops every room on a different build version and every full room, so two
  friends on adjacent patch versions can both see "NO ACTIVE ROOMS FOUND" with
  no clue why.
- **Evidence:** refresh only from the button (`scripts/ui/room_browser.gd:49,
  164-205`); `_prefilter` (`:266-274`) rejects any room whose `version` string
  differs from `ProjectSettings application/config/version` and any room at
  `MAX_PLAYERS`, with no counter or note; the empty state only says no rooms
  (`:357-381`).
- **Proposal:** auto-refresh while the browser is open (5–8 s, pause while the
  player is scrolling or typing a search), and when rooms were filtered out say
  `3 ROOMS HIDDEN — UPDATE TO vX TO JOIN` (using the version tag of the most
  common hidden room) plus `2 FULL` chips. Keep manual REFRESH.
- **Effort:** S. **Priority:** P2.
- **Risk / dependencies:** none to network protocol; purely presentation. Avoid
  list jumpiness: keep the scroll position and focus on refresh.
- **Acceptance sketch:** a room created after the browser opens appears within
  one refresh interval without input; scaffolding with a mismatched version
  shows a specific explanation instead of "0 rooms"; full rooms are named.

### Q25 · Duplicate default names make lobbies and standings ambiguous

- **Player problem:** the default player name is PLAYER, names are not checked
  for uniqueness, and nothing prompts for a name before joining. A room of
  friends can show three PLAYER rows, and the standings then have three PLAYER
  karts; only the tag colour distinguishes them.
- **Evidence:** default `player_name = "PLAYER"` (`scripts/systems/game_settings.gd:95`);
  `sanitize_name` validates characters/length but not duplicates
  (`:702-733`); the lobby player row shows the raw name plus the local/host
  prefixes (`scripts/ui/lobby_menu.gd:2055-2068`); HUD standings show the raw
  name plus `· YOU` for the local row (`scripts/hud.gd:1089-1091`).
- **Proposal:** prompt for a driver name on first multiplayer entry (reuse the
  briefing from Q06), and de-duplicate at display time: if a name collides, show
  a short suffix derived from the tag colour (`PLAYER · CYAN`, then `PLAYER ·
  CYAN 2`), plus the tag-colour dot that already exists. Do not rewrite the
  stored name.
- **Effort:** S. **Priority:** P2.
- **Risk / dependencies:** names are keyed by peer id in `network.gd`, so display
  suffixing is local and safe; keep the `[HOST]` sanitisation intact.
- **Acceptance sketch:** two players with the name PLAYER see `PLAYER · CYAN`
  and `PLAYER · PINK` in the lobby and standings; nobody's stored name changes;
  the host badge stays correct.

### Q26 · Party modes never state their objective before the whistle

- **Player problem:** Knockout, Deliver and Blast Tag teach their rules only
  through toasts during play ("BRAWL! …", "HOLD E ON A PRESENT", "BLAST TAG! …")
  or a one-line dock strip. A first-time player in an online match can spend the
  first round not knowing that Knockback % matters, that crates must be held
  for 0.45 s, or that ramming passes the bomb.
- **Evidence:** the only pre-play guidance is a toast at `GO`
  (`scripts/minigames/knockout.gd:1105`,
  `scripts/minigames/cargo_rush.gd:2367`,
  `scripts/minigames/bomb_tag.gd:1058`) and the fixed dock strip; there is no
  rules card or per-mode help. Mode descriptors exist in the registry
  (`scripts/minigames/track_defs.gd:358, 389, 420` taglines/hints) but are not
  used in-match.
- **Proposal:** during the 3-second countdown show a compact `HOW TO PLAY` strip
  under the countdown: one sentence + the key action for that mode (e.g.
  `JUKE SURGE = E · PASS THE BOMB BY RAMMING`), then fade. Add a `?` help button
  on the pause panel that re-opens the current mode's rules card (content
  authored next to the mode constants). Respect reduce motion.
- **Effort:** S. **Priority:** P2.
- **Risk / dependencies:** UI-team for the strip/card; content should be
  authored from the same constants the modes already use (fuse time, hold time,
  knockback range) so it cannot go stale.
- **Acceptance sketch:** every party mode shows a correct one-line objective
  during its countdown, with the live-bound action key/glyph; `?` in pause shows
  the full rules; a first-run player can complete one round without a toast
  being the first explanation.

### Q27 · No controller rumble

- **Player problem:** the game has a strong impact/landing/drift feedback model
  in the camera and audio, but a controller never vibrates. On a pad — the
  preferred way to play a kart racer — collisions, landings, boost start and
  mini-turbo tiers all feel flatter than they should.
- **Evidence:** no `Input.start_joy_vibration()` call exists in `scripts/`; the
  impact/landing cue chain is `scripts/feedback/cart_feedback.gd`
  (shake/audio/particles) and `scripts/chase_camera.gd:170-181` (`add_shake`,
  `punch_fov`) with no haptic branch.
- **Proposal:** a small haptic profile driven from the same events: short low
  rumble on impacts (scaled by impact energy), a click on landing, a rising
  pattern for drift tiers (`SPARK`/`BLAZE`/`ULTRA`), a pulse on boost start.
  Add `RUMBLE STRENGTH: OFF/LOW/HIGH` under ACCESSIBILITY (default LOW when a
  gamepad is the active device). Respect reduce motion as an additional damper.
- **Effort:** S. **Priority:** P2.
- **Risk / dependencies:** battery/comfort — keep defaults restrained and make
  OFF the choice for keyboard/mouse-only players. Needs manual hardware testing
  (headless cannot verify rumble).
- **Acceptance sketch:** on a connected pad, a wall hit buzzes briefly, drift
  tier-ups feel different, and OFF silences everything; no rumble when no pad is
  active; setting persists.

### Q28 · No camera preference and no look-back

- **Player problem:** the chase camera is fixed: 70° base FOV, 6.5 m boom,
  102° ceiling. Players who prefer a closer/farther view or a higher angle
  cannot adjust it, and there is no look-back to check on a rival before
  defending a corner in a multiplayer race.
- **Evidence:** camera constants `scripts/chase_camera.gd:12-21` (`base_fov`,
  `max_fov`, `camera_distance`, `camera_height`); the settings screen exposes
  only camera shake and HUD scale (`scripts/ui/settings_menu.gd:368-385`), and
  no look-back action exists in `project.godot`/`scripts/systems/input_setup.gd`.
- **Proposal:** `CAMERA: CLOSE / MID / FAR` (scales `camera_distance`,
  `camera_height` and slightly `base_fov`) as a gameplay/video option, and a
  hold-to-look-back binding (`B`/pad RB?) with a clear slot in the controls page
  from Q07. Keep the existing speed/boost FOV deltas relative to the chosen
  base.
- **Effort:** M. **Priority:** P2.
- **Risk / dependencies:** camera feel is WS-adjacent; do not change default
  handling. Look-back needs a graceful camera state that cannot fight the
  drift-peek offsets. Add a headless assertion that each preset yields a
  different, clamped FOV/boom.
- **Acceptance sketch:** each preset is visibly distinct and stays within
  safe bounds; look-back holds a rear view and snaps back; defaults unchanged;
  `driving_smoke` still passes.

### Q29 · Bot skill is buried and the solo AI pill is cryptic

- **Player problem:** the mode selector has a bare `AI 0 1 2 3 4 5` pill; the
  skill level lives in Settings → GAMEPLAY as an EASY/NORMAL/HARD button, far
  from where a race is started. A new player cannot tell that the pill adds
  opponents, what difficulty they will be, or that 0 AI is effectively a time
  trial.
- **Evidence:** pill labels/values `scripts/ui/minigames_menu.gd:48-49`,
  built at `:496-512`; skill control in `scripts/ui/settings_menu.gd:399-402`;
  the room lobby has a proper labeled BOT SKILL control
  (`scripts/ui/lobby_menu.gd:898-923`) that the solo screen does not mirror.
- **Proposal:** label the solo pill `AI OPPONENTS` with names (`OFF`, `1–5`),
  show the current skill next to it (`NORMAL`) and a one-line explainer per
  level (`EASY: forgiving pace`, `NORMAL: races you`, `HARD: defends and
  boosts`). Show `NO AI · TIME ATTACK` when 0. Remember the choice.
- **Effort:** S. **Priority:** P2.
- **Risk / dependencies:** UI-team screen; no gameplay change. Ties into Q32
  (medals) and Q33 (ghost) if those land.
- **Acceptance sketch:** the mode selector explains AI count and skill without
  opening settings; changing them there updates the same persisted values as the
  settings screen; 0 AI is labelled as time attack.

### Q30 · Window size, borderless and geometry are not configurable

- **Player problem:** windowed play is fixed to a 1280×720 window (the base
  viewport) with no size choice, no borderless option and no remembered window
  position/size. On a 1440p/4K desktop the default window is small; on a
  multi-monitor desk it forgets where it was. Alt+Enter is not bound.
- **Evidence:** `project.godot:37-42` pins `window_width_override`/
  `window_height_override` to 1280×720; the only persisted display setting is
  `fullscreen` (`scripts/systems/game_settings.gd:64`, applied at `:291-294`
  with a plain windowed/fullscreen switch).
- **Proposal:** add `WINDOW MODE: WINDOWED / BORDERLESS / FULLSCREEN` and a
  small resolution cycle (1280×720 / 1600×900 / 1920×1080 / native), persisting
  size and position (clamped to the monitor) and binding Alt+Enter to cycle
  fullscreen. Keep the 1280×720-base `canvas_items` stretch so UI scales
  correctly.
- **Effort:** M. **Priority:** P2.
- **Risk / dependencies:** DisplayServer differences across Windows/macOS/Linux;
  test macOS fullscreen spaces and Linux Wayland separately. Do not touch the
  export presets.
- **Acceptance sketch:** each mode applies immediately and persists; a window
  dragged to a second monitor reopens there; Alt+Enter toggles; 720p/1080p UI
  layout unaffected.

### Q31 · No next-track chaining from the result card

- **Player problem:** after a solo race the result card offers RACE AGAIN, BACK
  TO MODES and MAIN MENU. To run the next circuit the player must leave the
  card, navigate the mode selector, pick a map and start again — three screens
  between attempts. Party modes have the same gap.
- **Evidence:** solo result buttons `scripts/minigames/grass_race.gd:2516-2531`;
  party equivalents `scripts/minigames/knockout.gd:2440-2450` and
  `scripts/minigames/bomb_tag.gd:3150-3173` (mostly PLAY AGAIN / BACK / MAIN).
- **Proposal:** add `NEXT TRACK`/`NEXT MAP` (wraps the registry order for the
  current mode) next to RACE AGAIN, using Q09's in-place rebuild only when the
  map is unchanged and a normal scene load when it changes. In multiplayer the
  host gets `NEXT TRACK` as a room-level action and the server/config path is
  reused.
- **Effort:** S. **Priority:** P2.
- **Risk / dependencies:** depends on Q09 for the fast path; otherwise it is
  just a SceneLoader call with the next map id. Needs the registry order to be
  stable (it is: `TrackDefs.PRESETS`).
- **Acceptance sketch:** NEXT TRACK from a solo result loads the next map's
  loading screen and countdown; wrapping from the last map returns to the
  first; multiplayer variant uses the existing host start path.

### Q32 · Solo has no medals or goal times

- **Player problem:** a solo race gives you a position and lap times and then
  forgets everything. There is no Bronze/Silver/Gold goal to chase, so after the
  first win the only reason to return is self-improvement — which the game also
  does not track (Q08). Medals are the cheapest durable goal a track racer can
  have.
- **Evidence:** solo result card shows time/best/position/laps only
  (`scripts/minigames/grass_race.gd:2443-2465`); AI pace is deterministic and
  difficulty-scaled through `scripts/minigames/race_ai.gd` (`_speed_cap` and the
  speed profile at `:259-260, 594-624`), and `GameSettings.minigame_difficulty`
  is the existing skill switch, so par targets can be derived from a reference
  AI build instead of hand-tuned. Map records (Q08) already need the persistent
  store.
- **Proposal:** three target times per map (and per lap-count choice from Q20),
  stored in `TrackDefs` next to the map preset as `medal_ms: {bronze, silver,
  gold}`, generated once by a headless tool using the reference AI profile.
  Show earned medals on the map card and stamp the result card; a `NEW SILVER
  MEDAL` callout on improvement. No unlocks gated behind them in v1 — bragging
  rights only.
- **Effort:** M. **Priority:** P2.
- **Risk / dependencies:** target tuning is a balance task, not just code; make
  the generator reproducible and committed so maps cannot ship without medals.
  UI-team places the medal marks. Do not tie multiplayer results to medals.
- **Acceptance sketch:** every race map has three targets; a clean gold run
  stamps the result and map card; a slower run still shows the best earned
  medal; a headless test asserts every map has valid ordered targets and that a
  reference lap beats bronze.

---

## P3 — big bets

### Q33 · Ghost lap for time trial (concrete design)

- **Player problem:** open item in `workspace:docs/Future To Do's.md:87`.
  Solo time attack against your own best is the standard retention loop for an
  arcade racer, and the 0-bot race already exists — it just has no opponent and
  no record.
- **Evidence:** 0 AI is already selectable (`scripts/ui/minigames_menu.gd:48-49`);
  lap data is captured per race (`scripts/minigames/grass_race.gd:4481-4517`)
  but discarded; the effect/vehicle visuals are available for a translucent
  ghost (`VehicleVisual.build`, `scripts/vehicles/vehicle_visual.gd`), and the
  remote-cart ghost path already streams a transform and yaw per tick
  (`_accept_remote_race_state`, `grass_race.gd:3452-3488`).
- **Proposal (concrete design):** record the *local best clean lap* for a
  map+vehicle at 20 Hz as
  position (3×16-bit fixed point, relative to track start) + yaw (16-bit) + a
  moving flag; a 60 s lap is ~240 samples × 8 bytes ≈ 2 KB, so 5 circuits × 7
  vehicles ≈ 70 KB in `user://records/ghosts/<map>_<vehicle>.bin`. Playback:
  translucent lower-opacity cart, no collision, no AI, offset by the player's
  current lap start; HUD ghost delta (`+0.42` / `−0.31` vs ghost at the same
  track position). Only solo/time attack (0 AI) records. `GHOST: OFF / PB /
  LAST` in race options and in the map card. If the player beats the ghost, the
  result card offers SAVE NEW GHOST. Corrupt/old ghost files are discarded
  silently.
- **Effort:** L. **Priority:** P3 (but the highest-value solo bet; split Q08
  first).
- **Risk / dependencies:** audio/visual readability (ghost must not obscure the
  road — use a low-alpha silhouette and no volumetric effects); recording needs
  a clean-lap check (the existing teleport/rejection logic is a good gate); no
  multiplayer implications in v1. Coordinate with the workstream owning
  `grass_race.gd`.
- **Acceptance sketch:** a clean lap records and replays; the ghost follows the
  same racing line through ramps and chasm jumps; a faster run offers to replace
  it; a corrupt file disables the ghost without an error; the ghost toggle is
  visible on the map card before starting.

### Q34 · Two-player split-screen (concrete design)

- **Player problem:** open item in `workspace:docs/Future To Do's.md:88`.
  Couch co-op is the natural format for a party kart racer and the game only
  supports one local player today.
- **Evidence:** every mode assumes one local cart (e.g. `grass_race.gd:374-380`
  caches one `_cart` from the `player` group; HUD is a single instance per
  scene). The chase camera rig already parameterises distance/FOV, and input is
  action-based, so a second local player is mostly a routing problem.
- **Proposal (phased design):** Phase 1 — Sandbox split-screen only: one scene
  root with two `SubViewport`s (or two camera rigs in one viewport with a split
  shader;
  prefer SubViewports for clean HUD duplication), P1 keyboard (WASD + Space/
  Shift) and P2 controller, each with its own HUD instance scaled to 0.85.
  Phase 2 — Racing with 2 laps and 0–3 AI. Phase 3 — party modes only if the
  camera can follow per-player carts cleanly. Rendering: two 640×720 viewports
  at 0.72 internal scale on desktop; target 60 fps at Performance preset;
  no split-screen on web. Input: `Input.is_action_pressed` calls in
  `player_cart.gd` must be routed through a per-cart device/action prefix
  (`p1_*`, `p2_*`) — this is the large refactor and should be scoped honestly.
- **Effort:** L. **Priority:** P3.
- **Risk / dependencies:** high: double render cost, input routing rewrite,
  HUD duplication, camera occlusion in tight corners, and the multiplayer
  netcode must ignore the second local cart. Do not promise it for v0.8.7; a
  Sandbox-only vertical slice is the safe proof.
- **Acceptance sketch:** two local players can drive in the Sandbox at 60 fps on
  the Performance preset at 1280×720; each HUD is readable; pause pauses both;
  no crash on scene exit; a single-player build path is unchanged when the
  setting is off.

### Q35 · Daily challenge with a local leaderboard (retention bet)

- **Player problem:** there is no reason to launch the game on a given day. The
  game has five circuits, nine arenas and a deterministic AI/handling model, but
  no rotating objective, streak or local ranking to pull players back.
- **Evidence:** map/vehicle selection is free-form
  (`scripts/ui/minigames_menu.gd`, `scripts/ui/vehicle_select.gd`); no
  daily/seed/streak concept exists anywhere (searched); deterministic seeds
  already exist for races (`race_seed`, `scripts/net/network.gd:363`) and bots
  are deterministic per build (`scripts/minigames/race_ai.gd:245-260`).
- **Proposal (concrete design):** an offline daily card on the main menu:
  `DAILY #2026-11-26` —
  one map + fixed vehicle + fixed tune + one modifier (e.g. no boost pads,
  reverse grid vs Hard bots, ice-only sectors where the map supports it),
  derived from `hash(date)` so every player sees the same challenge without a
  server. Store best time per day (local), show a 7-day streak and a local
  all-time board of the last 20 attempts. Phase 2 can post results to the Pi for
  a global board (server work, separate workstream). No rewards gated behind it;
  a badge and a saved ghost of the best run is enough.
- **Effort:** L. **Priority:** P3.
- **Risk / dependencies:** needs the persistent store (Q08) and ideally the
  ghost (Q33); a modifier system is the main unknown because modes are not
  currently data-driven. Keep it solo/offline first; do not add server load
  until the Pi latency work is done.
- **Acceptance sketch:** the daily card is identical after relaunch on the same
  date and different on the next; attempts persist; the local board sorts
  correctly; no network call in the offline version.

---

## Quick wins under one day

These are small, low-risk, and each removes a papercut immediately.

| ID | Win | Files |
| --- | --- | --- |
| Q01 | Bind scoreboard to gamepad Back/Select and read it through `InputMap` | `scripts/systems/input_setup.gd`, `scripts/hud.gd` |
| Q02 | Device-aware prompts/glyphs in the ability dock and Deliver prompt | `scripts/ui/ability_dock.gd`, the three mode HUDs |
| Q03 | `WAITING FOR PLAYERS n/m` (plus names) instead of a bare WAITING | `scripts/minigames/grass_race.gd` |
| Q04 | Pause-on-focus-loss for solo with a setting | `scripts/ui/pause_menu.gd`, `scripts/systems/game_settings.gd`, race scenes |
| Q05 | Web guards on MULTIPLAYER/QUIT/UPDATE | `scripts/ui/main_menu.gd`, web branches only |
| Q12 | Hold hazard colours steady when reduce motion is on | `scripts/minigames/knockout.gd`, `scripts/minigames/bomb_tag.gd`, shared helper |
| Q24 | Room browser auto-refresh + "N rooms hidden (version)" note | `scripts/ui/room_browser.gd` |
| Q25 | De-duplicate duplicate player names at display time | `scripts/ui/lobby_menu.gd`, `scripts/hud.gd` |
| Q29 | Explain the solo AI pill and show the current skill beside it | `scripts/ui/minigames_menu.gd` |
| Q31 | NEXT TRACK from the solo result card (registry wrap) | the four result builders (`scripts/minigames/*.gd`) |
| Q22 | `M` mute + mute-when-unfocused | `scripts/ui/pause_menu.gd`, `scripts/systems/game_settings.gd` |
| Q26 | Per-mode one-line objective during the countdown | `scripts/minigames/knockout.gd`, `cargo_rush.gd`, `bomb_tag.gd` |

## Big bets

- **Q33 Ghost lap / time trial** — the highest-value solo retention loop; needs
  the record store first. *Design included above.*
- **Q34 Two-player split-screen** — high cost, high couch-play value; start with
  a Sandbox vertical slice. *Design included above.*
- **Q35 Daily challenge + local board** — cheap content generation from existing
  deterministic data, needs the record store; server board later.
- **Progression/cosmetics beyond paint** — paint is already free; if a meta
  layer is wanted, tie it to medals/records rather than a new currency. Not
  designed here because it needs an owner decision on monetisation-free scope.

## Suggested order for v0.8.7

1. **P0 sweep** (Q01–Q05): one sprint, no new systems, fixes misleading
   controls and two platform dead ends.
2. **Retention trio** (Q08 records → Q09 fast restart → Q31 next track), then
   **Q06 onboarding** and **Q07 remapping** on top of the record store.
3. **Multiplayer clarity batch** (Q03 counts, Q10 remote laps, Q11 ready
   gating, Q16 connection strip, Q18 host-disconnect card, Q17 leave-match) —
   land as one coordinated change with the multiplayer workstream and a
   two-process LAN test each time.
4. **Feel and accessibility** (Q12–Q15, Q27, Q28) once the UI workstream's
   end-screen pass is in, so camera/spectator entries do not collide with the
   new result layouts.
5. **P2 content** (Q19–Q32) in any order; they are independent.

## Caveats

- No windowed playtest or live multiplayer session was run for this review, so
  **perceived** timing claims (for example the ~3.7 s race load) come from code
  comments/measurements already in the tree, not from a fresh stopwatch.
- The 0.8.6 Glacier rebuild changes race-scene cost; any fast-restart or
  minimap work should be re-measured on the final v0.8.7 map before promising a
  number.
- Multiplayer items describe the **desired player-visible contract**; the
  protocol/ordering/failsafe details belong to the networking workstream and
  must keep old peers safe.
- Nothing here overrides the UI workstream's layout and theme ownership; where
  an item needs a visual home, that is called out in the item.
- This tree is being changed by the other v0.8.7 workstreams while this review
  is read: several items overlap their scopes (Q10/Q11/Q16/Q18 with networking,
  Q02/Q06/Q13/Q14/Q15 with UI, Q09 with the mode-scene owners, Q12/Q27 with the
  stability/audio pass). The review is written against the v0.8.6 baseline;
  reconcile it with their reports before scheduling, because some items may
  already be in progress or fixed.
