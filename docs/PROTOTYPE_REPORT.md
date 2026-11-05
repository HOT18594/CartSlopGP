# Cart Slop GP - Prototype Report (v0.1)
Date: 2026-11-04. Scope: single-player driving prototype only - no multiplayer, no networking, no laps, no items, no AI racers, no realistic VehicleBody3D physics.

## Files created
| File | Purpose |
| --- | --- |
| res://scenes/dev/asset_preview.tscn | Lineup of imported models (2 Kenney karts, Poly Pizza go-kart, shopping cart, cone, wheel) with Label3D names |
| res://scenes/dev/driving_test.tscn | 100x100 m test arena: ground, perimeter walls, spawn point, 6 collidable cones, one small ramp, HUD |
| res://scenes/player/cart_player.tscn | CharacterBody3D cart: collision box, MeshRoot with kart model, SpringArm3D camera |
| res://scripts/player_cart.gd | Arcade movement (typed GDScript, move_and_slide) |
| res://scripts/hud.gd | HUD label: live speed + controls + reset hint |
| res://scenes/dev/screenshot_probe.tscn + res://scripts/gameplay_probe.gd | Dev-only: auto-drives the cart, saves a screenshot, quits. Safe to delete |
| res://scenes/dev/preview_probe.tscn + res://scripts/preview_probe.gd | Dev-only: screenshots the asset preview. Safe to delete |
| project.godot | Input map + run/main_scene added |

Note: the task brief assumed the input actions already existed, but project.godot had none - they were added: accelerate (W/Up), brake (S/Down), steer_left (A/Left), steer_right (D/Right), handbrake (Space), reset_cart (R), pause (Esc).

## Kart selected
- kart-oozi.glb from the Kenney Car Kit (actual file verified before use).
- Measured GLB bounds: 0.97 wide x 1.33 tall x 1.43 long, origin at ground level; includes the driver figure.
- Scaled x1.541 to about 1.5 m wide x 2.2 m long. Collision box 1.35 x 1.10 x 2.09 m - height capped at 1.1 m so the driver's head does not bloat the collider.
- The model is rotated 180 deg so its authored +Z front matches Godot's -Z forward. Verified visually: while driving forward you see the kart's rear.

## How to open and run
1. Open C:\Users\ethan\Downloads\CartSlopGP\godot_project in Godot (editor: C:\Users\ethan\Downloads\CartSlopGP\downloads\godot_editor\Godot_v4.7.2-stable_win64.exe).
2. Press F5 - the main scene is already set to res://scenes/dev/driving_test.tscn. Or open that scene and press F6.
3. For the model lineup, open res://scenes/dev/asset_preview.tscn and press F6.

## Which scene to play first
res://scenes/dev/driving_test.tscn

## Validation performed (Godot 4.7.2.stable)
- Headless re-import: exit 0, no errors.
- --check-only on all four scripts: pass.
- Headless smoke runs: driving_test 90 frames, asset_preview 20 frames - no errors or warnings.
- Windowed probe (Vulkan, Forward Mobile renderer): the cart auto-drove from z=20.0 to z=8.3 in 70 physics frames and capped at exactly 16.0 m/s; HUD showed 58 km/h; screenshots confirmed kart facing, scale, cones/walls/ramp rendering, and preview labels.

## Known issues / notes
- The Poly Pizza go-kart reads smaller than the Kenney karts at the same 1.8 m target length (part of its length is a thin flag pole, and it is much sleeker). It is display-only for now.
- The Poly Pizza shopping cart file is authored in enormous raw units (about 467,000 per length) and is normalized with a very small node scale (~2.6e-6). Fine for previewing; consider re-exporting at a sane scale before using it in gameplay.
- Cones use simple cylinder colliders; nothing else in the arena blocks the cart except walls and the ramp.
- HUD speed is horizontal speed in km/h.
- In the preview scene, the grey band at the horizon is the sky's ground hemisphere, not missing geometry.
- The dev probe scenes print to stdout and save PNGs next to the workspace; they are not referenced by gameplay.

## Tuning guide (all @export on the CartPlayer root, res://scripts/player_cart.gd)
- Too slow: raise max_speed (16.0) and/or acceleration (18.0).
- Too fast: lower max_speed.
- Too slippery / coasts forever: raise friction (8.0).
- Too stiff / unresponsive: raise turn_speed (2.4). Steering reaches full power at half of max speed by design (the minf(speed_fraction * 2.0, 1.0) line).
- Brakes too weak: raise brake_power (24.0).
- Too floaty on the ramp: raise gravity (20.0).
- Camera too close/far: SpringArm3D spring_length (6.5) in cart_player.tscn; camera height/pivot on the CameraArm node transform.
- Body lean: mesh_tilt_amount (0.07, radians); set 0 to disable, flip the sign in _apply_mesh_tilt for lean-out.
- Reverse speed: reverse_speed (6.0); note brake first reverses only after stopping.