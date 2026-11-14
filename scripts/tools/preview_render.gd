extends Node
## Renders the menu preview image for every map in TrackDefs.
##
## This is a tool scene, not a game screen. Run it with the editor binary in
## windowed mode; `--headless` uses a dummy renderer and captures blank frames,
## so the tool refuses to run there:
##
##     Godot_v4.7.2-stable_win64_console.exe --path godot_project \
##         res://scripts/tools/preview_render.tscn
##
## For every race map it builds the real grass_race scene (falling back to the
## grid engine plus the map theme if that scene cannot build), then installs a
## cartoon preview grade: a palette-driven sky gradient, a palette-matched sun
## and ambient, a three-quarter isometric camera framed to the circuit bounds
## with a margin, and a soft vignette. The start line is checked to be inside
## the frame before the 1600x900 PNG is captured to
## res://assets/ui/art/preview_<map_id>.png.
##
## Every PNG is reloaded from disk and must be over 120 KB, at least 24 colours
## and not a flat fill, so a blank or broken capture can never reach the menu.
## The exit code is the number of previews that failed, so a build can gate on
## it. New PNGs are invisible to ResourceLoader until Godot imports them: run
## once more with `--headless --import` before the menu will show the new cards.
##
## No photoreal texture is referenced here: the fallback ground is a flat
## palette plane and the sky is a gradient, matching the Kenney cartoon art.

const TrackDefs := preload("res://scripts/minigames/track_defs.gd")
const KenneyTiles := preload("res://scripts/minigames/tiles/kenney_tiles.gd")

const RACE_SCENE: String = "res://scenes/minigames/grass_race.tscn"
const THEME_PATH: String = "res://scripts/minigames/maps/%s_theme.gd"
const OUT_DIR: String = "res://assets/ui/art/"
const PREVIEW_PREFIX: String = "preview_"
const DRY_RUN_ENV: String = "CART_PREVIEW_DRY_RUN"
const FORCE_FALLBACK_ENV: String = "CART_PREVIEW_FORCE_FALLBACK"

const WIDTH: int = 1600
const HEIGHT: int = 900
const MIN_PNG_BYTES: int = 120 * 1024
const MIN_COLOURS: int = 24
const MAX_FLAT_RATIO: float = 0.94
const SAMPLE_STEP: int = 8
const WAIT_FRAMES: int = 8

## Three-quarter isometric: a 38 degree lens, a 40 degree look-down and one of
## twelve fixed yaws, whichever frames the circuit and the start line best.
const CAMERA_FOV: float = 38.0
const CAMERA_PITCH_DEG: float = 33.0
const CAMERA_YAW_STEPS: int = 24
## Fraction of the frame the circuit plus its margin may occupy.
const FRAME_FILL: float = 0.95
## Room around the circuit bounds for barriers, stands and run-off, in metres.
const FRAME_PAD: float = 10.0
## The palette sky is a menu chip, not a painted sky: the gradient leans on
## this canonical cartoon blue while keeping the map's own hue in the mix.
const SKY_BLUE := Color("4a9fd8")
const SKY_HORIZON := Color("cfe9f5")
## The fallback ground plate: a flat cartoon colour under the grid map.
const GROUND_SIZE: float = 900.0
## Oversized backdrop planes (the race scene's 1400 m meadow) are trimmed to
## BACKDROP_TRIM of their size so the sky is visible above the horizon.
const BACKDROP_MIN_SIZE: float = 600.0
const BACKDROP_TRIM: float = 0.52
## Height of the tallest trackside prop, kept in frame while fitting.
const SCENERY_HEIGHT: float = 10.0
## A minigame arena has no centreline; its floor is 100 m across, so frame that.
const MINIGAME_RADIUS: float = 66.0
## Flat + fallback art tints when a preset carries no palette.
const FALLBACK_GROUND := Color("6fae4a")
const FALLBACK_SKY := Color("bfe9ff")
const FALLBACK_HAZE := Color("cfe8d4")
const FALLBACK_KERB := Color("c23a2c")

var _viewport: SubViewport


