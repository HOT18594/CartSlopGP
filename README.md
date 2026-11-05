# Cart Slop GP

An arcade cart-racing prototype built in **Godot 4.7.2** (GDScript, Mobile renderer).
Current version: **0.2.0**.

The repo is UI + tooling + the existing driving prototype: main menu, pause/settings,
in-game HUD, custom cursor, Windows export and a free in-game update checker that uses
GitHub Releases. Gameplay systems (handling, jumps, drift smoke, boost) are unchanged
from the prototype.

## Requirements

- Windows 10/11
- [Godot 4.7.2 stable](https://godotengine.org/download/windows/) (standard build, not .NET)
- The export templates for 4.7.2 (only needed to build the .exe)

## Open in Godot

1. Launch Godot 4.7.2.
2. **Import** → select `godot_project/project.godot` → **Import & Edit**.
3. Press **F5** to run. The project boots into the main menu; **PLAY** opens the
   mode select (SANDBOX works today, HOST/JOIN are multiplayer placeholders).

The first open reimports assets into `.godot/`; that folder is git-ignored.

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

In menus: mouse. The custom cursor is drawn by the game, so the OS pointer is hidden
while a menu is open.

## Build the Windows .exe

**From the editor:** Project → Export → *Windows Desktop* → *Export Project*.
Uncheck *Export With Debug* for a release build.

**From the command line** (from `godot_project/`):

```bash
godot --headless --export-release "Windows Desktop" "../builds/v0.1.0/CartSlopGP.exe"
```

The build lands in `CartSlopGP/builds/v0.1.0/` and contains `CartSlopGP.exe` plus
`CartSlopGP.pck`. Zip that folder to publish it. See `docs/RELEASE_WORKFLOW.md`.

## Auto-updates

`scripts/systems/update_checker.gd` runs as the `UpdateChecker` autoload. On the main
menu it asks the GitHub API for the latest release (5 s timeout). Offline or rate-limited
means the check is skipped silently — the game never blocks on the network.

When a newer tag exists, the menu shows an **UPDATE AVAILABLE vX.Y.Z** button:

1. opens the release page in the browser,
2. or downloads the release zip into `user://updates/`,
3. and can hand the swap to a generated `update_install.bat` (a running .exe cannot
   overwrite itself on Windows, so the .bat waits for the game to exit, copies the
   staged files over, restarts, and deletes itself).

Set the owner/repo once in `scripts/systems/update_checker.gd` (currently
`HOT18594/CartSlopGP`).

## Multiplayer (host / join)

Play -> HOST GAME opens a lobby with a 12-character join code.

- Host: opens a UDP port (8910+), asks the router for a UPnP mapping, and shows
  the code. If UPnP is unavailable the code uses the LAN address; sharing over
  the internet then needs UDP port forwarding (the port is in the code).
- Join: paste the code (or an `ip:port` address) into the lobby.
- Host presses START SANDBOX; late joiners drop straight in.

Design: each player simulates their own cart and streams its transform at
20 Hz; the host simulates props and broadcasts them at 10 Hz. Ping is measured
every two seconds and shown in the lobby. All of it is free and serverless -
ENet over UDP directly between players.

## Vehicles

SANDBOX leads to a vehicle picker (`scenes/ui/vehicle_select.tscn`). The catalog
lives in `scripts/vehicles/vehicle_catalog.gd`; add an entry there to offer a new
model. The selection is stored in `user://settings.cfg` and swapped onto the
player at spawn by `player_cart.gd`. The special minigame kart is not listed.

## HUD for minigames

The HUD ships with race position and lap pills that stay hidden in the free-drive
prototype. For a race minigame, instance `scenes/ui/hud.tscn` and either set
`show_position_badge` / `show_lap_badge` in the inspector or call:

```gdscript
hud.set_race_position(1)   # 1st, 2nd, 3rd...
hud.set_lap(2, 3)          # LAP 2 / 3
```

## Project layout

```
godot_project/
  scenes/ui/          main menu, HUD, pause, settings
  scenes/player/      cart_player.tscn
  scenes/feedback/    smoke, wind, audio
  scenes/dev/         driving_test.tscn (the playable prototype)
  scripts/            gameplay + UI scripts
  scripts/systems/    update_checker.gd
  assets/ui/          theme, fonts, cursor
  assets/models/      Kenney Car Kit, Poly Pizza props
  assets/audio/       Kenney CC0 SFX + synthesized loops
  assets/textures/    particle sheets
  docs/               credits, reports, release workflow
  tools/              asset generators (smoke sheet)
  version.txt         current version (read by the updater + menu)
```

## Credits

- **Engine:** Godot Engine 4.7.2 (MIT).
- **Models:** Kenney *Car Kit* (CC0) — [kenney.nl](https://kenney.nl/assets/car-kit).
  Poly Pizza go-kart and shopping-cart models (see `assets/models/poly_pizza/CREDITS.txt`).
- **Audio:** Kenney *Impact Sounds*, *Digital Audio*, *Interface Sounds* (CC0), plus
  synthesized engine/skid loops. Full table in `docs/AUDIO_CREDITS.txt`.
- **UI:** Kenney *Cursor Pack* (CC0), Fredoka font (SIL Open Font License 1.1).
- Full list: `docs/ASSET_CREDITS.txt`.

## Repo

https://github.com/HOT18594/CartSlopGP
