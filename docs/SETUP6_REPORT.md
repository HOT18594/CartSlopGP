# Setup 6 report - UI, cursor, git, builds, auto-updates, smoke fix

Generated: 2026-11-04 · version 0.1.0 · Godot 4.7.2 stable (Mobile renderer)

Scope was the setup brief only (no gameplay or multiplayer changes), plus the
requested smoke fix.

---

## 1. UI scenes and how they map to the reference images

The two mockups arrived after the first pass, and the menu and HUD were
rebuilt to match them. Everything is drawn with vector primitives and
StyleBoxFlat - no screenshots are pasted anywhere.

**Menu (mockup 1):** bright sky gradient, clouds, city skyline, SlopMart store
with sign and windows, parking lot with perspective bay lines, lamp posts,
green trees/bushes and three shopping carts. Title is three stacked Labels
(`CART` white, `SLOP` pink with drawn paint drips, `GP` yellow) with heavy
dark outlines, small rotations and drop shadows, plus a waving checkered flag
behind `GP`. Buttons use `candy_button.gd`: thick dark border, saturated fill,
hard offset shadow and a gloss highlight - yellow PLAY, blue SETTINGS, red
QUIT. HOST/JOIN stay as dimmed placeholders below PLAY.

**HUD (mockup 2):** bottom-right round speedometer (`speedometer.gd`) with
white rim, dark face, cyan-yellow-red sweep, ticks and a needle; bottom-left
segmented boost bar (`boost_meter.gd`) with a lightning bolt; cream state pill
top-centre; outlined controls hint. The mockup's `1st` position badge and
`LAP 1 / 3` pill are built too (top-left, checker strip included) but hidden by
default because you only want them in race-style minigames - enable with
`show_position_badge` / `show_lap_badge`, then `set_race_position(n)` and
`set_lap(current, total)`.

| File | Contents |
| --- | --- |
| `scenes/ui/main_menu.tscn` | Title stack + checkered flag, PLAY / HOST+JOIN / SETTINGS / QUIT, version label, update badge, settings overlay |
| `scenes/ui/hud.tscn` | Speedometer, boost meter, state pill, controls hint, optional position/lap pills, hidden F3 debug readout |
| `scenes/ui/pause_menu.tscn` | CanvasLayer overlay, dimmed backdrop, PAUSED panel with RESUME / SETTINGS / QUIT TO MENU |
| `scenes/ui/settings_menu.tscn` | Master volume, SFX volume, fullscreen, custom cursor, offline note, BACK |
| `assets/ui/theme.tres` | Cream sticker panels, candy buttons, check buttons, sliders; Fredoka + Luckiest Guy |

Background: `scripts/ui/menu_background.gd` draws the whole backdrop with
`_draw()`. Helper draw nodes: `checker_flag.gd`, `checker_strip.gd`,
`drip_label.gd`, `candy_button.gd`, `speedometer.gd`, `boost_meter.gd`.

Wiring:

- PLAY → `res://scenes/dev/driving_test.tscn`
- SETTINGS → settings overlay; QUIT → `get_tree().quit()`
- Esc toggles pause; pausing freezes driving, restores the cursor; QUIT TO MENU unpauses and returns to the menu
- HUD + pause menu are instanced in `driving_test.tscn`; the old debug Label was replaced by the HUD (F3 still shows the debug text)
- Main scene is now `scenes/ui/main_menu.tscn` (was the driving test)

Layout was verified by rendering the real scenes (1280x720): menu, settings,
pause, and the driving HUD all render correctly. Screenshots live in
`CartSlopGP/_shots/` if you want to compare against the mockups.

## 2. Cursor

Kenney **Cursor Pack v1.1** (CC0) extracted into `assets/ui/cursor/`.
Selected sprites (Outline style - white fill, black outline, reads on both dark
panels and the bright sky):

| State | Source file | Saved as |
| --- | --- | --- |
| idle pointer | `PNG/Outline/Default/pointer_toon_a.png` | `cursor_idle.png` |
| hover (button) | `PNG/Outline/Default/hand_small_point.png` | `cursor_hover.png` |
| pressed | `PNG/Outline/Default/pointer_toon_b.png` | `cursor_pressed.png` |

`scenes/ui/cursor_controller.tscn` + `scripts/ui/cursor_controller.gd` are an
autoload (`CursorController`). Behaviour:

- hides the OS pointer in menus (`Input.MOUSE_MODE_HIDDEN`), captures it while driving
- follows the mouse, switches to the hand over any enabled BaseButton
- press swaps to the pressed sprite, plays `ui_confirm.ogg` on the SFX bus and
  runs a tween pop (`cursor_scale` 1.6, `click_pop_strength` 0.22)