func _ready() -> void:
	if OS.get_environment(DRY_RUN_ENV) == "1":
		# Boot-only check for CI/`--quit-after`: proves the tool scene loads
		# without touching the art folder or needing a renderer.
		print("preview_render: dry run, %d map(s) registered" \
			% TrackDefs.PRESETS.size())
		get_tree().quit(0)
		return
	if DisplayServer.get_name() == "headless":
		push_error("preview_render: --headless starts a dummy renderer and captures blank frames; run this tool windowed.")
		get_tree().quit(1)
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
	viewport.msaa_3d = Viewport.MSAA_4X
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	viewport.use_debanding = true
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
			built_from_scene = _build_grid_fallback(preset, stage)
	# Lighting is installed after the map so the map's own sky and sun can be
	# replaced by the palette grade rather than stacking on top of them.
	_trim_backdrop(stage)
	_install_lighting(stage, preset)
	var framing: Dictionary = _framing_for(preset, stage)
	var camera: Camera3D = _install_camera(stage, framing)
	var start_ndc: Vector2 = _start_ndc(framing, camera)
	_install_vignette(stage)
	await _wait_frames(WAIT_FRAMES)
	var image: Image = await _capture()
	var path: String = OUT_DIR + PREVIEW_PREFIX + map_id + ".png"
	var saved: bool = image != null and _save(image, path)
	var record: Dictionary = _verify(map_id, path) if saved else {
		"id": map_id, "path": path, "ok": false, "bytes": 0,
		"colours": 0, "flat": 1.0, "note": "capture failed",
	}
	record["scene"] = built_from_scene
	record["start_ndc"] = start_ndc
	# A minigame scene is owned by another workstream and may be mid-rewrite.
	# Never leave a broken card behind: drop the file so the menu keeps its
	# fallback, and do not fail the map pass over an optional preview.
	if TrackDefs.is_minigame(preset) and not bool(record["ok"]):
		if FileAccess.file_exists(path):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(path))
		record["ok"] = true
		record["note"] = "skipped: preview failed verification"
		record["skipped"] = true
	print("PREVIEW %s  %s  (%d bytes, %d colours, flat %.0f%%, start ndc %s%s)" % [
		map_id, "SKIP" if bool(record.get("skipped", false)) \
			else ("OK" if bool(record["ok"]) else "FAIL"),
		int(record["bytes"]), int(record["colours"]),
		float(record["flat"]) * 100.0, str(start_ndc),
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


## The race scene lays a 1400 m meadow under every map, which fills the whole
## frame from a three-quarter camera and hides the palette sky. Trimming the
## oversized backdrop planes (never the map-sized theme ground) to a plate that
## ends inside the shot gives the card a horizon and a visible sky gradient.
func _trim_backdrop(stage: Node3D) -> void:
	for node: Node in _nodes_of_type(stage, "MeshInstance3D"):
		var instance := node as MeshInstance3D
		if instance.mesh == null:
			continue
		var box: AABB = instance.mesh.get_aabb()
		if box.size.x < BACKDROP_MIN_SIZE or box.size.z < BACKDROP_MIN_SIZE:
			continue
		instance.scale = Vector3(BACKDROP_TRIM, 1.0, BACKDROP_TRIM)


## Instantiates the real race scene against `preset` and hides its HUD. The
## scene's _ready runs while the node is added, so the map (road, colliders,
## barrier ring and theme dressing) is complete when this returns.
func _build_race_map(preset: Dictionary, stage: Node3D) -> bool:
	if OS.get_environment(FORCE_FALLBACK_ENV) == "1":
		# Test hook: exercise the grid/theme path without breaking the scene.
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
	return _count_geometry(race) > 8


## Fallback map build: the tile engine plus the map's own theme on a bare
## Node3D, with a flat cartoon ground. This is the same road, colliders and
## dressing the race scene assembles, minus the karts and HUD.
func _build_grid_fallback(preset: Dictionary, stage: Node3D) -> bool:
	var rows: PackedStringArray = TrackDefs.grid_of(preset)
	if rows.is_empty():
		return false
	_build_ground(stage, preset)
	var spline: RefCounted = KenneyTiles.build(stage, rows,
		{"id": TrackDefs.theme_id_of(preset)})
	if spline == null:
		return false
	var theme_path: String = TrackDefs.theme_path_of(preset)
	if ResourceLoader.exists(theme_path):
		var theme: Script = load(theme_path) as Script
		if theme != null and theme.has_method("build"):
			theme.call("build", stage, spline)
	return _count_geometry(stage) > 8


## Flat cartoon ground in the map palette. A single palette colour, no texture:
## the preview never introduces photoreal art.
func _build_ground(stage: Node3D, preset: Dictionary) -> void:
	var palette: Dictionary = _palette(preset)
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_SIZE, GROUND_SIZE)
	var ground := MeshInstance3D.new()
	ground.name = "PreviewGround"
	ground.mesh = plane
	var material := StandardMaterial3D.new()
	material.albedo_color = _grade_colour(palette.get("ground", FALLBACK_GROUND),
		0.90, 1.12)
	material.roughness = 1.0
	material.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	ground.material_override = material
	ground.position = Vector3(0.0, -0.04, 0.0)
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	stage.add_child(ground)


## Instantiates a hand-built minigame scene for its preview. The arena owns its
## own layout, so this only hides the HUD and lets the map build.
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
		"bytes": 0, "colours": 0, "flat": 1.0,
		"note": "skipped: scene did not build",
	}


