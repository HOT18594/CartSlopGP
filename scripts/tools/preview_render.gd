extends Node
## Renders the menu preview image for every map in TrackDefs.
##
## This is a tool scene, not a game screen. Run it with the editor binary in
## windowed mode (a real renderer is required: `--headless` captures blank
## frames) and it builds each map, frames the whole circuit with a high 3/4
## camera, adds a flat sky and a sun, captures a 1280x720 PNG into
## res://assets/ui/art/preview_<map_id>.png, verifies every file by loading it
## back and sampling its pixels, then quits itself.
##
##     Godot_v4.7.2-stable_win64_console.exe --path godot_project \
##         res://scripts/tools/preview_render.tscn
##
## Race maps are built from their real grass_race scene, so a preview can never
## drift from the circuit players actually drive. If that scene fails to build
## (a map that needs a network session, or a scene broken mid-refactor), the
## tool falls back to the map theme and the shared track builders dropped
## straight into a bare Node3D, never to placeholder geometry.
##
## The exit code is the number of previews that failed their checks (0 = all
## good), so a build script can gate on it.
##
## A new PNG is invisible to ResourceLoader until Godot imports it, so after a
## render run the binary once with `--headless --import` (or open the editor)
## before the menu will show the new cards.

const TrackDefs := preload("res://scripts/minigames/track_defs.gd")

## Loaded lazily: the map workstream may be rewriting these while a preview is
## being rendered, and a preview tool must never fail to parse over a file it
## only needs for the fallback path.
const TRACK_SPLINE_PATH: String = "res://scripts/minigames/track_spline.gd"
const TILE_LAYOUT_PATH: String = \
	"res://scripts/minigames/maps/tiles/tile_layout.gd"
const RACING_KIT_PATH: String = "res://scripts/minigames/racing_kit.gd"

const RACE_SCENE: String = "res://scenes/minigames/grass_race.tscn"
const THEME_PATH: String = "res://scripts/minigames/maps/%s_theme.gd"
const TRACKSIDE_STRUCTURES: String = \
	"res://scripts/minigames/scenery/trackside_structures.gd"
const TRACKSIDE_PROPS: String = \
	"res://scripts/minigames/scenery/trackside_props.gd"
const HORIZON_BUILDER: String = \
	"res://scripts/minigames/scenery/horizon_builder.gd"
const OUT_DIR: String = "res://assets/ui/art/"
const PREVIEW_PREFIX: String = "preview_"
const PBR_SHADER: String = "res://assets/materials/ground_pbr.gdshader"
const PBR_TEX: String = "res://assets/textures/polyhaven/"
## The bare fallback needs a field to stand on; the race scene normally builds
## its own 1400 m ground, so this only exists for the theme/track path.
const GROUND_SIZE: float = 4000.0

const WIDTH: int = 1280
const HEIGHT: int = 720
const MIN_PNG_BYTES: int = 40 * 1024
const MIN_COLOURS: int = 24
const MAX_FLAT_RATIO: float = 0.94
const SAMPLE_STEP: int = 12
const WAIT_FRAMES: int = 5

## Camera: fixed high 3/4 view, distance fitted to the projected circuit so the
## whole lap fills the frame instead of floating in a field.
const CAMERA_FOV: float = 40.0
const CAMERA_PITCH_DEG: float = 42.0
const CAMERA_YAW_DEG: float = 30.0
## Fraction of the frame the circuit may occupy before the fit is accepted.
const FRAME_FILL: float = 0.92
## Room around the centreline for grandstands, tree lines and run-off.
const SCENERY_MARGIN: float = 0.08
## Height of the tallest trackside prop, kept in frame while fitting.
const SCENERY_HEIGHT: float = 8.0
## A minigame arena has no spline; its floor is 100 m across, so frame that.
const MINIGAME_RADIUS: float = 66.0
## Meshes with a footprint larger than this are ground/backdrop, not landmarks.
const MAX_FRAME_MESH: float = 240.0
## A mesh flatter than this is a painted slab or apron, and is ignored when
## measuring an arena: the walls, crates and pads define the playable space.
const FLAT_MESH_HEIGHT: float = 0.08

const SKY_CLEAR := Color(0.38, 0.63, 0.86)
const SKY_WET := Color(0.46, 0.55, 0.62)
const SKY_ICE := Color(0.62, 0.75, 0.88)
const AMBIENT := Color(0.80, 0.86, 0.92)
const SUN_COLOUR := Color(1.0, 0.95, 0.86)

var _viewport: SubViewport


