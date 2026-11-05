# Cart Slop GP - Feedback Report (v0.3)
Date: 2026-11-04. Scope: single-player only - no multiplayer, networking, laps, boost system, items, or final art.

## Backups (made before any modification)
- res://scripts/player_cart_v2_backup.gd (class_name line stripped - see Known Issues)
- res://scenes/player/cart_player_v2_backup.tscn
- res://scenes/dev/driving_test_v2_backup.tscn

## What feedback systems were added
1. Skid marks - scenes/feedback/skid_mark.tscn + scripts/feedback/skid_mark_pool.gd:
   - Fixed pool of 80 quads (hard cap; the oldest mark is recycled when full - never unbounded).
   - Spawned by distance travelled (0.45 m spacing) at both rear wheel offsets, aligned to the travel direction, only while grounded.
   - Conditions: drifting, handbraking, hard braking above 9 m/s, or |steer| > 0.65 at speed.
   - Fade out over skid_lifetime (4 s) via per-instance transparency; dark grey, alpha 0.5, unshaded, no shadows.
2. Dust - GPUParticles3D in scenes/feedback/cart_feedback.tscn:
   - Continuous dust behind the rear axle while: accelerating below 6 m/s (launch), above 11 m/s (speed), drifting/handbraking (x1.6 density).
   - One-shot burst emitter (DustBurst) for landings (strength scales with fall speed) and collisions.
   - Grey/tan billboards, alpha ramp fade, cast shadows off.
3. Speed feedback:
   - Wind streak particles parented to the camera transform above 12 m/s, density ramps with speed, very subtle (alpha 0.16 thin sticks).
   - Speed-based FOV (70 -> 82) and boom length already existed from the v2 camera and remain.
4. Collision & landing feedback:
   - Existing camera shake + mesh squash retained; impacts now also fire a dust burst + impact sound; landings fire a dust burst + thud + shake.
5. Audio hooks - AudioStreamPlayer3D nodes under the Feedback component:
   - EngineAudio: seamless 2 s engine loop, autoplay, pitch scales 0.8 -> 1.5 with speed.
   - SkidAudio: seamless 1.4 s skid loop, paused/unpaused with the slide state.
   - ImpactAudio / ThudAudio: one-shots with slight random pitch.
   - BoostPlaceholder: node exists with no stream - hook for the future boost system.
   - All four WAVs were synthesized procedurally for this project (see docs/AUDIO_CREDITS.txt); engine + skid imported with forward looping.
6. Modular component - scripts/feedback/cart_feedback.gd (class_name CartFeedback):
   - Reads cart state (speed, grounded, drifting, inputs) from its parent; events pushed via on_collision() / on_landing(); reset_feedback() clears marks, particles, and audio states.
7. Toggles - all @export booleans on the Feedback node: enable_skid_marks, enable_dust, enable_speed_feedback, enable_collision_feedback, enable_audio.
8. Test scene - driving_test.tscn now has a collision barrier (8x1.2x1 m) straight ahead past the ramp landing area, so impacts are easy to trigger. Ramp, slalom, gate, chicane and the long spawn straight were already in place.
9. Debug HUD - new line: Skids count, Dust on/off, Speed FX on/off.

## Files created or changed
- NEW: scripts/feedback/cart_feedback.gd, scripts/feedback/skid_mark_pool.gd
- NEW: scenes/feedback/cart_feedback.tscn, scenes/feedback/skid_mark.tscn
- NEW: assets/audio/engine_loop.wav, skid_loop.wav, impact.wav, landing_thud.wav (+ generated .import files; loops enabled)
- NEW: docs/FEEDBACK_REPORT.md, docs/AUDIO_CREDITS.txt
- CHANGED: scripts/player_cart.gd (feedback hooks in collision/landing/reset), scripts/hud.gd (debug line), scripts/gameplay_probe.gd (dev-only probe), scenes/player/cart_player.tscn (Feedback instance), scenes/dev/driving_test.tscn (barrier)
- BACKUPS: player_cart_v2_backup.gd, cart_player_v2_backup.tscn, driving_test_v2_backup.tscn