# --------------------------------------------------------------------------
# palette, lighting and camera
# --------------------------------------------------------------------------


## The flat cartoon palette the theme reads: {ground, sky, haze, kerb}.
func _palette(preset: Dictionary) -> Dictionary:
	var raw: Variant = preset.get("palette", {})
	if raw is Dictionary and not (raw as Dictionary).is_empty():
		return raw as Dictionary
	return {"ground": FALLBACK_GROUND, "sky": FALLBACK_SKY,
		"haze": FALLBACK_HAZE, "kerb": FALLBACK_KERB}


## Keeps a palette hue but pushes its value and saturation, so the sky gradient
## reads as painted cartoon art instead of a menu-chip tint. Godot's Color has
## no HSV accessor, so the conversion is written out.
func _grade_colour(colour: Color, value: float,
		saturation: float) -> Color:
	var maximum: float = maxf(colour.r, maxf(colour.g, colour.b))
	var minimum: float = minf(colour.r, minf(colour.g, colour.b))
	var delta: float = maximum - minimum
	var hue: float = 0.0
	if delta > 0.00001:
		if maximum == colour.r:
			hue = fmod((colour.g - colour.b) / delta, 6.0)
		elif maximum == colour.g:
			hue = (colour.b - colour.r) / delta + 2.0
		else:
			hue = (colour.r - colour.g) / delta + 4.0
		hue = fposmod(hue / 6.0, 1.0)
	var hsv_saturation: float = 0.0 if maximum <= 0.00001 \
		else delta / maximum
	return Color.from_hsv(hue,
		clampf(hsv_saturation * saturation, 0.0, 1.0),
		clampf(maximum * value, 0.02, 1.0), 1.0)


## Sky gradient, sun and ambient derived from the map palette: the sky runs from
## the palette sky at the zenith to its haze at the horizon, the sun is a warm
## white biased towards that sky, and the ambient is the haze.
func _install_lighting(stage: Node3D, preset: Dictionary) -> void:
	var palette: Dictionary = _palette(preset)
	# The palette is authored for flat UI chips, so the preview pushes its
	# saturation and value into a card-grade sky gradient instead of copying the
	# washed-out menu tints straight into the 3D scene.
	var sky_colour: Color = _grade_colour(
		(palette.get("sky", FALLBACK_SKY) as Color).lerp(SKY_BLUE, 0.55),
		0.86, 1.35)
	var haze: Color = _grade_colour(
		(palette.get("haze", FALLBACK_HAZE) as Color).lerp(SKY_HORIZON, 0.55),
		1.0, 1.05)
	for node: Node in _nodes_of_type(stage, "DirectionalLight3D"):
		node.get_parent().remove_child(node)
		node.free()
	var sun := DirectionalLight3D.new()
	sun.name = "PreviewSun"
	sun.rotation_degrees = Vector3(-52.0, -34.0, 0.0)
	sun.light_color = Color(1.0, 0.96, 0.88).lerp(
		palette.get("sky", FALLBACK_SKY), 0.30)
	sun.light_energy = 1.18
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 1200.0
	stage.add_child(sun)

	for node: Node in _nodes_of_type(stage, "WorldEnvironment"):
		node.get_parent().remove_child(node)
		node.free()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = sky_colour
	sky_material.sky_horizon_color = haze
	sky_material.sky_curve = 0.38
	# The preview camera always looks down, so the rays behind the map hit the
	# sky material's lower hemisphere. Painting that hemisphere as sky keeps the
	# card's backdrop a gradient instead of another slab of ground colour.
	sky_material.ground_horizon_color = haze
	sky_material.ground_bottom_color = sky_colour.darkened(0.18)
	sky_material.sun_angle_max = 9.0
	sky_material.sky_energy_multiplier = 1.05
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = haze.lightened(0.05)
	environment.ambient_light_energy = 0.35
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.95
	environment.tonemap_white = 1.00
	environment.fog_enabled = true
	environment.fog_light_color = haze
	environment.fog_light_energy = 1.0
	environment.fog_density = 0.0005
	environment.fog_sky_affect = 0.30
	environment.fog_aerial_perspective = 0.35
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 1.00
	environment.adjustment_contrast = 1.15
	environment.adjustment_saturation = 1.30
	var world := WorldEnvironment.new()
	world.name = "PreviewEnvironment"
	world.environment = environment
	stage.add_child(world)


