# Maintaining Cart Slop GP

Everything you need to ship a version without breaking the repository.

**Path convention:** this repository is the game (`godot_project/`'s contents).
Commands and paths below are written relative to the **workspace root** — the
folder one level up that also holds `builds/`, `pi_setup/`, `downloads/`, and
the web-release assets **`website/`** (static site) and **`web_deploy/`**
(Cloudflare R2/Worker release package). Those are deliberately outside version
control.

Run all commands from the workspace root.


Godot binary used everywhere below:

```
downloads/godot_editor/Godot_v4.7.2-stable_win64_console.exe
```

## 1. Bumping the version

The version lives in **six** places. Miss one and the build script refuses to
run or ships a mislabelled build.

| # | File | What to change |
| --- | --- | --- |
| 1 | `godot_project/version.txt` | the number alone, e.g. `0.8.7` |
| 2 | `godot_project/project.godot` | `config/version="0.8.7"` under `[application]` |
| 3 | `godot_project/export_presets.cfg` | four `export_path="../builds/v0.8.7/..."` lines, plus the Windows `file_version`/`product_version` and macOS `short_version`/`version` fields |
| 4 | `pi_setup/build_0_8_7.ps1` | `[string]$Version = "0.8.7"` (rename the file too, by convention) |
| 5 | `pi_setup/Deploy-Server.cmd` | the `builds\v0.8.7\web` checks |
| 6 | `godot_project/CHANGELOG.md` | a new `## [0.8.7] - YYYY-MM-DD` section at the top |

`build_0_8_7.ps1` compares `version.txt` against its own `-Version` and aborts
on a mismatch, which is the safety net for item 1 vs item 4.

Before any export the script runs a six-place version preflight: it re-reads
`version.txt`, `project.godot`, the four `export_path` lines, its own file
name plus the default `-Version`, `pi_setup/Deploy-Server.cmd` and the top
`## [x.y.z]` section of `godot_project/CHANGELOG.md`, and aborts with a
`BUILD FAILED` message naming the mismatched file when any of them disagrees
with `-Version`. The preflight never edits versions itself — bump the six
places by hand, then re-run the script.

`scripts/systems/update_checker.gd` reads `version.txt` at runtime, so the
in-game "update available" check needs no edit — just the file.

## 2. Building a release

```powershell
powershell -ExecutionPolicy Bypass -File pi_setup\build_0_8_7.ps1
```

Writes `builds/v<version>/`:

```
windows\CartSlopGP.exe              mac\CartSlopGP.zip
linux\CartSlopGP.x86_64             web\index.html + .wasm + .pck
release\CartSlopGP_v<version>_<platform>.zip
release\SHA256SUMS
logs\<platform>.log
```

The script is safe to re-run: each platform folder and zip is recreated from
scratch, and a failed export stops the run instead of leaving a stale zip next
to a fresh one. Nothing is uploaded.

**Never zip with `Compress-Archive` or `ZipFile::CreateFromDirectory`.** On
Windows both record FAT attributes, so `CartSlopGP.x86_64` extracts as `0644`
and every Linux player gets "Permission denied" — that shipped in 0.7.1. The
build routes everything through `pi_setup/zip_unix.py`, which writes Unix modes
and `create_system = 3`, and then asserts the execute bits are present in the
Linux zip. Keep it that way.

**Never turn `binary_format/embed_pck` off.** With a separate `.pck`, a Windows
player who extracts only the `.exe`, moves it elsewhere, or launches it from
inside the zip gets `Couldn't load project data ... Is the .pck file missing?`
and the game never starts — that shipped in 0.7.2. Both desktop presets embed
the pack, and the build fails if the binary is too small to contain one.

**Check before publishing:** open `release\SHA256SUMS` and spot-check that every
platform zip is dated this run, and that `logs\` has no failed platform.

**The web export is version-stamped at build time.** The build calls
`pi_setup/sync_web_release.ps1`, which writes `version.json` (game + engine
version, build id, per-file sha256/sizes) into `builds/v<version>/web/` and
injects matching meta tags into `index.html`. Any script that later stages,
uploads or serves that folder re-runs the script with `-Check` and refuses a
stale or modified export. If you hand-edit or manually re-export the web
folder, re-stamp it (`sync_web_release.ps1 -WebDir builds\v<version>\web`)
before deploying, or the deploy will fail — intentionally.

## 3. Deploying the web client and the Pi server

The browser build is **not** served by the Pi in the normal architecture: the
static `.wasm/.pck/.js` assets are staged for **Cloudflare R2 + a CDN Worker**
(Cloudflare Pages cannot host this build — 25 MiB per-asset limit vs the
~121 MB pack). The Pi keeps the relay/HTTP API, the console and the `/play`
launcher, which points at the CDN via `CARTSLOP_WEB_BASE`.

```powershell
# 1. Build (stamps version.json) and stage a versioned CDN tree.
powershell -ExecutionPolicy Bypass -File pi_setup\build_0_8_7.ps1
powershell -ExecutionPolicy Bypass -File web_deploy\scripts\stage_release.ps1

# 2. Validate locally (no network): package + version parity + mock edge.
python web_deploy\scripts\validate_package.py
powershell -ExecutionPolicy Bypass -File web_deploy\scripts\test_version_parity.ps1
powershell -ExecutionPolicy Bypass -File web_deploy\scripts\verify_deploy.ps1

# 3. Upload to R2 and prime the Worker (needs a Cloudflare API token).
powershell -ExecutionPolicy Bypass -File web_deploy\scripts\upload_r2.ps1

# 4. Deploy the Pi server + launcher (prompts for the pi sudo password).
pi_setup\Deploy-Server.cmd
```

`deploy_server.ps1` re-checks the web folder's `version.json` **before any
SSH/upload** and refuses a stale export in under a second. The `/play` launcher
shows the served web version and a red **STALE WEB BUILD** warning if the served
build disagrees with the version the Pi knows (`CARTSLOP_GAME_VERSION` or the
update manifest). `web_deploy/README.md` lists the manual Cloudflare steps
(account, API token scope, R2 bucket, Worker route/custom domain, DNS, Pi
environment, rollback). `pi_setup/` holds the SSH key and credentials — it is
gitignored and must never be published.

## 4. Tests

All headless tests exit with the number of failures, so `echo $?` (or
`%ERRORLEVEL%`) tells you pass/fail without reading the log.

| Test | Command (after `--headless --path godot_project --script`) | Covers |
| --- | --- | --- |
| Map/tile audit | `res://scripts/tools/preview_verify.gd` | every grid map, barrier clearance, seam metrics, elevation, preview PNGs |
| HUD smoke | `res://scripts/tools/hud_smoke.gd` | race plaque, standings, gauge clamping, 720p/540p layout |
| Stadium | `res://scripts/minigames/maps/stadium/stadium_smoke.gd` | build, props, forest, clearance, 120-frame boot |
| Dockyard | `res://scripts/minigames/maps/dockyard/dockyard_selftest.gd` | build, clearance, object/draw budget |
| Dockyard (probe) | `res://scripts/minigames/maps/dockyard/dockyard_smoke.gd` | smoke boot |
| Glacier | `res://scripts/minigames/maps/glacier/glacier_selftest.gd` | build, clearance, ice spans |
| Vehicle roster | `res://scripts/tools/vehicle_roster_smoke.gd` | every racing chassis composes and renders |
| Mode rules | scene `res://scripts/tools/mode_rules_smoke.tscn` | party-mode rules regressions |
| Driving physics | scene `res://scripts/tools/driving_smoke.tscn` | real-physics handling checks for every vehicle |
| Updater | `res://scripts/tools/update_smoke.gd` | 133 archive/hash/installer-staging checks |
| Networking | scene `res://scripts/tools/net_mac_smoke.tscn` | address/broadcast helpers, IPv6 host syntax, TLS/DNS error mapping, host-authoritative standings reconciliation, LAN-route/NODELAY checks |
| UI layout audit | `res://scripts/ui/ui_layout_audit.gd` | every UI screen/state plus all result-card variants at 1280x720 and 1920x1080: zero legacy-theme controls, zero viewport overflows, closed focus ring, 0 failures |
| UI motion/loading/reactions | `res://scripts/ui/ws4_ui_smoke.gd` | **75 checks** for hover-backdrop priority, gradient helpers, true-100% loading (monotonic/terminal), lobby reaction limiter/overlay, nav dedup; `WS4_LOAD_TEST=1` adds the real-load mode (86 checks) |
| Phase-2 behaviour smoke | `res://scripts/tools/phase2_bugfix_smoke.gd` | **76 checks** covering MP rematch restart, RTT-compensated finish ordering, atomic settings save, scoreboard action, web guards, focus pause, lobby ready gate, host-lost overlay; 150 s watchdog |
| Phase-2 integrate checks | `res://scripts/tools/phase2_verify_checks.gd` | **32 checks** for the 0.8.7 Phase-2 integration invariants |
| FX budget probe | `res://scripts/effects/fx_budget_probe.gd` | ambient layer/draw/particle budgets per world + menus + forced-Web profile; one scene per process via `CARTSLOP_FX_SCOPE` |
| Audio fade probe | `res://scripts/effects/audio_fade_probe.gd` | deck pool/crossfade/retire envelope/pause duck checks |
| Physics probe | `res://scripts/tools/_p2_physics_probe.tscn` | `P2_MODE=ramp|chasm|stadium|ground|flex|maps` — ramp collider vs visible crest, chasm clears per mass, seating facing, vehicle grounding, local+remote flex, map collider audit |
| Main menu / Mapmaker / caret / backdrop | `res://scripts/ui/ws2_ui_checks.gd` | **116 checks**: rail order/labels, locked Mapmaker + `COMING SOON :D` popup + single confetti burst, caret blink/contrast on every LineEdit, autonomous backdrop (auto-advance, ≥2 slides, hover/focus cannot change it) |
| Lobby / end-screen flow | `res://scripts/ui/ws3_ui_checks.gd` | **168 checks** (add `CART_WS3_LIVE_MODES=1` for the 192-check live 3D variant): non-host action set + Cancel/Leave confirm, pause-ESC isolation, chrome-free emotes + spawn bounds, slanted preview motion, in-room lobby backdrop independence |
| Bot slots / teams | `res://scripts/tools/ws4_bot_slots_smoke.tscn` | **299 assertions**: 8-seat budget, `max_humans = 8 - bots`, clamps, BOT labels/icons, deterministic human+bot arrange, config/bot-RPC wire arity + old-host fallback, admission refusal, build-version gate, lobby backdrop contract. Two/four-process LAN runner: `_audit/run_ws4_bot_e2e.ps1` |
| Phase-3 second-pass smoke | `res://scripts/tools/phase3_bugfix_smoke.gd` | **84 checks** (91 under forced web): host-loss-during-load overlay, priority-aware SceneLoader queue, loading-overlay focus release, session-teardown abort, failed-load room rollback, pause hints, confirm-dialog ESC isolation, `_net_session_config` arity pin |
| Web release package | `web_deploy/scripts/validate_package.py`, `test_version_parity.ps1`, `verify_deploy.ps1`, `audit_logo_parity.py` (workspace root, Python/PowerShell) | JSONC/TOML/JS/headers validation, stale-vs-current version.json demo, mock-edge route/caching/negotiation checks, 80-point logo/icon parity audit. Not Godot suites |

The networking scene also runs two-process LAN end-to-end checks; run one copy
with `CSGP_NET_MODE=host` and a second with `CSGP_NET_MODE=client` (both
headless). Default mode is a fast unit run that needs no second process.
`scripts/tools/phase2_restart_probe.tscn` is the two-process MP rematch e2e
(host asserts a new scene instance + room `playing`, client asserts a new
instance + live session), and `scripts/ui/lobby_reactions.gd` gives the LAN
reaction e2e its limiter/catalog.
`scripts/tools/net_ping_probe.tscn` is the two-process live Pi latency harness
(`CSGP_PING_ROLE=host|client`, optional `CSGP_FORCE_RELAY=1`);
`scripts/tools/net_lan_probe.tscn` and `net_pi_host_probe.tscn` are route
diagnostics. None of the three is a pass/fail suite.

Pi-side suites (run on a Python machine, from the workspace root):
`python pi_setup\cartslop-server\tests_security.py`,
`python pi_setup\cartslop-server\tests_race_api.py` and
`python pi_setup\cartslop-tls\tests_tls_proxy.py`.

`scripts/tools/preview_render.tscn` regenerates the menu preview PNGs and
**must be run windowed** — under `--headless` it captures blank frames and
refuses to run.

## 5. Test harness — fixed 2026-11-16

Four defects used to make a green run untrustworthy. All are fixed; this is the
record so they are not re-introduced.

| Was | Now |
| --- | --- |
| `hud_smoke.gd` asserted a five-row standings cap that the HUD had deliberately outgrown, then crashed on `_speed_gauge.max_speed_kmh`, which no longer exists — so the boost-clamp check never ran. | Asserts one row per cart, checks the local row at its real slot, and verifies `_dial_max_kmh`. `HUD_SMOKE: PASS`. |
| `dockyard_selftest.gd` enforced a 600–900 object band while the kit rebuild places ~1234 (stadium ~1351). | Band is 900–1600 as a runaway guard; the 120-draw ceiling remains the real budget. |
| `preview_verify.gd` reported `closest inf m` for terrain banks: it only sampled `BoxShape3D`, but banks are convex hulls, so nothing was measured and `inf >= limit` passed vacuously. | `_shape_samples()` covers box, convex hull, sphere and AABB; a non-finite result now fails the check. Stadium measures 8.87 m against an 8.02 m limit. |
| The synthetic rolling-elevation build reused the real track's name, printing `KENNEY DRIVE stadium: NO (fix the seam metrics before racing)` for a profile that is never raced. | Diagnostic builds pass `"diagnostic": true` and report `stadium_rolling_test` with "(diagnostic profile, not a shipped track)". |

When a `HUD cluster ... exceeds viewport` or `object(s) outside` message appears,
it is a real regression — the harness no longer has known-bad assertions.

## 6. Housekeeping

- `builds/` keeps **only the current version**. Old versions total ~600 MB each;
  move them to the Recycle Bin rather than accumulating them.
- Keep `builds/v<current>/` — every export path, the deploy script and the Pi
  server README point at it.
- Loose `builds/*.log` files are scratch output from one-off runs; delete them.
- `godot_project/.godot/` is the import cache. It is regenerable but deleting it
  forces a full reimport (slow); leave it alone unless it is corrupt.
- Never create `project.godot`, `export_presets.cfg`, `version.txt` or
  `README.md` at the repository root — the real files are in `godot_project/`,
  and an empty decoy at the root makes the editor open the wrong folder.

## 7. Version control

This directory is a git repository (`main`, remote
`https://github.com/HOT18594/CartSlopGP.git`, 38 commits of 0.8.2 history).

- **Commit from inside this directory**, not from the workspace root. The root
  is not a repo; an empty `project.godot` there once made the editor open the
  wrong folder.
- `pi_setup/`, `builds/` and `downloads/` live outside the repo and are
  intentionally untracked. `pi_setup/` holds the Pi SSH key and a sudo
  password — keep it that way.
- `.godot/` (the import cache) is ignored; the `*.import` sidecars are tracked.
- Pushing needs GitHub credentials for `HOT18594`. Commit locally without
  pushing unless a push was explicitly requested.

## 8. Headless run noise

A headless run on a restricted Windows account prints errors that are not game
faults and can be ignored:

- `Failed to open 'user://logs/...'` — the log directory is not writable.
- `Failed to read the root certificate store` — no access to the Windows cert
  store, so the online relay check cannot validate TLS there.
- `Unicode parsing error ... Unexpected NUL character` — comes from the same
  certificate-store read, not from project files.
- `ObjectDB instances were leaked` / `resources still in use at exit` — engine
  shutdown bookkeeping after a `--quit-after` run.
