extends Node
## Renders 1600x900 menu preview screenshots (`res://assets/ui/art/preview_<id>.png`)
## for EVERY selectable race circuit, game mode cover, sandbox park, and
## individual minigame map (18 previews total):
##
##   * 5 Racing Circuits: `stadium`, `meadow`, `canyon`, `dockyard`, `glacier`
##   * 4 Mode Covers: `cargo_rush`, `knockout`, `bomb_tag`, `sandbox`
##   * 3 Deliver Maps: `harbour`, `farmyard`, `snowfield`
##   * 3 Knockout Maps: `ko_rooftop`, `ko_foundry`, `ko_iceberg`
##   * 3 Blast Tag Maps: `bt_plaza`, `bt_labyrinth`, `bt_ferries`
##
## Run windowed (never `--headless`):
##     Godot_v4.7.2-stable_win64_console.exe --path godot_project \
##         res://scripts/tools/preview_render.tscn

const TrackDefs := preload("res://scripts/minigames/track_defs.gd")
const KenneyTiles := preload("res://scripts/minigames/tiles/kenney_tiles.gd")
const CargoTheme := preload("res://scripts/minigames/cargo_rush_theme.gd")
const SceneryKit := preload("res://scripts/minigames/scenery/scenery_kit.gd")
const PropBatch := preload("res://scripts/minigames/scenery/prop_batch.gd")
const Catalog := preload("res://scripts/vehicles/vehicle_catalog.gd")
const VehicleVisual := preload("res://scripts/vehicles/vehicle_visual.gd")

const RACE_SCENE: String = "res://scenes/minigames/grass_race.tscn"
const KO_MAPS_SCRIPT: String = "res://scripts/minigames/knockout_maps.gd"
const BT_MAPS_SCRIPT: String = "res://scripts/minigames/bomb_tag_maps.gd"
const SANDBOX_PARK_SCRIPTS: Array[String] = [
	"res://scripts/sandbox_park.gd",
	"res://scripts/sandbox/sandbox_park.gd",
	"res://scripts/minigames/sandbox_park.gd",
	"res://scripts/world/sandbox_park.gd",
]
const SANDBOX_SCENES: Array[String] = [
	"res://scenes/sandbox.tscn",
	"res://scenes/sandbox/sandbox_world.tscn",
	"res://scenes/sandbox/sandbox.tscn",
	"res://scenes/world/sandbox.tscn",
]
const PREVIEW_VEHICLE_IDS: Array[String] = [
	"shopping_cart", "van", "truck", "sports",
]

const OUT_DIR: String = "res://assets/ui/art/"
const PREVIEW_PREFIX: String = "preview_"
const DRY_RUN_ENV: String = "CART_PREVIEW_DRY_RUN"
const FORCE_FALLBACK_ENV: String = "CART_PREVIEW_FORCE_FALLBACK"
const ONLY_ENV: String = "CART_PREVIEW_ONLY"

const WIDTH: int = 1600
const HEIGHT: int = 900
const MIN_PNG_BYTES: int = 120 * 1024
const MIN_COLOURS: int = 24
const MAX_FLAT_RATIO: float = 0.94
const SAMPLE_STEP: int = 8
const WAIT_FRAMES: int = 16

const CAMERA_FOV: float = 44.0
const CAMERA_PITCH_DEG: float = 33.0
const CAMERA_YAW_STEPS: int = 24
const FRAME_FILL: float = 0.95
const FRAME_PAD: float = 10.0
const SKY_BLUE := Color("4a9fd8")
const SKY_HORIZON := Color("cfe9f5")
const GROUND_SIZE: float = 900.0
const BACKDROP_MIN_SIZE: float = 600.0
const BACKDROP_TRIM: float = 0.52
const SCENERY_HEIGHT: float = 10.0
const MINIGAME_RADIUS: float = 54.0
const ARENA_CLAMP_HALF: float = 72.0

const FALLBACK_GROUND := Color("6fae4a")
const FALLBACK_SKY := Color("bfe9ff")
const FALLBACK_HAZE := Color("cfe8d4")
const FALLBACK_KERB := Color("c23a2c")

