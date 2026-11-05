# Minigames

**PLAY -> MINIGAMES** opens a grid of preview cards. **MEADOW LOOP** is
implemented; the other four events are marked COMING SOON.

## Layout

- Title row with the event count.
- 3-column card grid; every card has a generated preview image, a name and a
  READY / SOON tag.
- Selected-event details below the grid: name, tag, description.
- A **VEHICLE** cycle button (writes `GameSettings.minigame_vehicle`) and a
  **PLAY** button that is disabled for unreleased events.
- BACK returns to PLAY, or to the live multiplayer lobby when the host opened
  this screen from a session.

Cards carry `available`, `preview`, `accent` and `scene` in the `EVENTS` array
of `scripts/ui/minigames_menu.gd`. Adding a playable event means adding an
entry, a preview image and its scene.

## Flow

```
MAIN MENU
└── PLAY
    ├── SINGLE PLAYER
    │   ├── SANDBOX       -> vehicle picker -> open arena
    │   └── MINIGAMES     -> grid -> MEADOW LOOP -> waiting room -> race
    └── MULTIPLAYER
        ├── SANDBOX SESSION  -> lobby -> shared arena
        └── MINIGAME SESSION -> lobby -> Meadow Loop for every peer
```

## Multiplayer

The host chooses SANDBOX or MINIGAMES in the lobby. START RACE sends the scene
and session config to every peer. In Meadow Loop each peer owns its cart,
streams position/yaw plus lap distance at 20 Hz, exchanges its vehicle model,
and the host relays client states so everyone sees everyone. The result card
hides RACE AGAIN (which would desync the field); BACK TO LOBBY returns the
whole session to the lobby.

## Preview images

`tools/gen_minigame_previews.py` builds the five 480x270 cards in
`assets/ui/minigames/`. Meadow Loop uses a real in-game screenshot when one is
available; the coming-soon cards are flat illustrations in the same palette.
