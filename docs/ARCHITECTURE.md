# Architecture

Godot 4.7.2, mobile renderer, 1280x720 base viewport. Entry scene is
`scenes/ui/main_menu.tscn`.

## Autoloads

Registered in `godot_project/project.godot` under `[autoload]`, in load order:

| Name | Script / scene | Responsibility |
| --- | --- | --- |
| `GameSettings` | `scripts/systems/game_settings.gd` | persisted settings, quality tiers |
| `InputSetup` | `scripts/systems/input_setup.gd` | the input map |
| `Music` | `scripts/systems/music_player.gd` | music bus and track changes |
| `UpdateChecker` | `scripts/systems/update_checker.gd` | reads `version.txt`, compares against releases |
| `CursorController` | `scenes/ui/cursor_controller.tscn` | pointer, capture and menu cursor |
| `UiKit` | `scripts/ui/ui_kit.gd` | shared styleboxes, spacing, button chrome |
| `MenuNav` | `scripts/ui/menu_nav.gd` | keyboard/gamepad focus routing between menus |
| `Network` | `scripts/net/network.gd` | rooms, packets, LAN discovery, relay |
| `SceneLoader` | `scenes/ui/scene_loader.tscn` | every scene change, with fades |
| `WebQuality` | `scripts/systems/web_quality.gd` | caps quality when running in a browser |

Anything that survives a scene change belongs in an autoload; anything that
dies with a race belongs in the race scene.

## Screen flow

```
main_menu ─┬→ SINGLEPLAYER → play_menu → minigames_menu (SELECT MODE) ─→ vehicle_select ─┬→ grass_race
           │                                                                               ├→ cargo_rush
           │                                                                               ├→ knockout
           │                                                                               ├→ bomb_tag
           │                                                                               └→ sandbox
           ├→ MULTIPLAYER ─→ lobby_menu ─┬→ CREATE ONLINE / LAN ROOM ─→ room lobby ─→ match scene
           │                             └→ JOIN ROOM (code or room_browser)
           ├→ MAPMAKER (locked teaser: "COMING SOON :D" dialog, no scene change yet)
           └→ GARAGE → vehicle_select
```

`main_menu` is a four-tile hero rail — **SINGLEPLAYER → MULTIPLAYER →
MAPMAKER → GARAGE** — with the MAPMAKER tile styled as a greyed padlocked
teaser that only opens `scenes/ui/mapmaker_teaser.tscn` (plus a one-shot
confetti burst). `play_menu` still offers SOLO / MULTIPLAYER; SOLO opens
`minigames_menu` (`SELECT MODE`), showing all 5 modes (`RACING`, `DELIVER`,
`KNOCKOUT`, `BLAST TAG`, `SANDBOX`) front-and-center with `1600x900` map
screenshots. `SceneLoader` performs every transition — never call
`change_scene_to_file` directly, or the fade and the loading overlay are
skipped.

## Menu backdrops are autonomous

Menu and lobby backdrops are an **independent, self-timed shuffled slideshow**:
`scripts/ui/art_backdrop.gd` owns the timer/crossfades (random 8–12 s beat,
1.15 s fade, shuffle bag with no back-to-back repeats, optional Ken Burns,
reduced-motion freezes the plate), and `scripts/ui/menu_background.gd` hands each
screen a slide pool via `set_slide_pool()`. **Hover and focus must never choose,
freeze or retune the backdrop** — buttons keep their own local hover animation
only. (The old `menu_hover_backdrop.gd` hover driver was deleted in 0.8.7
Phase 3; do not reintroduce one.) Test hooks on ArtBackdrop:
`set_slides`/`slide_names`/`current_slide_name`/`advance_count`/`reset_schedule`.

## Script map

| Folder | Files | Contents |
| --- | --- | --- |
| `scripts/minigames/` | 67 | race scenes, track registry, AI, themes, tile engine |
| `scripts/ui/` | 39 | every menu, HUD, panels, UI kit, shared result-screen builder, autonomous backdrop slideshow, Mapmaker teaser, lobby emote overlay + slanted map preview, lobby reactions, headless layout/UI audits |
| `scripts/systems/` | 10 | settings (atomic save), collisions, backdrop, visual grade, web quality tiers |
| `scripts/tools/` | 18 | headless tests, the preview renderer, net/physics/FX/bot-slot diagnostics |
| `scripts/vehicles/` | 2 | per-vehicle data |
| `scripts/net/` | 3 | networking, relay tunnel, authoritative standings reconciler |
| `scripts/effects/` | 4 | layered GPU ambient systems, FX quality tiers, FX/audio budget probes |
| `scripts/feedback/` | 2 | `cart_feedback.gd` + batched per-car `skid_trail.gd` |
| `scripts/track/` | 1 | shared track pieces |
| `scripts/ai/` | 1 | shared AI helpers |

Top-level `scripts/`: `player_cart.gd`, `hud.gd`, `chase_camera.gd`,
`sandbox.gd`, `sandbox_park.gd`.

## Multiplayer transport

Two join paths exist and both end in the same ENet session API:

- **LAN room** — the host PC is the ENet server; a UDP beacon (42779) lets
  peers on the same network discover it and connect directly.
- **Online room (5-letter code)** — the host registers with the Pi, opens a
  TCP tunnel to it, and clients reach the Pi's UDP relay. When two peers are on
  the same local network and the server (1.9.0+) confirms it, the client first
  tries a **direct ENet connection to the host** and silently falls back to the
  relay if the host firewall blocks it.