func _ready() -> void:
	if OS.get_environment("CART_PREVIEW_DRY_RUN") == "1":
		# Boot-only check for CI/`--quit-after`: proves the tool scene loads
		# without touching the art folder.
		print("preview_render: dry run, %d map(s) registered" \
			% TrackDefs.PRESETS.size())
		get_tree().quit(0)
		return
	_viewport = _make_viewport()
	await get_tree().process_frame
	var failures: int = 0
	var records: Array[Dictionary] = []
	for preset: Dictionary in TrackDefs.PRESETS:
		var record: Dictionary = await _render_preset(preset)
		records.append(record)
		if not bool(record["ok"]):
			failures += 1
	_report(records, failures)
	# Quitting without a frame of slack can drop the last queued log lines.
	await get_tree().process_frame
	get_tree().quit(failures)


# --------------------------------------------------------------------------
# render target
# --------------------------------------------------------------------------


func _make_viewport() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = "PreviewViewport"
	viewport.size = Vector2i(WIDTH, HEIGHT)
	# A private World3D keeps each map from seeing the leftovers of the last.
	viewport.own_world_3d = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	viewport.msaa_3d = Viewport.MSAA_2X
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	add_child(viewport)
	return viewport


# --------------------------------------------------------------------------
# one preview
# --------------------------------------------------------------------------


func _render_preset(preset: Dictionary) -> Dictionary:
	var map_id: String = str(preset.get("id", TrackDefs.DEFAULT_ID))
	var stage := Node3D.new()
	stage.name = "Map_" + map_id
	_viewport.add_child(stage)
	var built_from_scene: bool = false
	if TrackDefs.is_minigame(preset):
		built_from_scene = _build_minigame(preset, stage)
		if not built_from_scene:
			var skipped: Dictionary = _skip_minigame(map_id)
			stage.queue_free()
			await _wait_frames(2)
			return skipped
	else:
		built_from_scene = _build_race_map(preset, stage)
		if not built_from_scene:
			_build_bare_map(preset, stage)
	# Lighting is installed after the map so the map's own sky and sun can be
	# replaced by the flat preview grade rather than stacking on top of them.
	_install_lighting(stage, _sky_for(preset))
	var framing: Dictionary = _framing_for(preset, stage)
	var camera := _install_camera(stage, framing)
	_install_vignette(stage)
	await _wait_frames(WAIT_FRAMES)
	var image: Image = await _capture()
	var path: String = OUT_DIR + PREVIEW_PREFIX + map_id + ".png"
	var saved: bool = image != null and _save(image, path)
	var record: Dictionary = _verify(map_id, path) if saved else {
		"id": map_id, "path": path, "ok": false, "bytes": 0,
		"colours": 0, "flat": 1.0, "luminance": 0.0,
		"note": "capture failed",
	}
	record["scene"] = built_from_scene
	# A minigame scene is owned by another workstream and may be mid-rewrite.
	# Never leave a broken card behind: drop the file so the menu keeps its
	# fallback, and do not fail the map pass over an optional preview.
	if TrackDefs.is_minigame(preset) and not bool(record["ok"]):
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		record["ok"] = true
		record["note"] = "skipped: preview failed verification"
		record["skipped"] = true
	print("PREVIEW %s  %s  (%d bytes, %d colours, flat %.0f%%, %s%s)" % [
		map_id, "SKIP" if bool(record.get("skipped", false)) \
			else ("OK" if bool(record["ok"]) else "FAIL"),
		int(record["bytes"]), int(record["colours"]),
		float(record["flat"]) * 100.0,
		"scene" if built_from_scene else "theme fallback",
		"" if str(record.get("note", "")) == "" \
			else ", " + str(record.get("note", ""))])
	if camera != null:
		camera.current = false
	stage.queue_free()
	await _wait_frames(2)
	return record


# --------------------------------------------------------------------------
# map building
# --------------------------------------------------------------------------


## Instantiates the real race scene against `preset` and hides its HUD. The
## scene's _ready runs while the node is added, so the map is complete when
## this returns.
func _build_race_map(preset: Dictionary, stage: Node3D) -> bool:
	if OS.get_environment("CART_PREVIEW_FORCE_FALLBACK") == "1":
		# Test hook: exercise the bare theme/track-builder path without having
		# to break the real race scene.
		return false
	if not ResourceLoader.exists(RACE_SCENE):
		return false
	var packed: PackedScene = load(RACE_SCENE) as PackedScene
	if packed == null:
		return false
	# grass_race reads selected_map in _ready, which add_child triggers below.
	_set_autoload_property("GameSettings", "selected_map",
		str(preset.get("id", TrackDefs.DEFAULT_ID)))
	var race := packed.instantiate() as Node3D
	if race == null:
		return false
	stage.add_child(race)
	_hide_overlays(race)
	# A scene that errored out leaves almost nothing to look at; the caller
	# then rebuilds the map from its theme and the shared track builders.
	return _count_geometry(race) > 8


