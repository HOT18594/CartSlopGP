# Meadow Loop - minigame design

Status: **implemented and playable** (v0.4.2 tree, unreleased).

`PLAY -> MINIGAMES -> FREE PLAY -> MEADOW LOOP -> PLAY`.

A solo 3-lap race on a winding dirt loop cut through a very dense low-poly
grassy forest. It reuses the sandbox kart, chase camera, boost/drift physics,
HUD, pause menu and candy UI theme. No multiplayer code is involved.

## Track

`scripts/minigames/track_spline.gd` generates a closed Catmull-Rom centreline
from a radial "wobbly ellipse" (20 control points, 20 samples per segment):

| Property | Value |
| --- | --- |
| Length | 491.4 m |
| Samples | 400 (~1.2 m apart) |
| Road width | 11 m (`ROAD_HALF = 5.5`) |
| Minimum corner radius | ~19 m |
| Minimum self-separation | 17.8 m |
| Bounds | x -83..90, z -77..61 m |

The radial formulation guarantees the loop winds without self-intersecting,
which matters because the lap counter projects the kart onto the nearest
centreline point.

`scripts/minigames/grass_race.gd` builds everything else at runtime from that
one spline, so the `.tscn` stays tiny:

- **Ground** - 1400 x 1400 m plane with a tileable generated grass texture,
  plus a flat box collider. Exponential fog hides the horizon.
- **Road** - one ribbon mesh with a tileable generated dirt texture, plus
  alternating red/white candy curbs baked as vertex colours.
- **Barriers** - one invisible `ConcavePolygonShape3D` walls both edges of the
  loop. The kart physically cannot leave the ribbon.
- **Start/finish** - a checker-shader line at `s = 0` and a gantry with a
  checkered strip and a `START / FINISH` Label3D.
- **Sector gates** - three more gantries at L/4, L/2 and 3L/4.
- **Countdown** - 3 / 2 / 1 / GO, with the kart frozen until GO.

## Lap logic

Completing **3 laps wins**. Progress is unwrapped arc length from the nearest
spline point:

1. `closest()` projects the kart onto every centreline segment (400 per frame).
2. The change in `s` is wrapped at L/2, then clamped to a frame's plausible
   travel distance, so a hairpin cannot teleport the counter forward.
3. A lap only counts when unwrapped distance reaches `lap * L` **and** all four
   sector flags were visited. Reversing over the line or shortcutting does not
   score.
4. Teleports (R reset, off-track respawn) resync `s` without banking distance.

Grass slowdown and auto-respawn are a fallback; the barrier walls are the
primary constraint.

## Ghost rivals

Three Kenney kart models follow the centreline at 11.6 / 12.4 / 13.2 m/s with
fixed lateral offsets. They are visual ghosts with no collision, start slightly
ahead, and stop after three laps. They drive the HUD's position badge and the
result card's finishing place, but they never gate the win condition.

## Scenery

`assets/models/kenney_nature-kit/` holds 87 curated CC0 GLB models from Kenney
*Nature Kit* 2.1: 38 tree variants, bushes, grass clumps, wildflowers, rocks,
stumps, logs, mushrooms and a fence.

`scripts/minigames/foliage_baker.gd` flattens every surface of a GLB into one
`ArrayMesh`, baking each surface's base colour into `ARRAY_COLOR`, then draws it
with one `MultiMeshInstance3D` per model (~75 draw calls for ~8,600 instances).
It also warms Kenney's teal `leafsGreen` palette into real greens and applies
per-instance tints for autumn/shaded/sunlit crowns.

Scatter is seeded (`20261105`) and deterministic. 64 % of instances land in a
9-55 m verge band along the track, the rest fill the wider field. A spatial
hash over the centreline rejects anything too close to the road. Small clutter
does not cast shadows.

Counts: 2,700 trees, 1,500 bushes, 4,200 grass clumps, 1,100 wildflowers,
520 rocks, 280 woodland props, ~110 trackside markers.

## Generated assets

`tools/gen_track_textures.py` writes two seamless 256 px CC0 textures:
`assets/textures/grass_field.png` and `assets/textures/dirt_track.png`. They are
tiled by `assets/materials/tiled_surface.gdshader`, which uses `repeat_enable`
so wrapping does not depend on the texture importer's repeat setting.

## UI

The race instance of `scenes/ui/hud.tscn` turns on `show_lap_badge` and
`show_position_badge`. `grass_race.gd` builds the rest of the overlay in code:

- big outlined countdown and lap-time toasts,
- an `OFF TRACK` warning,
- a result card with a checkered flag, `YOU WIN!`, total / best lap / finishing
  place / per-lap times, and three candy buttons:
  **RACE AGAIN**, **MINIGAMES**, **MAIN MENU**.

All navigation goes through the `SceneLoader` autoload so the themed loading
overlay appears. Finishing returns to the minigames hub as
`docs/MINIGAMES.md` requires.

The minigame honours `GameSettings.minigame_vehicle`: the race swaps it into
`selected_vehicle` in `_enter_tree()` (before the kart's `_ready` reads it) and
restores the sandbox choice in `_exit_tree()`. Nothing is written to
`user://settings.cfg`.

## Testing

```bash
godot --headless --path . --script res://tools/smoke_meadow_loop.gd
```

Builds the full scene, asserts the spline length and foliage density, walks the
kart around the loop three times, and asserts three lap times plus the visible
result card. Expected output ends with
`PASS  meadow loop builds and completes 3 laps`.