## Bespoke sky/sun/fog presets for all 18 map & mode preview targets.
const ENVIRONMENTS: Dictionary = {
	"stadium": {
		"sky_top": Color("3c95d6"), "sky_horizon": Color("d3eef8"),
		"sun_color": Color("fff6e5"), "sun_energy": 1.18,
		"sun_rot": Vector3(-52.0, -34.0, 0.0),
		"fog_color": Color("cfe8d8"), "fog_density": 0.00042,
	},
	"meadow": {
		"sky_top": Color("3298c9"), "sky_horizon": Color("d5f1e2"),
		"sun_color": Color("fff4d9"), "sun_energy": 1.22,
		"sun_rot": Vector3(-48.0, -42.0, 0.0),
		"fog_color": Color("cdebd9"), "fog_density": 0.00050,
	},
	"canyon": {
		"sky_top": Color("d96b38"), "sky_horizon": Color("ffd296"),
		"sun_color": Color("ffd494"), "sun_energy": 1.28,
		"sun_rot": Vector3(-38.0, -54.0, 0.0),
		"fog_color": Color("f6c28b"), "fog_density": 0.00055,
	},
	"dockyard": {
		"sky_top": Color("3a82b8"), "sky_horizon": Color("cde1eb"),
		"sun_color": Color("fff5e8"), "sun_energy": 1.18,
		"sun_rot": Vector3(-50.0, -28.0, 0.0),
		"fog_color": Color("c2d7e2"), "fog_density": 0.00048,
	},
	"glacier": {
		"sky_top": Color("4592cf"), "sky_horizon": Color("e5f3fc"),
		"sun_color": Color("f2f8ff"), "sun_energy": 1.16,
		"sun_rot": Vector3(-49.0, -36.0, 0.0),
		"fog_color": Color("dbeaf4"), "fog_density": 0.00058,
	},
	"sandbox": {
		"sky_top": Color("3596da"), "sky_horizon": Color("d8f2ec"),
		"sun_color": Color("fff6e2"), "sun_energy": 1.22,
		"sun_rot": Vector3(-48.0, -36.0, 0.0),
		"fog_color": Color("d2ece2"), "fog_density": 0.00040,
	},
	"cargo_rush": {
		"sky_top": Color("2f85c4"), "sky_horizon": Color("d2ebf7"),
		"sun_color": Color("fff6e6"), "sun_energy": 1.20,
		"sun_rot": Vector3(-50.0, -32.0, 0.0),
		"fog_color": Color("cce4f0"), "fog_density": 0.00038,
	},
	"harbour": {
		"sky_top": Color("2b80bf"), "sky_horizon": Color("cfe8f5"),
		"sun_color": Color("fff6e6"), "sun_energy": 1.22,
		"sun_rot": Vector3(-49.0, -34.0, 0.0),
		"fog_color": Color("c9e3f0"), "fog_density": 0.00038,
	},
	"farmyard": {
		"sky_top": Color("3892cc"), "sky_horizon": Color("e6f0cf"),
		"sun_color": Color("fff2d4"), "sun_energy": 1.24,
		"sun_rot": Vector3(-46.0, -40.0, 0.0),
		"fog_color": Color("dfeac8"), "fog_density": 0.00036,
	},
	"snowfield": {
		"sky_top": Color("4b94d1"), "sky_horizon": Color("eaf5fd"),
		"sun_color": Color("f4f9ff"), "sun_energy": 1.18,
		"sun_rot": Vector3(-50.0, -30.0, 0.0),
		"fog_color": Color("e1effa"), "fog_density": 0.00042,
	},
	"knockout": {
		"sky_top": Color("3158a8"), "sky_horizon": Color("f4b895"),
		"sun_color": Color("ffe2bd"), "sun_energy": 1.26,
		"sun_rot": Vector3(-42.0, -44.0, 0.0),
		"fog_color": Color("e8c4b0"), "fog_density": 0.00035,
	},
	"ko_rooftop": {
		"sky_top": Color("2e56a6"), "sky_horizon": Color("f5be9b"),
		"sun_color": Color("ffe4c2"), "sun_energy": 1.38, "ambient": 0.46,
		"sun_rot": Vector3(-42.0, -42.0, 0.0),
		"fog_color": Color("eac8b5"), "fog_density": 0.00035,
	},
	"ko_foundry": {
		"sky_top": Color("4a2824"), "sky_horizon": Color("e87838"),
		"sun_color": Color("ffc285"), "sun_energy": 1.55, "ambient": 0.58,
		"sun_rot": Vector3(-44.0, -36.0, 0.0),
		"fog_color": Color("d97a46"), "fog_density": 0.00030,
	},
	"ko_iceberg": {
		"sky_top": Color("2f7ec0"), "sky_horizon": Color("dff2fc"),
		"sun_color": Color("f0f8ff"), "sun_energy": 1.34, "ambient": 0.46,
		"sun_rot": Vector3(-48.0, -32.0, 0.0),
		"fog_color": Color("d5ebf8"), "fog_density": 0.00040,
	},
	"bomb_tag": {
		"sky_top": Color("377fc4"), "sky_horizon": Color("fbe0b8"),
		"sun_color": Color("fff0d4"), "sun_energy": 1.24,
		"sun_rot": Vector3(-46.0, -38.0, 0.0),
		"fog_color": Color("f0dec2"), "fog_density": 0.00038,
	},
	"bt_plaza": {
		"sky_top": Color("3482ca"), "sky_horizon": Color("fce2bd"),
		"sun_color": Color("fff1d8"), "sun_energy": 1.24,
		"sun_rot": Vector3(-46.0, -36.0, 0.0),
		"fog_color": Color("f2e0c6"), "fog_density": 0.00036,
	},
	"bt_labyrinth": {
		"sky_top": Color("cf6534"), "sky_horizon": Color("ffd194"),
		"sun_color": Color("ffd599"), "sun_energy": 1.28,
		"sun_rot": Vector3(-40.0, -48.0, 0.0),
		"fog_color": Color("f4c188"), "fog_density": 0.00045,
	},
	"bt_ferries": {
		"sky_top": Color("2879b8"), "sky_horizon": Color("cde6f4"),
		"sun_color": Color("fff6e8"), "sun_energy": 1.22,
		"sun_rot": Vector3(-48.0, -30.0, 0.0),
		"fog_color": Color("c6e0ee"), "fog_density": 0.00040,
	},
}

const MAP_VIEWS: Dictionary = {
	"stadium": {"pad": 13.0, "pitch_deg": 33.0},
	"meadow": {"pad": 14.0, "pitch_deg": 34.0, "start_fraction": 0.28},
	"canyon": {"pad": 15.0, "pitch_deg": 34.0},
	"dockyard": {"pad": 15.0, "pitch_deg": 33.0},
	"glacier": {"pad": 16.0, "pitch_deg": 34.0},
	"sandbox": {"pad": 8.0, "pitch_deg": 33.0, "yaw_deg": 38.0},
	"cargo_rush": {"pad": 6.0, "pitch_deg": 34.0, "yaw_deg": 32.0},
	"harbour": {"pad": 6.0, "pitch_deg": 33.0, "yaw_deg": 34.0},
	"farmyard": {"pad": 6.0, "pitch_deg": 34.0, "yaw_deg": 40.0},
	"snowfield": {"pad": 6.0, "pitch_deg": 34.0, "yaw_deg": 28.0},
	"knockout": {"pad": 6.0, "pitch_deg": 33.0, "yaw_deg": 36.0},
	"ko_rooftop": {"pad": 6.0, "pitch_deg": 27.0, "yaw_deg": 35.0},
	"ko_foundry": {"pad": 8.0, "pitch_deg": 19.0, "yaw_deg": 33.0},
	"ko_iceberg": {"pad": 6.0, "pitch_deg": 24.0, "yaw_deg": 40.0},
	"bomb_tag": {"pad": 6.0, "pitch_deg": 34.0, "yaw_deg": 35.0},
	"bt_plaza": {"pad": 6.0, "pitch_deg": 34.0, "yaw_deg": 35.0},
	"bt_labyrinth": {"pad": 6.0, "pitch_deg": 35.0, "yaw_deg": 40.0},
	"bt_ferries": {"pad": 6.0, "pitch_deg": 33.0, "yaw_deg": 32.0},
}