## Instantiates a hand-built minigame scene for its preview. The arena is the
## owner of its own layout, so this only hides the HUD and lets the map build.
func _build_minigame(preset: Dictionary, stage: Node3D) -> bool:
	var scene_path: String = str(preset.get("scene", ""))
	if scene_path == "" or not ResourceLoader.exists(scene_path):
		return false
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		return false
	var theme_id: String = TrackDefs.default_theme(preset)
	if theme_id != "":
		_set_autoload_property("GameSettings", "selected_minigame", theme_id)
	var scene := packed.instantiate() as Node3D
	if scene == null:
		return false
	stage.add_child(scene)
	_hide_overlays(scene)
	return _count_geometry(scene) > 8


## A minigame preview is optional: its scene belongs to another workstream and
## may need a session or be mid-rewrite. Report the skip without failing the
## map pass, and never leave a broken card in the art folder.
func _skip_minigame(map_id: String) -> Dictionary:
	var path: String = OUT_DIR + PREVIEW_PREFIX + map_id + ".png"
	if FileAccess.file_exists(path):
		DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
	print("PREVIEW %s  SKIP  (scene did not build)" % map_id)
	return {
		"id": map_id, "path": path, "ok": true, "skipped": true,
		"bytes": 0, "colours": 0, "flat": 1.0, "luminance": 0.0,
		"note": "skipped: scene did not build",
	}


## Fallback map build: the map's own theme plus the shared track builders on a
## bare Node3D. This is the same content the race scene assembles, minus the
## kart and HUD, and it needs no session or player scene.
func _build_bare_map(preset: Dictionary, stage: Node3D) -> void:
	var map_id: String = str(preset.get("id", TrackDefs.DEFAULT_ID))
	if preset.has("tiles"):
		_build_tile_fallback(preset, stage)
		return
	var spline: RefCounted = _new_spline(preset)
	if spline == null or spline.get("total_length") == null:
		return
	if float(spline.get("total_length")) <= 1.0:
		return
	_build_ground(stage, preset)
	# The road ribbon, kerbs and armco give the preview its circuit silhouette.
	var kit: Script = _load_script(RACING_KIT_PATH)
	if kit != null:
		var constants: Dictionary = kit.get_script_constant_map()
		var road_half: float = float(constants.get("ROAD_HALF", 5.5))
		kit.call("tarmac", stage, spline, 0.0, spline.get("total_length"),
			road_half * 2.0)
		for side: float in [-1.0, 1.0]:
			kit.call("kerbs", stage, spline, 0.0, spline.get("total_length"),
				side, Color("c23a2c"))
			kit.call("barriers", stage, spline, 0.0, spline.get("total_length"),
				side)
	# The map theme owns the ground, pit lane, stands and horizon. A map
	# without a theme still gets the shared trackside furniture so no preview
	# is ever an empty field.
	var themed: bool = _build_theme(stage, map_id, spline, preset)
	if not themed:
		_build_shared_trackside(stage, spline)
	_build_horizon(stage)


## The field the circuit sits on in the bare path. The race scene normally
## builds a meadow plane itself, so this exists only for the theme fallback.
## Surface data picks grass, asphalt or snow, matching the map's own grip rule.
func _build_ground(stage: Node3D, preset: Dictionary) -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	var ground := MeshInstance3D.new()
	ground.name = "PreviewGround"
	ground.mesh = plane
	ground.material_override = _ground_material(preset)
	ground.position = Vector3(0.0, -0.03, 0.0)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(ground)


func _ground_material(preset: Dictionary) -> Material:
	var diff: String = "grass_diff"
	var nor: String = "grass_nor"
	var rough: String = "grass_rough"
	var tint := Color(0.72, 0.88, 0.65)
	match _surface_kind(preset):
		"ice":
			diff = "snow_02_diff"
			nor = "snow_02_nor"
			rough = "snow_02_rough"
			tint = Color(0.90, 0.94, 1.0)
		"wet":
			diff = "asphalt_02_diff"
			nor = "asphalt_02_nor"
			rough = "asphalt_02_rough"
			tint = Color(0.62, 0.66, 0.70)
	var paths: PackedStringArray = [PBR_TEX + diff + ".jpg", PBR_TEX + nor + ".jpg",
		PBR_TEX + rough + ".jpg"]
	var complete: bool = true
	for path: String in paths:
		complete = complete and ResourceLoader.exists(path)
	if ResourceLoader.exists(PBR_SHADER) and complete:
		var mat := ShaderMaterial.new()
		mat.shader = load(PBR_SHADER) as Shader
		mat.set_shader_parameter("albedo_tex", load(paths[0]))
		mat.set_shader_parameter("normal_tex", load(paths[1]))
		mat.set_shader_parameter("rough_tex", load(paths[2]))
		mat.set_shader_parameter("uv_scale", GROUND_SIZE / 10.0)
		mat.set_shader_parameter("tint", tint)
		mat.set_shader_parameter("detail_strength", 0.10)
		mat.set_shader_parameter("macro_variation", 0.05)
		mat.set_shader_parameter("roughness_min", 0.55)
		return mat
	var fallback := StandardMaterial3D.new()
	fallback.albedo_color = tint
	fallback.roughness = 0.94
	return fallback


