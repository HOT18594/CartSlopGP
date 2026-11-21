extends RefCounted
## REDWOOD VALLEY (`meadow`): rolling woodland & river valley circuit.
##
## Entry point called by grass_race / preview_render / preview_verify:
##   static func build(race: Node3D, spline) -> void

const TileKit := preload("res://scripts/minigames/tile_kit.gd")
const MeadowScenery := preload("res://scripts/minigames/maps/meadow/meadow_scenery.gd")
const AmbientWorld := preload("res://scripts/minigames/scenery/ambient_world.gd")

const THEME_ID: String = "meadow"
const HOLDER_NAME: String = "MeadowDressing"
const META_STATS: String = "meadow_stats"
const HOARDING_DENSITY: float = 0.0


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
	_apply_valley_atmosphere(race)
	TileKit.dress_track(race, track, {
		"id": THEME_ID,
		"hoarding_density": HOARDING_DENSITY,
		"kerb_a": Color("f3ead6"),
		"kerb_b": Color("c9562c"),
	})
	var holder := Node3D.new()
	holder.name = HOLDER_NAME
	race.add_child(holder)
	AmbientWorld.build_track(holder, track, THEME_ID)
	var stats: Dictionary = MeadowScenery.build(holder, track)
	race.set_meta(META_STATS, stats)
	print("REDWOOD VALLEY: %d objects, %d draw nodes, %d barriers, %d trees, %d flora, %d props, %d bluffs" % [
		int(stats.get("objects", 0)), int(stats.get("draws", 0)),
		int(stats.get("barriers", 0)), int(stats.get("trees", 0)),
		int(stats.get("flora", 0)), int(stats.get("props", 0)),
		int(stats.get("cliffs", 0))])


static func _apply_valley_atmosphere(race: Node3D) -> void:
	var world_env := race.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world_env != null and world_env.environment != null:
		var env: Environment = world_env.environment.duplicate() as Environment
		env.fog_enabled = true
		env.fog_light_color = Color("cfe9d8")
		env.fog_density = 0.0012
		env.fog_sky_affect = 0.18
		world_env.environment = env