- exported toggles: `enable_custom_cursor`, `cursor_scale`, `click_pop_strength`
- respects the Settings "CUSTOM CURSOR" toggle (falls back to the OS pointer)

## 3. Fonts

- **Fredoka** (OFL 1.1) for body/buttons. Godot ignored the variable weight axis,
  so static wght 500 / 700 instances were baked with fontTools
  (`tools/README-fonts.md`).
- **Luckiest Guy** (Apache 2.0) for titles.
- Licenses stored next to the fonts; full credits in `docs/ASSET_CREDITS.txt`.

## 4. Smoke fix (the "boomerang" complaint)

Cause: `assets/textures/smoke_sheet.png` really was 16 thin crescent frames -
the particle was faithfully drawing a boomerang. No amount of particle tuning
could fix that.

What changed:

1. `tools/gen_smoke_sheet.py` regenerates the atlas as a 4x4 sheet of soft,
   billowing puffs (6-blob cluster + coherent noise that evolves over the 16
   frames, transparent margin per cell).
2. `scenes/feedback/cart_feedback.tscn`:
   - `local_coords = false` - smoke now stays in the world instead of being
     dragged along with the cart
   - gentler upward drift (velocity 0.7-1.6, spread 26, gravity 1.1), less
     turbulence (0.35 vs 0.9)
   - wider emission across the rear axle, 64 particles at 1.25 s for a plume
     instead of 36 blobs
   - depth-sorted billboards (`draw_order = 3`), 30 fps fixed emission
   - landing/crash burst softened to match the new sprite
3. Original sheet and scene are backed up in `_backup_setup6/`.

Verified in-engine with drift screenshots: a soft trail of round puffs, no
crescents, no giant white blob.

## 5. Git / GitHub

- Repo initialised in `godot_project` on branch `main`
- `.gitignore` covers `.godot/`, `builds/`, `exports/`, logs, OS junk
- Initial commit `65bd244` - "Add prototype shell: menus, HUD, cursor, updates, smoke fix"
- Annotated tag **v0.1.0**
- `version.txt` = `0.1.0`, `project.godot` `config/version="0.1.0"`
- Local identity used for the commit: `Ethan Bai <HOT18594@users.noreply.github.com>`
  (no global git identity was configured - change it if you prefer another email)

**Remote: not connected yet.** `gh` is installed but not authenticated, so the
repo was not created or pushed. Run these three commands in `godot_project`
after creating the empty repo at https://github.com/new (name: `CartSlopGP`,
no README):

```bash
git remote add origin https://github.com/HOT18594/CartSlopGP.git
git branch -M main
git push -u origin main
```

Then push the tag:

```bash
git push origin v0.1.0
```

Or authenticate once (`gh auth login`) and I can do it from here.

## 6. Windows export

- Export templates for 4.7.2.stable were already installed at
  `%APPDATA%\Godot\export_templates\4.7.2.stable\`
- Preset **Windows Desktop** in `export_presets.cfg` (x86_64, release,
  external .pck, resource modifiers off)
- Built to `CartSlopGP/builds/v0.1.0/CartSlopGP.exe` + `CartSlopGP.pck`
- `include_filter="version.txt"` in the preset - a plain .txt is not a Godot
  resource, so without this the exported build reads v0.0.0 and the updater
  compares against the wrong version
- Zipped: `CartSlopGP/builds/CartSlopGP_v0.1.0_windows.zip` (~39 MB)
- The exported exe was launched headless (`--quit-after`) and exited 0 with no
  script errors. A screenshot taken from inside the exported build (viewport
  texture) shows the full menu rendering correctly, cursor included; ordinary
  desktop captures of that window come back grey on this machine, which is a
  capture artifact, not a rendering problem.

## 7. Update checker

`scripts/systems/update_checker.gd`, autoload `UpdateChecker`.

- Silent check on menu load: `GET /repos/HOT18594/CartSlopGP/releases/latest`,
  `User-Agent` header, 5 s timeout
- Compares the tag with `res://version.txt` (numeric semver, so 0.1.10 > 0.1.9)
- On success with a newer tag: **UPDATE AVAILABLE vX** badge + **RELEASE NOTES**
  button (tier 1, opens the release page)
- Badge click downloads the Windows zip to `user://updates/` (tier 2, progress
  in the badge text), then becomes **RESTART TO INSTALL**