## The dominant surface of a map: ice beats wet beats dry.
func _surface_kind(preset: Dictionary) -> String:
	var wet: bool = false
	for entry: Variant in preset.get("surfaces", []) as Array:
		if not (entry is Dictionary):
			continue
		match str((entry as Dictionary).get("kind", "normal")):
			"ice":
				return "ice"
			"wet":
				wet = true
	return "wet" if wet else "normal"


## Tile-pattern maps have no spline; their fallback road is the layout's own
## centreline widened by the per-tile half width, so a broken race scene still
## previews the real plan shape instead of a default circuit.
func _build_tile_fallback(preset: Dictionary, stage: Node3D) -> void:
	var layout: RefCounted = _new_tile_layout(preset)
	_build_ground(stage, preset)
	if layout == null:
		_build_horizon(stage)
		return
	var points: Variant = layout.get("points")
	if points is PackedVector3Array and not (points as PackedVector3Array).is_empty():
		_build_layout_ribbon(stage, layout, points as PackedVector3Array)
	_build_horizon(stage)


func _build_layout_ribbon(stage: Node3D, layout: RefCounted,
		points: PackedVector3Array) -> void:
	var count: int = points.size()
	if count < 3:
		return
	var cumulative := PackedFloat32Array()
	var raw: Variant = layout.get("cumulative")
	if raw is PackedFloat32Array:
		cumulative = raw as PackedFloat32Array
	var can_width: bool = layout.has_method("half_width_at")
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	for i in count + 1:
		var index: int = i % count
		var point: Vector3 = points[index]
		var before: Vector3 = points[(index - 1 + count) % count]
		var after: Vector3 = points[(index + 1) % count]
		var forward: Vector3 = (after - before).normalized()
		var right: Vector3 = forward.cross(Vector3.UP).normalized()
		var distance: float = cumulative[index] if cumulative.size() == count else 0.0
		var half: float = float(layout.call("half_width_at", distance)) \
			if can_width else 5.5
		verts.append(point - right * half + Vector3.UP * 0.04)
		verts.append(point + right * half + Vector3.UP * 0.04)
		norms.append(Vector3.UP)
		norms.append(Vector3.UP)
		var v: float = distance / 6.0
		uvs.append(Vector2(0.0, v))
		uvs.append(Vector2(1.0, v))
	for i in count:
		var a: int = i * 2
		indices.append(a)
		indices.append(a + 2)
		indices.append(a + 1)
		indices.append(a + 1)
		indices.append(a + 2)
		indices.append(a + 3)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	var road := MeshInstance3D.new()
	road.name = "FallbackRoad"
	road.mesh = mesh
	road.material_override = _road_material()
	stage.add_child(road)


func _road_material() -> Material:
	var paths: PackedStringArray = [
		PBR_TEX + "asphalt_01_diff.jpg", PBR_TEX + "asphalt_01_nor.jpg",
		PBR_TEX + "asphalt_01_rough.jpg"]
	var complete: bool = true
	for path: String in paths:
		complete = complete and ResourceLoader.exists(path)
	if ResourceLoader.exists(PBR_SHADER) and complete:
		var mat := ShaderMaterial.new()
		mat.shader = load(PBR_SHADER) as Shader
		mat.set_shader_parameter("albedo_tex", load(paths[0]))
		mat.set_shader_parameter("normal_tex", load(paths[1]))
		mat.set_shader_parameter("rough_tex", load(paths[2]))
		mat.set_shader_parameter("uv_scale", 1.0)
		mat.set_shader_parameter("tint", Color(0.72, 0.73, 0.75))
		mat.set_shader_parameter("detail_strength", 0.10)
		mat.set_shader_parameter("macro_variation", 0.03)
		mat.set_shader_parameter("roughness_min", 0.55)
		return mat
	var fallback := StandardMaterial3D.new()
	fallback.albedo_color = Color(0.34, 0.34, 0.36)
	fallback.roughness = 0.9
	return fallback


