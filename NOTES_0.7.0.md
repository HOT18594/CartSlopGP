# Cart Slop GP 0.7.0 — notes (prepared, NOT released)

Status: **built locally, no tag, no GitHub release, no Pi mirror upload.**
The owner must approve the release; nothing has been pushed.

## What changed

### Skid marks in the race (root-cause fix)
- Meadow Loop's dirt road was a visual ribbon only. The kart physically drove
  on the ground box 4 cm lower, and the skid-trail raycasts painted marks at
  ground level — one centimetre or so UNDER the road texture, so nobody ever
  saw them in the race.
- `_build_track()` now also builds a `ConcavePolygonShape3D` from the road
  ribbon (`RoadCollision`, layer 1). Wheels rest on the visible dirt and the
  marks land on top of it. Verified with a real driving probe
  (`tools/skid_shot.tscn`, windowed): two parallel fading ribbons hug the road.
- The sandbox skid system was untouched; it already worked.

### Race identity: one car + tag colours
- In MINIGAMES sessions the host's vehicle is forced onto every peer:
  `grass_race._setup_multiplayer()` broadcasts `_net_force_race_vehicle`,
  `_net_race_ready` re-sends it to late/missed peers, and `_store_net_vehicle`
  applies host vehicles to the LOCAL cart via the new
  `CartPlayer.reapply_vehicle()` (pristine stats restore, so multipliers never
  stack). The off-track `_base_max_speed` is re-captured after the swap or
  the forced car silently reverts one frame later — that was a real bug the
  two-process test caught.
- Sandbox keeps per-peer vehicle choice.
- `GameSettings.player_tag_color` (hex, persisted). Lobby has 8 swatches.
  `Network.set_local_tag_color()` announces `_net_set_tag_color` (same relay
  pattern as names). Used on race + sandbox name labels, lobby list and the
  Tab list.

### Ping: ms + per-player table
- HUD line always shows ms; host shows `0 ms (host)`.
- Clients report RTT (`_net_report_ping`), host keeps `ping_table` and
  broadcasts `_net_ping_table`; lobby rows and the Tab list show it with
  green/amber/red colouring.
- Holding Tab (HUD `_unhandled_input`) opens the Minecraft-style list; rows
  rebuild at ~3 Hz while held.

### Floating carts fixed
- Remote ghosts have physics off and stayed at spawn height (race: 0.2 m,
  sandbox: 0.25 m); sandbox bots floated at 0.12 m forever. Race ghosts spawn
  at 0.05 (road top is 0.04), sandbox ghosts snap to a downward raycast
  (`driving_test._ground_height`), bots sit at 0.02.

### Update system (the greyed RESTART & UPDATE button)
- `update_checker.gd`: 600 s download budget; `_process` stall watchdog — if
  `get_downloaded_bytes()` stops moving for 20 s the request is detached
  (`HTTPRequest.cancel()` does not exist in Godot 4.7, and freeing it
  mid-flight can block the main loop on the thread join), its handler is
  disconnected, `timeout` is shortened so the engine ends the transfer, and
  `download_failed("stalled_connection")` is emitted. Partial files are
  deleted on any failure.
- `update_panel.gd`: self-heal loop — whenever the zip for the advertised
  version exists on disk and the dialog is not busy, it promotes to
  RESTART & UPDATE even if the finish signal was missed (hidden panel, scene
  change, freed instance).
- Verified headless with `tools/mock_update_server.py` +
  `tools/test_update_flow.tscn`: happy path reaches an enabled
  RESTART & UPDATE; the stall scenario recovers to TRY AGAIN in ~20 s.
- Known engine limit: the detached request's thread can stay blocked until
  the OS drops the dead connection, so *quitting the game* during that window
  can wait a bit. The dialog itself recovers immediately.

### Bug hunt / tests
- `test_car_collision.gd` was driving a cart into a ghost frozen mid-air
  (ghosts have no physics) and measured a free fall → FAIL since before
  0.6.2. The ghost now rests on the floor and the test PASSES.
- Full suite green: smoke_meadow_loop, vehicle_catalog, car_collision,
  car_collision_authority, pause_modes, ramp, loop_playback, update_panel,
  update_checker, update_extract, public_fallback.
- NEW `tools/test_sync_host|client(.gd/_driver.gd/.tscn)`: two headless
  processes over LAN — verifies forced race vehicle (client speed 19→18),
  tag colour relay both ways, ping table, scene readiness. Both peers PASS.
- Sandbox pair run through the LIVE Pi (host got code, client joined).

## Release checklist (when the owner says go)
1. Commit + tag `v0.7.0`, push.
2. Export all four platforms into `builds/v0.7.0/`, zip, `gh release create`.
3. Upload the Windows zip to the Pi mirror + bump
   `pi_setup/cartslop-server/updates/manifest.json` (version 0.7.0).
4. Old build should offer the update automatically.