var _viewport: SubViewport


func _ready() -> void:
	var targets: Array[Dictionary] = _all_targets()
	var only: String = OS.get_environment(ONLY_ENV).strip_edges()
	if only != "":
		var wanted: PackedStringArray = only.split(",", false)
		targets = targets.filter(func(target: Dictionary) -> bool:
			return wanted.has(str(target.get("id", ""))))
		if targets.is_empty():
			push_error("preview_render: %s did not match any preview id" % ONLY_ENV)
			get_tree().quit(1)
			return
	if OS.get_environment(DRY_RUN_ENV) == "1":
		print("preview_render: dry run, %d target(s) registered" % targets.size())
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
	for target: Dictionary in targets:
		var record: Dictionary = await _render_target(target)
		records.append(record)
		if not bool(record["ok"]):
			failures += 1
	_report(records, failures)
	await get_tree().process_frame
	get_tree().quit(failures)


## Builds the complete ordered list of 18 preview targets:
## 5 circuits + 3 minigame mode covers + sandbox + 9 individual minigame maps.
func _all_targets() -> Array[Dictionary]:
	var targets: Array[Dictionary] = []
	var seen: Dictionary = {}
	for preset: Dictionary in TrackDefs.PRESETS:
		var id: String = str(preset.get("id", ""))
		if id == "" or seen.has(id):
			continue
		seen[id] = true
		if TrackDefs.is_map(preset):
			targets.append({
				"id": id,
				"target_kind": "race_map",
				"preset": TrackDefs.get_preset(id),
			})
		else:
			targets.append({
				"id": id,
				"target_kind": "minigame_cover",
				"game_id": id,
				"arena_id": TrackDefs.default_theme(preset),
				"preset": preset,
			})
	# Sandbox free-roam park cover
	if not seen.has("sandbox"):
		seen["sandbox"] = true
		targets.append({
			"id": "sandbox",
			"target_kind": "sandbox",
			"preset": {"id": "sandbox", "kind": TrackDefs.KIND_MINIGAME},
		})
	# Every individual minigame map in TrackDefs
	for preset: Dictionary in TrackDefs.PRESETS:
		if not TrackDefs.is_minigame(preset):
			continue
		var game_id: String = str(preset.get("id", ""))
		for theme_id: String in TrackDefs.theme_ids(preset):
			if theme_id == "" or seen.has(theme_id):
				continue
			seen[theme_id] = true
			targets.append({
				"id": theme_id,
				"target_kind": "minigame_map",
				"game_id": game_id,
				"arena_id": theme_id,
				"preset": preset,
			})
	return targets


# --------------------------------------------------------------------------
# render target
# --------------------------------------------------------------------------


func _make_viewport() -> SubViewport:
	var viewport := SubViewport.new()
	viewport.name = "PreviewViewport"
	viewport.size = Vector2i(WIDTH, HEIGHT)
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


