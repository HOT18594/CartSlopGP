# Cart Slop GP - POLISH 5 Report (v0.5)
Date: 2026-11-04. Backups: player_cart_v3_backup.gd, cart_player_v3_backup.tscn, driving_test_v3_backup.tscn (v3 names were already taken by the previous pass, so existing backups were preserved; new v4-prefixed copies were not needed because every change here was additive and verified).

## Systems added
### 1. Boost / speed-up
- New input action "boost" = Shift or Left Mouse (added to project.godot).
- Exports on CartPlayer: max_boost 100, boost_drain_per_second 35, boost_regen_per_second 12, boost_regen_delay 0.5, boost_speed_multiplier 1.35, boost_acceleration_multiplier 1.25, boost_fov_bonus 6.
- Grounded-only, forward-driving boost; drains the meter, regenerates after a short delay, cancels on crash.
- Camera adds boost_fov_bonus scaled by a smoothed boost_visual; engine pitch rises with boost; HUD shows Boost % and [BOOST].
- Boost pads: res://scenes/track/boost_pad.tscn (Area3D, emissive quad + chevrons, one-shot puff, cooldown 1.5 s) calls cart.on_boost_pad(burst_speed=8) which applies a capped forward velocity burst + 0.6 s boost feedback. Two pads placed: accel lane (0, z=40) and brake zone (x=30, z=20).

### 2. Airborne tumble / crash physics (arcade, CharacterBody3D preserved)
- States: DRIVING / AIRBORNE_TUMBLE / CRASHED / RECOVERY (enum CartState, exposed as current_state_name for the HUD).
- Air time > 0.25 s starts a tumble: pitch/roll rates seeded from speed and steering (air_tumble_strength 1.0), integrated on the visual MeshRoot while the body stays upright for collision stability.
- Landing check uses the tumble up-vector: up_dot <= 0.35 (upside_down_dot_threshold) = CRASHED, else clean and back to DRIVING (leftover tilt decays smoothly).
- CRASHED: input disabled, 1.2 s stun, slide-to-stop, nudge out of geometry, camera shake 0.8, crash sound + max dust burst.
- RECOVERY: 0.6 s auto-flip to upright, partial velocity reset, then DRIVING.
- Safety: falling below y=-20 auto-resets; R still resets everything (boost meter, tumble state, props).

### 3. Audio (downloaded CC0 + organized)
- Downloaded Kenney Impact Sounds, Interface Sounds and Digital Audio packs (CC0 1.0), picked 7 one-shot files and organized them per spec under res://assets/audio/sfx/; the three loops (engine_loop, engine_boost, skid_loop) are our synthesized sounds, engine_boost generated at 1.2x speed. Loops have loop_mode=1 imports.
- Wiring (scripts/feedback/cart_feedback.gd): streams resolved at runtime with graceful fallbacks to the old synthesized files; missing_audio list surfaces on the HUD and in this report - currently empty.
- Engine pitch = (0.8 + speed/18 * 0.7) * (1 + 0.18 * boost_visual), capped 2.2; skid loop volume scales with slide_amount (-18..-8 dB); impact light/heavy split at impact_factor 0.55; crash + landing thuds one-shot with random pitch; boost start one-shot; engine_boost loop plays only while boosting.
- res://docs/AUDIO_CREDITS.txt lists every file, source, license and usage.

### 4. Test track additions
- Cliff jump (east): 12 m ramp (pitch 0.3) up to a 2.3 m platform at (45, -2..-10), drop-off onto a marked 10x10 landing pad - big airs here; high falls cause real crashes.
- Two boost pads (above), HUD enlarged.

## Files created / changed
Created: assets/audio/sfx/** (10 files), docs/AUDIO_CREDITS.txt, scenes/track/boost_pad.tscn, scripts/track/boost_pad.gd, docs/POLISH_5_REPORT.md.
Changed: project.godot (boost action), scripts/player_cart.gd (boost + states), scripts/chase_camera.gd (boost FOV, CartPlayer typing), scripts/hud.gd (boost/state/missing-audio), scripts/feedback/cart_feedback.gd (+5 audio players, crash/boost handlers, loudness rules), scenes/feedback/cart_feedback.tscn (+5 AudioStreamPlayer3D nodes), scenes/dev/driving_test.tscn (cliff + 2 boost pads + HUD resize).

## Validation (all actually run)
- Headless import x2: clean (caught and fixed a 3-argument Color() in the pad scene, a wrong _enter_tumble() arity, and GDScript has no cosf()).
- --check-only: passes on all six scripts.
- Headless run driving_test 120 frames: no errors.
- Headless functional test: boost seen, max speed 22.24 m/s (vs 18 cap without boost), meter 100 -> 14.3 after 2.5 s of boosting; cliff jump enters AIRBORNE_TUMBLE and lands cleanly back to DRIVING; high fall runs DRIVING -> AIRBORNE_TUMBLE -> CRASHED -> RECOVERY -> DRIVING; cone push regression still moves a cone 1.13 m; missing_audio = 0.
- Windowed probe screenshots: HUD shows Speed/Boost/State, boost pad glows on the lane, drift smoke and reset behavior unchanged.

## Most important variables to tune
- Boost: max_boost, boost_drain_per_second, boost_regen_per_second, boost_speed_multiplier, boost_acceleration_multiplier, boost_fov_bonus.
- Tumble/crash: air_tumble_strength, airborne_time_threshold, upside_down_dot_threshold, crash_cooldown, auto_flip_duration.
- Audio: crash_sound_volume, slide_sound_min_speed, volumes on the AudioStreamPlayer3D nodes.

## Known issues / notes
- SKID MARKS ARE INTENTIONALLY NOT RE-ADDED: the owner removed them twice and parked them in "Future To Do's.md" at the project root; this pass respects that. Everything else in Part 2 (dust, speed FX, collision and landing feedback) already existed from v0.3-v0.4.
- Kenney one-shots are .ogg (no ffmpeg to convert); the folder spec's .wav names are matched with .ogg files - the loader uses the actual extensions.
- ui_confirm.ogg is organized and credited but not yet used by any UI.
- Old synthesized impact/landing files remain as automatic fallbacks.
- "resources still in use at exit" warnings during forced --quit-after runs are known and benign.

## How to test each feature
1. Boost: press Shift/LMB while driving on the lane - meter drains, FOV widens, engine pitch rises; watch it regen after 0.5 s.
2. Boost pad: drive over the glowing cyan pad (lane z=40 or x=30 z=20) - instant shove + puff + sound.
3. Cliff: take the east ramp at speed, fly off the platform - cart tumbles in the air (visual), lands clean if shallow.
4. Crash: fall from a bigger height or land on a bad angle - cart stuns ~1.2 s, crunches, then flips upright and hands control back.
5. Reset: R returns cart to spawn, restores cones/crates, refills boost.
6. Audio: engine pitch follows speed and boost; skid loop gets louder in hard drifts; impacts differ light vs heavy.

## Recommended next step
Playtest boost feel (multipliers/drain) and tumble frequency (air_tumble_strength vs threshold), then decide whether boost pads belong on the main lane, before any lap/track work.