func _new_tile_layout(preset: Dictionary) -> RefCounted:
	if not preset.has("tiles"):
		return null
	var script: Script = _load_script(TILE_LAYOUT_PATH)
	if script == null:
		return null
	return script.new(preset) as RefCounted


## Runs the map's theme hook. A preset may name its script explicitly (the
## tile-map presets do), otherwise the historical maps/<id>_theme.gd is used.
func _build_theme(stage: Node3D, map_id: String, spline: RefCounted,
		preset: Dictionary = {}) -> bool:
	var candidates: PackedStringArray = PackedStringArray()
	var declared: String = str(preset.get("theme", ""))
	if declared != "":
		candidates.append(declared)
	candidates.append(THEME_PATH % map_id)
	for path: String in candidates:
		if not ResourceLoader.exists(path):
			continue
		var theme_script: Script = load(path) as Script
		if theme_script == null or not theme_script.has_method("build"):
			continue
		theme_script.call("build", stage, spline)
		return true
	return false


func _build_shared_trackside(stage: Node3D, spline: RefCounted) -> void:
	var holder := Node3D.new()
	holder.name = "SharedTrackside"
	stage.add_child(holder)
	var rng := RandomNumberGenerator.new()
	rng.seed = 9137
	var stats: Dictionary = {}
	for path: String in [TRACKSIDE_STRUCTURES, TRACKSIDE_PROPS]:
		if not ResourceLoader.exists(path):
			continue
		var builder: Script = load(path) as Script
		if builder != null and builder.has_method("build"):
			builder.call("build", holder, spline, rng, stats)


func _build_horizon(stage: Node3D) -> void:
	if not ResourceLoader.exists(HORIZON_BUILDER):
		return
	var builder: Script = load(HORIZON_BUILDER) as Script
	if builder != null and builder.has_method("build"):
		builder.call("build", stage, {})


# --------------------------------------------------------------------------
# lighting and camera
# --------------------------------------------------------------------------


func _sky_for(preset: Dictionary) -> Color:
	## Dry circuits get a clear sky, a wet calendar gets overcast steel and an
	## ice map gets a pale cold sky. The tint comes from the same surface data
	## the race scene reads for grip, so a preview always reads as its map.
	for entry: Variant in preset.get("surfaces", []) as Array:
		if not (entry is Dictionary):
			continue
		match str((entry as Dictionary).get("kind", "normal")):
			"ice":
				return SKY_ICE
			"wet":
				return SKY_WET
	return SKY_CLEAR


func _install_lighting(stage: Node3D, sky_colour: Color) -> void:
	# One sun, pointing down the same warm north-west line the game uses. The
	# shadow distance covers the whole circuit, not the chase camera's 100 m.
	for node: Node in _nodes_of_type(stage, "DirectionalLight3D"):
		node.get_parent().remove_child(node)
		node.free()
	var sun := DirectionalLight3D.new()
	sun.name = "PreviewSun"
	sun.rotation_degrees = Vector3(-54.0, -36.0, 0.0)
	sun.light_color = SUN_COLOUR
	sun.light_energy = 1.30
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 900.0
	stage.add_child(sun)

	for node: Node in _nodes_of_type(stage, "WorldEnvironment"):
		node.get_parent().remove_child(node)
		node.free()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = sky_colour
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = AMBIENT
	environment.ambient_light_energy = 0.62
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.94
	environment.tonemap_white = 1.10
	environment.fog_enabled = true
	environment.fog_light_color = sky_colour.lightened(0.14)
	environment.fog_light_energy = 1.0
	environment.fog_density = 0.00035
	environment.fog_sky_affect = 1.0
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 1.00
	environment.adjustment_contrast = 1.06
	environment.adjustment_saturation = 1.16
	var world := WorldEnvironment.new()
	world.name = "PreviewEnvironment"
	world.environment = environment
	stage.add_child(world)


## The circuit's centreline expanded outwards for run-off scenery. The camera
## fit projects every point (plus the tallest props) into the 1280x720 frame.
## The centreline comes from the built scene when the race exposes one, so a
## tile-layout or any future map still frames its whole circuit; the spline
## generated from the preset data is only the fallback.
func _framing_for(preset: Dictionary, stage: Node3D) -> Dictionary:
	if TrackDefs.is_minigame(preset):
		# A minigame has no centreline: frame the arena from its own geometry,
		# ignoring backdrops and horizon shells, then fall back to the nominal
		# 100 m floor if the scene exposed nothing measurable.
		var bounds: AABB = _visual_bounds(stage)
		if bounds.size.length_squared() > 1.0:
			return _expand_framing(_box_corners(bounds))
		var arena := PackedVector3Array()
		for i in 24:
			var angle: float = TAU * float(i) / 24.0
			arena.append(Vector3(cos(angle), 0.0, sin(angle)) * MINIGAME_RADIUS)
		return {"centre": Vector3.ZERO, "points": arena}
	var points: PackedVector3Array = _track_points_from(stage)
	if points.is_empty():
		var layout: RefCounted = _new_tile_layout(preset)
		if layout != null and layout.get("points") is PackedVector3Array:
			points = layout.get("points") as PackedVector3Array
	if points.is_empty():
		var spline: RefCounted = _new_spline(preset)
		if spline != null and spline.get("points") is PackedVector3Array:
			points = spline.get("points") as PackedVector3Array
	return _expand_framing(points)


