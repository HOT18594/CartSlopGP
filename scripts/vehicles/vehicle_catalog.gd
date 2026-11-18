extends RefCounted
## Playable sandbox vehicles. The kart from the special minigames is
## deliberately not listed here.
##
## Handling model: `mass` is the real-world-ish kerb weight. Engine cars get
## `engine_power` (acceleration at REFERENCE_MASS); the player divides it by
## the actual mass, so heavier vehicles accelerate slower and transfer more
## momentum into props. The shopping cart has no engine - it is pushed by leg
## power (`push_accel`) and rattles instead of idling.

const DEFAULT_ID: String = "shopping_cart"
const REFERENCE_MASS: float = 1200.0

## Racing class. The Kenney racing-kit cars are only offered in racing modes;
## the sandbox roster above stays exactly as it is. The stock shopping cart is
## the default racing pick because it is the game's signature vehicle; the four
## Kenney chassis below are an opt-in choice. A racing chassis entry is a base
## chassis: the player spends RACING_STAT_POINTS across four stats and the
## composition below rewrites the same catalog fields the physics already reads.
## The stock cart has no spendable build; it always runs its stock handling.
const DEFAULT_RACING_ID: String = DEFAULT_ID
const RACING_STAT_POINTS: int = 12
const RACING_STAT_MAX: int = 6
const RACING_STAT_KEYS: PackedStringArray = [
	"top_speed", "accel", "grip", "weight",
]
## A fresh racing build is balanced so a player who never opens the screen still
## gets a complete, valid allocation.
const RACING_DEFAULT_ALLOCATION: Dictionary = {
	"top_speed": 3, "accel": 3, "grip": 3, "weight": 3,
}
## Per-point effect on the composed catalog fields. Top speed is m/s, accel is
## engine_power at REFERENCE_MASS, grip is the handling multiplier, and weight
## is ballast in kg (heavier cars launch slower but shove props harder).
const RACING_SPEED_PER_POINT: float = 0.45
const RACING_POWER_PER_POINT: float = 1.05
const RACING_GRIP_PER_POINT: float = 0.028
const RACING_STEER_PER_POINT: float = 0.010
const RACING_MASS_PER_POINT: float = 24.0
const RACING_PUSH_PER_POINT: float = 0.030
## Shopping Cart racing deltas. Applied around RACING_DEFAULT_ALLOCATION (3 pts
## per stat) so a balanced 3/3/3/3 build preserves stock Shopping Cart feel while
## +/- garage tuning shifts speed, leg-push acceleration, grip and ballast.
const CART_RACING_BASE_POINTS: float = 3.0
const CART_SPEED_PER_POINT: float = 0.65
const CART_ACCEL_PER_POINT: float = 1.25
const CART_GRIP_PER_POINT: float = 0.035
const CART_STEER_PER_POINT: float = 0.015
const CART_MASS_PER_POINT: float = 4.5
const CART_PUSH_PER_POINT: float = 0.045
const CART_WEIGHT_ACCEL_DRAG: float = 0.18

## Keys used by the vehicle-picker comparison bars. Keep display order here.
const STAT_KEYS: PackedStringArray = [
	"top_speed", "accel", "weight", "grip",
	"steering", "smoke", "skid_width", "push",
]

