# What's new

Player-facing notes, newest first.

## [0.7.3] - 2026-11-17

### Windows players can actually start the game

- The Windows download was two files: `CartSlopGP.exe` plus a large
  `CartSlopGP.pck`. If a player extracted only the executable, moved it to the
  Desktop, or double-clicked the exe straight out of the zip (Windows extracts
  just the exe in that case), the game died with
  **"Couldn't load project data — is the .pck file missing?"** and never opened.
- The data pack is now built into the executable, so the download is one file
  and cannot be broken apart. Linux gets the same treatment, so `chmod +x` and
  run is all it takes there too.
- The build now refuses to publish a Windows or Linux binary whose data pack is
  not embedded, so this cannot ship again.
- Everything in 0.7.2 is included (see below).

## [0.7.2] - 2026-11-17

### Linux players can start the game again

- The Linux download shipped `CartSlopGP.x86_64` without its executable bit, so
  the file extracted unlaunchable and the game never started. The release zip now
  carries proper Unix permissions, and the build checks them before it publishes.

### Driving

- Car-to-car contact exchanges momentum again on a head-on hit. The impulse was
  measured after the physics engine had already separated the pair, so the
  approach speed read as zero and the shove disappeared.
- The impact cooldown after a hit now only gates the shake, hit-stop and sound.
  It used to skip the whole collision pass, so a cart that had just been bumped
  also lost its wall response for a moment.
- The first boost puff after a respawn is no longer swallowed, and landing on the
  grid no longer fires a phantom landing burst.

### Tracks

- A track's grip sectors (the dockyard wet lane, the glacier ice) now come from
  the same map module as the layout and the terrain, so the menu preview and the
  race can no longer disagree about where the surface changes.

### Multiplayer

- Joining a LAN room twice, or joining while already hosting, no longer tears
  down the live session.
- Cancelling a host request no longer leaves the loading overlay stuck over
  every later screen.
- Pings can no longer display a negative or multi-minute value from a stale
  reply, and a new session measures the server clock again instead of reusing
  the previous relay's offset.
- A rejected relay token drops the link and backs off instead of re-sending the
  handshake 60 times a second.

### Updates

- A build published to the Pi mirror is offered even when GitHub is reachable and
  its own latest release is older, which is the documented Pi-first flow.

### Interface

- Left and right arrows flip through the garage, as the screen always claimed.
- The race clock, best lap and speed readout reject corrupt values instead of
  printing garbage, and the standings list holds a full 13-cart field.

## [0.7.1] - 2026-11-14

### The whole game is now built from the Kenney cartoon kits

- Every circuit, the sandbox and Cargo Rush are built from real modular kit
  pieces: road tiles, barriers, grandstands, pit garages, floodlights, flags and
  signage. No more placeholder geometry dressed with photo textures.
- Race maps are authored as a tile grid and must form one closed lap, so the road
  always connects. Seam gaps, height steps and loop closure all measure 0 mm.
- Terrain is no longer flat: stadium climbs 0-6 m with a banked straight, the
  dockyard has a raised wharf and a sunken container lane, and Glacier climbs to
  9 m before a fast descent.
- Trees are placed as designed woodland - clustered, several rows deep, with
  clearings at the grandstands - between 432 and 751 trees per map.

### Driving

- Player collisions conserve momentum: two carts shove each other apart instead
  of one stopping dead, and heavy vehicles push light ones.
- Drifting now costs speed in proportion to how sideways you are, instead of
  carrying almost all your momentum through a corner.
- Brakes are stronger and also kill a slide, so stopping works while drifting.
- Bumps give a brief loss of steering rather than a dead stop, and no cart can
  tunnel through a wall, a crate or another cart at any tick rate.

### Bots

- Bots choose between four racing lines with per-driver braking points, and make
  overtaking and defensive moves.
- Bots ride ramps properly, recover when beached, and never drive through them.

### UI

- One spacing system across every screen, with nothing clipped at 1280x720.
- Settings use real sliders grouped by a single label column; menus use square
  tiles instead of stretched pills, and no divider lines anywhere.
- The speedometer is an arc with the number as the hero; the standings show every
  player; ping has its own corner so it cannot overlap the race order.
- The speed zone is a soft blue aurora field instead of a painted chevron.
- Racing and Deliver are games you pick, then pick a map or arena inside them,
  and the lobby handles both - including team assignment for Deliver.

### Modes

- Deliver: presents are scattered around the arena, hold the interact key for two
  seconds to load one, then carry it home. Teams are Alpha and Beta, and the host
  can move players between them.
