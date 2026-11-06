# Cart Slop GP

A silly shopping-cart racing sandbox built in **Godot 4.7.2**.
Current version: **0.6.1**.

Drive a shopping cart (or a sedan, truck, van...) around a 140 × 140 m arena,
hit boost pads, drift, smash cones and crates, then host a shared sandbox and
invite a friend with a join code.

---

## Play it (no coding, no Godot)

1. Open **[github.com/HOT18594/CartSlopGP/releases/latest](https://github.com/HOT18594/CartSlopGP/releases/latest)**.
2. Download the zip for your computer:
   - **Windows** — `CartSlopGP_v0.6.1_windows.zip`
   - **Mac** — `CartSlopGP_v0.6.1_macos.zip`
   - **Linux** — `CartSlopGP_v0.6.1_linux.zip`
   - **Browser** — `CartSlopGP_v0.6.1_web.zip` (no multiplayer)
3. Unzip it, then:
   - **Windows:** double-click `CartSlopGP.exe`. If Windows SmartScreen warns,
     click **More info → Run anyway** (the build is unsigned and safe).
   - **Mac:** open `Cart Slop GP.app`. First time only: right-click the app →
     **Open**, then confirm. (Unsigned build; Gatekeeper needs the extra click.)
   - **Linux:** `chmod +x CartSlopGP.x86_64` then run it.
4. That's it. The game updates itself — see below.

### Updating

The game checks for updates when the main menu opens and shows an
**UPDATE AVAILABLE** button when there is a newer version:

1. Click it → **UPDATE NOW**. The game downloads the zip, unpacks it, swaps
   the files and restarts itself. There is no separate unzip step and no
   manual file copying.
2. A live %/MB progress bar runs during the download. **LATER** hides it.
3. If the automatic swap is blocked (for example, the game is inside a
   read-only folder), the dialog offers **OPEN RELEASE PAGE** instead.

The check uses GitHub Releases by default. If a Cart Slop Pi server is set
under **MULTIPLAYER → ADVANCED**, the game asks that Pi first and falls back
to GitHub when the Pi has no update mirror.

You can also force a check with **SETTINGS → CHECK FOR UPDATES**.

---

## Controls

| Action | Key |
| --- | --- |
| Accelerate | W / Up |
| Brake / reverse | S / Down |
| Steer | A / D or Left / Right |
| Handbrake (drift) | Space |
| Boost | Shift or Left Mouse |
| Reset cart | R |
| Pause | Esc |

Menus use the mouse. Hold a drift or the handbrake and the rear tyres leave
classic skid marks that slowly fade away.

## Multiplayer

**PLAY → MULTIPLAYER** opens the lobby:

- Type a name (up to 16 characters).
- Choose **ONLINE** (across the internet) or **WI-FI / LAN** (same network).
- **HOST A GAME** shows a 5-character room code when the Pi lobby server is
  found, or a 14-character direct address code otherwise.
- Your friend opens **MULTIPLAYER**, pastes the code into **JOIN**, and clicks
  **JOIN**. **BROWSE** lists open rooms from the Pi.
- The host picks SANDBOX or MINIGAMES, optional AI bots, and clicks
  **START SANDBOX / START RACE**. Changing the map only updates the lobby;
  START launches it.

Online hosting first looks for a Cart Slop Pi server. The Pi hands out a room
code and relays the session, so the host PC needs **no port forwarding** and
Windows Firewall does not block inbound UDP. Without a Pi, the game asks the
router for a UPnP mapping and falls back to a LAN code if that fails.

**If online join fails:** many routers block UPnP or sit behind carrier-grade
NAT. Three options that work reliably:

1. **Same Wi-Fi:** share the LAN code.
2. **Port forward:** forward the UDP port shown in the code to the host PC, put
   your public IP in **ADVANCED**, then host again.
3. **No router access:** run the Pi server, or use Tailscale/ZeroTier on both
   PCs and join the same virtual network with the LAN code.

### Cart Slop Pi server

A Raspberry Pi 4 on the same network runs the lobby + UDP relay:

- Console: **`http://cartslop.local:42777`**
- HTTP/API: TCP **42777**, discovery: UDP **42778**, relay: UDP **42800–42819**,
  host tunnel: TCP **42820**
- The host game opens an outbound tunnel to the Pi, so Windows Firewall never
  sees an inbound UDP packet. Friends connect to the Pi; the host needs no port
  forwarding. The Pi attempts UPnP/NAT-PMP for its own ports and reports
  whether the internet can actually reach it.
- The game has a built-in public fallback of **`68.204.45.1:42777`**. LAN
  discovery wins first; outside the house the game probes that address when a
  short room code is used. The public IP and router forwarding must stay
  valid; the console shows the current address and reachability.
- Vehicles can be changed from the multiplayer lobby or the minigame screen.
  The full picker shows each car's top speed, weight, acceleration, grip,
  steering, smoke, skid width and push strength.
- Optional update mirror: drop zips plus `updates/manifest.json` next to the
  server. See `pi_setup/cartslop-server/updates/README.md`.
- Server source is in `pi_setup/cartslop-server/`; setup notes are in
  `docs/PI_SERVER.md`.

## Vehicles

After **PLAY → SANDBOX** you can pick a vehicle; the choice is remembered.

| Vehicle | Weight | Top speed | Feel |
| --- | --- | --- | --- |
| Shopping cart | 45 kg | 19 m/s | no engine, quick, rattles, thin skids, little smoke |
| Sedan | 1.35 t | 23 m/s | balanced all-rounder |
| Sports car | 1.15 t | 27 m/s | fastest, best grip, loudest skids |
| Taxi | 1.45 t | 22 m/s | rattly, slightly sluggish |
| Van | 2.05 t | 20 m/s | heavy, more smoke, wider marks |
| Box truck | 3.2 t | 18 m/s | slow to spin up, plows props, huge marks |
| Police cruiser | 1.55 t | 25 m/s | quick V8 cruiser |

Weight is real: heavier vehicles accelerate slower, lose less speed when they
hit a wall, shake the camera less, and transfer more momentum (`p = m·v`) into
cones and crates. Each vehicle has its own engine loop (the cart has a wheel
rattle instead), smoke output and tyre-mark width. The minigame buggy is
intentionally not listed.

Vehicle audio ships with the game (original CC0 loops, generated by
`tools/gen_vehicle_loops.py`). Free libraries used for research and optional
replacements are listed in `docs/AUDIO_SOURCES.md`.

The main menu's **CHANGELOG** button shows the full version history.

## Music

Background music ships in `godot_project/assets/audio/music/`:

- `menu_loop.mp3`
- `sandbox_loop.mp3`
- `race_loop.mp3`

The folder's **README.md** contains loop tips and optional variants. If a track
is missing the game runs silently — nothing breaks.

## Minigames

**PLAY → MINIGAMES** shows only events that are actually playable.
**MEADOW LOOP** is the shipped event: three laps of a winding, 491 m dirt track
through a dense grassy forest, with three rivals and four boost pads. Pick a
vehicle and press **RACE**.

Every event card uses a real in-game screenshot. If an event has no real
preview, the screen draws no image; there are no invented "coming soon" cards.
New events appear only when their scene works.

In multiplayer the host can choose **MINIGAME SESSION** in the lobby, open the
map picker, and press START. The race loads for every peer with remote carts,
name labels, race positions and car-to-car collisions. The result card brings
everyone back to the lobby instead of restarting one player alone.

Solo play skips the old waiting room: the race loads, then the 3-2-1-GO
countdown plays. The race shows LAP / place badges on the normal HUD, lap times
and a result card with **RACE AGAIN**, **BACK TO HUB** and **MAIN MENU**.

The scenery is deliberately the heaviest scene in the game: procedurally built
PBR trees with CC0 Poly Haven bark, leaf and normal-map textures; scanned
ground-cover plants; wind-animated grass cards that bend away from the kart;
PBR dirt and meadow ground; 4x MSAA, ACES tonemapping and bloom. The kart kicks
up speed-scaled dust, drift/boost/landing bursts, lap confetti and drifting
leaves. Boost pads, pushable cones, flashing checkpoint gates, a five-lamp
start gantry and animated rivals all react as you drive.

The kart, drift, boost, camera, speedometer and pause menu are the same as the
sandbox. The loop is fenced by invisible barrier walls; if you somehow get out,
grass slows you down and the kart respawns on the track. Full design notes:
`docs/MEADOW_LOOP.md`.

---

## Development

### Requirements

- [Godot 4.7.2 stable](https://godotengine.org/download/) (standard build, not
  .NET) and the matching export templates (needed only for building).

### Open and run

1. Launch Godot 4.7.2.
2. **Import** → select `godot_project/project.godot` → **Import & Edit**.
3. Press **F5**.

### Export

From `godot_project/`:

```bash
GODOT="C:/Users/ethan/AppData/Local/Programs/Godot/Godot_v4.7.2-stable_win64_console.exe"

"$GODOT" --headless --path . --export-release "Windows Desktop" ../builds/v0.6.1/windows/CartSlopGP.exe
"$GODOT" --headless --path . --export-release "macOS"           ../builds/v0.6.1/mac/CartSlopGP.zip
"$GODOT" --headless --path . --export-release "Linux"           ../builds/v0.6.1/linux/CartSlopGP.x86_64
"$GODOT" --headless --path . --export-release "Web"             ../builds/v0.6.1/web/index.html
```

Then zip each platform folder as `CartSlopGP_v0.6.1_<platform>.zip`.
Full details, signing notes and the release checklist are in
`docs/PLATFORMS.md` and `docs/RELEASE_WORKFLOW.md`.

### Project layout

```
godot_project/
  scenes/ui/          menus, HUD, pause, settings, loading overlay
  scenes/minigames/   grass_race.tscn (Meadow Loop)
  scenes/player/      cart_player.tscn
  scenes/feedback/    smoke, wind, skid audio
  scenes/dev/         driving_test.tscn (the playable arena)
  scripts/            gameplay + UI scripts
  scripts/minigames/  spline, foliage baker and race controller
  scripts/net/        network.gd (host / join / RPC)
  scripts/systems/    game_settings, update_checker, music_player, scene_loader
  assets/ui/          theme, fonts, cursor
  assets/models/      Kenney Car Kit, Kenney Nature Kit, Poly Pizza props
  assets/audio/       SFX + optional music drop folder
  assets/textures/    particle sheets + generated grass/dirt ground tiles
  assets/materials/   checker, boost pad and tiled-surface shaders
  docs/               platform, multiplayer, minigame, release and credits docs
  tools/              asset generators and dev probes
  version.txt         current version (updater + menu label)
```

### Tests / probes

`tools/` holds small Godot scripts used during development (update checker
live checks, download-state inspection, installer template checks). They are
excluded from exported builds.

Asset generators and one headless test are also there:

```bash
python tools/gen_track_textures.py         # fallback grass/dirt tiles
python tools/build_foliage_atlases.py      # RGBA foliage cards + particle sprites
python tools/build_arena.py                # regenerate the sandbox arena
godot --headless --path . --script res://tools/smoke_meadow_loop.gd
```

The last one builds the whole Meadow Loop scene and walks three laps without a
window; it ends with `PASS  meadow loop builds and completes 3 laps`.

---

## Credits

- **Engine:** Godot Engine 4.7.2 (MIT).
- **Models:** Kenney *Car Kit* and *Nature Kit* (CC0) —
  [kenney.nl](https://kenney.nl/assets); Poly Pizza go-kart and shopping-cart
  models (see `assets/models/poly_pizza/CREDITS.txt`); Poly Haven CC0 nature
  textures and scanned ground-cover models — [polyhaven.com](https://polyhaven.com)
  (see `assets/models/polyhaven/CREDITS.txt`).
- **Audio:** Kenney *Impact Sounds*, *Digital Audio*, *Interface Sounds* (CC0),
  plus synthesized engine/skid loops. See `docs/AUDIO_CREDITS.txt`.
- **UI:** Kenney *Cursor Pack* (CC0), Fredoka font (SIL Open Font License 1.1).
- Full list: `docs/ASSET_CREDITS.txt`.
