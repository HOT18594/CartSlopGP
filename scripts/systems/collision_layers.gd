class_name CollisionLayers
## Shared collision-layer table. Keep scene literals in sync with these values.
## WORLD: static terrain, track bodies and walls.
## PLAYER: local player cart bodies.
## PROP: pushable rigid bodies (sensor-pushed, never solid to the kart).
## GHOST: AI/rival bodies (and the host-side contact proxy source).
const WORLD: int = 1
const PLAYER: int = 2
const PROP: int = 4
const GHOST: int = 8
