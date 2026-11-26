extends RefCounted
## Glacier Pass: a raised alpine circuit dressed entirely in flat Kenney art.
##
## Entry point, called by grass_race once per race:
##
##   static func build(race: Node3D, spline) -> void
##
## KenneyTiles owns the road, its colliders and the spline; this theme dresses
## the pass and every solid piece is placed through scripts/minigames/tile_kit.gd
## or the glacier prop layer, so the map batches into a few dozen MultiMeshes and
## every prop collides on CollisionLayers.WORLD.
##
## The dress, outside in:
##
##   layout    barrier ring at the road edge, snowbank banks, avalanche fencing,
##             start gantry, two grandstands, ten floodlights, summit flags,
##             banner towers and the pit-lane split (glacier_layout.gd);
##   forest    a six-cell pine band around the loop plus an infield island and
##             underbrush (glacier_forest.gd);
##   terrain   rock faces under every raised deck, boulder outcrops, three rings
##             of distant ridges and a ski-lift line (glacier_terrain.gd);
##   ice       the slippery span painted on the descent (glacier_ice.gd);
##   ground    one flat snow plate replacing the photo-scanned meadow.
##
## Terrain: the circuit is authored with the grid engine's per-cell heights -
## summit plateau, crest ramp, long descent, lower return leg - by
## glacier_course.gd. That file is the route spec; the map registry
## (track_defs.gd) is what grass_race reads, and merging
## GlacierCourse.preset_fields() into the glacier preset is the whole
## integration. When the registry still carries the flat loop this theme quietly
## dresses it flat and prints a one-line note, so the map can never break over a
## missing height table.
##
## No photo texture is referenced anywhere: the art is the Kenney racing and
## nature kits only. The build is idempotent, so a scene reload can never double
## the props.

const TileKit := preload("res://scripts/minigames/tile_kit.gd")
const GlacierLayout := preload("res://scripts/minigames/maps/glacier/glacier_layout.gd")
const GlacierForest := preload("res://scripts/minigames/maps/glacier/glacier_forest.gd")
const GlacierTerrain := preload("res://scripts/minigames/maps/glacier/glacier_terrain.gd")
const GlacierIce := preload("res://scripts/minigames/maps/glacier/glacier_ice.gd")
const GlacierGround := preload("res://scripts/minigames/maps/glacier/glacier_ground.gd")
const GlacierSurface := preload("res://scripts/minigames/maps/glacier/glacier_surface.gd")
const GlacierCourse := preload("res://scripts/minigames/maps/glacier/glacier_course.gd")
const GlacierChasm := preload("res://scripts/minigames/maps/glacier/glacier_chasm.gd")
const AmbientWorld := preload("res://scripts/minigames/scenery/ambient_world.gd")

const HOLDER_NAME: String = "GlacierDressing"
const META_STATS: String = "glacier_stats"


## Builds the whole glacier dressing under `race`. `spline` is the grid spline
## KenneyTiles.build returned, or the legacy TrackSpline while the race scene is
## still being wired; both expose the sample/total_length surface the modules
## read.
static func build(race: Node3D, spline) -> void:
	if race == null:
		push_warning("GlacierTheme: build() needs the race root.")
		return
	if spline == null:
		push_warning("GlacierTheme: build() needs the race spline; nothing was dressed.")
		return
	if race.has_node(HOLDER_NAME):
		return
	TileKit.dress_track(race, spline, {
		"id": "glacier",
		"hoarding_density": 0.0,
		"kerb_a": Color("f4f9ff"),
		"kerb_b": Color("3b8ec9"),
	})
	var preset: Dictionary = GlacierSurface.preset_for(race)
	var holder := Node3D.new()
	holder.name = HOLDER_NAME
	race.add_child(holder)
	AmbientWorld.build_track(holder, spline, "glacier")
	var layout: Dictionary = GlacierLayout.build(holder, spline, preset)
	var forest: Dictionary = GlacierForest.build(holder, spline)
	var terrain: Dictionary = GlacierTerrain.build(holder, spline)
	var ice: Dictionary = GlacierIce.build(holder, race, spline, preset)
	var chasm: Dictionary = GlacierChasm.build(holder, race, spline)
	var ground: int = GlacierGround.build(race, preset)
	_apply_climate(race, preset)
	var measured: Dictionary = _measure(holder)
	var stats: Dictionary = {
		"objects": int(measured["objects"]),
		"draws": int(measured["draws"]) + int(ice.get("draws", 0)) + ground,
		"barriers": int(layout.get("barriers", 0)),
		"stands": int(layout.get("stands", 0)),
		"gantry": int(layout.get("gantry", 0)),
		"lights": int(layout.get("lights", 0)),
		"flags": int(layout.get("flags", 0)),
		"signage": int(layout.get("signage", 0)),
		"snowbanks": int(layout.get("snowbanks", 0)),
		"fences": int(layout.get("fences", 0)),
		"split": int(layout.get("split", 0)),
		"pines": int(forest.get("pines", 0)),
		"brush": int(forest.get("brush", 0)),
		"cliffs": int(terrain.get("cliffs", 0)),
		"outcrops": int(terrain.get("outcrops", 0)),
		"ridges": int(terrain.get("ridges", 0)),
		"pylons": int(terrain.get("pylons", 0)),
		"chasms": int(chasm.get("chasms", 0)),
		"ice_spans": int(ice.get("spans", 0)),
		"ice_length": float(ice.get("length", 0.0)),
		"ice_top": float(ice.get("top", 0.0)),
		"ground": ground,
		"elevation": _elevation(spline),
		"flat": _elevation(spline) < 0.5,
	}
	stats["clearance"] = _clearance(race, spline, int(stats["barriers"]))
	print("GLACIER PASS: %d objects, ~%d draw calls, %d barrier pieces, %d pines, %d snowbanks, %d fence panels" % [
		int(stats["objects"]), int(stats["draws"]), int(stats["barriers"]),
		int(stats["pines"]), int(stats["snowbanks"]), int(stats["fences"])])
	print("GLACIER PASS: %d rock faces, %d outcrops, %d ridges, %d lift pylons, %d stands, %d lights, %d flags, %d signs, %d split pieces" % [
		int(stats["cliffs"]), int(stats["outcrops"]), int(stats["ridges"]),
		int(stats["pylons"]), int(stats["stands"]), int(stats["lights"]),
		int(stats["flags"]), int(stats["signage"]), int(stats["split"])])
	print("GLACIER PASS: elevation %.1f m, ice %.0f%% of the lap in %d span(s) (%.0f m), white ground %s" % [
		float(stats["elevation"]), GlacierSurface.ice_fraction(preset) * 100.0,
		int(stats["ice_spans"]), float(stats["ice_length"]),
		"on" if ground > 0 else "kept"])
	if bool(stats["flat"]):
		print("GLACIER PASS: registry grid is still the flat %d-cell loop; the authored pass (%s) is in GlacierCourse.preset_fields(), so copy that into the glacier preset in track_defs.gd." % [
			int((spline.get("tiles") as Array).size()), GlacierCourse.summary()])
	race.set_meta(META_STATS, stats)