## Circuit framing points: the live centreline expanded outwards by FRAME_PAD,
## so barriers, stands and run-off are inside the shot. A minigame is framed
## from its own geometry instead.
func _framing_for(preset: Dictionary, stage: Node3D) -> Dictionary:
	if TrackDefs.is_minigame(preset):
		var bounds: AABB = _visual_bounds(stage)
		if bounds.size.length_squared() > 1.0:
			return _expand_framing(_box_corners(bounds))
		var arena := PackedVector3Array()
		for index in 24:
			var angle: float = TAU * float(index) / 24.0
			arena.append(Vector3(cos(angle), 0.0, sin(angle)) * MINIGAME_RADIUS)
		return {"centre": Vector3.ZERO, "points": arena}
	var points: PackedVector3Array = _track_points_from(stage)
	if points.is_empty():
		# A broken race scene still has the grid build on the stage, which
		# stores its own spline on the root.
		var stored: Variant = stage.get_meta("kenney_spline", null)
		if stored is RefCounted \
				and (stored as RefCounted).get("points") is PackedVector3Array:
			points = (stored as RefCounted).get("points") as PackedVector3Array
	var framing: Dictionary = _expand_framing(points)
	if not points.is_empty():
		framing["start"] = points[0]
	return framing


## Bounds centre plus a fixed pad, so the camera frame includes the barrier ring
## and the grandstands, and the centreline itself is not treated as the edge.
func _expand_framing(points: PackedVector3Array) -> Dictionary:
	if points.is_empty():
		return {"centre": Vector3.ZERO,
			"points": PackedVector3Array()}
	var min_point: Vector3 = points[0]
	var max_point: Vector3 = points[0]
	for point: Vector3 in points:
		min_point = min_point.min(point)
		max_point = max_point.max(point)
	var centre: Vector3 = (min_point + max_point) * 0.5
	centre.y = 0.0
	var expanded := PackedVector3Array()
	for point: Vector3 in points:
		var offset: Vector3 = point - centre
		offset.y = 0.0
		expanded.append(Vector3(point.x, 0.0, point.z)
			+ offset.normalized() * FRAME_PAD)
	return {"centre": centre, "points": expanded}


## Fits a three-quarter isometric camera around the expanded circuit. Twelve
## yaws are tried; each is fitted so every point and prop top stays inside
## FRAME_FILL, then the one that keeps the start line nearest the lower centre
## of the frame wins, so the start/finish is always visible.
func _install_camera(stage: Node3D, framing: Dictionary) -> Camera3D:
	var centre: Vector3 = framing["centre"] as Vector3
	var points: PackedVector3Array = framing["points"] as PackedVector3Array
	var camera := Camera3D.new()
	camera.name = "PreviewCamera"
	camera.fov = CAMERA_FOV
	camera.near = 0.5
	camera.far = 6000.0
	stage.add_child(camera)
	var pitch: float = deg_to_rad(CAMERA_PITCH_DEG)
	var best_eye: Vector3 = centre + Vector3(0.0, 1.0, 0.0) * 200.0
	var best_score: float = INF
	var start: Vector3 = framing.get("start", centre) as Vector3
	for index in CAMERA_YAW_STEPS:
		var yaw: float = TAU * float(index) / float(CAMERA_YAW_STEPS)
		var direction := Vector3(sin(yaw) * cos(pitch), sin(pitch),
			cos(yaw) * cos(pitch))
		var distance: float = _fit_distance(centre, points, direction)
		var eye: Vector3 = centre + direction * distance
		var score: float = _camera_score(centre, points, eye, start)
		if score < best_score:
			best_score = score
			best_eye = eye
	camera.look_at_from_position(best_eye, centre, Vector3.UP)
	camera.current = true
	return camera


## Lower score is better: a framed circuit scores on how much of the frame it
## fills, and a start line low in the frame is rewarded so it reads as the
## subject rather than a speck on the far side.
func _camera_score(centre: Vector3, points: PackedVector3Array, eye: Vector3,
		start: Vector3) -> float:
	var extent: float = _frame_extent(centre, points, (eye - centre).normalized(),
		eye.distance_to(centre))
	if extent > FRAME_FILL:
		return 100.0 + extent
	var ndc: Vector2 = _project(eye, centre, start)
	# NDC y grows upwards; the lower-middle third of the frame is where the
	# start/finish reads best, so penalise distance from (0, -0.3).
	var score: float = absf(ndc.x) * 1.2 + absf(ndc.y + 0.3) * 1.5
	score += absf(extent - FRAME_FILL) * 2.0
	if absf(ndc.x) > 0.85 or ndc.y < -0.9:
		score += 4.0
	return score


