# Maintaining Cart Slop GP

Everything you need to ship a version without breaking the repository.

**Path convention:** this repository is the game (`godot_project/`'s contents).
Commands and paths below are written relative to the **workspace root** — the
folder one level up that also holds `builds/`, `pi_setup/` and `downloads/`.
Those three are deliberately outside version control.

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
| 1 | `godot_project/version.txt` | the number alone, e.g. `0.7.2` |
| 2 | `godot_project/project.godot` | `config/version="0.7.2"` under `[application]` |
| 3 | `godot_project/export_presets.cfg` | four `export_path="../builds/v0.7.2/..."` lines |
| 4 | `pi_setup/build_0_7_2.ps1` | `[string]$Version = "0.7.2"` (rename the file too, by convention) |
| 5 | `pi_setup/Deploy-Server.cmd` | the `builds\v0.7.2\web` checks |
| 6 | `godot_project/CHANGELOG.md` | a new `## [0.7.2] - YYYY-MM-DD` section at the top |

`build_0_7_2.ps1` compares `version.txt` against its own `-Version` and aborts
on a mismatch, which is the safety net for item 1 vs item 4.

`scripts/systems/update_checker.gd` reads `version.txt` at runtime, so the
in-game "update available" check needs no edit — just the file.

## 2. Building a release

```powershell
powershell -ExecutionPolicy Bypass -File pi_setup\build_0_7_2.ps1
```

Writes `builds/v<version>/`:

```
windows\CartSlopGP.exe + .pck      mac\CartSlopGP.zip
linux\CartSlopGP.x86_64 + .pck     web\index.html + .wasm + .pck
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

**Check before publishing:** open `release\SHA256SUMS` and spot-check that every
platform zip is dated this run, and that `logs\` has no failed platform.

## 3. Deploying the web build to the Pi

```powershell
pi_setup\Deploy-Server.cmd
```

It uploads the server and, if `builds\v<version>\web\index.html` exists, the
browser build too. It prompts for the `pi` sudo password. `pi_setup/` holds the
SSH key and credentials — it is gitignored and must never be published.

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
`https://github.com/HOT18594/CartSlopGP.git`, 25+ commits of 0.7.1 history).

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