## Centres and pads a set of framing points for the camera fit.
func _expand_framing(points: PackedVector3Array) -> Dictionary:
	if points.is_empty():
		return {"centre": Vector3.ZERO, "points": PackedVector3Array()}
	var min_point: Vector3 = points[0]
	var max_point: Vector3 = points[0]
	for point: Vector3 in points:
		min_point = min_point.min(point)
		max_point = max_point.max(point)
	var centre: Vector3 = (min_point + max_point) * 0.5
	var expanded := PackedVector3Array()
	for point: Vector3 in points:
		expanded.append(centre + (point - centre) * (1.0 + SCENERY_MARGIN))
	return {"centre": centre, "points": expanded}


## World bounds of the visible arena geometry. Ground slabs and horizon shells
## are skipped so a 1400 m backdrop cannot zoom the arena out to a dot.
func _visual_bounds(root: Node) -> AABB:
	var state: Dictionary = {}
	_collect_visual_bounds(root, state)
	if not state.has("bounds"):
		return AABB()
	return state["bounds"] as AABB


func _collect_visual_bounds(root: Node, state: Dictionary) -> void:
	for child: Node in root.get_children():
		if child is MeshInstance3D:
			var mesh: Mesh = (child as MeshInstance3D).mesh
			if mesh != null:
				var local: AABB = mesh.get_aabb()
				# Flat slabs are ground/aprons and define no play area; huge
				# meshes are backdrops. The arena walls and props frame it.
				if local.size.y >= FLAT_MESH_HEIGHT \
						and local.size.x <= MAX_FRAME_MESH \
						and local.size.z <= MAX_FRAME_MESH:
					var world: AABB = _transform_aabb(
						(child as MeshInstance3D).global_transform, local)
					if state.has("bounds"):
						state["bounds"] = (state["bounds"] as AABB).merge(world)
					else:
						state["bounds"] = world
		_collect_visual_bounds(child, state)


func _transform_aabb(xform: Transform3D, box: AABB) -> AABB:
	var out: AABB = AABB(xform * box.position, Vector3.ZERO)
	for ix: int in [0, 1]:
		for iy: int in [0, 1]:
			for iz: int in [0, 1]:
				var corner: Vector3 = box.position + Vector3(
					box.size.x * float(ix), box.size.y * float(iy),
					box.size.z * float(iz))
				out = out.expand(xform * corner)
	return out


func _box_corners(box: AABB) -> PackedVector3Array:
	var points := PackedVector3Array()
	for ix: int in [0, 1]:
		for iy: int in [0, 1]:
			for iz: int in [0, 1]:
				points.append(box.position + Vector3(box.size.x * float(ix),
					box.size.y * float(iy), box.size.z * float(iz)))
	return points


## The live centreline the built race scene uses for laps, rivals and bot
## steering. Reading it keeps the camera correct no matter whether the map is
## a spline preset or a tile layout; an empty result means a minigame or a
## scene that failed to build.
func _track_points_from(root: Node) -> PackedVector3Array:
	for child: Node in root.get_children():
		if _has_property(child, "_track_points"):
			var raw: Variant = child.get("_track_points")
			var points: PackedVector3Array = _as_points(raw)
			if not points.is_empty():
				return points
		if _has_property(child, "_spline"):
			var spline: Variant = child.get("_spline")
			if spline != null and spline.get("points") is PackedVector3Array:
				var spline_points: PackedVector3Array = spline.get("points")
				if not spline_points.is_empty():
					return spline_points
		var nested: PackedVector3Array = _track_points_from(child)
		if not nested.is_empty():
			return nested
	return PackedVector3Array()


func _as_points(raw: Variant) -> PackedVector3Array:
	if raw is PackedVector3Array:
		return raw
	var points := PackedVector3Array()
	if raw is Array:
		for entry: Variant in raw as Array:
			if entry is Vector3:
				points.append(entry)
	return points