const VEHICLES: Array[Dictionary] = [
	{
		"id": "shopping_cart",
		"name": "SHOPPING CART",
		"scene": "res://assets/models/poly_pizza/shopping_cart/shopping_cart.glb",
		"length": 1.8,
		"width": 0.95,
		"height": 1.55,
		"wheelbase": 1.05,
		"track": 0.9,
		"yaw": 0.0,
		"mass": 45.0,
		"max_speed": 19.0,
		"engine_power": 0.0,
		"push_accel": 15.0,
		"grip": 0.90,
		"steering": 1.05,
		"push_scale": 0.50,
		"smoke": 0.30,
		"skid_width": 0.09,
		"skid_side": 0.44,
		"skid_back": 0.55,
		"loop_sound": "res://assets/audio/sfx/engines/cart_rattle.wav",
		"loop_pitch": 0.85,
		"loop_pitch_span": 0.70,
		"loop_idle": false,
		"has_engine": false,
	},
	{
		"id": "sedan",
		"name": "SEDAN",
		"scene": "res://assets/models/kenney_car-kit/Models/GLB format/sedan.glb",
		"length": 2.7,
		"width": 1.5,
		"height": 1.4,
		"wheelbase": 1.7,
		"track": 1.3,
		"yaw": 180.0,
		"mass": 1350.0,
		"max_speed": 23.0,
		"engine_power": 22.0,
		"push_accel": 15.0,
		"grip": 1.0,
		"steering": 1.0,
		"push_scale": 1.0,
		"smoke": 0.75,
		"skid_width": 0.20,
		"skid_side": 0.62,
		"skid_back": 0.78,
		"loop_sound": "res://assets/audio/sfx/engines/sedan_loop.wav",
		"loop_pitch": 0.85,
		"loop_pitch_span": 0.75,
		"loop_idle": true,
		"has_engine": true,
	},
	{
		"id": "sports",
		"name": "SPORTS CAR",
		"scene": "res://assets/models/kenney_car-kit/Models/GLB format/sedan-sports.glb",
		"length": 2.7,
		"width": 1.5,
		"height": 1.2,
		"wheelbase": 1.7,
		"track": 1.3,
		"yaw": 180.0,
		"mass": 1150.0,
		"max_speed": 27.0,
		"engine_power": 24.0,
		"push_accel": 15.0,
		"grip": 1.08,
		"steering": 1.05,
		"push_scale": 0.95,
		"smoke": 1.0,
		"skid_width": 0.225,
		"skid_side": 0.64,
		"skid_back": 0.80,
		"loop_sound": "res://assets/audio/sfx/engines/sports_loop.wav",
		"loop_pitch": 1.0,
		"loop_pitch_span": 0.9,
		"loop_idle": true,
		"has_engine": true,
	},
	{
		"id": "taxi",
		"name": "TAXI",
		"scene": "res://assets/models/kenney_car-kit/Models/GLB format/taxi.glb",
		"length": 2.7,
		"width": 1.5,
		"height": 1.5,
		"wheelbase": 1.7,
		"track": 1.3,
		"yaw": 180.0,
		"mass": 1450.0,
		"max_speed": 22.0,
		"engine_power": 20.0,
		"push_accel": 15.0,
		"grip": 0.98,
		"steering": 0.98,
		"push_scale": 1.0,
		"smoke": 0.65,
		"skid_width": 0.20,
		"skid_side": 0.62,
		"skid_back": 0.78,
		"loop_sound": "res://assets/audio/sfx/engines/taxi_loop.wav",
		"loop_pitch": 0.8,
		"loop_pitch_span": 0.7,
		"loop_idle": true,
		"has_engine": true,
	},
	{
		"id": "van",
		"name": "VAN",
		"scene": "res://assets/models/kenney_car-kit/Models/GLB format/van.glb",
		"length": 3.0,
		"width": 1.7,
		"height": 1.8,
		"wheelbase": 1.9,
		"track": 1.45,
		"yaw": 180.0,
		"mass": 2050.0,
		"max_speed": 20.0,
		"engine_power": 25.0,
		"push_accel": 15.0,
		"grip": 0.94,
		"steering": 0.90,
		"push_scale": 1.30,
		"smoke": 0.80,
		"skid_width": 0.26,
		"skid_side": 0.68,
		"skid_back": 0.95,
		"loop_sound": "res://assets/audio/sfx/engines/van_loop.wav",
		"loop_pitch": 0.75,
		"loop_pitch_span": 0.65,
		"loop_idle": true,
		"has_engine": true,
	},
	{
		"id": "truck",
		"name": "BOX TRUCK",
		"scene": "res://assets/models/kenney_car-kit/Models/GLB format/truck.glb",
		"length": 3.4,
		"width": 1.8,
		"height": 2.1,
		"wheelbase": 2.0,
		"track": 1.5,
		"yaw": 180.0,
		"mass": 3200.0,
		"max_speed": 18.0,
		"engine_power": 30.0,
		"push_accel": 15.0,
		"grip": 0.88,
		"steering": 0.82,
		"push_scale": 1.80,
		"smoke": 1.0,
		"skid_width": 0.30,
		"skid_side": 0.76,
		"skid_back": 1.05,
		"loop_sound": "res://assets/audio/sfx/engines/truck_loop.wav",
		"loop_pitch": 0.62,
		"loop_pitch_span": 0.55,
		"loop_idle": true,
		"has_engine": true,
	},
	{
		"id": "police",
		"name": "POLICE CRUISER",
		"scene": "res://assets/models/kenney_car-kit/Models/GLB format/police.glb",
		"length": 2.7,
		"width": 1.5,
		"height": 1.45,
		"wheelbase": 1.7,
		"track": 1.3,
		"yaw": 180.0,
		"mass": 1550.0,
		"max_speed": 25.0,
		"engine_power": 24.0,
		"push_accel": 15.0,
		"grip": 1.02,
		"steering": 1.0,
		"push_scale": 1.05,
		"smoke": 0.90,
		"skid_width": 0.21,
		"skid_side": 0.62,
		"skid_back": 0.78,
		"loop_sound": "res://assets/audio/sfx/engines/police_loop.wav",
		"loop_pitch": 0.90,
		"loop_pitch_span": 0.8,
		"loop_idle": true,
		"has_engine": true,
	},
]