func _render_target(target: Dictionary) -> Dictionary:
	var map_id: String = str(target.get("id", TrackDefs.DEFAULT_ID))
	var target_kind: String = str(target.get("target_kind", "race_map"))
	var preset: Dictionary = (target.get("preset", {}) as Dictionary).duplicate(true)
	preset["id"] = map_id

	var stage := Node3D.new()
	stage.name = "Map_" + map_id
	_viewport.add_child(stage)

	var built_ok: bool = false
	var arena_info: Dictionary = {}
	if target_kind == "race_map":
		built_ok = _build_race_map(preset, stage)
		if not built_ok:
			built_ok = _build_grid_fallback(preset, stage)
	elif target_kind == "sandbox":
		arena_info = _build_sandbox_preview(stage)
		built_ok = _count_geometry(stage) > 4
	else:
		var game_id: String = str(target.get("game_id", map_id))
		var arena_id: String = str(target.get("arena_id", map_id))
		arena_info = _build_arena_preview(game_id, arena_id, preset, stage)
		built_ok = _count_geometry(stage) > 4

	if target_kind != "race_map":
		_stage_preview_karts(stage, arena_info, map_id)

	_trim_backdrop(stage)
	_install_lighting(stage, preset)
	var framing: Dictionary = _framing_for(target_kind, preset, stage, arena_info)
	if target_kind == "race_map":
		_stage_race_vehicles(stage, framing)
	var camera: Camera3D = _install_camera(stage, framing)
	var start_ndc: Vector2 = _start_ndc(framing, camera)
	_install_vignette(stage)
	await _wait_frames(WAIT_FRAMES)
	var image: Image = await _capture()
	var path: String = OUT_DIR + PREVIEW_PREFIX + map_id + ".png"
	var saved: bool = built_ok and image != null and _save(image, path)
	var record: Dictionary = _verify(map_id, path) if saved else {
		"id": map_id, "path": path, "ok": false, "bytes": 0,
		"colours": 0, "flat": 1.0, "note": "capture failed",
	}
	record["scene"] = built_ok
	record["start_ndc"] = start_ndc
	print("PREVIEW %s  %s  (%d bytes, %d colours, flat %.0f%%, start ndc %s%s)" % [
		map_id, "OK" if bool(record["ok"]) else "FAIL",
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
# race map building
# --------------------------------------------------------------------------


func _trim_backdrop(stage: Node3D) -> void:
	for node: Node in _nodes_of_type(stage, "MeshInstance3D"):
		var instance := node as MeshInstance3D
		if instance.mesh == null or not (instance.mesh is PlaneMesh):
			continue
		var box: AABB = instance.mesh.get_aabb()
		if box.size.x < BACKDROP_MIN_SIZE or box.size.z < BACKDROP_MIN_SIZE:
			continue
		instance.scale = Vector3(BACKDROP_TRIM, 1.0, BACKDROP_TRIM)


func _build_race_map(preset: Dictionary, stage: Node3D) -> bool:
	if OS.get_environment(FORCE_FALLBACK_ENV) == "1":
		return false
	if not ResourceLoader.exists(RACE_SCENE):
		return false
	var packed: PackedScene = load(RACE_SCENE) as PackedScene
	if packed == null:
		return false
	_set_autoload_property("GameSettings", "selected_map",
		str(preset.get("id", TrackDefs.DEFAULT_ID)))
	var race := packed.instantiate() as Node3D
	if race == null:
		return false
	stage.add_child(race)
	_hide_overlays(race)
	return _count_geometry(race) > 8


func _build_grid_fallback(preset: Dictionary, stage: Node3D) -> bool:
	var rows: PackedStringArray = TrackDefs.grid_of(preset)
	if rows.is_empty():
		return false
	_build_ground(stage, preset)
	var theme_dict: Dictionary = {"id": TrackDefs.theme_id_of(preset)}
	var height_rows: PackedStringArray = TrackDefs.heights_of(preset)
	if not height_rows.is_empty():
		theme_dict["heights"] = height_rows
	var spline: RefCounted = KenneyTiles.build(stage, rows, theme_dict)
	if spline == null:
		return false
	var theme_path: String = TrackDefs.theme_path_of(preset)
	if ResourceLoader.exists(theme_path):
		var theme: Script = load(theme_path) as Script
		if theme != null and theme.has_method("build"):
			theme.call("build", stage, spline)
	return _count_geometry(stage) > 8


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


# --------------------------------------------------------------------------
# minigame & sandbox arena building (dynamic load + bespoke 3D fallback)
# --------------------------------------------------------------------------


func _build_arena_preview(game_id: String, arena_id: String,
		preset: Dictionary, stage: Node3D) -> Dictionary:
	if game_id == "cargo_rush":
		return CargoTheme.build_arena(stage, arena_id)

	var script_path: String = KO_MAPS_SCRIPT if game_id == "knockout" \
		else BT_MAPS_SCRIPT
	var built: Variant = _try_call_map_builder(script_path, stage, arena_id)
	if _count_geometry(stage) > 4:
		if built is Dictionary:
			return built as Dictionary
		return {"spawns": _default_arena_spawns(arena_id)}

	# Secondary fallback: try instantiating the minigame scene if it exists
	var scene_path: String = str(preset.get("scene", ""))
	if scene_path != "" and ResourceLoader.exists(scene_path):
		_set_autoload_property("GameSettings", "selected_minigame", arena_id)
		var packed: PackedScene = load(scene_path) as PackedScene
		if packed != null:
			var inst := packed.instantiate() as Node3D
			if inst != null:
				stage.add_child(inst)
				_hide_overlays(inst)
				if _count_geometry(inst) > 4:
					return {"spawns": _default_arena_spawns(arena_id), "has_scene_karts": true}
				inst.queue_free()

	# Tertiary fallback: rich bespoke 3D stage matching that exact map's design
	return _build_bespoke_fallback_arena(stage, game_id, arena_id)


func _build_sandbox_preview(stage: Node3D) -> Dictionary:
	for script_path: String in SANDBOX_PARK_SCRIPTS:
		if not ResourceLoader.exists(script_path):
			continue
		var script: Script = load(script_path) as Script
		if script == null:
			continue
		var res: Variant = _invoke_builder_method(script, "build", stage, "sandbox")
		if _count_geometry(stage) > 4:
			_ensure_floor_under(stage, Color("66ab48"))
			if res is Dictionary:
				return res as Dictionary
			return {"spawns": _default_arena_spawns("sandbox")}
	for scene_path: String in SANDBOX_SCENES:
		if not ResourceLoader.exists(scene_path):
			continue
		var packed: PackedScene = load(scene_path) as PackedScene
		if packed == null:
			continue
		var inst := packed.instantiate() as Node3D
		if inst != null:
			stage.add_child(inst)
			_hide_overlays(inst)
			if _count_geometry(inst) > 4:
				return {"spawns": _default_arena_spawns("sandbox"), "has_scene_karts": true}
			inst.queue_free()
	return _build_bespoke_fallback_arena(stage, "sandbox", "sandbox")


func _try_call_map_builder(script_path: String, stage: Node3D,
		arena_id: String) -> Variant:
	if not ResourceLoader.exists(script_path):
		return null
	var script: Script = load(script_path) as Script
	if script == null:
		return null
	for method_name: String in ["build_arena", "build_map", "build"]:
		var res: Variant = _invoke_builder_method(script, method_name, stage, arena_id)
		if _count_geometry(stage) > 4:
			return res
	return null


func _invoke_builder_method(script: Script, method_name: String,
		stage: Node3D, arena_id: String) -> Variant:
	for entry: Dictionary in script.get_script_method_list():
		if str(entry.get("name", "")) != method_name:
			continue
		var args: Array = entry.get("args", []) as Array
		var defaults: Array = entry.get("default_args", []) as Array
		var min_args: int = args.size() - defaults.size()
		if args.size() >= 2 and min_args <= 2:
			return script.call(method_name, stage, arena_id)
		if args.size() >= 1 and min_args <= 1:
			return script.call(method_name, stage)
	return null


func _ensure_floor_under(stage: Node3D, tint: Color) -> void:
	for node: Node in _nodes_of_type(stage, "MeshInstance3D"):
		var inst := node as MeshInstance3D
		if inst.mesh != null and inst.mesh.get_aabb().size.x >= 180.0:
			return
	var plane := PlaneMesh.new()
	plane.size = Vector2(520.0, 520.0)
	var floor_node := MeshInstance3D.new()
	floor_node.name = "SandboxPreviewGround"
	floor_node.mesh = plane
	floor_node.position = Vector3(0.0, -0.05, 0.0)
	floor_node.material_override = CargoTheme.flat_material(tint, false)
	stage.add_child(floor_node)


## Stage the real game roster instead of misleading generic race cars. The
## shopping cart leads every composition; vans and trucks make the party-game
## scale readable even in a small menu card.
func _stage_preview_karts(stage: Node3D, info: Dictionary,
		arena_id: String) -> void:
	if bool(info.get("has_scene_karts", false)):
		return
	var spawns: Array[Transform3D] = _extract_spawns(info, arena_id)
	var holder := Node3D.new()
	holder.name = "PreviewVehicles"
	stage.add_child(holder)
	for i in mini(PREVIEW_VEHICLE_IDS.size(), spawns.size()):
		var entry: Dictionary = Catalog.find(PREVIEW_VEHICLE_IDS[i])
		var vehicle: Node3D = VehicleVisual.build(entry)
		if vehicle == null:
			continue
		vehicle.name = "PreviewVehicle_%d" % i
		holder.add_child(vehicle)
		var xform: Transform3D = spawns[i]
		vehicle.position = xform.origin + Vector3.UP * 0.04
		vehicle.rotation.y = atan2(xform.basis.z.x, xform.basis.z.z)
		vehicle.scale = Vector3.ONE * 1.35


func _stage_race_vehicles(stage: Node3D, framing: Dictionary) -> void:
	if not framing.has("forward"):
		return
	for node: Node in _nodes_of_type(stage, "CharacterBody3D"):
		if node is Node3D:
			(node as Node3D).visible = false
	var start: Vector3 = framing["start"] as Vector3
	var forward: Vector3 = framing["forward"] as Vector3
	var right: Vector3 = framing["right"] as Vector3
	var yaw: float = atan2(-forward.x, -forward.z)
	var offsets: Array[Vector3] = [
		right * -2.2 + forward * 3.0,
		right * 2.0,
		right * -1.6 - forward * 4.0,
		right * 2.2 - forward * 5.5,
	]
	var holder := Node3D.new()
	holder.name = "PreviewRaceVehicles"
	stage.add_child(holder)
	for i in PREVIEW_VEHICLE_IDS.size():
		var entry: Dictionary = Catalog.find(PREVIEW_VEHICLE_IDS[i])
		var vehicle: Node3D = VehicleVisual.build(entry)
		if vehicle == null:
			continue
		holder.add_child(vehicle)
		vehicle.position = start + offsets[i] + Vector3.UP * 0.16
		vehicle.rotation.y = yaw
		vehicle.scale = Vector3.ONE * 1.25


func _extract_spawns(info: Dictionary, arena_id: String) -> Array[Transform3D]:
	var out: Array[Transform3D] = []
	for key: String in ["spawns", "spawn_points", "kart_spawns", "starts", "positions"]:
		if not info.has(key):
			continue
		var raw: Variant = info[key]
		if raw is Array:
			for item: Variant in raw as Array:
				if item is Transform3D:
					out.append(item as Transform3D)
				elif item is Vector3:
					var pt: Vector3 = item as Vector3
					var yaw: float = atan2(pt.x, pt.z)
					out.append(Transform3D(Basis(Vector3.UP, yaw), pt))
				elif item is Dictionary:
					var d: Dictionary = item as Dictionary
					var p_var: Variant = d.get("position", d.get("pos", Vector3.ZERO))
					if p_var is Vector3:
						var p: Vector3 = p_var as Vector3
						var yw: float = float(d.get("yaw", atan2(p.x, p.z)))
						out.append(Transform3D(Basis(Vector3.UP, yw), p))
		elif raw is PackedVector3Array:
			for pt: Vector3 in raw as PackedVector3Array:
				out.append(Transform3D(Basis(Vector3.UP, atan2(pt.x, pt.z)), pt))
		if out.size() >= 4:
			return out
	return _default_arena_spawns(arena_id)


func _default_arena_spawns(arena_id: String) -> Array[Transform3D]:
	match arena_id:
		"ko_foundry":
			return [
				Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-18.0, 0.2, -6.0)),
				Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(18.0, 0.2, 6.0)),
				Transform3D(Basis(Vector3.UP, 0.0), Vector3(-16.0, 0.2, 10.0)),
				Transform3D(Basis(Vector3.UP, PI), Vector3(16.0, 0.2, -10.0)),
			]
		"ko_iceberg":
			return [
				Transform3D(Basis(Vector3.UP, 0.75), Vector3(12.0, 0.2, 12.0)),
				Transform3D(Basis(Vector3.UP, -2.35), Vector3(-12.0, 0.2, -12.0)),
				Transform3D(Basis(Vector3.UP, -0.75), Vector3(-12.0, 0.2, 12.0)),
				Transform3D(Basis(Vector3.UP, 2.35), Vector3(12.0, 0.2, -12.0)),
			]
		"bt_ferries":
			return [
				Transform3D(Basis(Vector3.UP, -PI * 0.5), Vector3(-18.0, 1.2, -8.0)),
				Transform3D(Basis(Vector3.UP, PI * 0.5), Vector3(18.0, 1.2, 8.0)),
				Transform3D(Basis(Vector3.UP, 0.2), Vector3(-18.0, 1.2, 12.0)),
				Transform3D(Basis(Vector3.UP, PI - 0.2), Vector3(18.0, 1.2, -12.0)),
			]
		_:
			return [
				Transform3D(Basis(Vector3.UP, 0.65), Vector3(13.0, 0.25, 13.0)),
				Transform3D(Basis(Vector3.UP, -2.45), Vector3(-13.0, 0.25, -13.0)),
				Transform3D(Basis(Vector3.UP, -0.65), Vector3(-13.0, 0.25, 13.0)),
				Transform3D(Basis(Vector3.UP, 2.45), Vector3(13.0, 0.25, -13.0)),
			]