## Validation performed (Godot 4.7.2.stable)
- Headless import x2 (second pass applies the WAV loop-mode patch): exit 0, no errors.
- One real issue was caught and fixed here: the v2 backup script still declared class_name CartPlayer, which "hides a global script class" and broke the live script load during import. The class_name line was stripped from the backup; import is clean since.
- --check-only passes on all six scripts.
- Headless smoke runs: driving_test 120 frames, asset_preview 20 frames - no errors.
- Windowed probe (Vulkan): drift phase HUD showed "Skids: 14  Dust: on  Speed FX: off" (thresholds correct at 7.3 m/s); reset restored spawn exactly, Skids 0, engine audio confirmed playing; fast straight reached 14.4 m/s with Dust on, Speed FX on, FOV 77.7. Screenshots verified all three phases.

## Most important variables to tune (all @export on the Feedback node in cart_player)
- Skids: skid_spawn_spacing (0.45), skid_lifetime (4.0), wheel_offset (0.62, 0.62), skid_sharp_steer (0.65)
- Dust: dust_intensity (0.8), dust_high_speed_threshold (11.0), dust_launch_speed_threshold (6.0), landing_burst_strength (1.0)
- Speed FX: wind_speed_threshold (12.0)
- Audio loudness: volume_db on each AudioStreamPlayer3D node (Engine -12, Skid -10, Impact -5, Thud -7)

## What is missing (especially audio)
- The engine/skid loops are simple synthesized tones/noise - serviceable placeholders, not real recordings. To upgrade: replace the stream on EngineAudio/SkidAudio with any CC0 loop and keep the node names.
- BoostPlaceholder has no stream yet (future boost system).
- No music, no engine rev layers beyond pitch scaling.

## Known issues
- Occasional benign "ObjectDB instances leaked / resources still in use" warning at forced process exit (--quit-after in the probe); it correlates with active looping audio at kill time and did not reproduce on every run. Normal window close is unaffected; no gameplay impact.
- Skid marks are intentionally subtle; darken the material in scenes/feedback/skid_mark.tscn if you want them louder.
- Skid quads assume flat ground (fixed height above the cart origin) - fine in this arena.
- Dust particles are plain billboards; swap in a soft round texture later for nicer puffs.

## Recommended next step
Playtest with all toggles on, tune the exported values, then replace the placeholder audio with real CC0 recordings (Kenney audio packs are a good start) before moving on to any lap/track work.
## v0.3.1 - Feel fix pass (playtest feedback)
Date: 2026-11-04. Backups: cart_feedback_v3_backup.*, skid_mark_pool_v3_backup.*, skid_mark_v3_backup.* (in scripts/feedback and scenes/feedback).

1. Smoke no longer squares: added a procedurally generated soft cloud texture (assets/textures/smoke_puff.png, blobby blurred alpha, random per-particle rotation). Dust draw pass now uses it; puffs also scale with life and drift upward slightly.
2. No more smoke trail while normally driving: removed the high-speed dust condition entirely. Continuous smoke now ONLY while drifting/handbraking (tire smoke, hovering above the marks). Launch wisp is minimal: only below 3.5 m/s off the line at ~15% density. Crash and landing bursts are bigger and softer (36 particles, larger scale, longer life).
3. Skid marks rewritten as continuous tire lines: the pool now stamps thin connecting segments between successive rear-wheel samples (0.25 m spacing) instead of dashed quads - lines follow the drift arc with no gaps or circling. Pool raised to 600 segments (still hard-capped), 10 s life, fade in the last 40%. Lines are darker and wider (0.34 m, alpha 0.85 core fading) and sit just above the ground (no z-fighting).
4. Smoothness / no clipping: the camera boom (SpringArm3D) now uses a 0.45 m sphere cast shape, so the camera keeps its clearance from walls, props and the kart; impact recoil default lowered 0.45 -> 0.32; camera shake softened (max offset 0.22 -> 0.14, decay 4.0 -> 5.5).
5. Renames: dust_high_speed_threshold removed (no speed dust), dust_launch_speed_threshold -> launch_dust_speed (3.5), skid_spawn_spacing -> skid_segment_spacing (0.25), dust_intensity -> smoke_intensity (0.8).
Validation: headless import clean, all six script checks pass, headless smoke run clean, windowed probe re-verified: drift = 24 skid segments + smoke + engine audio; normal fast drive = Dust OFF, Speed FX on (PROBE_FAST_DUST=false); reset clears segments to 0. Screenshots confirm soft smoke and visible tire lines.

