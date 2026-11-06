# Minigames

**PLAY -> MINIGAMES** shows only events that are actually playable. Today that
is **MEADOW LOOP**: three laps of a winding 491 m dirt circuit through a dense
grassy forest, with three rivals and four boost pads.

## Preview policy

- Every event card uses a **real in-game screenshot** from
  `assets/ui/minigames/`.
- If an event has no real screenshot, the screen draws **no image at all**.
- There are no illustrated placeholders and no "coming soon" cards for events
  that do not exist. New cards are added only when the event ships.

## Layout

- A featured card: real preview on the left, name / stats / description on the
  right.
- A vehicle cycler and one primary action.
- The primary action reads **RACE MEADOW LOOP** in solo play and
  **SELECT MEADOW LOOP** when the host opened this screen from a live lobby.
- BACK returns to PLAY, or to the live multiplayer lobby.

## Flow

```
MAIN MENU
└── PLAY
    ├── SINGLE PLAYER
    │   ├── SANDBOX       -> vehicle picker -> open arena
    │   └── MINIGAMES     -> MEADOW LOOP -> race (3-2-1-GO after load)
    └── MULTIPLAYER
        ├── SANDBOX SESSION  -> lobby -> shared arena
        └── MINIGAME SESSION -> lobby -> map picker -> race for every peer
```

Selecting a map while hosting updates the lobby only. The host starts the race
from the lobby's START button. Solo play skips the waiting room and goes
straight to the race; the countdown runs after the race scene loads.

## Adding an event

1. Build the scene and make it playable.
2. Add one entry to `EVENTS` in `scripts/ui/minigames_menu.gd` with its real
   preview filename, metadata, description and scene.
3. Drop the real screenshot in `assets/ui/minigames/`.

Do not add an entry before the scene works.