## Bespoke 3D arena fallback used ONLY if `knockout_maps.gd`, `bomb_tag_maps.gd`
## or `sandbox_park.gd` is not yet on disk when preview_render runs standalone.
func _build_bespoke_fallback_arena(stage: Node3D, game_id: String,
		arena_id: String) -> Dictionary:
	var batch := PropBatch.new()
	if arena_id == "sandbox":
		_ensure_floor_under(stage, Color("68ad49"))
		batch.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.12, 0.0)),
			34.0, 0.24, 36, Color("48525c"))
		for idx in 4:
			var ang: float = float(idx) * PI * 0.5 + 0.4
			var p := Vector3(cos(ang) * 18.0, 0.9, sin(ang) * 18.0)
			batch.add_box(Transform3D(Basis(Vector3.UP, -ang), p),
				Vector3(6.5, 1.8, 9.0), Color("e8a838") if idx % 2 == 0 else Color("3a8fd6"))
		CargoTheme.place_model(stage, "grandStandCovered", Vector3(0.0, 0.0, -44.0),
			0.0, Vector3.ONE * 12.0, "ParkStand")
	elif game_id == "knockout":
		var backdrop := Color("1c2d42")
		if arena_id == "ko_foundry":
			backdrop = Color("cf4b1b")
			for sx: float in [-1.0, 1.0]:
				batch.add_box(Transform3D(Basis.IDENTITY, Vector3(sx * 19.0, 1.0, 0.0)),
					Vector3(20.0, 2.0, 34.0), Color("3f4652"))
				batch.add_box(Transform3D(Basis.IDENTITY, Vector3(sx * 19.0, 2.08, 0.0)),
					Vector3(18.6, 0.14, 32.6), Color("f09c38"))
			for bz: float in [-9.0, 9.0]:
				batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.85, bz)),
					Vector3(18.5, 0.5, 5.8), Color("6d7885"))
		elif arena_id == "ko_iceberg":
			backdrop = Color("1f6f9f")
			batch.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.9, 0.0)),
				30.0, 1.8, 10, Color("bfe8f8"))
			batch.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.86, 0.0)),
				24.0, 0.16, 10, Color("7bd4ee"))
			for idx in 4:
				var a: float = PI * 0.25 + float(idx) * PI * 0.5
				batch.add_cylinder(Transform3D(Basis.IDENTITY,
					Vector3(cos(a) * 21.0, 3.2, sin(a) * 21.0)),
					2.2, 3.2, 7, Color("effaff"))
		else:
			batch.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.0, 0.0)),
				30.0, 2.0, 8, Color("465362"))
			batch.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.06, 0.0)),
				22.0, 0.14, 8, Color("5a697a"))
			batch.add_cylinder(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.55, 0.0)),
				7.5, 0.95, 20, Color("f2b638"))
		_ensure_floor_under(stage, backdrop)
	else:
		if arena_id == "bt_labyrinth":
			_ensure_floor_under(stage, Color("d88248"))
			batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.08, 0.0)),
				Vector3(68.0, 0.16, 68.0), Color("c9723c"))
			batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.4, 0.0)),
				Vector3(10.0, 0.5, 34.0), Color("e69d56"))
			for sx: float in [-1.0, 1.0]:
				for sz: float in [-1.0, 1.0]:
					batch.add_box(Transform3D(Basis.IDENTITY,
						Vector3(sx * 16.0, 2.2, sz * 16.0)),
						Vector3(6.5, 4.4, 6.5), Color("a84c28"))
		elif arena_id == "bt_ferries":
			_ensure_floor_under(stage, Color("1f75a6"))
			for sx: float in [-1.0, 1.0]:
				batch.add_box(Transform3D(Basis.IDENTITY, Vector3(sx * 18.0, 0.6, 0.0)),
					Vector3(20.0, 1.2, 46.0), Color("b84434") if sx < 0.0 else Color("2d6d9a"))
				batch.add_box(Transform3D(Basis.IDENTITY, Vector3(sx * 18.0, 1.26, 0.0)),
					Vector3(18.4, 0.14, 43.0), Color("53606e"))
			for bz: float in [-10.0, 10.0]:
				batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.25, bz)),
					Vector3(16.5, 0.36, 6.0), Color("f0b836"))
		else:
			_ensure_floor_under(stage, Color("4c5b6b"))
			batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 0.3, 0.0)),
				Vector3(64.0, 0.6, 64.0), Color("5f7082"))
			batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 1.4, 0.0)),
				Vector3(36.0, 1.6, 36.0), Color("75889c"))
			batch.add_box(Transform3D(Basis.IDENTITY, Vector3(0.0, 2.7, 0.0)),
				Vector3(16.0, 1.2, 16.0), Color("f2ba42"))
	var mesh_inst := MeshInstance3D.new()
	mesh_inst.name = "FallbackArenaMesh"
	mesh_inst.mesh = batch.build()
	mesh_inst.material_override = SceneryKit.vertex_material()
	stage.add_child(mesh_inst)
	return {"spawns": _default_arena_spawns(arena_id)}


