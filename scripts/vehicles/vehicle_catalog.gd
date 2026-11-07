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


static func all() -> Array[Dictionary]:
	return VEHICLES


static func find(id: String) -> Dictionary:
	for entry: Dictionary in VEHICLES:
		if str(entry.get("id", "")) == id:
			return entry
	return {}


static func index_of(id: String) -> int:
	for index in VEHICLES.size():
		if str(VEHICLES[index].get("id", "")) == id:
			return index
	return 0