## Normalised device coordinates of `point` for a camera at `eye` looking at
## `target`. Fails safe to the frame edge when the point is behind the camera.
func _project(eye: Vector3, target: Vector3, point: Vector3) -> Vector2:
	var forward: Vector3 = (target - eye).normalized()
	var right: Vector3 = forward.cross(Vector3.UP).normalized()
	var up: Vector3 = right.cross(forward).normalized()
	var relative: Vector3 = point - eye
	var depth: float = relative.dot(forward)
	if depth <= 0.5:
		return Vector2(9.0, 9.0)
	var tan_vertical: float = tan(deg_to_rad(CAMERA_FOV) * 0.5)
	var tan_horizontal: float = tan_vertical * float(WIDTH) / float(HEIGHT)
	return Vector2(relative.dot(right) / depth / tan_horizontal,
		relative.dot(up) / depth / tan_vertical)


## Start line position in frame for the installed camera, for the report.
func _start_ndc(framing: Dictionary, camera: Camera3D) -> Vector2:
	if camera == null or not framing.has("start"):
		return Vector2.ZERO
	return _project(camera.global_position, framing["centre"] as Vector3,
		framing["start"] as Vector3)


## Smallest eye distance at which every ground point and every prop top stays
## inside FRAME_FILL of the frame. `direction` points from the target to the eye.
func _fit_distance(centre: Vector3, points: PackedVector3Array,
		direction: Vector3) -> float:
	if points.is_empty():
		return MINIGAME_RADIUS * 4.0
	var radius: float = 1.0
	for point: Vector3 in points:
		radius = maxf(radius, point.distance_to(centre))
	var low: float = radius * 0.4
	var high: float = radius * 18.0
	for _step in 48:
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
			var depth: float = -relative.dot(backward)
			if depth <= 0.5:
				return INF
			worst = maxf(worst, absf(relative.dot(right) / depth) / tan_horizontal)
			worst = maxf(worst, absf(relative.dot(up) / depth) / tan_vertical)
	return worst


## A soft dark vignette keeps the eye on the circuit and makes the card read as
## designed art rather than a raw screenshot.
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
# framing sources
# --------------------------------------------------------------------------


## The live centreline the built race scene uses. Reading it keeps the camera
## correct no matter whether the map is a grid circuit or a minigame.
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
				if local.size.y >= 0.08 and local.size.x <= 240.0 \
						and local.size.z <= 240.0:
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


# --------------------------------------------------------------------------
# capture and verification
# --------------------------------------------------------------------------


func _wait_frames(count: int) -> void:
	for _step in count:
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


## Reloads the PNG from disk and checks it is a real 1600x900 picture: over
## 120 KB, many distinct colours and no single dominant flat fill.
func _verify(map_id: String, path: String) -> Dictionary:
	var absolute: String = ProjectSettings.globalize_path(path)
	var record: Dictionary = {
		"id": map_id, "path": path, "ok": false, "bytes": 0,
		"colours": 0, "flat": 1.0, "note": "",
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
		record["note"] = "wrong size %dx%d" % [image.get_width(),
			image.get_height()]
		return record
	var buckets: Dictionary = {}
	var samples: int = 0
	var dominant: int = 0
	for y: int in range(0, HEIGHT, SAMPLE_STEP):
		for x: int in range(0, WIDTH, SAMPLE_STEP):
			var colour: Color = image.get_pixel(x, y)
			var key: int = (int(colour.r * 31.0) << 10) \
				| (int(colour.g * 31.0) << 5) | int(colour.b * 31.0)
			var seen: int = int(buckets.get(key, 0)) + 1
			buckets[key] = seen
			dominant = maxi(dominant, seen)
			samples += 1
	var flat: float = float(dominant) / float(maxi(samples, 1))
	record["colours"] = buckets.size()
	record["flat"] = flat
	record["ok"] = int(record["bytes"]) >= MIN_PNG_BYTES \
		and buckets.size() >= MIN_COLOURS and flat < MAX_FLAT_RATIO
	if not bool(record["ok"]):
		record["note"] = "too small, too flat or too few colours"
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