# --------------------------------------------------------------------------
# palette, lighting and camera
# --------------------------------------------------------------------------


func _palette(preset: Dictionary) -> Dictionary:
	var raw: Variant = preset.get("palette", {})
	if raw is Dictionary and not (raw as Dictionary).is_empty():
		return raw as Dictionary
	return {"ground": FALLBACK_GROUND, "sky": FALLBACK_SKY,
		"haze": FALLBACK_HAZE, "kerb": FALLBACK_KERB}


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


func _install_lighting(stage: Node3D, preset: Dictionary) -> void:
	var map_id: String = str(preset.get("id", TrackDefs.DEFAULT_ID))
	var palette: Dictionary = _palette(preset)
	var env_spec: Dictionary = ENVIRONMENTS.get(map_id, {}) as Dictionary
	var sky_colour: Color = env_spec.get("sky_top", _grade_colour(
		(palette.get("sky", FALLBACK_SKY) as Color).lerp(SKY_BLUE, 0.55),
		0.86, 1.35)) as Color
	var haze: Color = env_spec.get("sky_horizon", _grade_colour(
		(palette.get("haze", FALLBACK_HAZE) as Color).lerp(SKY_HORIZON, 0.55),
		1.0, 1.05)) as Color
	var sun_col: Color = env_spec.get("sun_color", Color(1.0, 0.96, 0.88).lerp(
		palette.get("sky", FALLBACK_SKY), 0.30)) as Color
	var sun_energy: float = float(env_spec.get("sun_energy", 1.18))
	var sun_rot: Vector3 = env_spec.get("sun_rot",
		Vector3(-52.0, -34.0, 0.0)) as Vector3
	var fog_col: Color = env_spec.get("fog_color", haze) as Color
	var fog_dens: float = float(env_spec.get("fog_density", 0.00045))
	for node: Node in _nodes_of_type(stage, "DirectionalLight3D"):
		node.get_parent().remove_child(node)
		node.free()
	var sun := DirectionalLight3D.new()
	sun.name = "PreviewSun"
	sun.rotation_degrees = sun_rot
	sun.light_color = sun_col
	sun.light_energy = sun_energy * 0.88
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 520.0
	stage.add_child(sun)

	for node: Node in _nodes_of_type(stage, "WorldEnvironment"):
		node.get_parent().remove_child(node)
		node.free()
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = sky_colour
	sky_material.sky_horizon_color = haze
	sky_material.sky_curve = 0.38
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
	environment.ambient_light_energy = float(env_spec.get("ambient", 0.30))
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.90
	environment.tonemap_white = 1.35
	environment.fog_enabled = true
	environment.fog_light_color = fog_col
	environment.fog_light_energy = 0.85
	environment.fog_density = fog_dens * 0.14
	environment.fog_sky_affect = 0.12
	environment.fog_aerial_perspective = 0.08
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 0.98
	environment.adjustment_contrast = 1.10
	environment.adjustment_saturation = 1.20
	var world := WorldEnvironment.new()
	world.name = "PreviewEnvironment"
	world.environment = environment
	stage.add_child(world)