Racing results are host-authoritative: `scripts/net/standings_reconciler.gd`
builds a deterministic, revisioned snapshot that every client accepts
monotonically (see its docstring for the row/snapshot contract). Do not
recompute final standings locally in a mode script. Finish times are reported by
each client on a reliable channel and RTT-compensated by the host; the host
broadcasts a forced scene reload for rematches (`_net_restart_game`).

**Lobby reactions** are the one deliberate exception to "visual state is
derived locally": `scripts/ui/lobby_reactions.gd` holds the catalog and the
client-side rate limiter, `scripts/ui/lobby_emote_overlay.gd` renders the
chrome-free floating text bubbles (random safe-margin spawn, wiggle up, fade —
no background plate or colour bar), `lobby_menu.gd` owns the footer emote
buttons, and an isolated reliable block at the end of `network.gd` relays
reactions client -> host -> all peers (host-authoritative name/colour, per-peer
rate limits). The host also tracks per-client presence so START can wait for
everyone (WAITING / AWAY / START ANYWAY). Keep this block isolated from the
gameplay netcode.

## Lobby roster: bot slots and teams

The 8 lobby seats are shared between humans and bots. `network.gd` exposes
`human_count()`, `active_bot_count()`, `lobby_slots_used/free()`,
`max_lobby_humans()` (`= 8 - bots`), `bot_team()/set_bot_team()` and
`auto_arrange_teams()`; the host refuses a join that would exceed capacity
(with a clear refusal reason) and the prepared 2.0.0 server carries additive
`bots`/`players`/`max_bots`/`max_humans` capacity fields in room
register/snapshot so it can enforce the same rule. Bot teams are replicated on
a separate validated `_net_bot_teams` RPC — **keep `_net_session_config` at its
original arity** so older builds still exchange the session config (Godot RPC
arity is strict). The roster UI (`lobby_menu.gd`) draws bots as
`BOT 1..N` with a procedural robot icon and lets the host move them between
ALPHA/BETA exactly like humans.

## Web release pipeline and CDN

The web export is a first-class release target with its own pipeline:

- `pi_setup/sync_web_release.ps1` stamps/verifies `version.json` (game +
  engine version, build id, per-file sha256/sizes) inside the export and injects
  matching meta tags into `index.html`; `-Check` refuses stale or modified
  folders. The build, staging, deploy scripts and the Pi `/play` launcher all
  consume it, so a stale web client cannot ship silently.
- `scripts/systems/web_quality.gd` owns the Web Low-Spec runtime tier
  (auto-detected from hardware; `CARTSLOP_FORCE_WEB_QUALITY=1` +
  `CARTSLOP_WEB_QUALITY=low|balanced` for headless verification). Do not
  re-enable MSAA/shadows/AA on web paths.
- Static hosting lives outside the game repo: `website/` (static landing site +
  reproducible brand-asset generator) and `web_deploy/` (Cloudflare R2 + Worker
  package: staging, Brotli/Gzip precompression, immutable/no-store pointers,
  versioned `/game/<version>/<build>/` paths, upload/verify/rollback scripts and
  the README with the manual credential/DNS steps). The Pi keeps only the
  relay/HTTP API + console; `CARTSLOP_WEB_BASE` points the launcher at the CDN.

## Visual FX and audio

Ambient weather lives in `scripts/minigames/scenery/ambient_world.gd`, which
delegates to `scripts/effects/ambient_particles.gd` (7 themed palettes x 3
layers) and `scripts/effects/fx_quality.gd` (quality tier, reduced motion and
forced-Web detection). Per-cart drift marks are one batched ImmediateMesh per
cart in `scripts/feedback/skid_trail.gd`, styled per vehicle from
`scripts/vehicles/` and shaded by `scripts/effects/skid_mark.gdshader`.
`scripts/systems/music_player.gd` runs a three-deck pool with equal-power
crossfades; do not hard-stop streams on scene changes.

## Tracks are ASCII grids

A race map is a grid of characters on a 16 m lattice plus a theme. The registry
is `scripts/minigames/track_defs.gd`; the engine is
`scripts/minigames/tiles/kenney_tiles.gd`.

Legend: `S` straight, `L` left, `R` right, `C` crossing, `W` wide sweeper,
`B` bump, `J` jump ramp, `P` pit straight, `E` pit entry, `G` pit garage,
`X` empty. Every drivable cell must sit on **one closed loop** — the engine
rejects a grid that does not.

A theme is a separate file with this contract:

```gdscript
# res://scripts/minigames/maps/<id>_theme.gd
static func build(race: Node3D, spline) -> void
```

It dresses the track by calling `tile_kit.*` and returns nothing. Theme layout:
`scripts/minigames/maps/<id>/`, with the theme entry point at
`scripts/minigames/maps/<id>_theme.gd`.

Per-map folders: `circuit/` (3 scripts), `stadium/` (8), `dockyard/` (10),
`glacier/` (9), plus `tiles/` (10) for the engine itself.

## Conventions

- GDScript, tabs, statically typed locals (`var x: int = 0`), `preload` into
  `const` at the top of a file rather than loading at runtime.
- Files carry a docstring comment above `extends ...` explaining the *why*, and
  long numeric tuning values get an inline `##` note.
- Map builders are static functions that take the host node and build into it,
  so a probe, a preview and the real race scene share one code path.
- Physics runs on the fixed 60 Hz step; do not move race logic into `_process`.
- The HUD grows with the player count. Do not reintroduce a fixed five-row
  standings cap.
- UI spacing goes through `UiKit`; do not hand-pick margins per screen.

## Assets

`assets/` holds the Kenney kits, UI art, preview images and audio. Menu previews
are generated by `scripts/tools/preview_render.tscn` (windowed only) and
verified by `preview_verify.gd`.