## The four Kenney racing-kit cars. Footprint values were measured from the
## GLB AABBs and the wheel nodes: raw length 1.346 m, width 0.729 m, height
## 0.397 m, wheelbase 0.801 m, track 0.410 m. The build below scales the model
## to a 2.55 m catalog length and derives every other side from that same
## uniform scale, so the visual and the collider stay on the shared contract.
## Paint is surface 1 of the "body" mesh on every one of the four models.
const RACING_VEHICLES: Array[Dictionary] = [
	{
		"id": "race_car_red",
		"name": "RED RACER",
		"scene": "res://assets/models/kenney_racing_kit/Models/GLTF format/raceCarRed.glb",
		"length": 2.55,
		"width": 1.38,
		"height": 0.75,
		"wheelbase": 1.52,
		"track": 0.78,
		"yaw": 180.0,
		"mass": 760.0,
		"max_speed": 29.0,
		"engine_power": 26.0,
		"push_accel": 15.0,
		"grip": 1.12,
		"steering": 1.08,
		"push_scale": 0.88,
		"smoke": 0.95,
		"skid_width": 0.235,
		"skid_side": 0.66,
		"skid_back": 0.84,
		"loop_sound": "res://assets/audio/sfx/engines/sports_loop.wav",
		"loop_pitch": 1.05,
		"loop_pitch_span": 0.90,
		"loop_idle": true,
		"has_engine": true,
		"racing": true,
		"paint_node": "body",
		"paint_surface": 1,
		"base_paint": Color("f59c9b"),
	},
	{
		"id": "race_car_green",
		"name": "GREEN RACER",
		"scene": "res://assets/models/kenney_racing_kit/Models/GLTF format/raceCarGreen.glb",
		"length": 2.55,
		"width": 1.38,
		"height": 0.75,
		"wheelbase": 1.52,
		"track": 0.78,
		"yaw": 180.0,
		"mass": 780.0,
		"max_speed": 28.0,
		"engine_power": 25.0,
		"push_accel": 15.0,
		"grip": 1.22,
		"steering": 1.12,
		"push_scale": 0.91,
		"smoke": 0.90,
		"skid_width": 0.225,
		"skid_side": 0.66,
		"skid_back": 0.84,
		"loop_sound": "res://assets/audio/sfx/engines/sports_loop.wav",
		"loop_pitch": 1.00,
		"loop_pitch_span": 0.85,
		"loop_idle": true,
		"has_engine": true,
		"racing": true,
		"paint_node": "body",
		"paint_surface": 1,
		"base_paint": Color("95c5af"),
	},
	{
		"id": "race_car_orange",
		"name": "ORANGE RACER",
		"scene": "res://assets/models/kenney_racing_kit/Models/GLTF format/raceCarOrange.glb",
		"length": 2.55,
		"width": 1.38,
		"height": 0.75,
		"wheelbase": 1.52,
		"track": 0.78,
		"yaw": 180.0,
		"mass": 720.0,
		"max_speed": 28.0,
		"engine_power": 29.0,
		"push_accel": 15.0,
		"grip": 1.08,
		"steering": 1.04,
		"push_scale": 0.84,
		"smoke": 1.0,
		"skid_width": 0.245,
		"skid_side": 0.66,
		"skid_back": 0.84,
		"loop_sound": "res://assets/audio/sfx/engines/sports_loop.wav",
		"loop_pitch": 1.10,
		"loop_pitch_span": 0.95,
		"loop_idle": true,
		"has_engine": true,
		"racing": true,
		"paint_node": "body",
		"paint_surface": 1,
		"base_paint": Color("fbdd8b"),
	},
	{
		"id": "race_car_white",
		"name": "WHITE RACER",
		"scene": "res://assets/models/kenney_racing_kit/Models/GLTF format/raceCarWhite.glb",
		"length": 2.55,
		"width": 1.38,
		"height": 0.75,
		"wheelbase": 1.52,
		"track": 0.78,
		"yaw": 180.0,
		"mass": 740.0,
		"max_speed": 31.0,
		"engine_power": 24.0,
		"push_accel": 15.0,
		"grip": 1.04,
		"steering": 1.02,
		"push_scale": 0.86,
		"smoke": 0.85,
		"skid_width": 0.220,
		"skid_side": 0.66,
		"skid_back": 0.84,
		"loop_sound": "res://assets/audio/sfx/engines/sports_loop.wav",
		"loop_pitch": 1.12,
		"loop_pitch_span": 1.00,
		"loop_idle": true,
		"has_engine": true,
		"racing": true,
		"paint_node": "body",
		"paint_surface": 1,
		"base_paint": Color("f9f9fb"),
	},
]