func _framing_for(target_kind: String, preset: Dictionary, stage: Node3D,
		arena_info: Dictionary) -> Dictionary:
	var map_id: String = str(preset.get("id", TrackDefs.DEFAULT_ID))
	var view_spec: Dictionary = MAP_VIEWS.get(map_id, {}) as Dictionary
	var pad: float = float(view_spec.get("pad", FRAME_PAD))
	var pitch_deg: float = float(view_spec.get("pitch_deg", CAMERA_PITCH_DEG))
	if target_kind != "race_map":
		var clamp_half: float = 38.0 if map_id == "knockout" or map_id.begins_with("ko_") else ARENA_CLAMP_HALF
		var bounds: AABB = arena_info.get("bounds", AABB()) as AABB
		if bounds.size.length_squared() < 1.0:
			bounds = _visual_bounds(stage, clamp_half)
		if bounds.size.length_squared() > 1.0:
			var min_p := Vector3(
				maxf(bounds.position.x, -clamp_half),
				maxf(bounds.position.y, -2.0),
				maxf(bounds.position.z, -clamp_half))
			var max_p := Vector3(
				minf(bounds.end.x, clamp_half),
				minf(bounds.end.y, 16.0),
				minf(bounds.end.z, clamp_half))
			if max_p.x - min_p.x > 8.0 and max_p.z - min_p.z > 8.0:
				bounds = AABB(min_p, max_p - min_p)
			var mg_framing: Dictionary = _expand_framing(_box_corners(bounds), pad)
			mg_framing["pitch_deg"] = pitch_deg
			if view_spec.has("yaw_deg"):
				mg_framing["yaw_deg"] = float(view_spec["yaw_deg"])
			return mg_framing
		var arena := PackedVector3Array()
		for index in 24:
			var angle: float = TAU * float(index) / 24.0
			arena.append(Vector3(cos(angle), 0.0, sin(angle)) * MINIGAME_RADIUS)
		var def_framing: Dictionary = {
			"centre": Vector3.ZERO, "points": arena, "pitch_deg": pitch_deg,
		}
		if view_spec.has("yaw_deg"):
			def_framing["yaw_deg"] = float(view_spec["yaw_deg"])
		return def_framing

	var points: PackedVector3Array = _track_points_from(stage)
	if points.is_empty():
		var stored: Variant = stage.get_meta("kenney_spline", null)
		if stored is RefCounted \
				and (stored as RefCounted).get("points") is PackedVector3Array:
			points = (stored as RefCounted).get("points") as PackedVector3Array
	var framing: Dictionary = _expand_framing(points, pad)
	framing["pitch_deg"] = pitch_deg
	if not points.is_empty():
		var start_fraction: float = float(view_spec.get("start_fraction", 0.12))
		var start_index: int = mini(int(points.size() * start_fraction), points.size() - 2)
		var start: Vector3 = points[start_index]
		var ahead: Vector3 = points[mini(start_index + 4, points.size() - 1)]
		var forward: Vector3 = (ahead - start).normalized()
		var right: Vector3 = forward.cross(Vector3.UP).normalized()
		framing["start"] = start
		framing["forward"] = forward
		framing["right"] = right
		framing["eye"] = start - forward * 17.0 + right * 11.0 + Vector3.UP * 9.0
		framing["target"] = start + forward * 18.0 + Vector3.UP * 1.6
	return framing


