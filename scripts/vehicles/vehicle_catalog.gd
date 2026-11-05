extends RefCounted
## Playable sandbox vehicles. The kart from the special minigames is
## deliberately not listed here.

const DEFAULT_ID: String = "shopping_cart"

const VEHICLES: Array[Dictionary] = [
	{
		"id": "shopping_cart",
		"name": "SHOPPING CART",
		"scene": "res://assets/models/poly_pizza/shopping_cart/shopping_cart.glb",
		"length": 1.8,
		"yaw": 0.0,
	},
	{
		"id": "sedan",
		"name": "SEDAN",
		"scene": "res://assets/models/kenney_car-kit/Models/GLB format/sedan.glb",
		"length": 2.7,
		"yaw": 180.0,
	},
	{
		"id": "sports",
		"name": "SPORTS CAR",
		"scene": "res://assets/models/kenney_car-kit/Models/GLB format/sedan-sports.glb",
		"length": 2.7,
		"yaw": 180.0,
	},
	{
		"id": "taxi",
		"name": "TAXI",
		"scene": "res://assets/models/kenney_car-kit/Models/GLB format/taxi.glb",
		"length": 2.7,
		"yaw": 180.0,
	},
	{
		"id": "van",
		"name": "VAN",
		"scene": "res://assets/models/kenney_car-kit/Models/GLB format/van.glb",
		"length": 3.0,
		"yaw": 180.0,
	},
	{
		"id": "truck",
		"name": "BOX TRUCK",
		"scene": "res://assets/models/kenney_car-kit/Models/GLB format/truck.glb",
		"length": 3.4,
		"yaw": 180.0,
	},
	{
		"id": "police",
		"name": "POLICE CRUISER",
		"scene": "res://assets/models/kenney_car-kit/Models/GLB format/police.glb",
		"length": 2.7,
		"yaw": 180.0,
	},
]


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