- Install (tier 3): unpacks to `user://updates/staging`, writes
  `update_install.bat` next to the .exe, launches it detached and quits. The
  .bat waits for the game PID to exit, xcopy's the files over, restarts the
  game and deletes itself.
- Exported settings: `enable_update_checks`, `update_check_timeout`,
  `github_owner` (HOT18594), `github_repo` (CartSlopGP), `download_timeout`,
  `require_windows_asset`

**Offline / no releases:** the check sets `status` to `offline` or `error` and
shows nothing on the menu except a small "Offline - update check skipped." line
in Settings. It never blocks or retries aggressively; the next menu load tries
again.

Tested: unit checks for version parsing/comparison
(`tools/test_update_checker.gd`) pass, and a live request against
`godotengine/godot` correctly returned tag 4.7.2 and picked a Windows zip asset
(`tools/test_update_network.gd`).

## 8. Validation performed

- `godot --headless --path . --import` - clean, smoke sheet and cursors reimported
- `godot --headless --path . --quit-after 90` - boots into the main menu, no errors
- `tools/build_ui_theme.gd` regenerates `theme.tres` without errors
- `tools/test_update_checker.gd` - 9/9 passed
- Live GitHub API check - passed
- Rendered screenshots of menu, settings, pause, drift smoke - all correct
- Exported build screenshot (from inside the game) - menu renders, v0.1.0 label
- Exported `.exe` launches and quits cleanly

## 9. Missing pieces / manual steps for you

1. **Send the two UI mockups** - I will restyle the menu/HUD to match
   (palette + layout, same node structure).
2. **Create the GitHub repo** `HOT18594/CartSlopGP` (empty) and run the three
   push commands above; then push tag `v0.1.0`.
3. **Publish the first release** (this is what turns the updater on):
   tag `v0.1.0`, upload `builds/CartSlopGP_v0.1.0_windows.zip`.
4. Optional: `gh auth login` so future releases can be one command
   (`docs/RELEASE_WORKFLOW.md`).
5. If you want a different commit email, `git config user.email ...` and amend.

## 10. Please test

- Open the menu: custom cursor appears, OS pointer hidden, hover swaps to the
  hand, click pops and plays a blip
- PLAY → drive; HUD speed/boost/state update; drift smoke looks like smoke
- Esc → pause menu appears; settings sliders and toggles work; RESUME returns
- Run `builds/v0.1.0/CartSlopGP.exe` and confirm the same


---

## 11. Follow-up pass (2026-11-04, after playtest feedback)

- **Menu**: title is now one playful line (`CART SLOP GP` with per-word tilt and
  a flag peeking out behind GP); the old subtitle/underline are gone; HOST/JOIN
  were removed from the main menu.
- **Play flow**: PLAY opens `scenes/ui/play_menu.tscn` - SANDBOX loads
  `driving_test.tscn`, HOST/JOIN show a "multiplayer coming" notice, BACK returns
  to the menu. No minigame wiring yet, as requested.
- **HUD**: speedometer, boost meter, state pill and hint shrunk (~40% smaller
  footprint) and the dial tilted for personality.
- **Track**: boost pads now use `assets/materials/boost_pad.gdshader` (cyan rim,
  scrolling yellow chevrons, pulsing glow); a checkered start line uses
  `checker.gdshader`; lane/landing/brake/drift pads were recoloured to the menu
  palette and the rollers are low ramps you can drive over.
- **Props**: cones 0.35 kg, crates 0.8 kg, rammed props get a strong upward and
  spin impulse and no longer slow the kart down.

Verified with fresh 1280x720 renders (menu, play screen, HUD, pad close-up).


---

## 12. GitHub + live update verification (2026-11-04)

- Repo created: https://github.com/HOT18594/CartSlopGP (public, `main` pushed).
- Tag `v0.1.0` pushed; release published with `CartSlopGP_v0.1.0_windows.zip`
  (40,930,680 bytes) attached.
- `UpdateChecker` against the real API: `status=up_to_date`, local `0.1.0`,
  latest `0.1.0`, asset `CartSlopGP_v0.1.0_windows.zip` resolved.
- Tier 2 exercised for real: downloaded 40,930,680 bytes to `user://updates/`;
  the zip lists `CartSlopGP.exe` + `CartSlopGP.pck`, which is what the installer
  needs to find.
- Tier 3 template printed and checked: waits on the game PID, xcopy's the staged
  files, relaunches and self-deletes. It refuses to run from the editor
  (`install_only_in_exported_build`), as designed.
- Tool scripts: `tools/check_release_live.gd`, `tools/check_download_live.gd`,
  `tools/check_installer_bat.gd` (excluded from builds via `tools/*`).