func _expand_framing(points: PackedVector3Array,
		pad: float = FRAME_PAD) -> Dictionary:
	if points.is_empty():
		return {"centre": Vector3.ZERO, "points": PackedVector3Array()}
	var min_point: Vector3 = points[0]
	var max_point: Vector3 = points[0]
	for point: Vector3 in points:
		min_point = min_point.min(point)
		max_point = max_point.max(point)
	var centre: Vector3 = (min_point + max_point) * 0.5
	centre.y = (min_point.y + max_point.y) * 0.35
	var expanded := PackedVector3Array()
	for point: Vector3 in points:
		var offset: Vector3 = point - centre
		offset.y = 0.0
		var dir: Vector3 = offset.normalized() if offset.length_squared() > 0.001 \
			else Vector3.ZERO
		expanded.append(point + dir * pad)
	return {"centre": centre, "points": expanded}


func _install_camera(stage: Node3D, framing: Dictionary) -> Camera3D:
	var centre: Vector3 = framing["centre"] as Vector3
	var points: PackedVector3Array = framing["points"] as PackedVector3Array
	var camera := Camera3D.new()
	camera.name = "PreviewCamera"
	camera.fov = CAMERA_FOV
	camera.near = 0.5
	camera.far = 6000.0
	stage.add_child(camera)
	if framing.has("eye") and framing.has("target"):
		camera.fov = 52.0
		camera.look_at_from_position(framing["eye"] as Vector3,
			framing["target"] as Vector3, Vector3.UP)
		camera.current = true
		return camera
	var pitch: float = deg_to_rad(float(framing.get("pitch_deg", CAMERA_PITCH_DEG)))
	if framing.has("yaw_deg"):
		pitch = deg_to_rad(float(framing.get("pitch_deg", CAMERA_PITCH_DEG)) * 0.78)
		var fixed_yaw: float = deg_to_rad(float(framing["yaw_deg"]))
		var fixed_dir := Vector3(sin(fixed_yaw) * cos(pitch), sin(pitch),
			cos(fixed_yaw) * cos(pitch))
		var map_id: String = str(stage.name).trim_prefix("Map_")
		var distance_scale: float = 0.86 if map_id == "knockout" or map_id.begins_with("ko_") else 0.76
		var fixed_dist: float = _fit_distance(centre, points, fixed_dir) * distance_scale
		camera.look_at_from_position(centre + fixed_dir * fixed_dist, centre,
			Vector3.UP)
		camera.current = true
		return camera

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


func _camera_score(centre: Vector3, points: PackedVector3Array, eye: Vector3,
		start: Vector3) -> float:
	var extent: float = _frame_extent(centre, points, (eye - centre).normalized(),
		eye.distance_to(centre))
	if extent > FRAME_FILL:
		return 100.0 + extent
	var ndc: Vector2 = _project(eye, centre, start)
	var score: float = absf(ndc.x) * 1.2 + absf(ndc.y + 0.3) * 1.5
	score += absf(extent - FRAME_FILL) * 2.0
	if absf(ndc.x) > 0.85 or ndc.y < -0.9:
		score += 4.0
	return score


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


func _start_ndc(framing: Dictionary, camera: Camera3D) -> Vector2:
	if camera == null or not framing.has("start"):
		return Vector2.ZERO
	return _project(camera.global_position, framing["centre"] as Vector3,
		framing["start"] as Vector3)


func _fit_distance(centre: Vector3, points: PackedVector3Array,
		direction: Vector3) -> float:
	if points.is_empty():
		return MINIGAME_RADIUS * 3.6
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


func _visual_bounds(root: Node, clamp_half: float = 70.0) -> AABB:
	var state: Dictionary = {}
	_collect_visual_bounds(root, state, clamp_half)
	if not state.has("bounds"):
		return AABB()
	return state["bounds"] as AABB


func _collect_visual_bounds(root: Node, state: Dictionary,
		clamp_half: float = 70.0) -> void:
	for child: Node in root.get_children():
		if child is MeshInstance3D:
			var mesh: Mesh = (child as MeshInstance3D).mesh
			if mesh != null:
				var local: AABB = mesh.get_aabb()
				if local.size.y >= 0.08 and local.size.x <= 150.0 \
						and local.size.z <= 150.0:
					var world: AABB = _transform_aabb(
						(child as MeshInstance3D).global_transform, local)
					if absf(world.get_center().x) <= clamp_half \
							and absf(world.get_center().z) <= clamp_half:
						_merge_bounds(state, world)
		elif child is MultiMeshInstance3D:
			var mm: MultiMesh = (child as MultiMeshInstance3D).multimesh
			if mm != null and mm.mesh != null and mm.instance_count > 0:
				var m_local: AABB = mm.mesh.get_aabb()
				var parent_xf: Transform3D = (child as MultiMeshInstance3D).global_transform
				var limit: int = mini(mm.instance_count, 96)
				for idx in limit:
					var ixf: Transform3D = parent_xf * mm.get_instance_transform(idx)
					if absf(ixf.origin.x) <= clamp_half and absf(ixf.origin.z) <= clamp_half:
						_merge_bounds(state, _transform_aabb(ixf, m_local))
		_collect_visual_bounds(child, state, clamp_half)


func _merge_bounds(state: Dictionary, world: AABB) -> void:
	if state.has("bounds"):
		state["bounds"] = (state["bounds"] as AABB).merge(world)
	else:
		state["bounds"] = world


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


func _set_autoload_property(autoload_name: String, property: String,
		value: Variant) -> void:
	var autoload: Node = get_node_or_null("/root/" + autoload_name)
	if autoload != null:
		autoload.set(property, value)


func _hide_overlays(root: Node) -> void:
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
	print("---- preview_render: %d preview(s), %d failure(s) ----" % [
		records.size(), failures])
	for record: Dictionary in records:
		print("  %s -> %s" % [
			str(record["id"]),
			ProjectSettings.globalize_path(str(record["path"]))])
	if failures > 0:
		push_error("preview_render: %d preview(s) failed verification" % failures)