## v0.3.2 - Smoke plumes + skid ribbon redo
Date: 2026-11-04. Backups: cart_feedback_v031_backup.gd / cart_feedback_v031_backup.tscn.

### Smoke (dynamic plumes, not circles)
- New 16-frame animated flipbook texture (assets/textures/smoke_sheet.png, 4x4 grid): each frame is a different churning blob pattern; blobs grow, rise and dissipate across the strip, so every particle visibly evolves from birth to fade instead of being one static circle.
- GPU turbulence enabled on both smoke materials (strength 0.8 drift / 1.2 crash): puffs curl and wander around the kart instead of moving in straight lines.
- Random per-particle rotation + angular velocity (-50..50 deg/s; bursts -80..80) so puffs tumble.
- Scale curve (0.35 -> 1.7 over life) makes plumes swell as they rise; color ramp now fades IN (0 -> 0.5 -> 0.32 -> 0) so smoke appears softly, lingers, then dissipates.
- Burst emitter upgraded (40 particles, bigger scale, longer life) for crash/land fog.
- Emitter raised above the tire marks so smoke floats over them, not on them.

### Skid marks (complete redo - why the old one failed, and what replaced it)
Why the pooled-quad approach kept looking broken:
1. Dashed quads: separate rectangles at fixed spacing can never look like a continuous tire line; at speed they read as blobs.
2. Spawned under the visible wheel: the newest quad appeared exactly beneath the leaning kart body, so it looked stuck under the tire.
3. Flat-world height: marks were stamped at cart-origin height + offset, which z-fought with the landing pad and sank into the ramp.
4. Recycle holes: when the pool filled, the oldest marks were stolen, so lines got holes mid-trail.
5. Alignment mismatch: quads aligned to velocity while the body yawed gave the odd circling impression.

