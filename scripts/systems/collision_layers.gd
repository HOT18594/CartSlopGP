class_name CollisionLayers
## Shared collision-layer table. Keep scene literals in sync with these values.
## WORLD: static terrain, track bodies and walls.
## PLAYER: local player cart bodies.
## PROP: pushable props that never block the kart (cones).
## GHOST: AI/rival bodies (and solid online player ghosts).
## SOLID_PROP: heavier pushables (crates) that also block the kart.
const WORLD: int = 1
const PLAYER: int = 2
const PROP: int = 4
const GHOST: int = 8
const SOLID_PROP: int = 16