## Alias for readers that look for the class by name. Same read-only list: the
## four opt-in chassis only, since racing_all() adds the stock cart default.
const RACING_CLASS: Array[Dictionary] = RACING_VEHICLES


static func stats_for(entry: Dictionary) -> Dictionary:
	## The single source of truth for the numbers behind the stat bars.
	## Everything is converted to the units a player would expect (km/h etc.)
	## and the no-engine shopping cart falls back to leg-power acceleration.
	var mass: float = float(entry.get("mass", 0.0))
	var engine: float = float(entry.get("engine_power", 0.0))
	var accel: float = (engine * REFERENCE_MASS / maxf(mass, 1.0)) \
		if engine > 0.0 else float(entry.get("push_accel", 0.0))
	return {
		"top_speed": float(entry.get("max_speed", 0.0)) * 3.6,
		"accel": accel,
		"weight": mass,
		"grip": float(entry.get("grip", 1.0)),
		"steering": float(entry.get("steering", 1.0)),
		"smoke": float(entry.get("smoke", 0.0)),
		"skid_width": float(entry.get("skid_width", 0.0)) * 100.0,
		"push": float(entry.get("push_scale", 1.0)),
	}


static func stat_ranges() -> Dictionary:
	## Min/max for every key across the garage, used to normalise the bars.
	var ranges: Dictionary = {}
	for key: String in STAT_KEYS:
		ranges[key] = {"min": INF, "max": -INF}
	for entry: Dictionary in VEHICLES:
		var values: Dictionary = stats_for(entry)
		for key: String in STAT_KEYS:
			var value: float = float(values.get(key, 0.0))
			var slot: Dictionary = ranges[key]
			slot["min"] = minf(float(slot["min"]), value)
			slot["max"] = maxf(float(slot["max"]), value)
	return ranges


static func stat_ratio(entry: Dictionary, key: String, ranges: Dictionary) -> float:
	var value: float = float(stats_for(entry).get(key, 0.0))
	var slot: Dictionary = ranges.get(key, {})
	var low: float = float(slot.get("min", 0.0))
	var high: float = float(slot.get("max", 1.0))
	if high - low < 0.0001:
		return 1.0
	return clampf((value - low) / (high - low), 0.0, 1.0)


static func racing_stat_ranges() -> Dictionary:
	## Min/max for the four allocatable racing stats across every legal racing
	## choice (including the tunable Shopping Cart). Probing each chassis at zero
	## and at the per-stat cap covers the full range a composed entry can reach.
	var ranges: Dictionary = {}
	for key: String in STAT_KEYS:
		ranges[key] = {"min": INF, "max": -INF}
	var variants: Array[Dictionary] = [sanitize_allocation({})]
	for stat_key: String in RACING_STAT_KEYS:
		var allocation: Dictionary = {}
		for other: String in RACING_STAT_KEYS:
			allocation[other] = 0
		allocation[stat_key] = RACING_STAT_MAX
		variants.append(allocation)
	for base: Dictionary in racing_all():
		var id: String = str(base.get("id", ""))
		for allocation: Dictionary in variants:
			var values: Dictionary = stats_for(compose_racing_entry(id, allocation))
			for key: String in STAT_KEYS:
				var value: float = float(values.get(key, 0.0))
				var slot: Dictionary = ranges[key]
				slot["min"] = minf(float(slot["min"]), value)
				slot["max"] = maxf(float(slot["max"]), value)
	return ranges