- Sandbox is a five zone test facility: paddock, handling loop, skidpad, jump lane
  and a dirt strip.

### Fixes

- Over 40 logic defects found and fixed across every mode, including later
  finishers outranking earlier ones, a present claimed by two players at once, a
  carrier disconnect freezing the crate, settings switches wired backwards, and
  corrupt settings wiping progress instead of recovering.
### Bumps that move you

- Hitting another cart now transfers momentum properly: two karts shove each
  other apart instead of one simply stopping dead.
- A careless hit costs you a moment of steering, not the whole race, and
  clipping a wall or a crate now keeps your speed and slides instead of
  stopping the kart.
- Heavier vehicles push lighter ones around, as you would expect.

### Bots that race

- Race bots follow a real racing line, brake before corners and stop driving
  into tyre walls.
- Bots now ride the dirt ramps instead of passing through them, and they
  recover on their own if they get beached.
- Free-roam bots in the sandbox steer around crates, ramps and other carts.

### A map worth looking at

- The row of dome-shaped hills is gone. Both maps now sit inside layered
  ridges, cliffs and distant peaks.
- The track has grandstands with crowds, a start gantry, tyre walls, marshal
  posts and sponsor boards.
- The park gained a pond, boulders, fencing, a paddock and denser woodland.

### Easier to use

- Menus work properly with a keyboard or gamepad: focus is visible, Escape
  closes only the top panel, and every menu has a way back.
- The HUD shows your gear, current and best lap, the gap to the leader, and
  the real ping to the server.

### Play in your browser

- The Pi can serve the game itself: sign in with the panel password and play
  in the browser, no download.

### Fixes

- The browser build no longer offers an update it cannot install.
- Rubber-banding is gone from bot races.

## [0.7.0] - 2026-11-10

### Races run by the Pi

- The Pi now owns the multiplayer race clock, the official lap and finish
  times, and the standings.
- Bots are simulated by the Pi and streamed to every player, so the whole room
  races the same field.
- If the room server is older than 1.6.0, the game falls back to the previous
  host-run race automatically.

## [0.6.9] - 2026-11-10

### Cleaner racing

- Players now collide with each other online instead of driving through one
  another.
- Bots are simulated by the room host and streamed to every player, so
  everyone races the same rivals on the same line.
- The host's ping now shows the real round trip to the Pi relay instead of a
  hard-coded 0 ms.
- Boxes and cones react on every screen: a client's hit is predicted locally
  and confirmed by the host. Crates now physically block carts.
- Bots no longer ram you off the road. They give you room and lift off when you
  are alongside, while still racing each other hard.
- The OFF TRACK warning only appears once you are past the barrier. A recovery
  puts you back on the road ahead of where you left it, never behind.

## [0.6.8] - 2026-11-10

### Online rooms

- Online rooms connect through the Cart Slop relay again.
- Gameplay is unchanged from 0.6.6.

## [0.6.6] - 2026-11-08

### Settings, rebuilt

- SETTINGS is now one clean panel with AUDIO, VIDEO, GAMEPLAY, ACCESSIBILITY
  and UPDATES sections. Everything fits at 720p.
- QUALITY and BOT DIFFICULTY are explicit cycle buttons, and the switches are
  small and readable instead of giant checkboxes.

### Map select

- The map picker is now **MAP SELECT**, with a larger track preview, one short
  description and just VEHICLE and RACE as actions.

### Curved ground

- The cart uses a capsule body with four wheels, so it follows domes, banks and
  the mesa instead of catching on terrain corners.
- Curbs and low bumpers no longer stop the cart dead.

### Effects and rivals

- Boost and landing kick up warm dust; impacts throw real sparks.
- Bot difficulty changes speed, boost use and cornering, and sandbox bots pick
  different lines instead of driving as one train.

### Online

- Remote carts receive the real vehicle size, finished racers stop being solid,
  and race-state packets carry velocity so side-by-side driving stays smooth.

## [0.6.5] - 2026-11-08

### Faster races

- Collision, AI, the race clock and lap progress run on the fixed 60 Hz physics
  step, so bumps and lap times no longer depend on frame rate.
- Meadow Loop keeps detail where you can see it, and the HUD updates only when
  a number changes.

### Real car shapes

- Every vehicle has its own length, width, height, wheelbase and track.
- Car-to-car contact uses an oriented box instead of a fixed circle, so
  side-by-side cars stop bumping empty air.

### Racing HUD

- One top-left race plaque for position, lap, time and best lap, live standings
  on the right, a segmented boost meter and a compact speedometer.
