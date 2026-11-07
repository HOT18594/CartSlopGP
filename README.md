# Cart Slop GP

A silly shopping-cart racing sandbox built in **Godot 4.7.2**.
Current version: **0.6.3**.

Drive a shopping cart (or a sedan, truck, van...) around a 140 x 140 m arena,
hit boost pads, drift, smash cones and crates, then host a shared world and
invite a friend with a 5 letter room code.

This README is the setup guide for every feature: installing, controls,
vehicles, minigames, LAN and online multiplayer, the Pi server, auto updates,
and building the game yourself.

---

## 1. Install and run

1. Open **[github.com/HOT18594/CartSlopGP/releases/latest](https://github.com/HOT18594/CartSlopGP/releases/latest)**.
2. Download the zip for your computer:
   - **Windows** - `CartSlopGP_v0.6.3_windows.zip`
   - **Mac** - `CartSlopGP_v0.6.3_macos.zip`
   - **Linux** - `CartSlopGP_v0.6.3_linux.zip`
   - **Browser** - `CartSlopGP_v0.6.3_web.zip` (single player only, no multiplayer)
3. Unzip it somewhere you own, for example your Desktop or `~/Games`. Do not
   run it from inside the zip.
4. Launch:

| Platform | What to do |
| --- | --- |
| Windows | Double-click `CartSlopGP.exe`. SmartScreen may warn because the build is unsigned. Click **More info**, then **Run anyway**. |
| macOS | Double-click `Cart Slop GP.app`. If Gatekeeper blocks it, right-click the app, choose **Open**, then confirm. See the macOS section below. |
| Linux | `chmod +x CartSlopGP.x86_64`, then run `./CartSlopGP.x86_64`. |
| Browser | Serve `index.html` over HTTP (opening it as a `file://` URL will not load the `.pck`). |

No install wizard, no account, no launcher. Player data and downloaded updates
live in Godot's `user://` folder:

- Windows: `%APPDATA%/Godot/app_userdata/Cart Slop GP/`
- macOS: `~/Library/Application Support/Godot/app_userdata/Cart Slop GP/`
- Linux: `~/.local/share/godot/app_userdata/Cart Slop GP/`

### First launch settings

**SETTINGS** on the main menu controls master and SFX volume, fullscreen, and
the custom cartoon cursor. All of it is saved locally. **CHANGELOG** shows the
short player-facing release notes. **UPDATE AVAILABLE** appears at the top right
when a newer build exists.

### macOS, unsigned builds and Gatekeeper

The macOS build is **ad-hoc signed by Godot** (`codesign/codesign=1` with an
empty identity). It is not notarized with an Apple Developer ID. That is normal
for a hobby build and macOS will ask for one extra click the first time.

If the app says it is damaged or cannot be opened, either:

- right-click `Cart Slop GP.app`, choose **Open**, then confirm, or
- run `xattr -dr com.apple.quarantine "/path/to/Cart Slop GP.app"`.

Both only affect this copy of the app. Do not disable Gatekeeper system-wide.

**Does one-click updating still work on an unsigned Mac?** Yes. The updater
replaces the whole `.app` bundle, restores the executable bits that zip
extraction drops, clears Gatekeeper quarantine on the new bundle, and re-signs
ad-hoc only if the copied signature is broken. It also keeps a backup and rolls
back automatically if the new build will not launch. Because the new bundle is
created locally rather than downloaded by a browser, it is not quarantined, so
the extra right-click Open is not needed again.

If the previous build carried a real Developer ID signature, that signature is
replaced by the ad-hoc one. The app still opens, but macOS may ask again for
permissions tied to the old signature (camera, microphone, accessibility).
To keep a Developer ID signature, sign the bundle yourself after exporting and
skip the in-game updater.

The updater **never asks you to re-sign anything**. Godot exports are already
ad-hoc signed. The installer verifies the copied bundle and only re-signs if
that signature was actually broken by the copy. A blanket `chmod` used to
invalidate it on every single update; that is fixed. Gatekeeper quarantine is
cleared on the new bundle.

The one case that cannot self-update is a **read-only location**, for example a
standard macOS account with the app in `/Applications`, or a Windows install
under `C:\Program Files` without admin rights. The dialog detects this, tells
you, and opens the release page instead. Fix: move the game to a folder your
account can write to, or run it once as an admin.

---

## 2. Controls

| Action | Key |
| --- | --- |
| Accelerate | W / Up |
| Brake / reverse | S / Down |
| Steer | A / D or Left / Right |
| Handbrake (drift) | Space |
| Boost | Shift or Left Mouse |
| Reset cart | R |
| Player list (multiplayer) | hold Tab |
| Pause / menu | Esc |

Menus support **arrow keys, WASD and a gamepad d-pad**, plus Tab and Enter.
Left/right also does something useful on the screen you are on: it turns
changelog pages, flips through vehicles, switches PLAY states, and cycles
BOTS / MODE pills. Text fields keep their own arrow keys for the caret.

Single-player Esc pauses the world. In multiplayer Esc opens the menu but the
world keeps running (Minecraft-style). Hold Tab to see everyone's name tag,
tag colour and ping.

---

## 3. Single player

**PLAY** opens two big cards. Pick **SINGLE** or **MULTIPLAYER**, then use the
**BACK** bar to move between states.

### Sandbox

SINGLE, then **SANDBOX**, then pick a vehicle. A 140 x 140 m arena with boost
pads, ramps, cones, crates and speed bumps. Hold a drift or the handbrake and
the rear tyres leave fading skid marks. Press R if you get stuck.

The vehicle picker shows 10 block comparison bars instead of raw numbers, so
you can see how each car stacks up against the whole garage. Your choice is
remembered.

| Vehicle | Weight | Top speed | Feel |
| --- | --- | --- | --- |
| Shopping cart | 45 kg | 19 m/s | no engine, quick, rattles, thin skids |
| Sedan | 1.35 t | 23 m/s | balanced all-rounder |
| Sports car | 1.15 t | 27 m/s | fastest, best grip, loudest skids |
| Taxi | 1.45 t | 22 m/s | rattly, slightly sluggish |
| Van | 2.05 t | 20 m/s | heavy, more smoke, wider marks |
| Box truck | 3.2 t | 18 m/s | slow to spin up, plows props |
| Police cruiser | 1.55 t | 25 m/s | quick V8 cruiser |

Mass is real: heavier vehicles accelerate slower, lose less speed on impact and
transfer more momentum into props. Each car has its own engine loop, smoke and
tyre-mark width. The minigame buggy is deliberately not in this list.

### Minigames

SINGLE, then **MINIGAMES**. **MEADOW LOOP** is the shipped event: three laps of
a winding dirt track through a grassy forest, three rivals and four boost pads.
Pick a vehicle and press **RACE**. Only playable events are listed, and every
card uses a real in-game screenshot.

The start gantry is two rows of five lamps, like a real Formula 1 start. One
column (two lamps) lights per countdown beat, so two dots coming on together is
intentional. All ten go green on GO. See `docs/MEADOW_LOOP.md`.

Optional music: drop `menu_loop.mp3`, `sandbox_loop.mp3` and `race_loop.mp3`
into `assets/audio/music/` before exporting. Missing tracks simply play no
music. See that folder's README and `docs/AUDIO_SOURCES.md`.

---

### Artwork

Five illustrated backgrounds ship in `assets/ui/art/`:

| File | Used for |
| --- | --- |
| `bg_parking.png` | Menu shell and loading screen |
| `scene_track_aerial.png` | Game selector, aerial dirt track |
| `scene_road.png` | Game selector, winding country road |
| `scene_arena.png` | Game selector, stunt arena |
| `scene_finish.png` | Game selector, finish line |

The game selector crossfades through the four scene images every 4.5 seconds.
Everything is drawn by `scripts/ui/art_backdrop.gd`. If any image is missing,
the hand-drawn vector backgrounds are used instead, so nothing breaks.

## 4. Multiplayer setup

PLAY, then **MULTIPLAYER**. The card takes you straight to the lobby. It has one
clean column: your name and tag colour at the top, then numbered HOST and JOIN
steps.

### Set your identity

- **NAME** - your display name, up to 16 characters.
- **TAG** - eight colour swatches. The colour appears above your cart, in the
  lobby player list and in the Tab list. It is saved and synced to everyone.

### Option A: host on your Wi-Fi (no internet)

1. On the host press **HOST LAN ROOM**.
2. On the other players press **FIND LAN ROOMS**. A popup lists nearby rooms
   with host name, player count and state. Type in the search box to filter.
3. Pick the room. No code, IP address or port needed.
4. Everyone on the same network sees the room appear. UDP **42779** is used for
   LAN discovery, so allow it on the local firewall if your network is strict.

### Option B: host online (5 letter room code)

1. On the host press **CREATE ONLINE ROOM**. The Cart Slop Pi returns a 5 letter
   room code such as `ABCDE`.
2. Friends press **BROWSE ONLINE ROOMS** and pick the room, or type the code
   into **5-LETTER CODE** and press **JOIN**. The browser popup has a search
   field and a REFRESH button.
3. The Pi relays the session. The host opens an outbound tunnel, so the host
   needs no port forwarding and Windows Firewall sees no inbound UDP.
4. No server status is shown when everything works. If the server is down, the
   lobby just says **Game server is down. Try again later.** and the online
   buttons disable themselves. LAN hosting still works.

There is no IP address, port, hostname or advanced server field anywhere in the
game. Joining a room that has already started is refused.

### In the room

- The host picks **SANDBOX** or **MINIGAMES**, the number of AI bots, the map
  and the vehicle, then presses **START**.
- In MINIGAMES races **everyone drives the host's car**. Only name tags tell
  players apart. Sandbox keeps per-player vehicle choices.
- **COPY CODE** puts the code on the clipboard. **LEAVE ROOM** returns to the
  host/join steps without leaving the menu.
- Errors appear in a small line at the bottom only when something is wrong.

### Pi server (only needed for online rooms)

A Raspberry Pi 4 on the same network runs the lobby and UDP relay.

- Console: `http://cartslop.local:42777` (password protected)
- HTTP/API: TCP **42777**, discovery: UDP **42778**, relay: UDP **42800-42819**,
  host tunnel: TCP **42820**
- LAN IP: `192.168.1.22`. Public fallback in the game: `68.204.45.1:42777`.
  The public IP is dynamic, so update `DEFAULT_RELAY_SERVER` in
  `scripts/net/network.gd` if it changes, or set up DDNS.
- Forward those ports on the router if friends play from outside the house.
- Server source and systemd units: `pi_setup/cartslop-server/`.
- Full setup: `docs/PI_SERVER.md` and `docs/MULTIPLAYER.md`.

### Multiplayer troubleshooting

| Symptom | Fix |
| --- | --- |
| "Game server is down" | The Pi is asleep (nightly schedule stops it 00:15 to 07:15 ET) or unreachable. Restart the game to re-check, or use HOST LAN ROOM. |
| No LAN rooms found | Both machines must be on the same subnet. Allow UDP 42779 and make sure the host already pressed HOST LAN ROOM. |
| Code not accepted | Codes are exactly 5 letters. Copy it again from the host. |
| School / work network | Outbound UDP is often blocked. LAN rooms still work on the same Wi-Fi. |
| Game sticks on "Syncing players..." | A peer did not finish loading. The host retries the scene start every 5 seconds and falls back after 12 seconds. |

---

## 5. Auto updates

The game checks for updates when the main menu opens. It asks the **Cart Slop Pi
update mirror** first and falls back to **GitHub Releases**, so a stale mirror
cannot hide a newer build. Force a check with **SETTINGS > CHECK FOR UPDATES**.

1. The dialog appears automatically and starts downloading. A live %/MB bar
   shows progress. **LATER** hides the dialog; the download continues.
2. When it finishes, press **RESTART & UPDATE**. The game closes, swaps the
   files and reopens itself. No unzipping and no manual copying on Windows,
   macOS or Linux.
3. If the swap is blocked (read-only folder, missing asset for the platform),
   the dialog offers **OPEN RELEASE PAGE** instead.

Downloads go to `user://updates/`. Partial files are deleted on failure. A
stalled connection flips the dialog to **TRY AGAIN** after 20 seconds instead
of hanging forever.

### For maintainers: publishing an update

1. Bump `project.godot` (`application/config/version`), `version.txt`,
   `export_presets.cfg`, and the version strings in this README.
2. Export all four platforms and zip them as
   `CartSlopGP_v<version>_<platform>.zip`. The macOS zip must contain the
   `.app` bundle at the top level.
3. Tag `v<version>`, push, and create the GitHub Release with those zips as
   assets. The updater matches the zip name containing `windows`, `macos` or
   `linux`.
4. Optional Pi mirror: drop the Windows zip and `updates/manifest.json` into
   `pi_setup/cartslop-server/updates/`. See the README in that folder, plus
   `docs/RELEASE_WORKFLOW.md`.
5. Older builds will offer the update automatically.

`CARTSLOP_UPDATE_SERVER` can be set to `host:port` to point the checker at a
custom mirror during testing.

---

## 6. Build it yourself

### Requirements

- [Godot 4.7.2 stable](https://godotengine.org/download/), standard build (not
  .NET), plus matching export templates for the platforms you want to build.
- Git, and Python 3 only if you regenerate art assets.

### Open and run

1. `git clone https://github.com/HOT18594/CartSlopGP.git`
2. In Godot, **Import**, select `godot_project/project.godot`, **Import & Edit**.
3. Press **F5**, or run headless:
   `godot --headless --path godot_project --quit`

Important: the git repository contains only `godot_project/`. `pi_setup/` and
`builds/` live next to it and are not tracked.

### Export

From `godot_project/`:

```bash
godot --headless --path . --export-release "Windows Desktop" ../builds/v0.6.3/windows/CartSlopGP.exe
godot --headless --path . --export-release "macOS"           ../builds/v0.6.3/mac/CartSlopGP.zip
godot --headless --path . --export-release "Linux"           ../builds/v0.6.3/linux/CartSlopGP.x86_64
godot --headless --path . --export-release "Web"             ../builds/v0.6.3/web/index.html
```

Then zip each folder as `CartSlopGP_v0.6.3_<platform>.zip`. Signing notes and
the full release checklist are in `docs/PLATFORMS.md` and
`docs/RELEASE_WORKFLOW.md`.

### Tests

```bash
godot --headless --path . --quit                                  # boot / parse check
godot --headless --path . res://tools/ui_pass_check.tscn         # all UI screens + navigation
godot --headless --path . --script res://tools/test_macos_update.gd
godot --headless --path . --script res://tools/smoke_meadow_loop.gd
godot --headless --path . --script res://tools/test_vehicle_catalog.gd
godot --headless --path . --script res://tools/test_update_checker.gd
```

The last smoke test builds the whole race scene and walks three laps without a
window. It ends with `PASS  meadow loop builds and completes 3 laps`.
`tools/` is excluded from exported builds.

Optional generators:

```bash
python tools/gen_track_textures.py       # fallback grass/dirt tiles
python tools/build_foliage_atlases.py    # foliage cards + particle sprites
python tools/build_arena.py              # regenerate the sandbox arena
```

### Project layout

```
godot_project/
  scenes/ui/          menus, HUD, pause, settings, loading, room browser
  scenes/minigames/   grass_race.tscn (Meadow Loop)
  scenes/player/      cart_player.tscn
  scenes/dev/         driving_test.tscn (the playable arena)
  scripts/ui/         menus, UiAnim, MenuNav, StatBar, play cards
  scripts/minigames/  spline, foliage baker and race controller
  scripts/net/        network.gd (host / join / RPC)
  scripts/systems/    settings, update_checker, music, scene_loader
  scripts/vehicles/   catalog, visuals
  assets/ui/          theme, fonts, cursor
  assets/models/      Kenney Car Kit, Nature Kit, Poly Pizza, Poly Haven
  assets/audio/       SFX + optional music drop folder
  docs/               setup, platform, multiplayer, minigame, release docs
  tools/              generators, headless tests and screenshot probes
  version.txt         current version (updater + menu label)
  CHANGELOG.md        short player-facing release notes
```

### More docs

- `docs/MULTIPLAYER.md` - networking architecture
- `docs/PI_SERVER.md` - Pi provisioning and the console
- `docs/MEADOW_LOOP.md` - race design and start lights
- `docs/MINIGAMES.md`, `docs/PLATFORMS.md`, `docs/RELEASE_WORKFLOW.md`
- `docs/AI_ART_PROMPTS.md` - curated AI image prompts for game backgrounds
- `docs/ASSET_CREDITS.txt`, `docs/AUDIO_CREDITS.txt`

---

## Credits

- **Engine:** Godot Engine 4.7.2 (MIT).
- **Models:** Kenney *Car Kit* and *Nature Kit* (CC0), Poly Pizza go-kart and
  shopping-cart models, Poly Haven CC0 nature textures and scanned plants.
- **Audio:** Kenney *Impact Sounds*, *Digital Audio*, *Interface Sounds* (CC0),
  plus synthesized engine and skid loops.
- **UI:** Kenney *Cursor Pack* (CC0), Fredoka and Luckiest Guy fonts (SIL OFL).
- Full list: `docs/ASSET_CREDITS.txt` and `docs/AUDIO_CREDITS.txt`.