static func default_allocation() -> Dictionary:
	## A mutable copy of the balanced build, safe for callers to edit.
	return RACING_DEFAULT_ALLOCATION.duplicate()


static func all() -> Array[Dictionary]:
	## The sandbox roster. Racing cars are deliberately separate so every
	## existing picker, save and spawn keeps its old list.
	return VEHICLES


static func racing_all() -> Array[Dictionary]:
	## The stock shopping cart first, then the four racing-class chassis. Every
	## racing picker opens on index 0, so a player only leaves the game's
	## signature cart after deliberately stepping onto a Kenney chassis.
	var entries: Array[Dictionary] = []
	var stock: Dictionary = find(DEFAULT_ID)
	if not stock.is_empty():
		entries.append(stock)
	entries.append_array(RACING_VEHICLES)
	return entries


static func is_racing_id(id: String) -> bool:
	## True only for a real id in RACING_VEHICLES. Paths and sandbox ids are
	## never accepted, so a saved string cannot smuggle another model in. The
	## stock cart is the racing default but is not a composed chassis.
	for entry: Dictionary in RACING_VEHICLES:
		if str(entry.get("id", "")) == id:
			return true
	return false


static func is_racing_choice(id: String) -> bool:
	## Every legal racing-class pick: the stock shopping cart default plus the
	## four Kenney chassis. Physics composition, paint and the network racing
	## fields stay keyed to is_racing_id(), which excludes the stock cart.
	return id == DEFAULT_ID or is_racing_id(id)


static func racing_find(id: String) -> Dictionary:
	## A real Kenney chassis only. The stock cart default is resolved through
	## find(DEFAULT_ID) so callers keep the uncomposed sandbox handling.
	for entry: Dictionary in RACING_VEHICLES:
		if str(entry.get("id", "")) == id:
			return entry
	return {}


static func racing_index_of(id: String) -> int:
	## Index inside racing_all(), where 0 is the stock cart default.
	var entries: Array[Dictionary] = racing_all()
	for index in entries.size():
		if str(entries[index].get("id", "")) == id:
			return index
	return 0


static func _allocation_points(raw: Dictionary, key: String) -> int:
	## Read one allocation value defensively: wrong types and NaN/Inf become 0
	## and every value is clamped to a spendable range.
	var value: Variant = raw.get(key, 0)
	var kind: int = typeof(value)
	if kind != TYPE_INT and kind != TYPE_FLOAT:
		return 0
	var number: float = float(value)
	if not is_finite(number):
		return 0
	return clampi(int(number), 0, RACING_STAT_MAX)


static func sanitize_allocation(raw: Dictionary) -> Dictionary:
	## Always returns all four keys, each 0..RACING_STAT_MAX, and trims
	## over-budget saves deterministically from weight backwards.
	var clean: Dictionary = {}
	var total: int = 0
	for key: String in RACING_STAT_KEYS:
		var points: int = _allocation_points(raw, key)
		clean[key] = points
		total += points
	if total > RACING_STAT_POINTS:
		for index in range(RACING_STAT_KEYS.size() - 1, -1, -1):
			var key: String = RACING_STAT_KEYS[index]
			while total > RACING_STAT_POINTS and int(clean[key]) > 0:
				clean[key] = int(clean[key]) - 1
				total -= 1
	return clean


static func allocation_total(allocation: Dictionary) -> int:
	var total: int = 0
	for key: String in RACING_STAT_KEYS:
		total += _allocation_points(allocation, key)
	return total