The replacement (scripts/feedback/skid_trail.gd, class_name SkidTrail):
- Per-wheel ImmediateMesh ribbons: each rear wheel keeps a ring buffer of world-space samples (0.18 m spacing, 320 samples = ~57 m of line per wheel) drawn as one continuous triangle strip.
- Every sample raycasts straight down (cart body excluded) and stamps the ribbon onto the REAL ground surface - correct height on flats, the landing pad and ramps; no z-fighting.
- Per-vertex age fade: samples hold full darkness for 60% of their life, then fade smoothly over the last 40% (8 s total) - no popping.
- Gap-aware: if the wheel stops sliding, goes airborne, teleports or resets, the strip is broken and a new one starts on the next slide - lines never jump across gaps.
- The pooled-quad system (skid_mark.tscn, skid_mark_pool.gd) was removed entirely.
Validation: import clean (a malformed hand-written Curve sub-resource was found via the engine's ELEMS error and fixed by asking Godot to save the canonical Curve format: Array of Vector2+offset/value plus tangents/modes per point, and Curve max_value had to be raised to 2.0 for the growth curve), all six script checks pass, headless run clean, probe: drift = 32 ribbon samples + smoke + audio, normal fast drive = Skids 0 / Dust off / Speed FX on, reset = 0 samples. Screenshots confirm soft plumes and a continuous dark tire line.

## v0.3.3 - Skids removed, smoke plumes reworked
Date: 2026-11-04. Backups: cart_feedback_v032_backup.gd / .tscn.

1. Skid marks REMOVED entirely per owner decision (the ribbon pass still looked bad under the tire). Removed: enable_skid_marks toggle, SkidTrail nodes, skid_trail.gd (deleted), all skid exports/logic, the HUD Skids field and probe prints. The skid SOUND remains: slide_sound_min_speed (4.0) now gates it. A handoff note lives at CartSlopGP\Future To Do's.md (what was tried, why it failed, ideas for a future attempt). The skid ribbon code is preserved in the v031/v032 backups.
2. Smoke reworked into drifting plumes with a subagent-designed flipbook:
   - New 16-frame atlas (assets/textures/smoke_sheet.png): S-curved smoke columns that stretch, tear and shed side wisps as the animation plays - no more round blobs.
   - Fake-fluid motion (cheap Navier-Stokes feel): buoyancy gravity (0, 1.6, 0) + damping 1.4-2.4 (puffs rise ~1.5 m and slow), turbulence 0.9/2.2/2.6 with influence 0.25-0.6 (curl paths), gentle orbit swirl (+-0.18), random spin +-35 deg/s, lifetime randomness.
   - Plume shape: scale curve 0.35 -> 1.7 over life (Curve max_value raised to 2.0), quad 1.1 m, billboard_keep_scale, emission from a small box across the rear tread, fade-IN ramp so smoke appears softly and lingers.
   - Crash/landing burst uses the same plume look with stronger turbulence.
3. Validation: import clean (the hand-written Curve serialization was corrected to the canonical Vector2+tangents format after the engine flagged it), all five script checks pass, headless run clean, probe: drift smoke on with drifting wisps visible behind the kart; normal fast drive has no smoke at all (Dust off, Speed FX on); reset clean.

Tuning: smoke_intensity (0.85), smoke_lifetime (1.4), all material values live on the Dust/DustBurst GPUParticles3D nodes in scenes/feedback/cart_feedback.tscn (density -> amount_ratio, curl -> turbulence_strength, rise -> gravity).

## v0.4 - Physics audit + sandbox redesign
Date: 2026-11-04. Backups: player_cart_v3_backup.gd, driving_test_v3_backup.tscn.

### Physics audit (player_cart.gd)
- Audited 6 areas; 4 clean (gravity, steering signs, squash/stretch, recoil math).
- Fixed: (1) _prev_velocity was captured before drive+gravity ran, so impact/landing speeds were stale by up to ~0.6 m/s - capture now happens immediately before move_and_slide(); (2) a mid-air reset left _prev_velocity/_was_on_floor stale and fired a spurious landing - both cleared in _reset_cart().

### Pushable props (new)
- The map's cones and crates are now RigidBody3D nodes in group "pushable" (mass 1.5/3.0, continuous_cd, shared PhysicsMaterial 0.9 friction / 0.15 bounce).
- CharacterBody3D never pushes rigid bodies on its own, so the cart applies a mass-scaled velocity kick (push_force = 4.0 m/s at full speed, capped, slight upward component so cones tumble) with a 0.12 s per-prop cooldown so grinding does not compound.
- R restores the whole sandbox: every pushable prop is teleported back to its spawn transform and put to sleep. Measured: a rammed cone moved 1.12 m; after R it is back within 5 mm.

### Sandbox redesign (scenes/dev/driving_test.tscn)
Organized zones instead of random scatter, all visible as colored pads:
- Blue ACCELERATION LANE (x=0, z 50-28) walled by cone corridors, leading to the SLALOM (alternating cones z 22-4), the crate GATE, the RAMP with green LANDING PAD, and the crash BARRIER straight ahead.
- Orange DRIFT CIRCLE (east, r=8 cone ring) for handbrake practice.
- Tan PUSH/BOWLING ZONE (west): cone triangle + 3x2 crate wall to smash; two rollers for small jumps.
- White BRAKE-ZONE markers (east-north) at 5 m intervals.
- 40 pushable rigid props total (32 cones + 8 crates); debris props remain decor-only.

Validation: import clean, 5/5 script checks pass, headless run clean, push physics proven headless (cone moved 1.12 m, reset restored it to 5 mm), probe screenshots show the zoned layout. Note: "resources still in use at exit" warnings remain a known benign artifact of forced quits.