## Highest road deck on the lap, in metres, sampled finely enough to find the
## summit between two tile joints.
static func _elevation(spline: RefCounted) -> float:
	var total: float = maxf(float(spline.total_length), 1.0)
	var highest: float = 0.0
	for index in 96:
		var frame: Dictionary = spline.call("sample",
			total * float(index) / 96.0) as Dictionary
		highest = maxf(highest, (frame["position"] as Vector3).y)
	return highest


## Runs the kit's own barrier audit, so every race prints the measured clearance
## of its wall from the racing line and a regression fails loudly.
static func _clearance(race: Node3D, spline: RefCounted, barriers: int) -> float:
	var report: Dictionary = TileKit.barrier_clearance(race, spline)
	print("GLACIER PASS: barrier clearance %.2f m (limit %.2f m, %d piece(s)) -> %s" % [
		float(report["closest"]), float(report["limit"]), int(report["pieces"]),
		"CLEARS" if bool(report["clears"]) else "ON THE ROAD"])
	if not bool(report["clears"]) and OS.is_debug_build():
		push_error("GlacierTheme: %d barrier piece(s) sit inside %.2f m of the centreline (closest %.2f m)." % [
			int(report["offenders"]), float(report["limit"]),
			float(report["closest"])])
	return float(report["closest"])


## Objects and draw calls of the built dressing, measured on the scene graph
## instead of estimated: one draw per MultiMesh or MeshInstance, and the object
## count is the instances those nodes actually hold.
static func _measure(holder: Node) -> Dictionary:
	var objects: int = 0
	var draws: int = 0
	for node: Node in _descendants(holder):
		var multi := node as MultiMeshInstance3D
		if multi != null and multi.multimesh != null:
			draws += 1
			objects += multi.multimesh.instance_count
			continue
		if node is MeshInstance3D:
			draws += 1
			objects += 1
	return {"objects": objects, "draws": draws}


static func _descendants(root: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in root.get_children():
		found.append(child)
		found.append_array(_descendants(child))
	return found


## Winter Night & Aurora Moonlit Alpine Grade:
## Keeps the sky a true deep dark winter night so the Northern Lights & stars pop,
## while bathing the 3D sculpted snow mountains, valley snowfields, and cliffs in
## luminous icy moonlight + soft opposite aurora fill light (zero black shadows!).
static func _apply_climate(race: Node3D, _preset: Dictionary) -> void:
	var world := race.get_node_or_null("WorldEnvironment") as WorldEnvironment
	if world != null and world.environment != null:
		var env: Environment = world.environment.duplicate() as Environment
		var winter_haze := Color("2b4f82")
		env.fog_enabled = true
		env.fog_mode = Environment.FOG_MODE_EXPONENTIAL
		env.fog_light_color = winter_haze
		env.fog_light_energy = 0.78
		env.fog_density = 0.00038
		env.fog_aerial_perspective = 0.22
		env.fog_sky_affect = 0.03
		env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
		env.ambient_light_color = Color("78aae8")
		env.ambient_light_energy = 0.74
		env.ambient_light_sky_contribution = 0.10
		env.glow_enabled = true
		env.glow_intensity = 0.48
		env.glow_bloom = 0.10
		env.glow_hdr_threshold = 1.02
		if env.sky != null and env.sky.sky_material is ProceduralSkyMaterial:
			var sky: ProceduralSkyMaterial = \
				env.sky.sky_material as ProceduralSkyMaterial
			sky.sky_top_color = Color("04081a")
			sky.sky_horizon_color = Color("152c54")
			sky.sky_curve = 0.20
			sky.ground_horizon_color = Color("224270")
			sky.ground_bottom_color = Color("142848")
		world.environment = env
	var sun := race.get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.light_color = Color("eaf4ff")
		sun.light_energy = 0.94
	if not race.has_node("GlacierAuroraFillLight"):
		var fill := DirectionalLight3D.new()
		fill.name = "GlacierAuroraFillLight"
		fill.light_color = Color("62a4eb")
		fill.light_energy = 0.36
		fill.shadow_enabled = false
		fill.rotation_degrees = Vector3(-36.0, 142.0, 0.0)
		race.add_child(fill)
