# Minigames menu - prototype spec

Status: the screens and settings are implemented; the minigames themselves are
not wired yet (every PLAY / START button is disabled with "COMING SOON").

## Flow

```
MAIN MENU
└── PLAY
    ├── SANDBOX          -> vehicle picker -> driving sandbox (solo)
    ├── MULTIPLAYER      -> lobby: name, LAN/ONLINE, host code, join code
    ├── MINIGAMES        -> Free Play | Tournament
    └── BACK

MINIGAMES (tabs)
├── FREE PLAY          -> card list + details + options + PLAY
└── TOURNAMENT         -> rounds / difficulty / vehicle + START
    └── BACK -> PLAY
```

## Free Play screen (button placement)

```
+--------------------------------------------------------------+
|                        MINIGAMES                             |
|--------------------------------------------------------------|
| [ FREE PLAY ]  [ TOURNAMENT ]        <- tabs, equal width    |
|                                                              |
| [ CONE SLALOM   SOLO   SOON ]        <- card, full width     |
| [ CRATE SMASH   SOLO   SOON ]                                |
| [ DRIFT SCORE   SOLO   SOON ]                                |
| [ BOOST RUN     SOLO   SOON ]                                |
|                                                              |
| +----------------------------------------------------------+ |
| | CONE SLALOM                                              | |
| | description ...                                          | |
| | [DIFFICULTY v] [ROUNDS v] [VEHICLE v]   <- 3 equal opts  | |
| +----------------------------------------------------------+ |
| [ PLAY - COMING SOON ]              <- disabled, primary     |
| "Every minigame is solo..."          <- rule line            |
| [ BACK ]                             <- secondary, red       |
+--------------------------------------------------------------+
```

Placement rules:

- The tab row is always at the top and uses equal widths, so the active tab can
  be highlighted without moving the layout.
- Cards are full-width rows in a fixed order; the selected card is yellow, the
  rest grey. Selection never moves the details panel (fixed slot below).
- The three options share one row at equal widths: Difficulty, Rounds, Vehicle.
- PLAY is the only primary button and sits directly under the details; BACK is
  the only red button and is always last.

## Tournament screen

```
+--------------------------------------------------------------+
| description: solo gauntlet, points carry over                |
| [MINIGAMES v] [DIFFICULTY v] [VEHICLE v]                     |
| [ START TOURNAMENT - COMING SOON ]   (disabled)               |
| note: ghost times / friend leaderboards later                 |
+--------------------------------------------------------------+
```

## Data model

`scripts/ui/minigames_menu.gd`

```gdscript
const MINIGAMES = [
  {id, name, desc}, ...   # add an entry -> a new card appears
]
```

Options are persisted in `GameSettings` (`user://settings.cfg`):

| Setting | Values | Default |
| --- | --- | --- |
| `minigame_difficulty` | 0 easy, 1 normal, 2 hard | 1 |
| `minigame_rounds` | 3, 5, 7 | 3 |
| `minigame_vehicle` | vehicle catalog id | `shopping_cart` |

## Rules for future minigames

- Every minigame is **solo** by default. The special multiplayer ones are wired
  separately (they use the same Network session, but start from their own
  screen and are not listed in Free Play).
- A minigame scene should receive its options from `GameSettings` and return to
  the minigames hub when finished, not to the main menu.
- Scores/times are local for now; a future update adds ghost times and
  leaderboards (the tournament screen is where they will surface).