func _has_property(node: Node, property: String) -> bool:
	for entry: Dictionary in node.get_property_list():
		if str(entry.get("name", "")) == property:
			return true
	return false


## A fresh TrackSpline for `preset`, or null when the map workstream has
## replaced the script (the scene path above is the primary preview source).
func _new_spline(preset: Dictionary) -> RefCounted:
	var script: Script = _load_script(TRACK_SPLINE_PATH)
	if script == null:
		return null
	return script.new(preset) as RefCounted


func _load_script(path: String) -> Script:
	if not ResourceLoader.exists(path):
		return null
	return load(path) as Script


## Fits a fixed-orientation perspective camera around the expanded centreline
## by binary-searching the nearest distance that keeps every point inside
## FRAME_FILL of the frame. An aerial sphere fit left the loop small in the
## middle of an empty field; this fills the card with the actual circuit.
func _install_camera(stage: Node3D, framing: Dictionary) -> Camera3D:
	var centre: Vector3 = framing["centre"] as Vector3
	var points: PackedVector3Array = framing["points"] as PackedVector3Array
	var camera := Camera3D.new()
	camera.name = "PreviewCamera"
	camera.fov = CAMERA_FOV
	camera.near = 0.5
	camera.far = 4000.0
	stage.add_child(camera)
	var yaw: float = deg_to_rad(CAMERA_YAW_DEG)
	var pitch: float = deg_to_rad(CAMERA_PITCH_DEG)
	var direction := Vector3(sin(yaw) * cos(pitch), sin(pitch),
		cos(yaw) * cos(pitch))
	var distance: float = _fit_distance(centre, points, direction)
	camera.look_at_from_position(centre + direction * distance, centre,
		Vector3.UP)
	camera.current = true
	return camera


## Smallest eye distance at which every ground point and every prop top stays
## inside FRAME_FILL of the normalised device coordinates. `direction` points
## from the target towards the camera.
func _fit_distance(centre: Vector3, points: PackedVector3Array,
		direction: Vector3) -> float:
	if points.is_empty():
		return MINIGAME_RADIUS * 4.0
	var radius: float = 1.0
	for point: Vector3 in points:
		radius = maxf(radius, point.distance_to(centre))
	var low: float = radius * 0.4
	var high: float = radius * 18.0
	for i in 48:
		var mid: float = (low + high) * 0.5
		if _frame_extent(centre, points, direction, mid) <= FRAME_FILL:
			high = mid
		else:
			low = mid
	return high


## Largest |NDC| coordinate over the circuit and its prop tops at `distance`.
func _frame_extent(centre: Vector3, points: PackedVector3Array,
		direction: Vector3, distance: float) -> float:
	var eye: Vector3 = centre + direction * distance
	var backward: Vector3 = direction
	var right: Vector3 = Vector3.UP.cross(backward).normalized()
	var up: Vector3 = backward.cross(right).normalized()
	var tan_vertical: float = tan(deg_to_rad(CAMERA_FOV) * 0.5)
	var tan_horizontal: float = tan_vertical * float(WIDTH) / float(HEIGHT)
	var worst: float = 0.0
	for point: Vector3 in points:
		for lift: float in [0.0, SCENERY_HEIGHT]:
			var relative: Vector3 = point + Vector3.UP * lift - eye
			# In front of the camera is positive along -backward.
			var depth: float = -relative.dot(backward)
			if depth <= 0.5:
				return INF
			worst = maxf(worst, absf(relative.dot(right) / depth) / tan_horizontal)
			worst = maxf(worst, absf(relative.dot(up) / depth) / tan_vertical)
	return worst


