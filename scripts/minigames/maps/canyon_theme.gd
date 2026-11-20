extends RefCounted
## SUNSET CANYON (`canyon`): red-rock desert mesa & turquoise oasis circuit.
##
## Entry point called by grass_race / preview_render / preview_verify:
##   static func build(race: Node3D, spline) -> void

const TileKit := preload("res://scripts/minigames/tile_kit.gd")
const CanyonScenery := preload("res://scripts/minigames/maps/canyon/canyon_scenery.gd")
const AmbientWorld := preload("res://scripts/minigames/scenery/ambient_world.gd")

const THEME_ID: String = "canyon"
const HOLDER_NAME: String = "CanyonDressing"
const META_STATS: String = "canyon_stats"
const HOARDING_DENSITY: float = 0.22


static func build(race: Node3D, spline) -> void:
	if race == null or spline == null:
		return
	if race.has_node(HOLDER_NAME):
		return
	var track: RefCounted = spline as RefCounted
	if track == null:
		return
	var meadow_ground: Node3D = race.get_node_or_null("MeadowGround") as Node3D
	if meadow_ground != null:
		meadow_ground.visible = false
	_apply_sunset_atmosphere(race)
	TileKit.dress_track(race, track, {
		"id": THEME_ID,
		"hoarding_density": HOARDING_DENSITY,
	})
	var holder := Node3D.new()
	holder.name = HOLDER_NAME
	race.add_child(holder)
	var stats: Dictionary = CanyonScenery.build(holder, track)
	AmbientWorld.build_track(holder, track, THEME_ID)
	race.set_meta(META_STATS, stats)
	print("SUNSET CANYON: %d objects, %d draw nodes, %d barriers, %d mesas, %d arches, %d cliffs, %d palms, %d cacti" % [
		int(stats.get("objects", 0)), int(stats.get("draws", 0)),
		int(stats.get("barriers", 0)), int(stats.get("mesas", 0)),
		int(stats.get("arches", 0)), int(stats.get("cliffs", 0)),
		int(stats.get("palms", 0)), int(stats.get("cacti", 0))])


static func _apply_sunset_atmosphere(race: Node3D) -> void:
	var sun := race.get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.light_color = Color("ffd093")
		sun.light_energy = 1.25
	var world_env := race.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env != null and world_env.environment != null:
		var env: Environment = world_env.environment.duplicate() as Environment
		env.fog_enabled = true
		env.fog_light_color = Color("f6bf8a")
		env.fog_density = 0.0014
		env.fog_sky_affect = 0.22
		world_env.environment = env
