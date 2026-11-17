# AGENTS.md

Operating rules for AI agents working in this repository. Read this before
touching anything.

## The one trap that matters

**The repository root is not a Godot project.** The project is
`godot_project/`. Open, run and export from there. Never create
`project.godot`, `export_presets.cfg`, `version.txt` or `README.md` at the root
— empty decoys there once made the editor open the wrong folder.

## Hard boundaries

- **`pi_setup/` is off limits** unless the task is explicitly about deployment.
  It contains an SSH private key, a sudo password and credential notes. It is
  gitignored. Never print, copy, diff into a report, or commit its contents.
- **Never delete `builds/v<current>/`.** Export paths, the deploy script and the
  Pi server README all point at it.
- **This directory is the git repo.** Commit from here, on `main`, with a short
  descriptive message. `pi_setup/`, `builds/` and `downloads/` sit one level up
  and are untracked on purpose. Do not push unless asked — the remote needs
  GitHub credentials.
- Do not "clean up" by deleting `assets/` or `.godot/`: the first is the game's
  art, the second is a regenerable import cache that costs a long reimport if
  removed.

## Running things

```bash
G=downloads/godot_editor/Godot_v4.7.2-stable_win64_console.exe

# boot check
$G --headless --path godot_project --quit-after 120

# tests (exit code = number of failures)
$G --headless --path godot_project --script res://scripts/tools/preview_verify.gd
$G --headless --path godot_project --script res://scripts/tools/hud_smoke.gd
$G --headless --path godot_project --script res://scripts/minigames/maps/stadium/stadium_smoke.gd
$G --headless --path godot_project --script res://scripts/minigames/maps/dockyard/dockyard_selftest.gd
$G --headless --path godot_project --script res://scripts/minigames/maps/glacier/glacier_selftest.gd

# build a release (PowerShell, from the repo root)
powershell -ExecutionPolicy Bypass -File pi_setup\build_0_7_1.ps1
```

`preview_render.tscn` must run **windowed**; it refuses `--headless`.

## Reading a test run

Exit code is the number of failures. Ignore this noise, it is not the game:

- `Failed to open 'user://logs/...'`
- `Failed to read the root certificate store`
- `Unicode parsing error ... Unexpected NUL character`
- `ObjectDB instances were leaked` / `resources still in use at exit`

`docs/MAINTENANCE.md` §5 records the four harness defects fixed on 2026-11-16
(stale standings assertions, a stale object band, a vacuous `inf` bank clearance
and a synthetic track that reported a racing blocker). The harness no longer has
known-bad assertions — a failing check is now a real regression.

## How to change the game safely

1. Find the code path. Races are built from ASCII grids by
   `scripts/minigames/tiles/kenney_tiles.gd` via
   `scripts/minigames/track_defs.gd`; themes live in
   `scripts/minigames/maps/`. Read `docs/ARCHITECTURE.md`.
2. Keep map builders static and host-parameterised, so the probe, the preview
   renderer and the race scene keep sharing one path.
3. Physics and race logic belong on the fixed 60 Hz step, not `_process`.
4. Route UI spacing through `UiKit` and scene changes through `SceneLoader`.
5. Run the tests that cover what you touched. A change to the tile engine needs
   `preview_verify.gd` plus all three map tests.
6. If a test asserts an old shape of the code (for example a five-row standings
   cap), fix the test to the current contract — do not "restore" the old
   behaviour to make it green.

## Editing conventions

- GDScript, tabs, typed locals, `const X := preload(...)` at file top.
- Keep the docstring above `extends` accurate; it is the only map of intent.
- Match the surrounding style; this codebase heavily comments tuning constants.
- After changing any map grid or theme, regenerate previews with
  `preview_render.tscn` and re-run `preview_verify.gd`.

## Version bumps

Six files, listed in `docs/MAINTENANCE.md` §1. The build script aborts if
`version.txt` and its `-Version` disagree — treat that abort as correct.

## Housekeeping

- `builds/` keeps only the current version. Send old versions to the Recycle
  Bin, never `rm -rf`.
- Loose `builds/*.log` files are scratch; delete them.
- Put new documentation in `docs/` and link it from `README.md`.