## A soft dark vignette keeps the eye on the circuit and makes the card read
## as designed art rather than a raw screenshot.
func _install_vignette(stage: Node3D) -> void:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.58, 1.0])
	gradient.colors = PackedColorArray([
		Color(0.0, 0.0, 0.0, 0.0), Color(0.0, 0.0, 0.0, 0.0),
		Color(0.02, 0.04, 0.08, 0.30)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.86)
	texture.width = 512
	texture.height = 512
	var rect := TextureRect.new()
	rect.name = "PreviewVignette"
	rect.texture = texture
	rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	rect.stretch_mode = TextureRect.STRETCH_SCALE
	rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var layer := CanvasLayer.new()
	layer.name = "PreviewOverlay"
	layer.add_child(rect)
	stage.add_child(layer)


# --------------------------------------------------------------------------
# capture and verification
# --------------------------------------------------------------------------


func _wait_frames(count: int) -> void:
	for i in count:
		await get_tree().process_frame


func _capture() -> Image:
	await RenderingServer.frame_post_draw
	if _viewport == null:
		return null
	var texture: ViewportTexture = _viewport.get_texture()
	if texture == null:
		return null
	return texture.get_image()


func _save(image: Image, path: String) -> bool:
	var absolute: String = ProjectSettings.globalize_path(path)
	var directory: String = absolute.get_base_dir()
	if not DirAccess.dir_exists_absolute(directory):
		DirAccess.make_dir_recursive_absolute(directory)
	var error: Error = image.save_png(absolute)
	if error != OK:
		push_error("preview_render: could not save %s (%s)" % [
			absolute, error_string(error)])
		return false
	return true


## Reloads the PNG from disk and checks it is a real 1280x720 picture: big
## enough, many distinct colours and no single dominant flat fill.
func _verify(map_id: String, path: String) -> Dictionary:
	var absolute: String = ProjectSettings.globalize_path(path)
	var record: Dictionary = {
		"id": map_id, "path": path, "ok": false, "bytes": 0,
		"colours": 0, "flat": 1.0, "luminance": 0.0, "note": "",
	}
	var file := FileAccess.open(absolute, FileAccess.READ)
	if file == null:
		record["note"] = "missing file"
		return record
	record["bytes"] = file.get_length()
	file.close()
	var image := Image.new()
	var error: Error = image.load(absolute)
	if error != OK:
		record["note"] = "cannot decode (%s)" % error_string(error)
		return record
	if image.get_width() != WIDTH or image.get_height() != HEIGHT:
		record["note"] = "wrong size %dx%d" % [image.get_width(), image.get_height()]
		return record
	var buckets: Dictionary = {}
	var samples: int = 0
	var luminance: float = 0.0
	var dominant: int = 0
	for y: int in range(0, HEIGHT, SAMPLE_STEP):
		for x: int in range(0, WIDTH, SAMPLE_STEP):
			var colour: Color = image.get_pixel(x, y)
			var key: int = (int(colour.r * 31.0) << 10) \
				| (int(colour.g * 31.0) << 5) | int(colour.b * 31.0)
			var seen: int = int(buckets.get(key, 0)) + 1
			buckets[key] = seen
			dominant = maxi(dominant, seen)
			luminance += colour.get_luminance()
			samples += 1
	var flat: float = float(dominant) / float(maxi(samples, 1))
	var average: float = luminance / float(maxi(samples, 1))
	record["colours"] = buckets.size()
	record["flat"] = flat
	record["luminance"] = average
	record["ok"] = int(record["bytes"]) > MIN_PNG_BYTES \
		and buckets.size() >= MIN_COLOURS and flat < MAX_FLAT_RATIO \
		and average > 0.02
	if not bool(record["ok"]):
		record["note"] = "flat or empty capture"
	return record


# --------------------------------------------------------------------------
# node helpers
# --------------------------------------------------------------------------


## Sets a property on an autoload through the tree instead of a global name.
## Autoload identifiers are not resolvable by `--check-only`, so going through
## /root keeps the tool parseable without the known false positive.
func _set_autoload_property(autoload_name: String, property: String,
		value: Variant) -> void:
	var autoload: Node = get_node_or_null("/root/" + autoload_name)
	if autoload != null:
		autoload.set(property, value)


func _hide_overlays(root: Node) -> void:
	## The race and minigame scenes both parent their UI to the map node. A
	## preview must not contain the HUD, pause menu or result card.
	for child: Node in root.get_children():
		if child is CanvasLayer:
			(child as CanvasLayer).visible = false
			child.process_mode = Node.PROCESS_MODE_DISABLED
		elif child is Control:
			(child as Control).visible = false
			child.process_mode = Node.PROCESS_MODE_DISABLED


func _count_geometry(root: Node) -> int:
	var count: int = 0
	for child: Node in root.get_children():
		if child is GeometryInstance3D:
			count += 1
		count += _count_geometry(child)
	return count


func _nodes_of_type(root: Node, type_name: String) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in root.get_children():
		if child.is_class(type_name):
			found.append(child)
		else:
			found.append_array(_nodes_of_type(child, type_name))
	return found


# --------------------------------------------------------------------------
# report
# --------------------------------------------------------------------------


func _report(records: Array[Dictionary], failures: int) -> void:
	print("---- preview_render: %d map(s), %d failure(s) ----" % [
		records.size(), failures])
	for record: Dictionary in records:
		if bool(record.get("skipped", false)):
			print("  %s -> SKIPPED (no card written)" % str(record["id"]))
			continue
		print("  %s -> %s" % [
			str(record["id"]),
			ProjectSettings.globalize_path(str(record["path"]))])
	if failures > 0:
		push_error("preview_render: %d preview(s) failed verification" % failures)