static func compose_racing_entry(id: String, allocation: Dictionary,
		tint: Color = Color(0, 0, 0, 0)) -> Dictionary:
	## Turn a chassis id plus a point spend into a normal catalog entry. Every
	## field player_cart.gd and vehicle_visual.gd already read is preserved; only
	## mass, engine_power/push_accel, max_speed, grip, steering and push_scale are
	## rewritten from the four allocation axes, so the physics shape is unchanged.
	## For the Shopping Cart, allocation deltas apply around the balanced 3/3/3/3
	## default so stock allocation keeps baseline feel while +/- tuning and paint work.
	var clean: Dictionary = sanitize_allocation(allocation)
	if id == DEFAULT_ID:
		var stock_base: Dictionary = find(DEFAULT_ID)
		if stock_base.is_empty():
			return {}
		var cart_entry: Dictionary = stock_base.duplicate(true)
		var d_speed: float = float(clean["top_speed"]) - CART_RACING_BASE_POINTS
		var d_accel: float = float(clean["accel"]) - CART_RACING_BASE_POINTS
		var d_grip: float = float(clean["grip"]) - CART_RACING_BASE_POINTS
		var d_weight: float = float(clean["weight"]) - CART_RACING_BASE_POINTS
		cart_entry["max_speed"] = maxf(float(stock_base.get("max_speed", 19.0))
			+ CART_SPEED_PER_POINT * d_speed, 8.0)
		cart_entry["push_accel"] = maxf(float(stock_base.get("push_accel", 15.0))
			+ CART_ACCEL_PER_POINT * d_accel - CART_WEIGHT_ACCEL_DRAG * d_weight, 6.0)
		cart_entry["grip"] = maxf(float(stock_base.get("grip", 0.90))
			+ CART_GRIP_PER_POINT * d_grip, 0.5)
		cart_entry["steering"] = maxf(float(stock_base.get("steering", 1.05))
			+ CART_STEER_PER_POINT * d_grip, 0.6)
		cart_entry["mass"] = maxf(float(stock_base.get("mass", 45.0))
			+ CART_MASS_PER_POINT * d_weight, 20.0)
		cart_entry["push_scale"] = maxf(float(stock_base.get("push_scale", 0.50))
			+ CART_PUSH_PER_POINT * d_weight, 0.2)
		cart_entry["racing_allocation"] = clean
		if tint.a > 0.0:
			cart_entry["tint_color"] = tint
		return cart_entry
	var base: Dictionary = racing_find(id)
	if base.is_empty():
		return {}
	var entry: Dictionary = base.duplicate(true)
	entry["max_speed"] = float(base.get("max_speed", 0.0)) \
		+ RACING_SPEED_PER_POINT * float(clean["top_speed"])
	entry["engine_power"] = float(base.get("engine_power", 0.0)) \
		+ RACING_POWER_PER_POINT * float(clean["accel"])
	entry["grip"] = float(base.get("grip", 1.0)) \
		+ RACING_GRIP_PER_POINT * float(clean["grip"])
	entry["steering"] = float(base.get("steering", 1.0)) \
		+ RACING_STEER_PER_POINT * float(clean["grip"])
	entry["mass"] = float(base.get("mass", 0.0)) \
		+ RACING_MASS_PER_POINT * float(clean["weight"])
	entry["push_scale"] = float(base.get("push_scale", 1.0)) \
		+ RACING_PUSH_PER_POINT * float(clean["weight"])
	entry["racing_allocation"] = clean
	if tint.a > 0.0:
		entry["tint_color"] = tint
	return entry


static func tinted_racing_entry(id: String, tint: Color) -> Dictionary:
	## Base chassis plus a paint tint only. Remote ghosts use this when only a
	## colour swatch is needed, including custom Shopping Cart paint.
	if id == DEFAULT_ID:
		var stock_base: Dictionary = find(DEFAULT_ID)
		if stock_base.is_empty():
			return {}
		var cart_entry: Dictionary = stock_base.duplicate(true)
		if tint.a > 0.0:
			cart_entry["tint_color"] = tint
		return cart_entry
	var base: Dictionary = racing_find(id)
	if base.is_empty():
		return {}
	var entry: Dictionary = base.duplicate(true)
	if tint.a > 0.0:
		entry["tint_color"] = tint
	return entry


static func find(id: String) -> Dictionary:
	## Sandbox roster first (unchanged order), then the racing class. Callers
	## that need to distinguish the two use is_racing_id(). The default id lives
	## in the sandbox roster, so the stock cart always resolves there.
	for entry: Dictionary in VEHICLES:
		if str(entry.get("id", "")) == id:
			return entry
	for entry: Dictionary in RACING_VEHICLES:
		if str(entry.get("id", "")) == id:
			return entry
	return {}


static func index_of(id: String) -> int:
	## Sandbox roster index only. Racing cars have their own list and index
	## helper so a sandbox picker can never point at the wrong array.
	for index in VEHICLES.size():
		if str(VEHICLES[index].get("id", "")) == id:
			return index
	return 0
