# Cart Slop GP - Polish Report (v0.2)
Date: 2026-11-04. Scope unchanged: single-player only - no multiplayer, networking, laps, items, AI, or realistic vehicle physics.

## Backups (made before any modification)
- res://scripts/player_cart_v1_backup.gd
- res://scenes/player/cart_player_v1_backup.tscn
- res://scenes/dev/driving_test_v1_backup.tscn
Note: the backed-up scenes reference the live script path, so the .gd backup is the true v1 code.

## What was changed / new systems
1. Movement - scripts/player_cart.gd rewritten (velocity-based):
   - Forward and lateral velocity components handled in the cart's local frame.
   - Acceleration tapers near top speed (smooth curve); rolling momentum when you release throttle (friction 6.0).
   - Lateral grip cancels slip; holding handbrake swaps grip to drift_grip (2.5) for slidey drifts, plus mild speed scrub.
   - Speed-sensitive steering: no turning at standstill, full authority at min_turn_speed (3.0 m/s), scales down to high_speed_steering_scale (0.65) at top speed; reversing inverts steering.
   - Slight lateral slip emerges when turning hard (body rotates faster than grip cancels).
   - Air control (air_control_strength 0.35), extra fall gravity (x1.6) and a landing stability assist (bleeds 60% of sideways speed on touchdown).
   - Collision recoil: speed loss proportional to impact, small capped bounce away from the surface, 0.25 s cooldown, ignored below 2.5 m/s.
2. Chase camera - NEW scripts/chase_camera.gd (on the CameraArm SpringArm3D):
   - Yaw lag with velocity-direction lookahead (0.35) and steer lookahead (0.22 rad).
   - Speed response: FOV 70 -> 82, boom 6.5 -> ~7.7 m, pivot drops 0.3 m at top speed.
   - Position lag is folded into the boom length; shake uses Camera3D h_offset/v_offset. (A first attempt wrote camera.position directly, which fights the SpringArm's child placement and collapsed the camera into the kart - caught by the probe screenshot and fixed.)
   - add_shake() fires on impacts and hard landings, exponential recovery.
3. Squash & stretch - MeshRoot only, hard-capped at 8%:
   - Stretch on hard acceleration (strongest at launch), squash on braking, squash impulse on landings/impacts, stretch impulse on ramp launches, lean into turns, nose up/down on throttle/brake, smooth exponential return.
   - The Kenney kart GLB is one welded mesh (wheels not separated), so wheel spin/steer was skipped per the brief's "skip rather than make it unstable".
4. Arena v2 - scenes/dev/driving_test.tscn (140x140 m):
   - Perimeter walls, safe spawn at the south edge.
   - Slalom (4 cones) on the way north, narrow gate (2 crates, ~3.7 m gap), ramp with green landing pad, 2 rollers, chicane (4 cones) on the east side, crate stack + scattered crates (box colliders), 5 debris props (decor only), 14 cones total.
   - Greybox materials: grey ground, blue-grey walls, dark ramp/rollers, green landing pad.
5. Debug HUD - scripts/hud.gd: speed, state (GROUNDED/AIRBORNE/DRIFTING), live FOV, handbrake indicator, reset prompt.

## Files created or changed
- scripts/player_cart.gd (rewritten, class_name CartPlayer)
- scripts/chase_camera.gd (new, class_name ChaseCamera)
- scripts/hud.gd (extended)
- scripts/gameplay_probe.gd (dev-only; now tests drift + reset. Safe to delete)
- scenes/player/cart_player.tscn (camera rig script attached)
- scenes/dev/driving_test.tscn (new arena)
- res://docs/POLISH_REPORT.md (this file)

## Validation performed (Godot 4.7.2.stable)
- Headless import: exit 0, no errors.
- --check-only: passes on player_cart.gd, chase_camera.gd, hud.gd, gameplay_probe.gd.
- Headless smoke runs: driving_test 120 frames, asset_preview 20 frames - no errors.
- Windowed probe (Vulkan, Forward Mobile): auto-accelerate -> handbrake drift -> reset.
  PROBE_DRIFTING=true, speed scrubbed 15 -> 7.3 m/s under handbrake, HUD showed "DRIFTING / FOV 74.0 / Handbrake ON", reset restored the spawn exactly (0, ~0, 55) and FOV returned to 70. Screenshots verified drift framing, body lean, arena sections, and clean post-reset state.

## Most important variables to tune (all @export, Inspector on CartPlayer / CameraArm)
- Drift feel: drift_grip (2.5, lower = slidey), lateral_grip (10.0, higher = grippier)
- Steering: steering_speed (2.6), high_speed_steering_scale (0.65), min_turn_speed (3.0)
- Top end: max_speed (18.0), acceleration (16.0), friction (6.0)
- Camera: smoothing_speed (5.0), look_ahead_strength (0.35), steer_look_ahead_strength (0.22), fov_speed_multiplier (12.0)
- Shake: shake_max_offset (0.22), shake_decay (4.0)
- Impacts: impact_speed_loss (0.35), impact_recoil (0.45), max_recoil_speed (3.0)

## How to test the new feel
1. Press F5. Hold W down the long straight: feel the acceleration taper, FOV widen, camera pull back.
2. At speed, hold Space + steer: the kart slides (HUD switches to DRIFTING) and the camera leads the slide.
3. Aim for the ramp past the gate: stretch on launch, squash + small shake on landing.
4. Ram a cone, crate or wall: small speed loss, gentle nudge away, quick shake.
5. Press R anywhere: everything (position, motion, camera, FOV, shake, squash) resets cleanly.

## Known issues
- Debris props are decor only (no collision).
- No wheel spin/steer animation (welded Kenney mesh).
- The cart can be bounced oddly by roller edges at extreme speed if you clip a corner - press R.
- Backed-up v1 scenes reference the live script; use player_cart_v1_backup.gd for the true v1 code.

## Quick tuning reference
- Too slow: max_speed 18 -> 22, acceleration 16 -> 20
- Too fast: max_speed 18 -> 14
- Too slippery: lateral_grip 10 -> 14, drift_grip 2.5 -> 4.0
- Too stiff: steering_speed 2.6 -> 3.2, min_turn_speed 3.0 -> 2.0
- Too floaty: gravity 22 -> 26, extra_fall_gravity 1.6 -> 2.0
- Too shaky: shake_max_offset 0.22 -> 0.10, shake_decay 4.0 -> 6.0