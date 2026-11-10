extends Node3D
## MEADOW LOOP - a solo 3-lap race on a winding dirt track through a dense,
## low-poly grassy forest. Built at runtime from one closed Catmull-Rom spline.
##
## Pipeline:
##   spline -> road ribbon + curbs + invisible barrier walls + ground plane
##          -> start/finish line + four sector gates
##          -> Kenney Nature Kit foliage, merged into one MultiMesh per model
##          -> physical AI rivals that drive the same vehicle as the player
##          -> lap/sector tracking, countdown, HUD badges and a candy result card
##
## The kart, chase camera, boost, drift, HUD and pause menu are the same ones
## the sandbox uses. Nothing here touches multiplayer.

const TrackSpline := preload("res://scripts/minigames/track_spline.gd")
const CART_SCENE := preload("res://scenes/player/cart_player.tscn")
const VehicleCatalog := preload("res://scripts/vehicles/vehicle_catalog.gd")
const FoliageBaker := preload("res://scripts/minigames/foliage_baker.gd")
const RaceScenery := preload("res://scripts/minigames/race_scenery.gd")
const MeadowLandmarks := preload("res://scripts/minigames/meadow_landmarks.gd")
const RaceEffects := preload("res://scripts/minigames/race_effects.gd")
const VehicleVisual := preload("res://scripts/vehicles/vehicle_visual.gd")
const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const ART_BACKDROP := preload("res://scripts/ui/art_backdrop.gd")
const VisualGrade := preload("res://scripts/systems/visual_grade.gd")
const Backdrop := preload("res://scripts/systems/backdrop.gd")
const OUTLINE_SHADER := preload("res://assets/materials/toon_outline.gdshader")

const RACE_SCENE: String = "res://scenes/minigames/grass_race.tscn"
const LOBBY_SCENE: String = "res://scenes/minigames/meadow_lobby.tscn"
const MINIGAMES_MENU: String = "res://scenes/ui/minigames_menu.tscn"
const MAIN_MENU: String = "res://scenes/ui/main_menu.tscn"
const PBR_SHADER: String = "res://assets/materials/ground_pbr.gdshader"
const PBR_TEX: String = "res://assets/textures/polyhaven/"
const BOOST_PAD_SCENE: String = "res://scenes/track/boost_pad.tscn"
const CONE_MODEL: String = "res://assets/models/kenney_car-kit/Models/GLB format/cone.glb"
const CHECKER_SHADER: String = "res://assets/materials/checker.gdshader"
const CANDY_BUTTON: String = "res://scripts/ui/candy_button.gd"
const CHECKER_FLAG: String = "res://scripts/ui/checker_flag.gd"
const THEME: String = "res://assets/ui/theme.tres"
const TITLE_FONT: String = "res://assets/ui/fonts/LuckiestGuy-Regular.ttf"
const KART_ROOT: String = "res://assets/models/kenney_car-kit/Models/GLB format/"
const COUNTDOWN_BEEP: AudioStream = preload("res://assets/audio/sfx/race/countdown_beep.wav")
const COUNTDOWN_GO: AudioStream = preload("res://assets/audio/sfx/race/countdown_go.wav")
const LAP_CHIME: AudioStream = preload("res://assets/audio/sfx/race/lap_chime.wav")
const FINISH_FANFARE: AudioStream = preload("res://assets/audio/sfx/race/finish_fanfare.wav")
const FOREST_AMBIENCE: AudioStream = preload("res://assets/audio/ambience/forest_ambience.mp3")
const NET_SYNC_INTERVAL: float = 0.05
## A spoofed far-future sender stamp must not permanently freeze a peer's
## progress and leave every result card waiting forever. A huge backwards jump
## is treated as a clock reset and re-baselined.
const NET_CLOCK_RESET_MS: int = 60_000

const TOTAL_LAPS: int = 3
var _total_laps: int = TOTAL_LAPS
const ROAD_HALF: float = 5.5
const ROAD_Y: float = 0.04
const CURB_WIDTH: float = 0.8
const BARRIER_OFFSET: float = 0.5
const BARRIER_HEIGHT: float = 2.4
const START_DISTANCE: float = 8.0
const FIELD_X: float = 200.0
const FIELD_Z: float = 170.0
const GROUND_X: float = 1400.0
const GROUND_Z: float = 1400.0
const GRID_CELL: float = 16.0
const ROAD_STEP: float = 1.5

const TREES: PackedStringArray = [
	"tree_default", "tree_default_dark", "tree_default_fall",
	"tree_oak", "tree_oak_dark", "tree_oak_fall",
	"tree_cone", "tree_cone_dark", "tree_cone_fall",
	"tree_fat", "tree_fat_darkh", "tree_fat_fall",
	"tree_tall", "tree_tall_dark", "tree_tall_fall",
	"tree_thin", "tree_thin_dark", "tree_thin_fall",
	"tree_simple", "tree_simple_dark", "tree_detailed", "tree_detailed_dark",
	"tree_small", "tree_small_dark", "tree_small_fall",
	"tree_pineTallA", "tree_pineTallB", "tree_pineTallC", "tree_pineTallD",
	"tree_pineRoundA", "tree_pineRoundB", "tree_pineRoundC", "tree_pineRoundE",
	"tree_pineSmallA", "tree_pineSmallB", "tree_pineSmallC",
	"tree_plateau", "tree_plateau_dark",
]
const BUSHES: PackedStringArray = [
	"plant_bush", "plant_bushDetailed", "plant_bushLarge", "plant_bushSmall",
	"plant_bushTriangle", "plant_bushLargeTriangle", "plant_flatShort", "plant_flatTall",
]
const GRASSES: PackedStringArray = ["grass", "grass_large", "grass_leafs", "grass_leafsLarge"]
const FLOWERS: PackedStringArray = [
	"flower_purpleA", "flower_purpleB", "flower_redA", "flower_redB",
	"flower_yellowA", "flower_yellowB",
]
const ROCKS: PackedStringArray = [
	"rock_largeA", "rock_largeB", "rock_largeC", "rock_smallA", "rock_smallB",
	"rock_smallC", "rock_smallFlatA", "rock_tallA", "stone_largeA", "stone_smallA",
]
const WOODLAND: PackedStringArray = [
	"stump_round", "stump_old", "stump_roundDetailed", "log", "log_large",
	"mushroom_red", "mushroom_tan", "mushroom_redGroup",
]

const RAMP_FRACTIONS: Array[float] = [0.315, 0.915]
const RAMP_WIDTH: float = 6.4
const RAMP_LENGTH: float = 6.0
const RAMP_HEIGHT: float = 1.90

const BOT_NAMES: PackedStringArray = [
	"SLOPPY", "CLANK", "BEEP", "POPPY", "TURBO", "RUSTY",
	"MUNCH", "WHEEZY", "BUCKET", "NOODLE", "CRUMB", "ZIPPY",
	"SQUEAK", "BONK", "PUDDING", "GIZMO",
]
const BOT_COLORS: Array[Color] = [
	Color("45b6f0"), Color("f26ca7"), Color("ffd22e"), Color("4fbf52"),
	Color("f2545b"), Color("38d6f0"), Color("b18cff"), Color("ff9f45"),
]

enum Phase { COUNTDOWN, RACING, FINISHED }

var _spline: RefCounted
var _cart: CartPlayer
var _hud: Node
var _hud_time_accum: float = 0.0
var _hud_standings_accum: float = 0.0
var _hud_last_place: int = -1
var _hud_last_lap: int = -1
var _rival_tick_accum: float = 0.0
var _baked: Dictionary = {}
var _grid: Dictionary = {}
var _foliage_material: Material
var _rivals: Array[Dictionary] = []
var _scenery: RefCounted
var _scenery_stats: Dictionary = {}
var _effects: Node3D
var _bend_materials: Array = []
var _start_lights: Array[MeshInstance3D] = []
var _gate_beams: Array[MeshInstance3D] = []
var _last_sector: int = 0
var _ramp_distances: Array[float] = []

var _phase: Phase = Phase.COUNTDOWN
var _countdown: float = 3.0
var _go_time: float = 0.0
var _last_count: int = 0
var _waiting_for_peers: bool = false
var _wait_elapsed: float = 0.0
var _go_shown: bool = false
var _race_time: float = 0.0
var _lap: int = 1
var _lap_start: float = 0.0
var _lap_times: Array[float] = []
var _unwrapped: float = START_DISTANCE
var _prev_s: float = START_DISTANCE
var _sector_flags: int = 1
var _skip_progress: bool = true
var _last_cart_pos: Vector3 = Vector3.ZERO
var _off_timer: float = 0.0
var _was_off_track: bool = false
var _base_max_speed: float = 19.0
var _saved_vehicle: String = ""
var _toast_timer: float = 0.0
var _multiplayer: bool = false
var _is_host: bool = false
var _remote_carts: Dictionary = {}
var _peer_vehicles: Dictionary = {}
var _race_vehicle: String = "" ## The host's car - everyone drives it in a race.
var _name_labels: Dictionary = {}
var _remote_progress: Dictionary = {}
var _remote_progress_ms: Dictionary = {} ## peer id -> newest accepted stamp
var _net_sync_timer: float = 0.0
var _bot_sync_timer: float = 0.0
var _horn_stamp: Dictionary = {}
## Host-authoritative race props: the host simulates cones and broadcasts
## snapshots; clients freeze their copy and ask the host to apply pushes.
var _props: Array[RigidBody3D] = []
var _prop_targets: Dictionary = {}
var _prop_sync_timer: float = 0.0
var _push_stamp: Dictionary = {}
## Client-side prediction: a pushed frozen prop is unfrozen briefly so the
## player sees it fly immediately instead of driving through it.
var _prop_kick_until: Dictionary = {}
var _prop_serial: int = 0
const PROP_SYNC_INTERVAL: float = 0.10

var _canvas: CanvasLayer
var _countdown_label: Label
var _toast_label: Label
var _offtrack_label: Label
var _result_root: Control
var _result_title: Label
var _result_subtitle: Label
var _result_total: Label
var _result_best: Label
var _result_place: Label
var _result_laps: Label
var _result_lap_rows: VBoxContainer
var _result_standings_section: VBoxContainer
var _result_wait_banner: PanelContainer
var _result_wait_label: Label
var _result_wait_style: StyleBoxFlat
var _result_done_style: StyleBoxFlat
var _result_standings_rows: VBoxContainer
var _result_standings_cache: Dictionary = {}
var _result_row_style: StyleBoxFlat
var _result_local_row_style: StyleBoxFlat
var _result_refresh_timer: float = 0.0
var _result_primary: Button
var _ambient_audio: AudioStreamPlayer


# --------------------------------------------------------------------------
# lifecycle



func _rpc_sender() -> int:
	## RPCs can still be queued when a peer is tearing down; never dereference
	## a null multiplayer peer.
	return multiplayer.get_remote_sender_id() if multiplayer.multiplayer_peer != null else 0

func _enter_tree() -> void:
	# CartPlayer reads GameSettings.selected_vehicle in its own _ready, which
	# runs before this node's _ready. Swap in the minigame vehicle here and put
	# the sandbox choice back when the scene is left (memory only, not saved).
	_saved_vehicle = GameSettings.selected_vehicle
	GameSettings.selected_vehicle = GameSettings.minigame_vehicle


func _exit_tree() -> void:
	GameSettings.selected_vehicle = _saved_vehicle


func _ready() -> void:
	_spline = TrackSpline.new()
	var test_laps: String = OS.get_environment("CART_TEST_LAPS")
	if test_laps.is_valid_int():
		_total_laps = clampi(test_laps.to_int(), 1, 9)
	_foliage_material = FoliageBaker.make_material()
	CursorController.set_menu_mode(false)
	_upgrade_graphics()

	_cart = get_tree().get_first_node_in_group("player") as CartPlayer
	_hud = $HUD
	# The result card is built below, so decide the session type first. Without
	# this, multiplayer showed RACE AGAIN (which is a no-op) and a solo-only
	# back button.
	_multiplayer = Network.is_session_active()
	_is_host = Network.is_host
	if _cart != null:
		_base_max_speed = _cart.max_speed
		_last_cart_pos = _cart.global_position

	_build_ground()
	_build_hills()
	_build_track()
	_build_barriers()
	_build_start_line()
	_build_gates()
	_build_start_lights()
	_build_start_festival()
	_build_boost_pads()
	_build_ramps()
	_build_grid()
	_build_scenery()
	_build_trackside_props()
	_build_verge_details()
	_build_corner_furniture()
	_build_corner_hazards()
	_build_track_fence()
	_build_sponsor_boards()
	_build_rivals()
	_build_overlay()
	_start_ambience()

	if _cart != null:
		var spawn: Transform3D = _track_transform(START_DISTANCE)
		_cart.set_spawn_transform(spawn)
		_cart.global_transform = spawn
		_cart.velocity = Vector3.ZERO
		_cart.set_physics_process(false)
		_effects = RaceEffects.new()
		_effects.name = "RaceEffects"
		add_child(_effects)
		_effects.call("setup", _cart)
		if not _cart.horn_requested.is_connected(_on_horn_requested):
			_cart.horn_requested.connect(_on_horn_requested)
		if Network.is_session_active():
			_setup_multiplayer()
			_waiting_for_peers = true
			_wait_elapsed = 0.0
			_countdown_label.text = "WAITING"

	_hud.call("set_lap", 1, _total_laps)
	_hud.call("set_race_position", 1, _field_size())
	_hud.call("set_race_time", 0.0, -1.0)
	if not _waiting_for_peers:
		_countdown_label.text = "3"
		_toast("MEADOW LOOP  ·  3 LAPS", 2.2)


func _upgrade_graphics() -> void:
	# MEADOW LOOP keeps 4x MSAA; sky, sun, fog and post come from the shared
	# VisualGrade so the race and the sandbox stay visually consistent.
	var viewport: Viewport = get_viewport()
	if viewport != null:
		# 2x MSAA plus FXAA antialiases the alpha-scissor foliage that MSAA
		# alone cannot touch, at a fraction of 4x MSAA's bandwidth.
		viewport.msaa_3d = Viewport.MSAA_2X
		viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	VisualGrade.apply($WorldEnvironment, "race")
	VisualGrade.apply_sun($Sun)


func _track_transform(distance: float, lateral: float = 0.0, height: float = 0.2) -> Transform3D:
	var frame: Dictionary = _spline.sample(distance)
	var position: Vector3 = frame["position"] + frame["right"] * lateral + Vector3.UP * height
	return Transform3D(Basis(Vector3.UP, _spline.yaw_at(distance)), position)


# --------------------------------------------------------------------------
# world


func _build_ground() -> void:
	var plane := PlaneMesh.new()
	plane.size = Vector2(GROUND_X, GROUND_Z)
	var mesh_instance := MeshInstance3D.new()
	mesh_instance.name = "MeadowGround"
	mesh_instance.mesh = plane
	mesh_instance.material_override = _pbr_material(
		"grass_diff", "grass_nor", "grass_rough", GROUND_X / 10.0,
		Color(0.72, 0.88, 0.65), 0.10, 0.05)
	add_child(mesh_instance)

	var body := StaticBody3D.new()
	body.name = "GroundCollision"
	var shape := BoxShape3D.new()
	shape.size = Vector3(GROUND_X, 2.0, GROUND_Z)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(0.0, -1.0, 0.0)
	body.add_child(collision)
	add_child(body)


func _build_hills() -> void:
	# The old horizon was a flat sheet of grass. A ring of soft, grassy hills
	# gives the chase camera a layered background and hides the world edge.
	var rng := RandomNumberGenerator.new()
	rng.seed = 7713
	var mat := _pbr_material("grass_diff", "grass_nor", "grass_rough", 20.0,
		Color(0.62, 0.78, 0.55), 0.10, 0.06)
	for index in 18:
		var angle: float = TAU * float(index) / 18.0 + rng.randf_range(-0.08, 0.08)
		var radius: float = rng.randf_range(210.0, 380.0)
		var hill_radius: float = rng.randf_range(40.0, 70.0)
		var hill_height: float = hill_radius * rng.randf_range(1.35, 1.75)
		var sphere := SphereMesh.new()
		sphere.radius = hill_radius
		sphere.height = hill_height
		sphere.radial_segments = 24
		sphere.rings = 12
		var hill := MeshInstance3D.new()
		hill.name = "Hill_%02d" % index
		hill.mesh = sphere
		hill.material_override = mat
		hill.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hill.position = Vector3(cos(angle) * radius, -hill_height * 0.18,
			sin(angle) * radius)
		hill.scale = Vector3(rng.randf_range(1.1, 1.3), 1.0, rng.randf_range(1.1, 1.3))
		add_child(hill)
	# A darker ridge behind the first ring closes the horizon.
	var ridge_mat := StandardMaterial3D.new()
	ridge_mat.albedo_color = Color(0.24, 0.38, 0.28)
	ridge_mat.roughness = 1.0
	ridge_mat.shading_mode = BaseMaterial3D.SHADING_MODE_PER_PIXEL
	for index in 9:
		var angle: float = TAU * float(index) / 9.0 + 0.28
		var radius: float = rng.randf_range(430.0, 600.0)
		var sphere := SphereMesh.new()
		sphere.radius = rng.randf_range(70.0, 120.0)
		sphere.height = rng.randf_range(75.0, 120.0)
		sphere.radial_segments = 16
		sphere.rings = 8
		var ridge := MeshInstance3D.new()
		ridge.mesh = sphere
		ridge.material_override = ridge_mat
		ridge.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		ridge.position = Vector3(cos(angle) * radius, -sphere.height * 0.18,
			sin(angle) * radius)
		ridge.scale = Vector3(rng.randf_range(1.4, 1.8), 1.0, rng.randf_range(1.4, 1.8))
		add_child(ridge)
	# Far peaks, rural landmarks and woodland push the horizon out in layers.
	Backdrop.add_mountains(self, rng, 14)
	Backdrop.add_clouds(self, rng, 18)
	MeadowLandmarks.build(self, _spline)


func _pbr_material(diff: String, nor: String, rough: String, uv_scale: float,
		tint: Color, detail: float, macro: float, tracks: float = 0.0) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(PBR_SHADER) as Shader
	mat.set_shader_parameter("albedo_tex", load(PBR_TEX + diff + ".jpg"))
	mat.set_shader_parameter("normal_tex", load(PBR_TEX + nor + ".jpg"))
	mat.set_shader_parameter("rough_tex", load(PBR_TEX + rough + ".jpg"))
	mat.set_shader_parameter("uv_scale", uv_scale)
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("detail_strength", detail)
	mat.set_shader_parameter("macro_variation", macro)
	mat.set_shader_parameter("roughness_min", 0.55)
	if tracks > 0.0:
		mat.set_shader_parameter("track_strength", tracks)
	return mat


func _build_track() -> void:
	var steps: int = int(ceil(_spline.total_length / ROAD_STEP))

	# Dirt road ribbon. V is arc length / 5 m so the texture tiles along it.
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var road_faces := PackedVector3Array()
	for i in steps + 1:
		var s: float = float(i) / float(steps) * _spline.total_length
		var frame: Dictionary = _spline.sample(s)
		var centre: Vector3 = frame["position"]
		var right: Vector3 = frame["right"]
		var lift := Vector3.UP * ROAD_Y
		verts.append(centre - right * ROAD_HALF + lift)
		verts.append(centre + right * ROAD_HALF + lift)
		norms.append(Vector3.UP)
		norms.append(Vector3.UP)
		var v: float = s / 5.0
		uvs.append(Vector2(0.0, v))
		uvs.append(Vector2(1.0, v))
	for i in steps:
		var a: int = i * 2
		# Front faces must point up: with cull_disabled a reversed winding makes
		# Godot flip the normal for the back face and the whole road goes dark.
		indices.append(a)
		indices.append(a + 2)
		indices.append(a + 1)
		indices.append(a + 1)
		indices.append(a + 2)
		indices.append(a + 3)
		# The same triangles double as the road's physical surface so the wheels
		# rest on the visible dirt (not 4 cm lower on the ground box) and the
		# skid-mark raycasts land on the road instead of under it.
		road_faces.append_array([
			verts[a], verts[a + 2], verts[a + 1],
			verts[a + 1], verts[a + 2], verts[a + 3],
		])

	var road := ArrayMesh.new()
	road.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
		_make_arrays(verts, norms, uvs, PackedColorArray(), indices))
	var road_mesh := MeshInstance3D.new()
	road_mesh.name = "DirtTrack"
	road_mesh.mesh = road
	road_mesh.material_override = _pbr_material(
		"dirt_diff", "dirt_nor", "dirt_rough", 1.0,
		Color(0.84, 0.80, 0.68), 0.13, 0.025, 0.16)
	add_child(road_mesh)

	# Physical road surface: the kart drives on the dirt it sees. Without this
	# body the wheels rest on the ground box 4 cm lower and every skid mark is
	# painted underneath the road texture where nobody can see it.
	var road_body := StaticBody3D.new()
	road_body.name = "RoadCollision"
	road_body.collision_layer = 1
	road_body.collision_mask = 0
	var road_shape := ConcavePolygonShape3D.new()
	road_shape.set_faces(road_faces)
	var road_collision := CollisionShape3D.new()
	road_collision.shape = road_shape
	road_body.add_child(road_collision)
	add_child(road_body)

	# Alternating red/white curbs, baked as vertex colours (one draw call).
	var curb_verts := PackedVector3Array()
	var curb_norms := PackedVector3Array()
	var curb_colors := PackedColorArray()
	var red := UiPalette.RED
	var white := Color("fff6e3")
	for i in steps:
		var s0: float = float(i) / float(steps) * _spline.total_length
		var s1: float = float(i + 1) / float(steps) * _spline.total_length
		var f0: Dictionary = _spline.sample(s0)
		var f1: Dictionary = _spline.sample(s1)
		var shade: Color = red if int(s0 / 3.0) % 2 == 0 else white
		for side in [-1.0, 1.0]:
			var inner0: Vector3 = f0["position"] + f0["right"] * (ROAD_HALF * side) + Vector3.UP * (ROAD_Y + 0.008)
			var outer0: Vector3 = f0["position"] + f0["right"] * ((ROAD_HALF + CURB_WIDTH) * side) + Vector3.UP * (ROAD_Y + 0.008)
			var inner1: Vector3 = f1["position"] + f1["right"] * (ROAD_HALF * side) + Vector3.UP * (ROAD_Y + 0.008)
			var outer1: Vector3 = f1["position"] + f1["right"] * ((ROAD_HALF + CURB_WIDTH) * side) + Vector3.UP * (ROAD_Y + 0.008)
			_append_quad(curb_verts, curb_norms, curb_colors,
				inner0, outer0, outer1, inner1, shade)

	var curbs := ArrayMesh.new()
	curbs.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
		_make_arrays(curb_verts, curb_norms, PackedVector2Array(), curb_colors, PackedInt32Array()))
	var curb_mesh := MeshInstance3D.new()
	curb_mesh.name = "CandyCurbs"
	curb_mesh.mesh = curbs
	var curb_mat := StandardMaterial3D.new()
	curb_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	curb_mat.vertex_color_use_as_albedo = true
	curb_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	curb_mesh.material_override = curb_mat
	add_child(curb_mesh)


func _make_arrays(verts: PackedVector3Array, norms: PackedVector3Array,
		uvs: PackedVector2Array, colors: PackedColorArray,
		indices: PackedInt32Array) -> Array:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	if not uvs.is_empty():
		arrays[Mesh.ARRAY_TEX_UV] = uvs
	if not colors.is_empty():
		arrays[Mesh.ARRAY_COLOR] = colors
	if not indices.is_empty():
		arrays[Mesh.ARRAY_INDEX] = indices
	return arrays


func _append_quad(verts: PackedVector3Array, norms: PackedVector3Array,
		colors: PackedColorArray, a: Vector3, b: Vector3, c: Vector3,
		d: Vector3, color: Color) -> void:
	for vertex: Vector3 in [a, b, c, a, c, d]:
		verts.append(vertex)
		norms.append(Vector3.UP)
		colors.append(color)


func _build_barriers() -> void:
	# An invisible trimesh wall just outside each curb keeps the kart on the
	# winding ribbon. One static body for the whole loop.
	var steps: int = int(ceil(_spline.total_length / (ROAD_STEP * 2.0)))
	var faces := PackedVector3Array()
	for i in steps:
		var s0: float = float(i) / float(steps) * _spline.total_length
		var s1: float = float(i + 1) / float(steps) * _spline.total_length
		var f0: Dictionary = _spline.sample(s0)
		var f1: Dictionary = _spline.sample(s1)
		for side in [-1.0, 1.0]:
			var offset: float = (ROAD_HALF + BARRIER_OFFSET) * side
			var a: Vector3 = f0["position"] + f0["right"] * offset
			var b: Vector3 = f1["position"] + f1["right"] * offset
			var a_top: Vector3 = a + Vector3.UP * BARRIER_HEIGHT
			var b_top: Vector3 = b + Vector3.UP * BARRIER_HEIGHT
			faces.append(a)
			faces.append(a_top)
			faces.append(b)
			faces.append(b)
			faces.append(a_top)
			faces.append(b_top)
	var shape := ConcavePolygonShape3D.new()
	shape.set_faces(faces)
	shape.backface_collision = true
	var body := StaticBody3D.new()
	body.name = "TrackBarriers"
	var collision := CollisionShape3D.new()
	collision.shape = shape
	body.add_child(collision)
	add_child(body)


func _build_start_line() -> void:
	var f: Dictionary = _spline.sample(0.0)
	var p: Vector3 = f["position"]
	var r: Vector3 = f["right"]
	var fw: Vector3 = f["forward"]
	var lift := Vector3.UP * (ROAD_Y + 0.02)
	var a := p - r * ROAD_HALF - fw * 0.9 + lift
	var b := p + r * ROAD_HALF - fw * 0.9 + lift
	var c := p + r * ROAD_HALF + fw * 0.9 + lift
	var d := p - r * ROAD_HALF + fw * 0.9 + lift
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	for v: Vector3 in [a, b, c, a, c, d]:
		verts.append(v)
		norms.append(Vector3.UP)
	for uv: Vector2 in [Vector2(0, 0), Vector2(1, 0), Vector2(1, 1),
			Vector2(0, 0), Vector2(1, 1), Vector2(0, 1)]:
		uvs.append(uv)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
		_make_arrays(verts, norms, uvs, PackedColorArray(), PackedInt32Array()))
	var line := MeshInstance3D.new()
	line.name = "StartFinishLine"
	line.mesh = mesh
	var mat := ShaderMaterial.new()
	mat.shader = load(CHECKER_SHADER) as Shader
	mat.set_shader_parameter("cells", Vector2(14.0, 2.0))
	line.material_override = mat
	add_child(line)


func _build_gates() -> void:
	_build_gate(0.0, "START / FINISH", UiPalette.YELLOW, true)
	var quarter: float = _spline.total_length / 4.0
	_build_gate(quarter, "SECTOR 1", UiPalette.CYAN, false)
	_build_gate(quarter * 2.0, "SECTOR 2", UiPalette.PINK, false)
	_build_gate(quarter * 3.0, "SECTOR 3", UiPalette.BLUE, false)


func _build_gate(distance: float, caption: String, color: Color, finish: bool) -> void:
	var gate := Node3D.new()
	gate.name = "Gate_" + caption.replace(" ", "_").replace("/", "-")
	gate.transform = _track_transform(distance, 0.0, 0.0)
	add_child(gate)

	var post_height: float = 5.2
	var span: float = ROAD_HALF + 1.1
	var post_mat := StandardMaterial3D.new()
	post_mat.albedo_color = UiPalette.OUTLINE
	post_mat.roughness = 1.0
	post_mat.next_pass = _outline_material(0.05)
	var beam_mat := StandardMaterial3D.new()
	beam_mat.albedo_color = Color(0.15, 0.18, 0.22)
	beam_mat.roughness = 0.82
	beam_mat.next_pass = _outline_material(0.035)

	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.55, post_height, 0.55)
		post.mesh = box
		post.position = Vector3(side * span, post_height * 0.5, 0.0)
		post.material_override = post_mat
		gate.add_child(post)

	var beam := MeshInstance3D.new()
	var beam_box := BoxMesh.new()
	beam_box.size = Vector3(span * 2.0 + 0.55, 0.95, 0.6)
	beam.mesh = beam_box
	beam.position = Vector3(0.0, post_height, 0.0)
	beam.material_override = beam_mat
	gate.add_child(beam)
	_gate_beams.append(beam)
	var accent := MeshInstance3D.new()
	var accent_box := BoxMesh.new()
	accent_box.size = Vector3(span * 2.0 + 0.58, 0.16, 0.64)
	accent.mesh = accent_box
	accent.position = Vector3(0.0, post_height + 0.27, 0.0)
	var accent_mat := StandardMaterial3D.new()
	accent_mat.albedo_color = color
	accent_mat.roughness = 0.8
	accent.material_override = accent_mat
	gate.add_child(accent)

	if finish:
		# Checkered strip across the front of the finish beam.
		var strip := MeshInstance3D.new()
		var strip_box := BoxMesh.new()
		strip_box.size = Vector3(span * 2.0 + 0.55, 0.36, 0.66)
		strip.mesh = strip_box
		strip.position = Vector3(0.0, post_height - 0.6, 0.0)
		var checker := ShaderMaterial.new()
		checker.shader = load(CHECKER_SHADER) as Shader
		checker.set_shader_parameter("cells", Vector2(20.0, 1.0))
		strip.material_override = checker
		gate.add_child(strip)

	if finish:
		# Sector gates are read from their colour and flash; three floating
		# SECTOR labels were visual noise in the chase camera.
		var label := Label3D.new()
		label.text = caption
		label.font = load(TITLE_FONT)
		label.font_size = 64
		label.pixel_size = 0.017
		label.outline_size = 18
		label.outline_modulate = UiPalette.OUTLINE
		label.modulate = color
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position = Vector3(0.0, post_height + 1.0, 0.0)
		gate.add_child(label)


func _outline_material(thickness: float) -> ShaderMaterial:
	var outline := ShaderMaterial.new()
	outline.shader = OUTLINE_SHADER
	outline.set_shader_parameter("thickness", thickness)
	return outline


func _build_start_lights() -> void:
	# One clean row of five lamps: one lamp per countdown beat, all five green
	# on GO. The old 2x5 F1 grid read as two confusing rows in a cartoon game.
	var distance: float = START_DISTANCE + 12.0
	var rig := Node3D.new()
	rig.name = "StartLights"
	rig.transform = _track_transform(distance, 0.0, 0.0)
	add_child(rig)
	for side in [-1.0, 1.0]:
		var post := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(0.28, 5.8, 0.28)
		post.mesh = box
		post.position = Vector3(side * (ROAD_HALF + 0.8), 2.9, 0.0)
		var dark := StandardMaterial3D.new()
		dark.albedo_color = UiPalette.OUTLINE
		post.material_override = dark
		rig.add_child(post)
	var bar := MeshInstance3D.new()
	var bar_box := BoxMesh.new()
	bar_box.size = Vector3(ROAD_HALF * 2.0 + 1.9, 1.05, 0.3)
	bar.mesh = bar_box
	bar.position = Vector3(0.0, 5.48, 0.0)
	var bar_mat := StandardMaterial3D.new()
	bar_mat.albedo_color = Color(0.16, 0.18, 0.29, 1)
	bar.material_override = bar_mat
	rig.add_child(bar)
	for column in 5:
		var lamp := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.30
		sphere.height = 0.60
		lamp.mesh = sphere
		# +Z faces the approaching grid; the lamps sit on the near side of the
		# beam so the whole rig does not read as a blank black bar.
		lamp.position = Vector3((float(column) - 2.0) * 0.72, 5.48, 0.26)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.16, 0.14, 0.22, 1)
		mat.emission_enabled = true
		mat.emission = Color(0.35, 0.06, 0.08, 1)
		mat.emission_energy_multiplier = 0.35
		lamp.material_override = mat
		rig.add_child(lamp)
		_start_lights.append(lamp)


func _set_start_lights(red_count: int, green: bool) -> void:
	for i in _start_lights.size():
		var mat: StandardMaterial3D = _start_lights[i].material_override as StandardMaterial3D
		if mat == null:
			continue
		var lit: bool = green or i < red_count
		mat.emission = Color(0.15, 0.95, 0.32, 1) if green \
			else (Color(1.0, 0.14, 0.16, 1) if lit else Color(0.35, 0.06, 0.08, 1))
		mat.emission_energy_multiplier = 3.2 if lit else 0.25
		mat.albedo_color = Color(0.1, 0.35, 0.14, 1) if green \
			else (Color(0.5, 0.1, 0.1, 1) if lit else Color(0.16, 0.14, 0.22, 1))


func _build_start_festival() -> void:
	## The start is the identity shot: bunting, a hay-bale grandstand, a parked
	## tractor and a giant checkered flag. Everything sits outside the barriers,
	## so it is pure scenery and costs no lap collision.
	var root := Node3D.new()
	root.name = "StartFestival"
	root.transform = _track_transform(START_DISTANCE, 0.0, 0.0)
	add_child(root)

	var bunting := MeshInstance3D.new()
	bunting.name = "Bunting"
	bunting.mesh = _bunting_mesh(ROAD_HALF * 2.0 + 1.4, 18)
	var bunting_mat := StandardMaterial3D.new()
	bunting_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	bunting_mat.vertex_color_use_as_albedo = true
	bunting_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	bunting.material_override = bunting_mat
	bunting.position = Vector3(0.0, 5.1, 0.0)
	root.add_child(bunting)

	# Hay-bale grandstand, three stepped rows facing the grid.
	var hay_mat := StandardMaterial3D.new()
	hay_mat.albedo_color = Color(0.72, 0.57, 0.28)
	hay_mat.roughness = 0.95
	var hay_mesh := BoxMesh.new()
	hay_mesh.size = Vector3(1.25, 0.78, 1.7)
	var hay := MultiMesh.new()
	hay.transform_format = MultiMesh.TRANSFORM_3D
	hay.mesh = hay_mesh
	hay.instance_count = 12
	var hay_index: int = 0
	for row in 3:
		for col in 4:
			hay.set_instance_transform(hay_index, Transform3D(Basis.IDENTITY,
				Vector3(8.1 + float(row) * 1.32, 0.40 + float(row) * 0.80,
					-3.2 + float(col) * 1.76)))
			hay_index += 1
	var hay_instances := MultiMeshInstance3D.new()
	hay_instances.name = "HayGrandstand"
	hay_instances.multimesh = hay
	hay_instances.material_override = hay_mat
	root.add_child(hay_instances)

	# A real Kenney tractor grounds the farm theme without a custom model.
	var tractor_scene: PackedScene = load(
		"res://assets/models/kenney_car-kit/Models/GLB format/tractor.glb") as PackedScene
	if tractor_scene != null:
		var tractor: Node3D = tractor_scene.instantiate() as Node3D
		tractor.name = "ParkedTractor"
		tractor.position = Vector3(-9.6, 0.0, 3.4)
		tractor.rotation.y = 0.85
		tractor.scale = Vector3.ONE * 1.05
		root.add_child(tractor)

	# Giant checkered flag on the inside of the first corner.
	var pole := MeshInstance3D.new()
	var pole_mesh := CylinderMesh.new()
	pole_mesh.top_radius = 0.07
	pole_mesh.bottom_radius = 0.09
	pole_mesh.height = 6.4
	pole_mesh.radial_segments = 10
	pole.mesh = pole_mesh
	pole.position = Vector3(-8.6, 3.2, -2.6)
	var pole_mat := StandardMaterial3D.new()
	pole_mat.albedo_color = Color(0.86, 0.84, 0.78)
	pole.material_override = pole_mat
	root.add_child(pole)
	var flag := MeshInstance3D.new()
	var flag_mesh := QuadMesh.new()
	flag_mesh.size = Vector2(2.7, 1.65)
	flag.mesh = flag_mesh
	flag.position = Vector3(-7.25, 5.45, -2.6)
	flag.rotation.y = 0.18
	var flag_mat := ShaderMaterial.new()
	flag_mat.shader = load(CHECKER_SHADER) as Shader
	flag_mat.set_shader_parameter("cells", Vector2(8.0, 4.0))
	flag.material_override = flag_mat
	root.add_child(flag)


func _bunting_mesh(width: float, count: int) -> ArrayMesh:
	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var palette: Array[Color] = [UiPalette.YELLOW, UiPalette.CYAN,
		UiPalette.PINK, UiPalette.GRASS, UiPalette.CREAM]
	var span: float = width / float(count)
	for i in count:
		var x0: float = -width * 0.5 + span * float(i)
		var x1: float = x0 + span * 0.82
		var mid: float = (x0 + x1) * 0.5
		var sag: float = 0.42 * sin(PI * (float(i) + 0.5) / float(count))
		var base: int = verts.size()
		verts.append(Vector3(x0, 0.0, 0.0))
		verts.append(Vector3(x1, 0.0, 0.0))
		verts.append(Vector3(mid, -0.58 - sag, 0.0))
		for n in 3:
			normals.append(Vector3(0.0, 0.0, 1.0))
		var color: Color = palette[i % palette.size()]
		colors.append(color)
		colors.append(color)
		colors.append(color)
		indices.append(base)
		indices.append(base + 1)
		indices.append(base + 2)
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _build_boost_pads() -> void:
	var packed: PackedScene = load(BOOST_PAD_SCENE) as PackedScene
	if packed == null:
		return
	var holder := Node3D.new()
	holder.name = "BoostPads"
	add_child(holder)
	for i in 4:
		var distance: float = _spline.total_length * (0.13 + float(i) * 0.245)
		var lateral: float = [-2.4, 2.4, 0.0, -1.6][i]
		var pad: Node3D = packed.instantiate() as Node3D
		# The road surface is at y = 0.04; a pad at 0.03 was completely hidden
		# under the dirt. Sit it just above the surface so the glow reads.
		pad.transform = _track_transform(distance, lateral, 0.075)
		holder.add_child(pad)


func _build_ramps() -> void:
	# Two dirt kickers on the racing line. The collision is a convex wedge, so
	# the normal physics loop handles the launch; rivals get a matching lift in
	# _place_rival.
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.58, 0.38, 0.20)
	mat.roughness = 0.92
	mat.metallic = 0.0
	# The hand-built wedge winding faces down on some drivers; keep both faces
	# visible so the ramp never looks like an invisible floor.
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	var lip_mat := StandardMaterial3D.new()
	lip_mat.albedo_color = Color(0.96, 0.88, 0.67)
	lip_mat.roughness = 0.85
	lip_mat.emission_enabled = true
	lip_mat.emission = Color(0.55, 0.42, 0.18)
	lip_mat.emission_energy_multiplier = 0.25
	for fraction: float in RAMP_FRACTIONS:
		var distance: float = _spline.total_length * fraction
		_ramp_distances.append(distance)
		var body := StaticBody3D.new()
		body.name = "Ramp_%d" % int(fraction * 100.0)
		body.transform = _track_transform(distance, 0.0, 0.045)
		body.collision_layer = 1
		body.collision_mask = 0
		add_child(body)

		var half_w: float = RAMP_WIDTH * 0.5
		var half_l: float = RAMP_LENGTH * 0.5
		var verts := PackedVector3Array()
		var norms := PackedVector3Array()
		var uvs := PackedVector2Array()
		_add_tri(verts, norms, uvs,
			Vector3(-half_w, 0.0, half_l), Vector3(half_w, 0.0, half_l),
			Vector3(half_w, RAMP_HEIGHT, -half_l), Vector3.UP)
		_add_tri(verts, norms, uvs,
			Vector3(-half_w, 0.0, half_l), Vector3(half_w, RAMP_HEIGHT, -half_l),
			Vector3(-half_w, RAMP_HEIGHT, -half_l), Vector3.UP)
		_add_tri(verts, norms, uvs,
			Vector3(-half_w, 0.0, half_l), Vector3(-half_w, RAMP_HEIGHT, -half_l),
			Vector3(-half_w, 0.0, -half_l), Vector3.LEFT)
		_add_tri(verts, norms, uvs,
			Vector3(half_w, 0.0, half_l), Vector3(half_w, 0.0, -half_l),
			Vector3(half_w, RAMP_HEIGHT, -half_l), Vector3.RIGHT)
		_add_tri(verts, norms, uvs,
			Vector3(-half_w, RAMP_HEIGHT, -half_l), Vector3(half_w, RAMP_HEIGHT, -half_l),
			Vector3(half_w, 0.0, -half_l), Vector3.BACK)
		_add_tri(verts, norms, uvs,
			Vector3(-half_w, RAMP_HEIGHT, -half_l), Vector3(half_w, 0.0, -half_l),
			Vector3(-half_w, 0.0, -half_l), Vector3.BACK)

		var mesh := ArrayMesh.new()
		mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
			_make_arrays(verts, norms, uvs, PackedColorArray(), PackedInt32Array()))
		var visual := MeshInstance3D.new()
		visual.mesh = mesh
		visual.material_override = mat
		body.add_child(visual)

		# A pale lip at the crest makes the kicker readable from a distance.
		var lip := MeshInstance3D.new()
		var lip_mesh := BoxMesh.new()
		lip_mesh.size = Vector3(RAMP_WIDTH + 0.1, 0.16, 0.55)
		lip.mesh = lip_mesh
		lip.material_override = lip_mat
		lip.position = Vector3(0.0, RAMP_HEIGHT + 0.02, -half_l + 0.32)
		body.add_child(lip)

		# Bright side rails make the kicker read as a ramp at speed.
		var rail_mat := StandardMaterial3D.new()
		rail_mat.albedo_color = Color(0.96, 0.82, 0.50)
		rail_mat.roughness = 0.8
		rail_mat.emission_enabled = true
		rail_mat.emission = Color(0.45, 0.30, 0.10)
		rail_mat.emission_energy_multiplier = 0.2
		var slope_length: float = sqrt(RAMP_LENGTH * RAMP_LENGTH
			+ RAMP_HEIGHT * RAMP_HEIGHT)
		var slope_angle: float = atan2(RAMP_HEIGHT, RAMP_LENGTH)

		# A thin solid top slab guarantees a visible driving surface.
		var top := MeshInstance3D.new()
		var top_mesh := BoxMesh.new()
		top_mesh.size = Vector3(RAMP_WIDTH, 0.07, slope_length)
		top.mesh = top_mesh
		top.material_override = mat
		top.position = Vector3(0.0, RAMP_HEIGHT * 0.5 + 0.035, 0.0)
		top.rotation.x = slope_angle
		body.add_child(top)
		for side: float in [-1.0, 1.0]:
			var rail := MeshInstance3D.new()
			var rail_mesh := BoxMesh.new()
			rail_mesh.size = Vector3(0.18, 0.12, slope_length)
			rail.mesh = rail_mesh
			rail.material_override = rail_mat
			rail.position = Vector3(side * (half_w + 0.06), RAMP_HEIGHT * 0.5 + 0.07, 0.0)
			rail.rotation.x = slope_angle
			body.add_child(rail)

		var shape := ConvexPolygonShape3D.new()
		shape.points = PackedVector3Array([
			Vector3(-half_w, 0.0, half_l), Vector3(half_w, 0.0, half_l),
			Vector3(-half_w, RAMP_HEIGHT, -half_l), Vector3(half_w, RAMP_HEIGHT, -half_l),
			Vector3(-half_w, 0.0, -half_l), Vector3(half_w, 0.0, -half_l),
		])
		var collision := CollisionShape3D.new()
		collision.shape = shape
		body.add_child(collision)


func _add_tri(verts: PackedVector3Array, norms: PackedVector3Array,
		uvs: PackedVector2Array, a: Vector3, b: Vector3, c: Vector3,
		_normal_dir: Vector3) -> void:
	var normal: Vector3 = (b - a).cross(c - a).normalized()
	for vertex: Vector3 in [a, b, c]:
		verts.append(vertex)
		norms.append(normal)
	uvs.append(Vector2(0, 0))
	uvs.append(Vector2(1, 0))
	uvs.append(Vector2(0.5, 1))


func _ramp_lift_at(progress: float) -> float:
	var wrapped: float = fposmod(progress, _spline.total_length)
	for distance: float in _ramp_distances:
		var start: float = distance - RAMP_LENGTH * 0.5
		var end: float = distance + RAMP_LENGTH * 0.5
		if wrapped >= start and wrapped <= end:
			return RAMP_HEIGHT * ((wrapped - start) / maxf(RAMP_LENGTH, 0.001))
	return 0.0


func _build_trackside_props() -> void:
	# Designed obstacles instead of random clutter: two cone chicanes and a
	# narrow gate sit on the straights, with a light scatter of cones near the
	# edges for chaos. Cones are pushable so they fly when clipped rather than
	# stopping the kart dead.
	var cone: PackedScene = load(CONE_MODEL) as PackedScene
	if cone == null:
		return
	var holder := Node3D.new()
	holder.name = "TrackCones"
	add_child(holder)
	var length: float = _spline.total_length
	# Slalom chicanes: alternating cones force a weave down the straight.
	_chicane(holder, cone, length * 0.515, 4, 6.0, 1.9)
	_chicane(holder, cone, length * 0.135, 3, 6.5, 1.8)
	# A tight gate: thread it or smash through.
	var gate_d: float = length * 0.635
	for row in 3:
		for side: float in [-1.0, 1.0]:
			_spawn_cone(holder, cone, gate_d + float(row) * 3.0, side * 2.0, 0.8)
	# A few loose cones near the verges, never on the ideal line.
	var rng := RandomNumberGenerator.new()
	rng.seed = 5511
	for i in 8:
		var distance: float = length * rng.randf()
		if absf(fposmod(distance - START_DISTANCE, length)) < 26.0:
			continue
		var side: float = 1.0 if rng.randf() < 0.5 else -1.0
		_spawn_cone(holder, cone, distance, side * rng.randf_range(3.6, 4.6), 0.72)


func _chicane(holder: Node3D, cone: PackedScene, center: float, count: int,
		spacing: float, lateral: float) -> void:
	var start: float = center - float(count - 1) * spacing * 0.5
	for i in count:
		var side: float = 1.0 if i % 2 == 0 else -1.0
		_spawn_cone(holder, cone, start + float(i) * spacing, side * lateral, 0.8)


func _spawn_cone(holder: Node3D, cone: PackedScene, distance: float,
		lateral: float, scale: float) -> void:
	var body := RigidBody3D.new()
	# Explicit names keep the prop index identical on every peer, so a push
	# request and a snapshot always address the same cone.
	body.name = "TrackProp%03d" % _prop_serial
	_prop_serial += 1
	body.add_to_group("pushable")
	body.collision_layer = 4
	body.collision_mask = 5
	body.mass = 0.4
	body.transform = _track_transform(distance, lateral, 0.06)
	var model: Node3D = cone.instantiate() as Node3D
	model.scale = Vector3.ONE * scale
	body.add_child(model)
	var shape := BoxShape3D.new()
	shape.size = Vector3(0.45, 0.62, 0.45)
	var collision := CollisionShape3D.new()
	collision.shape = shape
	collision.position = Vector3(0, 0.31, 0)
	body.add_child(collision)
	holder.add_child(body)


func _build_verge_details() -> void:
	## Low-cost colour and clutter between the track and the forest: flowers,
	## mushrooms, rocks and fallen logs. One MultiMesh per model, no shadows.
	var rng := RandomNumberGenerator.new()
	rng.seed = 8123
	var holder := Node3D.new()
	holder.name = "VergeDetails"
	add_child(holder)
	var material: Material = FoliageBaker.make_material()
	var specs: Array[Dictionary] = [
		{"model": "flower_redA", "count": 180, "scale": 0.55},
		{"model": "flower_purpleA", "count": 180, "scale": 0.55},
		{"model": "flower_yellowA", "count": 180, "scale": 0.55},
		{"model": "flower_redB", "count": 120, "scale": 0.50},
		{"model": "mushroom_redGroup", "count": 70, "scale": 0.75},
		{"model": "mushroom_tan", "count": 50, "scale": 0.65},
		{"model": "rock_largeA", "count": 26, "scale": 1.15},
		{"model": "rock_largeB", "count": 26, "scale": 1.15},
		{"model": "log", "count": 20, "scale": 1.0},
	]
	for spec: Dictionary in specs:
		var mesh: ArrayMesh = FoliageBaker.bake(str(spec["model"]))
		if mesh == null:
			continue
		var transforms: Array = []
		for i in int(spec["count"]):
			var distance: float = rng.randf() * _spline.total_length
			var side: float = 1.0 if rng.randf() < 0.5 else -1.0
			var lateral: float = side * rng.randf_range(7.5, 34.0)
			var position: Vector3 = _track_transform(distance, lateral, 0.02).origin
			if _near_track(position, 7.0):
				continue
			var scale: float = float(spec["scale"]) * rng.randf_range(0.8, 1.25)
			var basis: Basis = Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * scale)
			transforms.append(Transform3D(basis, position))
		if transforms.is_empty():
			continue
		holder.add_child(FoliageBaker.create_chunked_instances(
			mesh, material, transforms, false, 80.0, [], 96.0))


func _tight_corners(max_count: int) -> Array[Dictionary]:
	## The tightest bends, spaced apart, each tagged with which side is outside.
	var candidates: Array[Dictionary] = []
	var step: float = 8.0
	var d: float = 20.0
	while d < _spline.total_length - 20.0:
		var before: float = _spline.yaw_at(d - 7.0)
		var after: float = _spline.yaw_at(d + 7.0)
		var curve: float = angle_difference(before, after)
		if absf(curve) > 0.14:
			candidates.append({"d": d, "curve": curve})
		d += step
	candidates.sort_custom(func(a: Dictionary, b: Dictionary) -> bool:
		return absf(float(a["curve"])) > absf(float(b["curve"])))
	var chosen: Array[Dictionary] = []
	for candidate: Dictionary in candidates:
		var ok: bool = true
		for other: Dictionary in chosen:
			if absf(fposmod(float(candidate["d"]) - float(other["d"]),
					_spline.total_length)) < 55.0:
				ok = false
				break
		if ok:
			candidate["outside"] = 1.0 if float(candidate["curve"]) > 0.0 else -1.0
			chosen.append(candidate)
		if chosen.size() >= max_count:
			break
	return chosen


func _build_corner_furniture() -> void:
	## Chevron boards and tire stacks at the six tightest corners. These are
	## the visual language of a race track and cost only a handful of meshes.
	var chosen: Array[Dictionary] = _tight_corners(6)
	if chosen.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "CornerFurniture"
	add_child(holder)
	var board_mat := StandardMaterial3D.new()
	board_mat.albedo_color = UiPalette.YELLOW
	board_mat.roughness = 0.9
	var stripe_mat := StandardMaterial3D.new()
	stripe_mat.albedo_color = UiPalette.OUTLINE
	var tire_mat := StandardMaterial3D.new()
	tire_mat.albedo_color = Color(0.09, 0.08, 0.10)
	tire_mat.roughness = 1.0
	var tire_xf: Array = []
	var tire_cylinder := CylinderMesh.new()
	tire_cylinder.top_radius = 0.44
	tire_cylinder.bottom_radius = 0.44
	tire_cylinder.height = 0.26
	var stripe_xf: Array = []
	var post_xf: Array = []
	var pole_xf: Array = []
	var stripe_box := BoxMesh.new()
	stripe_box.size = Vector3(0.34, 0.85, 0.02)
	var post_box := BoxMesh.new()
	post_box.size = Vector3(0.12, 1.1, 0.12)
	var pole_cylinder := CylinderMesh.new()
	pole_cylinder.top_radius = 0.05
	pole_cylinder.bottom_radius = 0.05
	pole_cylinder.height = 3.6
	for candidate: Dictionary in chosen:
		var distance: float = float(candidate["d"])
		var outside: float = 1.0 if float(candidate["curve"]) > 0.0 else -1.0
		var root := Node3D.new()
		root.transform = _track_transform(distance, outside * (ROAD_HALF + 2.2), 0.0)
		root.rotation.y += PI
		holder.add_child(root)
		var board := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(3.1, 0.85, 0.14)
		board.mesh = box
		board.position = Vector3(0.0, 1.15, 0.0)
		board.material_override = board_mat
		root.add_child(board)
		for stripe in 3:
			stripe_xf.append(root.transform * Transform3D(
				Basis.from_euler(Vector3(0.0, 0.0, deg_to_rad(28.0))),
				Vector3(-0.85 + float(stripe) * 0.85, 1.15, 0.08)))
		for post_side in [-1.0, 1.0]:
			post_xf.append(root.transform * Transform3D(Basis.IDENTITY,
				Vector3(post_side * 1.25, 0.55, 0.0)))
		# A tall pennant makes the corner readable from a distance.
		pole_xf.append(root.transform * Transform3D(Basis.IDENTITY,
			Vector3(0.0, 1.8, -0.2)))
		var flag := MeshInstance3D.new()
		var flag_mesh := BoxMesh.new()
		flag_mesh.size = Vector3(0.9, 0.55, 0.03)
		flag.mesh = flag_mesh
		flag.position = Vector3(0.45, 3.35, -0.2)
		var flag_mat := StandardMaterial3D.new()
		flag_mat.albedo_color = BOT_COLORS[chosen.find(candidate) % BOT_COLORS.size()]
		flag.material_override = flag_mat
		root.add_child(flag)
		for stack in 3:
			var stack_transform: Transform3D = _track_transform(
				distance - 2.0 + float(stack) * 2.0,
				outside * (ROAD_HALF + 4.0), 0.0)
			for tire in 3:
				tire_xf.append(stack_transform * Transform3D(Basis.IDENTITY,
					Vector3(0.0, 0.13 + float(tire) * 0.26, 0.0)))
	holder.add_child(_multimesh_instances(tire_cylinder, tire_mat, tire_xf,
		"CornerTireStacks"))
	holder.add_child(_multimesh_instances(stripe_box, stripe_mat, stripe_xf,
		"CornerChevrons"))
	holder.add_child(_multimesh_instances(post_box, stripe_mat, post_xf,
		"CornerPosts"))
	holder.add_child(_multimesh_instances(pole_cylinder, stripe_mat, pole_xf,
		"CornerPennants"))


func _build_corner_hazards() -> void:
	## Real penalties at the three tightest corners: a hay-bale wall on the
	## outside exit catches anyone running wide, and a solid tire stack marks
	## the apex on the inside. Both sit at the road edge so the centreline the
	## bots follow stays clear.
	var chosen: Array[Dictionary] = _tight_corners(3)
	if chosen.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "CornerHazards"
	add_child(holder)
	var straw := StandardMaterial3D.new()
	straw.albedo_color = Color(0.85, 0.68, 0.34)
	straw.roughness = 1.0
	var strap := StandardMaterial3D.new()
	strap.albedo_color = Color(0.45, 0.34, 0.18)
	strap.roughness = 1.0
	var tire_mat := StandardMaterial3D.new()
	tire_mat.albedo_color = Color(0.10, 0.09, 0.11)
	tire_mat.roughness = 1.0
	var bale_xf: Array = []
	var band_xf: Array = []
	var apex_xf: Array = []
	var bale_size := Vector3(0.7, 0.9, 1.8)
	var bale_box := BoxMesh.new()
	bale_box.size = bale_size
	var band_box := BoxMesh.new()
	band_box.size = Vector3(0.74, 0.92, 0.12)
	var tire_cylinder := CylinderMesh.new()
	tire_cylinder.top_radius = 0.5
	tire_cylinder.bottom_radius = 0.5
	tire_cylinder.height = 0.28
	for candidate: Dictionary in chosen:
		var distance: float = float(candidate["d"])
		var outside: float = float(candidate["outside"])
		# Hay wall along the outside exit.
		for bale in 7:
			var d: float = distance + 1.0 + float(bale) * 2.0
			var body := StaticBody3D.new()
			body.collision_layer = 1
			body.collision_mask = 0
			body.transform = _track_transform(d, outside * (ROAD_HALF - 0.3), 0.0)
			holder.add_child(body)
			bale_xf.append(body.transform * Transform3D(Basis.IDENTITY,
				Vector3(0.0, 0.45, 0.0)))
			for strap_z in [-0.5, 0.5]:
				band_xf.append(body.transform * Transform3D(Basis.IDENTITY,
					Vector3(0.0, 0.45, strap_z)))
			var shape := BoxShape3D.new()
			shape.size = bale_size
			var collision := CollisionShape3D.new()
			collision.shape = shape
			collision.position = Vector3(0.0, 0.45, 0.0)
			body.add_child(collision)
		# Solid apex tire stack on the inside.
		var apex := StaticBody3D.new()
		apex.collision_layer = 1
		apex.collision_mask = 0
		apex.transform = _track_transform(distance, -outside * (ROAD_HALF - 1.2), 0.0)
		holder.add_child(apex)
		for tire in 3:
			apex_xf.append(apex.transform * Transform3D(Basis.IDENTITY,
				Vector3(0.0, 0.14 + float(tire) * 0.28, 0.0)))
		var apex_shape := CylinderShape3D.new()
		apex_shape.radius = 0.5
		apex_shape.height = 0.84
		var apex_collision := CollisionShape3D.new()
		apex_collision.shape = apex_shape
		apex_collision.position = Vector3(0.0, 0.42, 0.0)
		apex.add_child(apex_collision)
	holder.add_child(_multimesh_instances(bale_box, straw, bale_xf, "HayBales"))
	holder.add_child(_multimesh_instances(band_box, strap, band_xf, "HayStraps"))
	holder.add_child(_multimesh_instances(tire_cylinder, tire_mat, apex_xf, "ApexTires"))


func _build_track_fence() -> void:
	## Low cream fence along both verges. Two MultiMeshes for the whole loop
	## (posts + rails) add structure without a draw-call per segment.
	var post_mesh := BoxMesh.new()
	post_mesh.size = Vector3(0.12, 1.0, 0.12)
	var rail_mesh := BoxMesh.new()
	rail_mesh.size = Vector3(0.10, 0.12, 4.0)
	var post_xf: Array = []
	var rail_xf: Array = []
	var step: float = 4.0
	var d: float = 0.0
	while d < _spline.total_length:
		for side in [-1.0, 1.0]:
			var lateral: float = side * (ROAD_HALF + 3.2)
			var base: Transform3D = _track_transform(d, lateral, 0.0)
			post_xf.append(Transform3D(Basis(Vector3.UP, _spline.yaw_at(d)),
				base.origin + Vector3.UP * 0.5))
			if d + step < _spline.total_length:
				var rail: Transform3D = _track_transform(d + step * 0.5, lateral, 0.0)
				for height: float in [0.38, 0.82]:
					rail_xf.append(Transform3D(Basis(Vector3.UP, _spline.yaw_at(d + step * 0.5)),
						rail.origin + Vector3.UP * height))
		d += step
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("fff6e3")
	material.roughness = 1.0
	var posts := FoliageBaker.create_instances(_box_to_array(post_mesh), material, post_xf, false)
	posts.name = "FencePosts"
	add_child(posts)
	var rails := FoliageBaker.create_instances(_box_to_array(rail_mesh), material, rail_xf, false)
	rails.name = "FenceRails"
	add_child(rails)


func _box_to_array(box: BoxMesh) -> ArrayMesh:
	var arrays: Array = box.surface_get_arrays(0)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _multimesh_instances(mesh: Mesh, material: Material,
		transforms: Array, node_name: String) -> MultiMeshInstance3D:
	## One draw call for every repeated bale, band, tire or marker. Collision
	## bodies stay separate; only the visuals are batched.
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multi
	instance.material_override = material
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


func _build_sponsor_boards() -> void:
	## Muted painted farm signs with two posts and lettering on both faces.
	var holder := Node3D.new()
	holder.name = "SponsorBoards"
	add_child(holder)
	var texts: PackedStringArray = ["SLOP", "CART SLOP GP", "MEADOW LOOP", "GO FAST"]
	var colors: Array[Color] = [
		Color("a94f42"), Color("527789"), Color("c5a44f"), Color("637e58"),
		Color("a94f42"), Color("527789"), Color("c5a44f"), Color("637e58"),
	]
	var dark := StandardMaterial3D.new()
	dark.albedo_color = Color("342f2b")
	dark.roughness = 1.0
	var post_xf: Array = []
	var post_box := BoxMesh.new()
	post_box.size = Vector3(0.16, 1.65, 0.16)
	for i in 8:
		var distance: float = _spline.total_length * (0.07 + float(i) * 0.115)
		var side: float = 1.0 if i % 2 == 0 else -1.0
		var root := Node3D.new()
		root.transform = _track_transform(distance, side * (ROAD_HALF + 5.2), 0.0)
		root.rotation.y += PI
		holder.add_child(root)
		var board := MeshInstance3D.new()
		var box := BoxMesh.new()
		box.size = Vector3(4.4, 1.35, 0.16)
		board.mesh = box
		board.position = Vector3(0.0, 1.55, 0.0)
		var mat := StandardMaterial3D.new()
		mat.albedo_color = colors[i % colors.size()]
		mat.roughness = 0.95
		board.material_override = mat
		root.add_child(board)
		for post_x: float in [-1.65, 1.65]:
			post_xf.append(root.transform * Transform3D(Basis.IDENTITY,
				Vector3(post_x, 0.82, 0.0)))
		# Only the track-facing side needs lettering; a back-face label was
		# invisible and doubled the label draw calls.
		var label := Label3D.new()
		label.text = texts[i % texts.size()]
		label.font = load(TITLE_FONT)
		label.font_size = 64
		label.pixel_size = 0.008
		label.outline_size = 8
		label.outline_modulate = Color(UiPalette.OUTLINE, 0.65)
		label.modulate = UiPalette.CREAM
		label.position = Vector3(0.0, 1.62, 0.10)
		root.add_child(label)
	holder.add_child(_multimesh_instances(post_box, dark, post_xf, "SponsorPosts"))


func _flash_gate(sector: int) -> void:
	# Sector 0 is the start gantry; sectors 1..3 are the three split gates.
	var index: int = sector % _gate_beams.size()
	if _gate_beams.is_empty():
		return
	var beam: MeshInstance3D = _gate_beams[index]
	var mat: StandardMaterial3D = beam.material_override as StandardMaterial3D
	if mat == null:
		return
	mat.emission_enabled = true
	mat.emission = Color(1, 0.95, 0.6, 1)
	mat.emission_energy_multiplier = 2.4
	var tween := create_tween()
	tween.tween_property(mat, "emission_energy_multiplier", 0.0, 0.85)


# --------------------------------------------------------------------------
# dense scenery


func _build_grid() -> void:
	for i in _spline.points.size():
		var p: Vector3 = _spline.points[i]
		var key := Vector2i(int(floor(p.x / GRID_CELL)), int(floor(p.z / GRID_CELL)))
		if not _grid.has(key):
			_grid[key] = []
		_grid[key].append(i)


func _near_track(position: Vector3, radius: float) -> bool:
	if MeadowLandmarks.is_clearing(_spline, position):
		return true
	var key := Vector2i(int(floor(position.x / GRID_CELL)),
		int(floor(position.z / GRID_CELL)))
	var radius_sq: float = radius * radius
	# Large exclusions (the far-field forest starts 34 m out) need a wider
	# neighbourhood than the usual 3x3 used for the 7-10 m track clearance.
	var reach: int = clampi(ceili(radius / GRID_CELL), 1, 4)
	for dx in range(-reach, reach + 1):
		for dz in range(-reach, reach + 1):
			var bucket: Array = _grid.get(key + Vector2i(dx, dz), [])
			for index: int in bucket:
				if position.distance_squared_to(_spline.points[index]) < radius_sq:
					return true
	return false


func _bake_cached(model_name: String) -> ArrayMesh:
	if _baked.has(model_name):
		return _baked[model_name]
	var mesh: ArrayMesh = FoliageBaker.bake(model_name)
	_baked[model_name] = mesh
	return mesh


func _candidate(rng: RandomNumberGenerator) -> Vector3:
	# Two thirds of everything is packed into the verges the camera actually
	# sees; the rest fills the wider field so the horizon is never empty.
	if rng.randf() < 0.64:
		var frame: Dictionary = _spline.sample(rng.randf() * _spline.total_length)
		var angle: float = rng.randf() * TAU
		var distance: float = rng.randf_range(9.0, 55.0)
		return frame["position"] + Vector3(cos(angle), 0.0, sin(angle)) * distance
	return Vector3(rng.randf_range(-FIELD_X, FIELD_X), 0.0,
		rng.randf_range(-FIELD_Z, FIELD_Z))


func _scatter(rng: RandomNumberGenerator, models: PackedStringArray,
		attempts: int, exclusion: float, scale_min: float, scale_max: float,
		cast_shadow: bool, group_name: String, tint_variation: bool = false) -> void:
	var buckets: Dictionary = {}
	for i in attempts:
		var position: Vector3 = _candidate(rng)
		if absf(position.x) > FIELD_X or absf(position.z) > FIELD_Z:
			continue
		if _near_track(position, exclusion):
			continue
		var model: String = models[rng.randi_range(0, models.size() - 1)]
		var scale: float = rng.randf_range(scale_min, scale_max)
		var basis: Basis = Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * scale)
		if not buckets.has(model):
			buckets[model] = {"xf": [], "col": []}
		buckets[model]["xf"].append(Transform3D(basis, position + Vector3.UP * 0.02))
		if tint_variation:
			buckets[model]["col"].append(_foliage_tint(rng))

	var holder := Node3D.new()
	holder.name = group_name
	add_child(holder)
	for model: String in buckets:
		var baked: ArrayMesh = _bake_cached(model)
		if baked == null:
			continue
		var data: Dictionary = buckets[model]
		holder.add_child(FoliageBaker.create_instances(
			baked, _foliage_material, data["xf"], cast_shadow, data["col"]))


func _foliage_tint(rng: RandomNumberGenerator) -> Color:
	# Per-instance colour keeps 2,700 trees from reading as one flat wall of
	# green: a few warm autumn crowns, some shaded ones, some sunlit.
	var roll: float = rng.randf()
	if roll < 0.09:
		return Color(1.0, 0.76, 0.44)
	if roll < 0.28:
		return Color(0.72, 0.88, 0.76)
	if roll < 0.52:
		return Color(1.0, 0.98, 0.86)
	return Color.WHITE


func _build_scenery() -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 20261105
	# No flat-shaded Kenney trees in the background: the PBR forest and the
	# grassy hill ring own the horizon now. Small ground cover stays cheap.
	_scatter(rng, BUSHES, 280, 22.0, 1.1, 2.4, false, "FarUnderbrush", true)
	_scatter(rng, GRASSES, 850, 7.4, 0.9, 2.1, false, "GrassClumps")
	_scatter(rng, FLOWERS, 300, 7.4, 0.8, 1.6, false, "Wildflowers")
	_scatter(rng, ROCKS, 200, 9.0, 0.8, 2.2, false, "Rocks")
	_scatter(rng, WOODLAND, 130, 10.0, 1.0, 2.0, false, "WoodlandProps")
	_build_trackside_fences(rng)

	_scenery = RaceScenery.new()
	var data: Dictionary = _scenery.build(self, _spline, self, 9137)
	_bend_materials = data["bend_materials"]
	_scenery_stats = data["stats"]
	print("MEADOW LOOP scenery: %d PBR trees, %d grass cards, %d scanned plants" % [
		int(_scenery_stats["trees"]), int(_scenery_stats["grass_cards"]),
		int(_scenery_stats["scanned"])])


func _build_trackside_fences(rng: RandomNumberGenerator) -> void:
	# Short wooden markers on the outside of the corners make the track read
	# from the chase camera even when the forest is thick.
	var transforms: Array = []
	var spacing: float = 9.0
	var count: int = int(floor(_spline.total_length / spacing))
	for i in count:
		var s: float = float(i) * spacing
		var frame: Dictionary = _spline.sample(s)
		var side: float = -1.0 if i % 2 == 0 else 1.0
		var offset: float = (ROAD_HALF + CURB_WIDTH + 1.3) * side
		if _near_track(frame["position"] + frame["right"] * offset, 5.0):
			# Skip the marker when another part of the loop passes right there.
			continue
		var position: Vector3 = frame["position"] + frame["right"] * offset
		var basis: Basis = Basis(Vector3.UP, _spline.yaw_at(s) + rng.randf_range(-0.15, 0.15))
		transforms.append(Transform3D(basis, position + Vector3.UP * 0.02))
	var baked: ArrayMesh = _bake_cached("fence_simple")
	if baked == null or transforms.is_empty():
		return
	var holder := Node3D.new()
	holder.name = "TracksideMarkers"
	holder.add_child(FoliageBaker.create_instances(
		baked, _foliage_material, transforms, false))
	add_child(holder)


# --------------------------------------------------------------------------
# rivals


func _bot_count() -> int:
	## Solo: the BOTS pill in PLAY. Multiplayer: whatever the host chose.
	if _multiplayer:
		return clampi(Network.session_bot_count, 0, 5) if Network.session_bots else 0
	return GameSettings.effective_bot_count()


func _build_rivals() -> void:
	var count: int = _bot_count()
	if count <= 0:
		return
	# Only the host runs the rival simulation. Clients spawn the same bodies as
	# interpolated ghosts and follow the host's snapshot, so every player sees
	# the same bots on the same line.
	var authority: bool = not _multiplayer or _is_host
	var rng := RandomNumberGenerator.new()
	if _multiplayer and Network.race_seed != 0:
		rng.seed = Network.race_seed
	elif _multiplayer and Network.join_code != "":
		rng.seed = Network.join_code.hash()
	else:
		rng.seed = Time.get_ticks_msec()
	var names: Array = Array(BOT_NAMES)
	for j in range(names.size() - 1, 0, -1):
		var k: int = rng.randi_range(0, j)
		var swap: Variant = names[j]
		names[j] = names[k]
		names[k] = swap
	var vehicle_id: String = GameSettings.minigame_vehicle
	if VehicleCatalog.find(vehicle_id).is_empty():
		vehicle_id = VehicleCatalog.DEFAULT_ID
	var difficulty: int = clampi(GameSettings.minigame_difficulty, 0, 2)
	var skill_lo: Array[float] = [0.62, 0.72, 0.86]
	var skill_hi: Array[float] = [0.82, 1.00, 1.12]
	var boost_lo: Array[float] = [0.15, 0.40, 0.65]
	var boost_hi: Array[float] = [0.55, 0.85, 1.00]
	var aggr_lo: Array[float] = [0.15, 0.35, 0.60]
	var aggr_hi: Array[float] = [0.40, 0.70, 1.00]
	for i in count:
		var lane: float = [-2.5, 2.5, 0.0, -1.2, 1.2][i % 5]
		var progress: float = START_DISTANCE + 5.0 + float(i) * 4.5
		var spawn: Transform3D = _track_transform(progress, lane, 0.12)
		var rival: CartPlayer = CART_SCENE.instantiate() as CartPlayer
		# Transform before add_child: a body created at the origin spends its
		# first tick overlapping the player and other rivals.
		rival.transform = spawn
		if authority:
			rival.name = "Rival_" + str(names[i % names.size()])
			# Mark AI before add_child so CartFeedback skips audio, skid ribbons
			# and per-frame particle work during _ready.
			rival.ai_mode = true
			add_child(rival)
			rival.setup_ai(vehicle_id)
		else:
			# Client copy: a solid ghost driven only by the host's snapshot.
			add_child(rival)
			rival.call("setup_remote", 1000 + i)
			rival.name = "Rival_" + str(names[i % names.size()])
			rival.set_vehicle_id(vehicle_id)
		var label := Label3D.new()
		label.text = str(names[i % names.size()])
		label.font = load(TITLE_FONT)
		label.font_size = 56
		label.pixel_size = 0.011
		label.outline_size = 16
		label.outline_modulate = UiPalette.OUTLINE
		label.modulate = BOT_COLORS[i % BOT_COLORS.size()]
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position = Vector3(0.0, 2.2, 0.0)
		rival.add_child(label)
		rival.set_spawn_transform(spawn)
		_rivals.append({
			"node": rival,
			"label": label,
			"progress": progress,
			"prev_s": _spline.wrap_distance(progress),
			"lateral": lane,
			"lane": lane,
			"skill": rng.randf_range(skill_lo[difficulty], skill_hi[difficulty]),
			"lookahead": rng.randf_range(0.82, 1.18),
			"boost_bias": rng.randf_range(boost_lo[difficulty], boost_hi[difficulty]),
			"aggression": rng.randf_range(aggr_lo[difficulty], aggr_hi[difficulty]),
			"phase": rng.randf() * TAU,
			"vehicle": vehicle_id,
			"stuck": 0.0,
			"off_time": 0.0,
			"finished": false,
		})


func _reset_rival(index: int) -> void:
	var rival: Dictionary = _rivals[index]
	var node: CartPlayer = rival["node"]
	var spawn: Transform3D = _track_transform(float(rival["progress"]),
		float(rival["lane"]), 0.15)
	node.set_spawn_transform(spawn)
	node.global_transform = spawn
	node.reset_for_respawn()
	node.velocity = Vector3.ZERO
	rival["prev_s"] = _spline.wrap_distance(float(rival["progress"]))
	rival["stuck"] = 0.0
	rival["off_time"] = 0.0


func _bot_obstacle_lane(progress: float, desired: float) -> float:
	## Follow a readable line through the two slaloms and thread the cone gate.
	var wrapped: float = _spline.wrap_distance(progress)
	var chicanes: Array = [
		[0.515, 4, 6.0, 1.9],
		[0.135, 3, 6.5, 1.8],
	]
	for course: Array in chicanes:
		var center: float = _spline.total_length * float(course[0])
		var count: int = int(course[1])
		var spacing: float = float(course[2])
		var start: float = center - float(count - 1) * spacing * 0.5
		var local: float = fposmod(wrapped - start + 5.0, _spline.total_length)
		var span: float = float(count - 1) * spacing + 10.0
		if local < span:
			var index: int = clampi(int(floor((local - 5.0) / spacing + 0.5)), 0, count - 1)
			var cone_side: float = 1.0 if index % 2 == 0 else -1.0
			return -cone_side * maxf(float(course[3]) + 0.8, 2.5)
	var gate_local: float = fposmod(wrapped - _spline.total_length * 0.635 + 5.0,
		_spline.total_length)
	if gate_local < 15.0:
		return 0.0
	return desired


func _bot_boost_lane(progress: float, desired: float) -> float:
	## Bots deliberately line up for pads instead of merely hoping to touch one.
	var wrapped: float = _spline.wrap_distance(progress)
	var laterals: Array[float] = [-2.4, 2.4, 0.0, -1.6]
	for i in 4:
		var pad_s: float = _spline.total_length * (0.13 + float(i) * 0.245)
		var gap: float = fposmod(pad_s - wrapped, _spline.total_length)
		if gap < 26.0:
			desired = laterals[i]
	return _bot_obstacle_lane(progress + 4.0, desired)


func _tick_rivals(delta: float) -> void:
	var limit: float = _race_finish_distance()
	for i in _rivals.size():
		var rival: Dictionary = _rivals[i]
		var node: CartPlayer = rival["node"]
		if not is_instance_valid(node):
			continue
		if bool(rival["finished"]):
			node.set_ai_controls(0.0, 0.35, 0.0)
			continue
		var info: Dictionary = _spline.closest(node.global_position)
		var s: float = info["s"]
		var step: float = s - float(rival["prev_s"])
		if step < -_spline.total_length * 0.5:
			step += _spline.total_length
		elif step > _spline.total_length * 0.5:
			step -= _spline.total_length
		var progress: float = float(rival["progress"])
		progress += clampf(step, -node.max_speed * delta * 2.0 - 1.0,
			node.max_speed * delta * 2.0 + 1.0)
		rival["progress"] = progress
		rival["prev_s"] = s
		var frame: Dictionary = _spline.sample(s)
		rival["lateral"] = (node.global_position - frame["position"]).dot(frame["right"])
		if progress >= limit:
			rival["finished"] = true
			node.collision_layer = 0
			node.contact_enabled = false
			node.set_ai_controls(0.0, 0.5, 0.0)
			continue

		var forward: Vector3 = -node.global_transform.basis.z
		var speed: float = maxf(node.velocity.dot(forward), 0.0)
		var skill: float = rival["skill"]
		var lookahead: float = clampf(speed * 0.65, 7.0, 15.0) * float(rival["lookahead"])
		var curve_near: float = absf(_spline.curvature_at(progress + 4.0))
		var curve_ahead: float = absf(_spline.curvature_at(progress + lookahead + 7.0))
		var corner: float = clampf(1.0 - maxf(curve_near, curve_ahead * 0.9)
			* lerpf(12.5, 8.5, inverse_lerp(0.72, 1.06, skill)), 0.48, 1.0)
		var target_speed: float = node.max_speed * corner * lerpf(0.78, 1.0, skill)
		var phase: float = rival["phase"]
		var wander: float = sin(_race_time * 0.55 + phase) * lerpf(0.75, 0.16, skill)
		var target_lane: float = _bot_boost_lane(progress + lookahead * 0.4,
			float(rival["lane"]) + wander)

		var traffic: Array[CartPlayer] = []
		for other_rival: Dictionary in _rivals:
			traffic.append(other_rival["node"])
		if _cart != null:
			traffic.append(_cart)
		for remote: CartPlayer in _remote_carts.values():
			traffic.append(remote)
		for other: CartPlayer in traffic:
			if other == node or not is_instance_valid(other):
				continue
			var human: bool = other == _cart
			var offset: Vector3 = other.global_position - node.global_position
			offset.y = 0.0
			var ahead: float = offset.dot(forward)
			var side: float = offset.dot(node.global_transform.basis.x)
			var avoid_range: float = 12.0 if human else 11.0
			var avoid_side: float = 3.0 if human else 2.5
			if ahead > 0.0 and ahead < avoid_range and absf(side) < avoid_side:
				var other_speed: float = maxf(other.get_collision_velocity().dot(forward), 0.0)
				if ahead < 5.0:
					target_speed = minf(target_speed, other_speed + (ahead - 2.0) * 0.5)
				var aggression: float = float(rival["aggression"])
				# Never ram a human off the road: give the player the outside
				# line and a clear pass. Hard bots still trade paint with each
				# other, where a shunt cannot end somebody's race.
				if not human and aggression > 0.62 and ahead < 2.6 and absf(side) < 1.4:
					target_lane = clampf(target_lane - signf(side) * 1.4, -3.4, 3.4)
					target_speed = maxf(target_speed, other_speed + 1.5)
				else:
					var margin: float = 3.1 if human else 2.6
					target_lane = clampf(target_lane + (-margin if side > 0.0 else margin), -3.4, 3.4)
					if human and ahead < 3.6 and absf(side) < 2.0:
						# Ease off rather than bump the player aside.
						target_speed = minf(target_speed, other_speed + 0.6)

		var target_frame: Dictionary = _spline.sample(progress + lookahead)
		var target: Vector3 = target_frame["position"] + target_frame["right"] * target_lane
		var local_target: Vector3 = node.to_local(target)
		var steer: float = clampf(atan2(-local_target.x, -local_target.z) * 2.2, -1.0, 1.0)
		steer += sin(_race_time * 1.3 + phase) * (1.06 - skill) * 0.16
		var throttle: float = clampf(skill + 0.06, 0.72, 1.0) if speed < target_speed else 0.0
		var brake: float = clampf((speed - target_speed) / 5.0, 0.0, 0.85) if speed > target_speed + 1.0 else 0.0
		var use_boost: bool = curve_ahead < 0.022 and curve_near < 0.026 \
			and speed > node.max_speed * 0.55 and node.boost_amount > 24.0 \
			and float(rival["boost_bias"]) > 0.52 and brake <= 0.0
		var drift: bool = curve_near > 0.045 and speed > node.max_speed * 0.65 and skill > 0.94
		var stuck_time: float = float(rival["stuck"])
		if stuck_time > 1.2 and stuck_time < 4.0:
			# Reverse out of a wall or a pile-up before the hard reset fires.
			throttle = 0.0
			brake = 1.0
			steer = clampf(-steer * 0.8, -1.0, 1.0)
			use_boost = false
			drift = false
		if float(rival["off_time"]) > 0.35:
			target_lane = clampf(-float(rival["lateral"]), -3.4, 3.4)
			target_speed *= 0.72
			var recovery_frame: Dictionary = _spline.sample(progress + lookahead)
			var recovery_target: Vector3 = recovery_frame["position"] \
				+ recovery_frame["right"] * target_lane
			var recovery_local: Vector3 = node.to_local(recovery_target)
			steer = clampf(atan2(-recovery_local.x, -recovery_local.z) * 2.2, -1.0, 1.0)
		node.set_ai_controls(throttle, brake, steer, use_boost, drift)

		if speed < 0.8:
			rival["stuck"] = float(rival["stuck"]) + delta
		else:
			rival["stuck"] = maxf(float(rival["stuck"]) - delta * 2.0, 0.0)
		if float(info["distance"]) > ROAD_HALF + 5.0 or node.global_position.y < -3.0:
			rival["off_time"] = float(rival["off_time"]) + delta
		else:
			rival["off_time"] = 0.0
		if float(rival["stuck"]) > 4.0 or float(rival["off_time"]) > 2.0:
			_reset_rival(i)


func _place() -> int:
	var position: int = 1
	for rival: Dictionary in _rivals:
		if float(rival["progress"]) > _unwrapped:
			position += 1
	for peer_id: int in _remote_progress:
		if float(_remote_progress[peer_id]) > _unwrapped:
			position += 1
	return position


func _field_size() -> int:
	return 1 + _rivals.size() + _remote_progress.size()


# --------------------------------------------------------------------------
# overlay (candy UI, matching the menus)


func _build_overlay() -> void:
	_canvas = CanvasLayer.new()
	_canvas.layer = 15
	add_child(_canvas)

	var root := Control.new()
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = load(THEME)
	_canvas.add_child(root)

	_countdown_label = _make_label(root, 112, UiPalette.YELLOW,
		Vector2(-260.0, -110.0), Vector2(260.0, 110.0), 0.5, 0.0)
	_countdown_label.text = "3"

	_toast_label = _make_label(root, 26, Color("ffffff"),
		Vector2(-360.0, 96.0), Vector2(360.0, 146.0), 0.5, 0.0)
	_toast_label.visible = false

	_offtrack_label = _make_label(root, 22, UiPalette.RED,
		Vector2(-260.0, 150.0), Vector2(260.0, 186.0), 0.5, 0.0)
	_offtrack_label.text = "OFF TRACK"
	_offtrack_label.visible = false

	_result_root = Control.new()
	_result_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_result_root.visible = false
	# Registering the card as a nav scope lets MenuNav build a focus map for
	# its buttons; the race scene root is a Node3D, so the fallback finds
	# nothing on its own.
	_result_root.add_to_group("nav_scope")
	root.add_child(_result_root)
	# The pause menu is a nav scope too. Keep the card out of the way while it
	# is open, or MenuNav would pick the deeper result card and arrow keys
	# would move focus behind the pause panel.
	var pause_menu: Control = get_node_or_null("PauseMenu/Root") as Control
	if pause_menu != null:
		pause_menu.visibility_changed.connect(_on_pause_visibility_changed)

	# Finish-line artwork behind the card, matching the menu art set. The plain
	# scrim on top keeps the card readable and still lets the art show through.
	var art: Control = ART_BACKDROP.new()
	art.set("texture_names", PackedStringArray(["scene_finish.png"]))
	art.set("dim", 0.10)
	_result_root.add_child(art)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.06, 0.09, 0.19, 0.42)
	_result_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(620 if _multiplayer else 560, 0)
	panel.add_theme_stylebox_override("panel", _make_result_panel_style())
	center.add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", 0)
	panel.add_child(column)

	var pad := MarginContainer.new()
	pad.add_theme_constant_override("margin_left", 30)
	pad.add_theme_constant_override("margin_right", 30)
	pad.add_theme_constant_override("margin_top", 12)
	pad.add_theme_constant_override("margin_bottom", 18)
	column.add_child(pad)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 14 if _multiplayer else 18)
	pad.add_child(body)

	var flag := Control.new()
	flag.custom_minimum_size = Vector2(190, 30)
	flag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	flag.set_script(load(CHECKER_FLAG))
	flag.set("show_pole", false)
	flag.set("wave_amount", 0.0)
	flag.set("columns", 8)
	flag.set("rows", 3)
	body.add_child(flag)

	var title_banner := PanelContainer.new()
	title_banner.add_theme_stylebox_override("panel",
		_make_result_banner_style(UiPalette.YELLOW))
	body.add_child(title_banner)
	_result_title = Label.new()
	_result_title.theme_type_variation = &"TitleLabel"
	_result_title.add_theme_font_size_override("font_size", 34)
	_result_title.add_theme_color_override("font_color", UiPalette.INK)
	_result_title.add_theme_constant_override("outline_size", 0)
	_result_title.text = "YOU WIN!"
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title_banner.add_child(_result_title)

	_result_subtitle = Label.new()
	_result_subtitle.text = "MEADOW LOOP  ·  %d LAPS" % _total_laps
	_result_subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_subtitle.add_theme_font_size_override("font_size", 14)
	_result_subtitle.add_theme_color_override("font_color", UiPalette.MUTED)
	body.add_child(_result_subtitle)

	# One compact table row of captions over a row of values.
	var stats := GridContainer.new()
	stats.columns = 4
	stats.add_theme_constant_override("h_separation", 10)
	stats.add_theme_constant_override("v_separation", 2)
	body.add_child(stats)
	for caption_text: String in ["TOTAL", "BEST LAP", "POSITION", "LAPS"]:
		var caption := Label.new()
		caption.text = caption_text
		caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		caption.add_theme_font_size_override("font_size", 18)
		caption.add_theme_color_override("font_color", UiPalette.MUTED)
		stats.add_child(caption)
	_result_total = _make_result_value()
	_result_best = _make_result_value()
	_result_place = _make_result_value()
	_result_laps = _make_result_value()
	stats.add_child(_result_total)
	stats.add_child(_result_best)
	stats.add_child(_result_place)
	stats.add_child(_result_laps)

	body.add_child(_make_result_divider())
	_result_lap_rows = VBoxContainer.new()
	_result_lap_rows.add_theme_constant_override("separation", 2)
	body.add_child(_result_lap_rows)

	# Multiplayer-only standings. Remote peers do not replicate lap times, so
	# their total/best stay "—" and the gap is the real track distance behind
	# the leader; the card never invents a time for another player.
	_result_standings_section = VBoxContainer.new()
	_result_standings_section.add_theme_constant_override("separation", 4)
	_result_standings_section.visible = false
	body.add_child(_result_standings_section)

	var standings_title := Label.new()
	standings_title.text = "STANDINGS"
	standings_title.theme_type_variation = &"TitleLabel"
	standings_title.add_theme_font_size_override("font_size", 18)
	standings_title.add_theme_color_override("font_color", UiPalette.INK)
	standings_title.add_theme_constant_override("outline_size", 0)
	_result_standings_section.add_child(standings_title)

	_result_wait_style = _make_result_banner_style(UiPalette.YELLOW)
	_result_done_style = _make_result_banner_style(UiPalette.GRASS)
	_result_wait_banner = PanelContainer.new()
	_result_wait_banner.visible = false
	_result_wait_banner.add_theme_stylebox_override("panel", _result_wait_style)
	_result_standings_section.add_child(_result_wait_banner)
	_result_wait_label = Label.new()
	_result_wait_label.text = "WAITING FOR OTHER PLAYERS"
	_result_wait_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_wait_label.add_theme_font_size_override("font_size", 14)
	_result_wait_label.add_theme_color_override("font_color", UiPalette.INK)
	_result_wait_banner.add_child(_result_wait_label)

	var standings_header_pad := MarginContainer.new()
	standings_header_pad.add_theme_constant_override("margin_left", 8)
	standings_header_pad.add_theme_constant_override("margin_right", 8)
	_result_standings_section.add_child(standings_header_pad)
	var standings_header := HBoxContainer.new()
	standings_header.add_theme_constant_override("separation", 6)
	standings_header_pad.add_child(standings_header)
	standings_header.add_child(_make_standings_header("POS", 26.0,
		HORIZONTAL_ALIGNMENT_CENTER))
	standings_header.add_child(_make_standings_header("", 12.0,
		HORIZONTAL_ALIGNMENT_LEFT))
	standings_header.add_child(_make_standings_header("DRIVER", 0.0,
		HORIZONTAL_ALIGNMENT_LEFT, true))
	standings_header.add_child(_make_standings_header("TOTAL", 58.0,
		HORIZONTAL_ALIGNMENT_RIGHT))
	standings_header.add_child(_make_standings_header("BEST", 58.0,
		HORIZONTAL_ALIGNMENT_RIGHT))
	standings_header.add_child(_make_standings_header("GAP", 56.0,
		HORIZONTAL_ALIGNMENT_RIGHT))

	var standings_scroll := ScrollContainer.new()
	standings_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	standings_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	standings_scroll.custom_minimum_size = Vector2(0, 108)
	_result_standings_section.add_child(standings_scroll)
	_result_standings_rows = VBoxContainer.new()
	_result_standings_rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_result_standings_rows.add_theme_constant_override("separation", 2)
	standings_scroll.add_child(_result_standings_rows)

	_result_row_style = StyleBoxFlat.new()
	_result_row_style.bg_color = Color(0, 0, 0, 0)
	_result_row_style.set_corner_radius_all(8)
	_result_row_style.content_margin_left = 8.0
	_result_row_style.content_margin_right = 8.0
	_result_row_style.content_margin_top = 1.0
	_result_row_style.content_margin_bottom = 1.0
	_result_local_row_style = StyleBoxFlat.new()
	# "(YOU)" marks the local row; keep it neutral instead of a yellow bar.
	_result_local_row_style.bg_color = Color(1.0, 1.0, 1.0, 0.10)
	_result_local_row_style.set_corner_radius_all(8)
	_result_local_row_style.content_margin_left = 8.0
	_result_local_row_style.content_margin_right = 8.0
	_result_local_row_style.content_margin_top = 1.0
	_result_local_row_style.content_margin_bottom = 1.0

	if _multiplayer:
		# Restarting only one peer would desync the field.
		var lobby: Button = _make_button("BACK TO LOBBY", UiPalette.RED, 58.0)
		lobby.pressed.connect(_on_back_to_lobby)
		body.add_child(lobby)
		_result_primary = lobby
		var menu: Button = _make_button("MAIN MENU", UiPalette.RED, 52.0)
		menu.pressed.connect(_on_main_menu)
		body.add_child(menu)
	else:
		var again: Button = _make_button("RACE AGAIN", UiPalette.YELLOW, 58.0)
		again.pressed.connect(_on_race_again)
		body.add_child(again)
		_result_primary = again
		var secondary := HBoxContainer.new()
		secondary.add_theme_constant_override("separation", 12)
		body.add_child(secondary)
		var lobby: Button = _make_button("BACK TO EVENTS", UiPalette.RED, 52.0)
		lobby.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		lobby.pressed.connect(_on_back_to_lobby)
		secondary.add_child(lobby)
		var menu: Button = _make_button("MAIN MENU", UiPalette.RED, 52.0)
		menu.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		menu.pressed.connect(_on_main_menu)
		secondary.add_child(menu)


func _make_label(parent: Control, font_size: int, color: Color,
		top_left: Vector2, bottom_right: Vector2, anchor_y: float,
		y_offset: float) -> Label:
	var label := Label.new()
	label.anchor_left = 0.5
	label.anchor_right = 0.5
	label.anchor_top = anchor_y
	label.anchor_bottom = anchor_y
	label.offset_left = top_left.x
	label.offset_right = bottom_right.x
	label.offset_top = top_left.y + y_offset
	label.offset_bottom = bottom_right.y + y_offset
	label.grow_horizontal = Control.GROW_DIRECTION_BOTH
	label.grow_vertical = Control.GROW_DIRECTION_BOTH
	label.theme_type_variation = &"TitleLabel"
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.add_theme_color_override("font_outline_color", UiPalette.OUTLINE)
	label.add_theme_constant_override("outline_size", 12)
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
	return label


func _make_button(text: String, color: Color, height: float = 52.0) -> Button:
	var button := Button.new()
	button.set_script(load(CANDY_BUTTON))
	button.set("fill_color", color)
	button.text = text
	button.custom_minimum_size = Vector2(0, height)
	button.add_theme_font_size_override("font_size", 22)
	return button


func _make_result_panel_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = UiPalette.CREAM
	style.border_color = UiPalette.OUTLINE
	style.set_border_width_all(5)
	style.set_corner_radius_all(26)
	# Keep the body inside the 5 px border, following the inner
	# radius (26 - 5 = 21) instead of painting over the outline.
	style.content_margin_left = 5.0
	style.content_margin_top = 5.0
	style.content_margin_right = 5.0
	style.content_margin_bottom = 5.0
	style.shadow_color = Color(0.12, 0.10, 0.23, 0.45)
	style.shadow_offset = Vector2(0, 10)
	return style


func _make_result_banner_style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.border_color = UiPalette.OUTLINE
	style.set_border_width_all(4)
	style.set_corner_radius_all(16)
	style.content_margin_left = 16.0
	style.content_margin_right = 16.0
	style.content_margin_top = 4.0
	style.content_margin_bottom = 4.0
	return style


func _make_result_value() -> Label:
	var label := Label.new()
	label.text = "—"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 24)
	label.add_theme_color_override("font_color", UiPalette.INK)
	return label


func _make_result_divider() -> ColorRect:
	var line := ColorRect.new()
	line.color = Color(UiPalette.INK, 0.16)
	line.custom_minimum_size = Vector2(0, 2)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return line


func _make_standings_header(text: String, width: float, align: int,
		expand: bool = false) -> Label:
	var label := Label.new()
	label.text = text
	label.custom_minimum_size = Vector2(width, 0)
	label.horizontal_alignment = align
	if expand:
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 13)
	label.add_theme_color_override("font_color", Color(UiPalette.INK, 0.62))
	return label


func _make_standings_row() -> Dictionary:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 30)
	panel.add_theme_stylebox_override("panel", _result_row_style)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	panel.add_child(row)
	var place := Label.new()
	place.custom_minimum_size = Vector2(26, 0)
	place.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	place.add_theme_font_size_override("font_size", 14)
	place.add_theme_color_override("font_color", UiPalette.INK)
	row.add_child(place)
	var dot := ColorRect.new()
	dot.custom_minimum_size = Vector2(12, 12)
	dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(dot)
	var name_label := Label.new()
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.clip_text = true
	name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	name_label.add_theme_font_size_override("font_size", 15)
	name_label.add_theme_color_override("font_color", UiPalette.INK)
	row.add_child(name_label)
	var total := Label.new()
	total.custom_minimum_size = Vector2(58, 0)
	total.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	total.add_theme_font_size_override("font_size", 14)
	total.add_theme_color_override("font_color", UiPalette.INK)
	row.add_child(total)
	var best := Label.new()
	best.custom_minimum_size = Vector2(58, 0)
	best.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	best.add_theme_font_size_override("font_size", 14)
	best.add_theme_color_override("font_color", UiPalette.INK)
	row.add_child(best)
	var gap := Label.new()
	gap.custom_minimum_size = Vector2(56, 0)
	gap.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	gap.add_theme_font_size_override("font_size", 14)
	gap.add_theme_color_override("font_color", UiPalette.INK)
	row.add_child(gap)
	_result_standings_rows.add_child(panel)
	return {
		"panel": panel,
		"place": place,
		"dot": dot,
		"name": name_label,
		"total": total,
		"best": best,
		"gap": gap,
	}


func _update_standings_row(row_data: Dictionary, entry: Dictionary, place: int,
		leader_progress: float) -> void:
	var panel: PanelContainer = row_data["panel"]
	panel.add_theme_stylebox_override("panel",
		_result_local_row_style if bool(entry["local"]) else _result_row_style)
	(row_data["place"] as Label).text = str(place)
	(row_data["dot"] as ColorRect).color = entry["color"]
	(row_data["name"] as Label).text = str(entry["name"])
	var total_seconds: float = float(entry["total"])
	if total_seconds >= 0.0:
		(row_data["total"] as Label).text = _format_time(total_seconds)
	else:
		(row_data["total"] as Label).text = "—"
	var best_seconds: float = float(entry["best"])
	if best_seconds >= 0.0:
		(row_data["best"] as Label).text = _format_time(best_seconds)
	else:
		(row_data["best"] as Label).text = "—"
	var gap_text: String = "—"
	if place > 1:
		if bool(entry["finished"]):
			gap_text = "FINISHED"
		else:
			var behind: float = maxf(leader_progress - float(entry["progress"]), 0.0)
			gap_text = "+%d m" % int(round(behind))
	(row_data["gap"] as Label).text = gap_text


func _result_entries() -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	var local_id: int = multiplayer.get_unique_id() if _multiplayer else 0
	entries.append({
		"key": "local",
		"id": local_id,
		"name": (Network.name_of(local_id) + "  (YOU)") if _multiplayer else "YOU",
		"color": Network.color_of(local_id) if _multiplayer else UiPalette.YELLOW,
		"progress": _unwrapped,
		"finished": true,
		"local": true,
		"total": _race_time,
		"best": _best_lap_time(),
	})
	for index in _rivals.size():
		var progress: float = float(_rivals[index]["progress"])
		var rival_label: Label3D = _rivals[index]["label"]
		entries.append({
			"key": "rival_%d" % index,
			"id": -1 - index,
			"name": rival_label.text,
			"color": rival_label.modulate,
			"progress": progress,
			"finished": progress >= _race_finish_distance() - 12.0,
			"local": false,
			"total": -1.0,
			"best": -1.0,
		})
	for peer_id: int in _remote_progress:
		var progress: float = float(_remote_progress[peer_id])
		entries.append({
			"key": "peer_%d" % peer_id,
			"id": peer_id,
			"name": Network.name_of(peer_id),
			"color": Network.color_of(peer_id),
			"progress": progress,
			"finished": progress >= _race_finish_distance() - 12.0,
			"local": false,
			"total": -1.0,
			"best": -1.0,
		})
	entries.sort_custom(Callable(self, "_standings_before"))
	return entries


func _standings_before(a: Dictionary, b: Dictionary) -> bool:
	var pa: float = float(a["progress"])
	var pb: float = float(b["progress"])
	if not is_equal_approx(pa, pb):
		return pa > pb
	if bool(a["local"]):
		return true
	if bool(b["local"]):
		return false
	return int(a["id"]) < int(b["id"])


func _refresh_result_standings() -> void:
	if not _multiplayer or _result_standings_rows == null:
		return
	_result_standings_section.visible = true
	var entries: Array[Dictionary] = _result_entries()
	var leader_progress: float = 0.0
	if not entries.is_empty():
		leader_progress = float(entries[0]["progress"])
	var live_keys: Dictionary = {}
	for entry: Dictionary in entries:
		live_keys[str(entry["key"])] = true
	var stale: Array[String] = []
	for key: String in _result_standings_cache:
		if not live_keys.has(key):
			stale.append(key)
	for key: String in stale:
		var old: Dictionary = _result_standings_cache[key]
		var old_panel: Control = old["panel"]
		if is_instance_valid(old_panel):
			_result_standings_rows.remove_child(old_panel)
			old_panel.queue_free()
		_result_standings_cache.erase(key)
	for index in entries.size():
		var entry: Dictionary = entries[index]
		var key: String = str(entry["key"])
		var row_data: Dictionary = _result_standings_cache.get(key, {})
		if row_data.is_empty():
			row_data = _make_standings_row()
			_result_standings_cache[key] = row_data
		_update_standings_row(row_data, entry, index + 1, leader_progress)
		_result_standings_rows.move_child(row_data["panel"] as Control, index)
	if _result_place != null:
		# Remote progress can arrive after our finish; keep the big position
		# in sync with the live standings.
		var live_place: int = _place()
		_result_place.text = "%s / %d" % [_ordinal(live_place), _field_size()]
	var waiting: int = _waiting_peer_count()
	_result_wait_banner.visible = true
	if waiting > 0:
		_result_wait_label.text = "WAITING FOR %d PLAYER%s..." % [
			waiting, "" if waiting == 1 else "S"]
		_result_wait_banner.add_theme_stylebox_override("panel", _result_wait_style)
	else:
		_result_wait_label.text = "ALL PLAYERS FINISHED"
		_result_wait_banner.add_theme_stylebox_override("panel", _result_done_style)


func _on_pause_visibility_changed() -> void:
	if _result_root == null or not _result_root.visible:
		return
	var pause_menu: Control = get_node_or_null("PauseMenu/Root") as Control
	var pause_open: bool = pause_menu != null and pause_menu.visible
	if pause_open:
		_result_root.remove_from_group("nav_scope")
	elif not _result_root.is_in_group("nav_scope"):
		_result_root.add_to_group("nav_scope")
	var menu_nav: Node = get_node_or_null("/root/MenuNav")
	if menu_nav != null:
		menu_nav.call("refresh")
	if not pause_open and _result_primary != null:
		pass


func _waiting_peer_count() -> int:
	if not _multiplayer:
		return 0
	var finish_distance: float = _race_finish_distance()
	var local_id: int = multiplayer.get_unique_id()
	var waiting: int = 0
	for peer_id: int in Network.participants():
		if peer_id == local_id:
			continue
		# A peer that returned to the lobby is still connected but no longer
		# in this race scene. Do not wait on it forever. Clients only track the
		# host in scene_ready_peers, so use the progress table there instead.
		if Network.is_host:
			if not Network.is_scene_ready(peer_id):
				continue
		elif not _remote_progress.has(peer_id):
			continue
		if float(_remote_progress.get(peer_id, 0.0)) < finish_distance - 12.0:
			waiting += 1
	return waiting


func _race_finish_distance() -> float:
	if _spline == null:
		return 0.0
	# Progress is absolute track distance and starts at START_DISTANCE (the
	# grid sits before the line), so the finish is START_DISTANCE + 3 laps.
	# The old value (3 laps only) made the player and every result threshold
	# finish 8 m early relative to the rivals.
	return START_DISTANCE + float(_total_laps) * _spline.total_length


func _best_lap_time() -> float:
	if _lap_times.is_empty():
		return -1.0
	var best: float = _lap_times[0]
	for time: float in _lap_times:
		best = minf(best, time)
	return best


func _fill_result_laps() -> void:
	for child: Node in _result_lap_rows.get_children():
		_result_lap_rows.remove_child(child)
		child.queue_free()
	for index in _total_laps:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 12)
		var caption := Label.new()
		caption.text = "LAP %d" % (index + 1)
		caption.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		caption.add_theme_font_size_override("font_size", 16)
		caption.add_theme_color_override("font_color", UiPalette.MUTED)
		row.add_child(caption)
		var value := Label.new()
		value.text = _format_time(_lap_times[index]) if index < _lap_times.size() else "—"
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		value.add_theme_font_size_override("font_size", 18)
		value.add_theme_color_override("font_color", UiPalette.INK)
		row.add_child(value)
		_result_lap_rows.add_child(row)


func _toast(text: String, duration: float) -> void:
	_toast_label.text = text
	_toast_label.visible = true
	_toast_timer = duration


func _pop_label(label: Label) -> void:
	label.scale = Vector2.ONE * 1.25
	var tween := create_tween()
	tween.tween_property(label, "scale", Vector2.ONE, 0.28) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# --------------------------------------------------------------------------
# multiplayer ghosts (host-authoritative start, peers own their carts)


func _setup_multiplayer() -> void:
	_multiplayer = true
	_is_host = Network.is_host
	if OS.get_environment("CART_DEBUG_NET") == "1":
		print("RACE_NET setup peers=", multiplayer.get_peers(), " host=", _is_host)
	if _is_host:
		# Race rule: the host picks ONE car for the whole field. Only the name
		# tag (and its colour) tells players apart.
		_race_vehicle = GameSettings.minigame_vehicle
	_peer_vehicles[multiplayer.get_unique_id()] = \
		_race_vehicle if _is_host else GameSettings.minigame_vehicle
	_place_local_on_grid()
	_setup_props_net()
	for peer_id: int in multiplayer.get_peers():
		_spawn_remote(peer_id)
	multiplayer.peer_connected.connect(_on_net_peer_connected)
	multiplayer.peer_disconnected.connect(_on_net_peer_disconnected)
	Network.names_changed.connect(_refresh_net_names)
	Network.tag_colors_changed.connect(_refresh_net_names)
	Network.notify_scene_ready()
	if _is_host:
		# Push the forced car to every peer. Peers that have not loaded the
		# scene yet receive it again in _net_race_ready.
		rpc("_net_force_race_vehicle", _race_vehicle)
		_broadcast_race_vehicle(multiplayer.get_unique_id(), _race_vehicle)
	else:
		rpc_id(1, "_net_race_ready", GameSettings.minigame_vehicle)


func _place_local_on_grid() -> void:
	if _cart == null:
		return
	var ids: Array[int] = Network.participants()
	var found: int = ids.find(multiplayer.get_unique_id())
	# A missing id used to collapse every peer onto slot 0, stacking spawns.
	var index: int = found if found >= 0 else absi(multiplayer.get_unique_id()) % 8
	var row: int = index / 2
	var column: int = index % 2
	var start_s: float = START_DISTANCE - float(row) * 4.5
	var spawn: Transform3D = _track_transform(start_s, -2.6 + float(column) * 5.2)
	_cart.set_spawn_transform(spawn)
	_cart.global_transform = spawn
	_cart.velocity = Vector3.ZERO
	_last_cart_pos = _cart.global_position
	_prev_s = start_s
	_unwrapped = start_s


func _on_net_peer_connected(peer_id: int) -> void:
	_spawn_remote(peer_id)


func _on_net_peer_disconnected(peer_id: int) -> void:
	if OS.get_environment("CART_DEBUG_NET") == "1":
		print("RACE_NET disconnected peer=", peer_id, " peers=", multiplayer.get_peers())
	var cart: CartPlayer = _remote_carts.get(peer_id)
	if cart != null:
		cart.queue_free()
		_remote_carts.erase(peer_id)
	_peer_vehicles.erase(peer_id)
	_name_labels.erase(peer_id)
	_remote_progress.erase(peer_id)
	_remote_progress_ms.erase(peer_id)


func _spawn_remote(peer_id: int) -> void:
	if _remote_carts.has(peer_id) or peer_id == multiplayer.get_unique_id():
		return
	var ids: Array[int] = Network.participants()
	var index: int = maxi(ids.find(peer_id), 0)
	var row: int = index / 2
	var column: int = index % 2
	# 0.05 sits the ghost ON the dirt road (top at 0.04): ghosts run no physics,
	# so anything higher leaves them hovering in the air until the first sync.
	var spawn: Transform3D = _track_transform(START_DISTANCE - float(row) * 4.5,
		-2.6 + float(column) * 5.2, 0.05)
	var cart: CartPlayer = CART_SCENE.instantiate() as CartPlayer
	# Transform before add_child: otherwise the body starts at the world origin
	# for one physics tick and shoves every cart already near it.
	cart.transform = spawn
	add_child(cart)
	cart.setup_remote(peer_id)
	cart.net_position = cart.global_position
	cart.net_yaw = cart.rotation.y
	if _peer_vehicles.has(peer_id):
		cart.set_vehicle_id(str(_peer_vehicles[peer_id]))
	elif peer_id == 1 and _race_vehicle != "":
		# The host's vehicle table can arrive after its ghost is created.
		cart.set_vehicle_id(_race_vehicle)
	var label := Label3D.new()
	label.text = Network.name_of(peer_id)
	label.font = load(TITLE_FONT)
	label.font_size = 56
	label.pixel_size = 0.011
	label.outline_size = 16
	label.outline_modulate = UiPalette.OUTLINE
	label.modulate = Network.color_of(peer_id)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.no_depth_test = true
	label.position = Vector3(0.0, 2.2, 0.0)
	cart.add_child(label)
	_name_labels[peer_id] = label
	_remote_carts[peer_id] = cart
	_remote_progress[peer_id] = START_DISTANCE - float(row) * 4.5
	if OS.get_environment("CART_DEBUG_NET") == "1":
		print("RACE_NET remote=", peer_id, " vehicle=", _peer_vehicles.get(peer_id, "?"))
	if _cart != null:
		var camera := _cart.get_node_or_null("CameraArm/Camera3D") as Camera3D
		if camera != null:
			camera.current = true


func _refresh_net_names() -> void:
	for peer_id: int in _name_labels:
		var label: Label3D = _name_labels[peer_id]
		if is_instance_valid(label):
			label.text = Network.name_of(peer_id)
			label.modulate = Network.color_of(peer_id)


func _broadcast_race_state(peer_id: int, position: Vector3, yaw: float,
		progress: float, sent_ms: int = 0,
		velocity: Vector3 = Vector3.ZERO) -> void:
	if sent_ms <= 0:
		sent_ms = Time.get_ticks_msec()
	for target: int in multiplayer.get_peers():
		if Network.is_scene_ready(target):
			rpc_id(target, "_net_race_cart_state", peer_id, position, yaw, progress, sent_ms, velocity)


func _broadcast_race_vehicle(peer_id: int, vehicle_id: String) -> void:
	for target: int in multiplayer.get_peers():
		if Network.is_scene_ready(target):
			rpc_id(target, "_net_race_vehicle", peer_id, vehicle_id)


@rpc("any_peer", "reliable")
func _net_race_ready(vehicle_id: String) -> void:
	var sender: int = _rpc_sender()
	if OS.get_environment("CART_DEBUG_NET") == "1":
		print("RACE_NET ready from=", sender, " vehicle=", vehicle_id)
	if sender <= 1 or sender == multiplayer.get_unique_id():
		return
	Network.mark_peer_scene_ready(sender)
	# The host's car is everyone's car, so the client's own pick is ignored in
	# a race (the sandbox keeps per-peer choices).
	_store_net_vehicle(sender, _race_vehicle if _is_host else vehicle_id)
	if _is_host and not _waiting_for_peers:
		if _phase == Phase.COUNTDOWN:
			rpc_id(sender, "_net_race_countdown", maxf(_countdown, 0.1))
		elif _phase == Phase.RACING or _phase == Phase.FINISHED:
			# The host already started (or finished) while this peer was still
			# loading. Release its WAITING screen; a finished host still lets a
			# late loader drive instead of freezing on an empty track.
			rpc_id(sender, "_net_race_join_now")
	if not _is_host:
		return
	# Re-send the forced car in case the broadcast landed before this peer's
	# scene existed, then reply with the whole vehicle map.
	rpc_id(sender, "_net_force_race_vehicle", _race_vehicle)
	for peer_id: Variant in _peer_vehicles.keys():
		rpc_id(sender, "_net_race_vehicle", int(peer_id), str(_peer_vehicles[peer_id]))


@rpc("authority", "reliable")
func _net_race_vehicle(peer_id: int, vehicle_id: String) -> void:
	_store_net_vehicle(peer_id, vehicle_id)


func _store_net_vehicle(peer_id: int, vehicle_id: String) -> void:
	if OS.get_environment("CART_DEBUG_NET") == "1":
		print("RACE_NET store peer=", peer_id, " vehicle=", vehicle_id)
	if vehicle_id.length() > 64:
		return
	if VehicleCatalog.find(vehicle_id).is_empty():
		return
	if peer_id == 1 and not _is_host:
		# The host's car is the car everyone drives. Remember it for the host's
		# ghost too, or that ghost renders with the client's local pick.
		_peer_vehicles[1] = vehicle_id
		var host_cart: CartPlayer = _remote_carts.get(1)
		if host_cart != null:
			host_cart.set_vehicle_id(vehicle_id)
		_apply_forced_vehicle(vehicle_id)
		return
	_peer_vehicles[peer_id] = vehicle_id
	var cart: CartPlayer = _remote_carts.get(peer_id)
	if cart != null:
		cart.set_vehicle_id(vehicle_id)


func _apply_forced_vehicle(vehicle_id: String) -> void:
	## Client side: switch the LOCAL race cart to the host's car.
	if _race_vehicle == vehicle_id \
			and str(_peer_vehicles.get(multiplayer.get_unique_id(), "")) == vehicle_id:
		return
	_race_vehicle = vehicle_id
	_peer_vehicles[multiplayer.get_unique_id()] = vehicle_id
	if _cart != null:
		_cart.reapply_vehicle(vehicle_id)
		# The off-track slowdown resets max_speed to _base_max_speed every
		# frame; re-capture it or the forced car silently reverts to the old
		# stats one frame after the swap.
		_base_max_speed = _cart.max_speed
	for rival: Dictionary in _rivals:
		var node: CartPlayer = rival["node"]
		node.reapply_vehicle(vehicle_id)
		rival["vehicle"] = vehicle_id


@rpc("authority", "call_local", "reliable")
func _net_force_race_vehicle(vehicle_id: String) -> void:
	if _is_host:
		return
	_apply_forced_vehicle(vehicle_id)


func _on_horn_requested() -> void:
	## Local cart already honked; share it with the room.
	var my_id: int = multiplayer.get_unique_id()
	if _is_host:
		_broadcast_horn(my_id, 0)
	elif Network.is_scene_ready(1):
		rpc_id(1, "_net_horn", my_id)


func _broadcast_horn(peer_id: int, except_id: int) -> void:
	for target: int in multiplayer.get_peers():
		if target != except_id and Network.is_scene_ready(target):
			rpc_id(target, "_net_horn", peer_id)


@rpc("any_peer", "reliable")
func _net_horn(peer_id: int) -> void:
	var sender: int = _rpc_sender()
	if sender != 1 and peer_id != sender:
		return
	if peer_id == multiplayer.get_unique_id():
		return
	var now: int = Time.get_ticks_msec()
	if now - int(_horn_stamp.get(peer_id, -10000)) < 140:
		return
	_horn_stamp[peer_id] = now
	var cart: CartPlayer = _remote_carts.get(peer_id)
	if cart != null:
		cart.honk()
	if _is_host and sender != 1:
		_broadcast_horn(peer_id, sender)


@rpc("any_peer", "unreliable")
func _net_race_cart_state(peer_id: int, position: Vector3, yaw: float,
		progress: float, sent_ms: int = 0,
		velocity: Vector3 = Vector3.ZERO) -> void:
	var sender: int = _rpc_sender()
	if sender != 1 and peer_id != sender:
		return
	# The host relays a client's packet to every ready peer, including its
	# sender. Storing your own echo creates a phantom self entry in the
	# standings (and a duplicate result row), so ignore it.
	if peer_id == multiplayer.get_unique_id():
		return
	if not position.is_finite() or not is_finite(yaw) or not is_finite(progress) \
			or not velocity.is_finite():
		return
	if position.length_squared() > 5000.0 * 5000.0:
		return
	if sent_ms < 0:
		return
	# Drop a reordered datagram before it can move the ghost or the standings
	# backwards. The sender's own clock makes the stamp comparable per peer.
	var newest: int = int(_remote_progress_ms.get(peer_id, -1))
	if sent_ms > 0 and sent_ms <= newest:
		if newest - sent_ms <= NET_CLOCK_RESET_MS:
			return
		# Sender restarted its process or sent one absurd stamp. Accept the
		# new baseline instead of rejecting every later packet forever.
		newest = -1
	if sent_ms > 0:
		_remote_progress_ms[peer_id] = sent_ms
	var cart: CartPlayer = _remote_carts.get(peer_id)
	if cart != null and cart.remote_mode:
		_accept_remote_race_state(peer_id, cart, position, yaw, progress,
			sent_ms, velocity, newest)
	if _is_host and sender != 1:
		_broadcast_race_state(peer_id, position, yaw,
			float(_remote_progress.get(peer_id, progress)), sent_ms, velocity)


func _accept_remote_race_state(peer_id: int, cart: CartPlayer, position: Vector3,
		yaw: float, progress: float, sent_ms: int, velocity: Vector3,
		previous_stamp: int) -> void:
	## The timestamped, bounded progress pipeline shared by the RPC above and
	## the focused headless regression test.
	cart.set_net_state(position, yaw, sent_ms, velocity)
	var limit: float = float(_total_laps + 1) * _spline.total_length
	var previous: float = float(_remote_progress.get(peer_id, progress))
	# A peer reports its own lap distance. Bound the jump by the elapsed
	# sender time and the cart's real top speed, so a dropped packet still
	# catches up but a modified client cannot gain 8 m every 50 ms.
	var elapsed_s: float = 0.05
	if sent_ms > 0 and previous_stamp >= 0:
		elapsed_s = clampf(float(sent_ms - previous_stamp) / 1000.0, 0.05, 2.0)
	var max_step: float = 12.0
	if _cart != null:
		max_step = _cart.max_speed * elapsed_s * 1.5 + 1.0
	var clamped_progress: float = clampf(progress, maxf(previous - max_step, 0.0),
		minf(previous + max_step, limit))
	_remote_progress[peer_id] = clamped_progress
	# Remote progress is lap-relative once the cart crosses the start line
	# (the first crossing subtracts the grid offset). Use the same finish
	# distance as the local placement code, or a finished ghost stays solid.
	var finish_line: float = _race_finish_distance()
	if clamped_progress >= finish_line - 2.0:
		# A crossed cart is not an obstacle, and it must stay that way even
		# though it keeps streaming state until the race ends.
		cart.mark_race_finished()


# --------------------------------------------------------------------------
# host-authoritative props and bots


func _setup_props_net() -> void:
	for node in get_tree().get_nodes_in_group("pushable"):
		if node is RigidBody3D:
			_props.append(node as RigidBody3D)
	_props.sort_custom(func(a: RigidBody3D, b: RigidBody3D) -> bool: return str(a.name) < str(b.name))
	if _cart != null and not _cart.net_push_requested.is_connected(_on_local_push_requested):
		_cart.net_push_requested.connect(_on_local_push_requested)
	if not _is_host:
		for prop: RigidBody3D in _props:
			prop.freeze_mode = RigidBody3D.FREEZE_MODE_STATIC
			prop.freeze = true


func _on_local_push_requested(prop: Node, direction: Vector3, kick: float) -> void:
	if _is_host or not _multiplayer:
		return
	var index: int = _props.find(prop as RigidBody3D)
	if index < 0:
		return
	# Predict locally so the cone flies on this screen too; the host stays
	# authoritative and the next snapshot corrects the pose.
	_kick_prop(prop as RigidBody3D, direction, kick)
	rpc_id(1, "_net_request_push", index, direction, kick)


func _kick_prop(prop: RigidBody3D, direction: Vector3, kick: float) -> void:
	if not is_instance_valid(prop) or not direction.is_finite() or not is_finite(kick):
		return
	if direction.length_squared() < 0.0001:
		return
	prop.freeze = false
	prop.sleeping = false
	direction = direction.normalized()
	kick = clampf(kick, 0.1, 4.0)
	prop.apply_central_impulse(direction * prop.mass * kick + Vector3.UP * prop.mass * kick * 0.85)
	var spin := Vector3(randf_range(-1.0, 1.0), randf_range(-0.5, 0.5), randf_range(-1.0, 1.0))
	prop.apply_torque_impulse(spin * prop.mass * 1.6)
	_prop_kick_until[prop.get_instance_id()] = Time.get_ticks_msec() + 400


func _expire_prop_kicks() -> void:
	if _prop_kick_until.is_empty():
		return
	var now: int = Time.get_ticks_msec()
	for id: int in _prop_kick_until.keys():
		if now < int(_prop_kick_until[id]):
			continue
		_prop_kick_until.erase(id)
		var prop: RigidBody3D = instance_from_id(id) as RigidBody3D
		if is_instance_valid(prop):
			prop.freeze = true


func _broadcast_props() -> void:
	if _props.is_empty():
		return
	var positions := PackedVector3Array()
	var rotations := PackedVector3Array()
	for prop: RigidBody3D in _props:
		if not is_instance_valid(prop):
			positions.append(Vector3.ZERO)
			rotations.append(Vector3.ZERO)
			continue
		positions.append(prop.global_position)
		rotations.append(prop.global_rotation)
	for target: int in multiplayer.get_peers():
		if Network.is_scene_ready(target):
			rpc_id(target, "_net_props", positions, rotations)


func _apply_prop_targets(delta: float) -> void:
	if _prop_targets.is_empty():
		return
	var blend: float = 1.0 - exp(-12.0 * delta)
	for index: int in _prop_targets:
		if index < 0 or index >= _props.size():
			continue
		var prop: RigidBody3D = _props[index]
		if not is_instance_valid(prop):
			continue
		if _prop_kick_until.has(prop.get_instance_id()):
			continue
		var data: Array = _prop_targets[index]
		prop.global_position = prop.global_position.lerp(data[0] as Vector3, blend)
		var target_rotation: Vector3 = data[1] as Vector3
		prop.global_rotation = Vector3(
			lerp_angle(prop.global_rotation.x, target_rotation.x, blend),
			lerp_angle(prop.global_rotation.y, target_rotation.y, blend),
			lerp_angle(prop.global_rotation.z, target_rotation.z, blend))


@rpc("authority", "unreliable")
func _net_props(positions: PackedVector3Array, rotations: PackedVector3Array) -> void:
	if _is_host or not _multiplayer:
		return
	if positions.size() != _props.size() or rotations.size() != _props.size():
		return
	for index in positions.size():
		if not positions[index].is_finite() or not rotations[index].is_finite():
			continue
		_prop_targets[index] = [positions[index], rotations[index]]


@rpc("any_peer", "reliable")
func _net_request_push(index: int, direction: Vector3, kick: float) -> void:
	if not _is_host or index < 0 or index >= _props.size():
		return
	if not direction.is_finite() or not is_finite(kick):
		return
	if direction.length_squared() < 0.0001:
		return
	var sender: int = _rpc_sender()
	var now: int = Time.get_ticks_msec()
	if now - int(_push_stamp.get(sender, -10000)) < 100:
		return
	_push_stamp[sender] = now
	_kick_prop(_props[index], direction, kick)


func _broadcast_bot_states() -> void:
	if _rivals.is_empty():
		return
	var positions := PackedVector3Array()
	var yaws := PackedFloat32Array()
	var velocities := PackedVector3Array()
	var progresses := PackedFloat32Array()
	for rival: Dictionary in _rivals:
		var node: CartPlayer = rival["node"]
		if not is_instance_valid(node):
			positions.append(Vector3.ZERO)
			yaws.append(0.0)
			velocities.append(Vector3.ZERO)
			progresses.append(float(rival["progress"]))
			continue
		positions.append(node.global_position)
		yaws.append(node.rotation.y)
		velocities.append(node.velocity.limit_length(60.0))
		progresses.append(float(rival["progress"]))
	var stamp: int = Time.get_ticks_msec()
	for target: int in multiplayer.get_peers():
		if Network.is_scene_ready(target):
			rpc_id(target, "_net_bot_states", positions, yaws, velocities, progresses, stamp)


@rpc("authority", "unreliable")
func _net_bot_states(positions: PackedVector3Array, yaws: PackedFloat32Array,
		velocities: PackedVector3Array, progresses: PackedFloat32Array,
		sent_ms: int) -> void:
	if _is_host or not _multiplayer:
		return
	var count: int = mini(positions.size(), _rivals.size())
	if yaws.size() < count or velocities.size() < count or progresses.size() < count:
		return
	var finish: float = _race_finish_distance()
	for i in count:
		var position: Vector3 = positions[i]
		if not position.is_finite() or not is_finite(yaws[i]) \
				or not velocities[i].is_finite() or not is_finite(progresses[i]):
			continue
		var rival: Dictionary = _rivals[i]
		var node: CartPlayer = rival["node"]
		if not is_instance_valid(node) or not node.remote_mode:
			continue
		node.set_net_state(position, yaws[i], sent_ms, velocities[i])
		rival["progress"] = progresses[i]
		if not bool(rival["finished"]) and progresses[i] >= finish - 2.0:
			rival["finished"] = true
			node.mark_race_finished()


# --------------------------------------------------------------------------
# race loop


func _physics_process(delta: float) -> void:
	# Contact impulses, AI inputs, lap progress and the race clock are all
	# fixed-step work. Running them from _process made bumps, AI and lap timing
	# depend on the render rate.
	if _multiplayer and _is_host and _cart != null:
		Network.resolve_car_collisions(_cart, _remote_carts)
	if _multiplayer and Network.is_session_active():
		if _is_host:
			_prop_sync_timer += delta
			if _prop_sync_timer >= PROP_SYNC_INTERVAL:
				_prop_sync_timer = 0.0
				_broadcast_props()
		else:
			_expire_prop_kicks()
			_apply_prop_targets(delta)
	match _phase:
		Phase.COUNTDOWN:
			_tick_countdown(delta)
		Phase.RACING:
			_tick_race(delta)


func _process(delta: float) -> void:
	if _waiting_for_peers:
		_wait_elapsed += delta
		if _is_host:
			var all_ready: bool = true
			for peer_id: int in multiplayer.get_peers():
				if not Network.is_scene_ready(peer_id):
					all_ready = false
					break
			if all_ready or _wait_elapsed >= 8.0:
				_begin_race_countdown()
		return
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			_toast_label.visible = false
	if _multiplayer and _cart != null and _phase != Phase.FINISHED \
			and Network.is_session_active() and Network.is_connected_to_server():
		_net_sync_timer += delta
		if _net_sync_timer >= NET_SYNC_INTERVAL:
			_net_sync_timer = 0.0
			if _is_host:
				_broadcast_race_state(multiplayer.get_unique_id(),
					_cart.global_position, _cart.rotation.y, _unwrapped,
					Time.get_ticks_msec(), _cart.velocity)
			elif Network.is_scene_ready(1):
				rpc_id(1, "_net_race_cart_state", multiplayer.get_unique_id(),
					_cart.global_position, _cart.rotation.y, _unwrapped,
					Time.get_ticks_msec(), _cart.velocity)
	if _multiplayer and _is_host and Network.is_session_active() \
			and not _rivals.is_empty():
		# Stream the bots even while the host sits on its result card: clients
		# are still racing and must see them keep driving.
		_bot_sync_timer += delta
		if _bot_sync_timer >= 0.05:
			_bot_sync_timer = 0.0
			_broadcast_bot_states()
	match _phase:
		Phase.FINISHED:
			# Peers keep streaming their progress after we cross the line, so
			# the standings and the waiting banner stay live.
			if _multiplayer and _result_root != null and _result_root.visible:
				_result_refresh_timer += delta
				if _result_refresh_timer >= 0.5:
					_result_refresh_timer = 0.0
					_refresh_result_standings()


func _begin_race_countdown() -> void:
	if not _is_host:
		return
	_waiting_for_peers = false
	_countdown = 3.0
	_last_count = 0
	_go_shown = false
	_phase = Phase.COUNTDOWN
	_countdown_label.visible = true
	_countdown_label.text = "3"
	if OS.get_environment("CART_DEBUG_NET") == "1":
		print("RACE_COUNTDOWN_START host peers=", multiplayer.get_peers())
	rpc("_net_race_countdown", 3.0)


@rpc("authority", "call_local", "reliable")
func _net_race_countdown(seconds: float) -> void:
	_waiting_for_peers = false
	_countdown = maxf(seconds, 0.1)
	_last_count = 0
	_go_shown = false
	_phase = Phase.COUNTDOWN
	_countdown_label.visible = true
	_countdown_label.text = str(int(ceil(_countdown)))
	if OS.get_environment("CART_DEBUG_NET") == "1":
		print("RACE_COUNTDOWN_RECV seconds=", _countdown, " host=", _is_host)


@rpc("authority", "reliable")
func _net_race_join_now() -> void:
	## A lobby peer that finished loading after the host's GO still gets a
	## drivable race instead of sitting on WAITING forever.
	if _is_host:
		return
	_waiting_for_peers = false
	_go_shown = true
	_countdown = 0.0
	_countdown_label.visible = false
	_phase = Phase.RACING
	if _cart != null:
		_cart.set_physics_process(true)


func _tick_countdown(delta: float) -> void:
	if _countdown > 0.0:
		_countdown -= delta
		var count: int = int(ceil(maxf(_countdown, 0.0)))
		if count != _last_count:
			_last_count = count
			_countdown_label.text = str(count) if count > 0 else "GO!"
			_pop_label(_countdown_label)
			_set_start_lights([1, 3, 5][clampi(3 - count, 0, 2)], false)
			if count > 0:
				_play_one_shot(COUNTDOWN_BEEP, -9.0, 1.0)
		return
	if not _go_shown:
		_go_shown = true
		_countdown_label.text = "GO!"
		_countdown_label.add_theme_color_override("font_color", UiPalette.GRASS)
		_pop_label(_countdown_label)
		_set_start_lights(_start_lights.size(), true)
		_flash_gate(0)
		_play_one_shot(COUNTDOWN_GO, -7.0, 1.0)
		# Control and the race clock start on the GO frame. The label stays up
		# for a short visual beat without freezing the karts.
		_phase = Phase.RACING
		_go_time = 0.0
		if _cart != null:
			_cart.set_physics_process(true)
		return


func _tick_race(delta: float) -> void:
	_race_time += delta
	if _go_shown and _countdown_label.visible:
		_go_time += delta
		if _go_time >= 0.7:
			_countdown_label.visible = false
	if _cart == null:
		return

	var info: Dictionary = _spline.closest(_cart.global_position)
	var s: float = info["s"]
	var closest_point: Vector3 = info["point"] as Vector3

	# A reset (R) or a respawn is a teleport: resync, never bank the jump.
	if _cart.global_position.distance_squared_to(_last_cart_pos) > 100.0:
		var total: float = maxf(_spline.total_length, 0.001)
		var lap_index: float = floorf(_unwrapped / total)
		# Any teleport (R reset, respawn, backwards or wrapped-forward) must
		# not let sectors from the old position count toward the new lap.
		_sector_flags = 0
		_last_sector = clampi(int(s / (total / 4.0)), 0, 3)
		# Re-base the unwrapped distance to the new physical position in the
		# current lap; otherwise the lap completes mid-track after a reset.
		_unwrapped = lap_index * total + s
		_skip_progress = true
	_last_cart_pos = _cart.global_position

	if _skip_progress:
		_prev_s = s
		_skip_progress = false
	else:
		var step: float = s - _prev_s
		if step < -_spline.total_length * 0.5:
			step += _spline.total_length
		elif step > _spline.total_length * 0.5:
			step -= _spline.total_length
		var max_step: float = _cart.velocity.length() * delta * 2.5 + 1.0
		_unwrapped += clampf(step, -max_step, max_step)
	_prev_s = s

	var sector: int = clampi(int(s / (_spline.total_length / 4.0)), 0, 3)
	_sector_flags |= 1 << sector
	if sector != _last_sector:
		_last_sector = sector
		_flash_gate(sector)
	if _unwrapped >= START_DISTANCE + float(_lap) * _spline.total_length \
			and _sector_flags == 0b1111:
		_complete_lap()

	# Lateral offset from the centreline, not raw nearest-point distance: a
	# barrier scrape or a tight hairpin can spike the 3D/nearest distance while
	# the kart is still fully on the road.
	var frame: Dictionary = _spline.sample(s)
	var right: Vector3 = frame["right"] as Vector3
	var lateral: float = absf((_cart.global_position - closest_point).dot(right))
	# Hysteresis: leave the road at the curb, come back only once clearly
	# inside it, so a scrape cannot flip the warning and the slowdown on and
	# off every frame.
	var off_limit: float = ROAD_HALF + 1.1
	var back_on: float = ROAD_HALF + 0.5
	var off: bool = lateral > (back_on if _was_off_track else off_limit)
	_was_off_track = off
	if off:
		_off_timer += delta
		_offtrack_label.visible = true
		_cart.max_speed = _base_max_speed * 0.55
		# Only pull a kart back once it is really out (past the barrier or the
		# grass) or has been stuck out there for a while. The respawn point is
		# forward of the current arc length, never behind it.
		if _off_timer > 4.5 or lateral > 13.0 or _cart.global_position.y < -3.0:
			_respawn(s)
	else:
		_off_timer = 0.0
		_offtrack_label.visible = false
		_cart.max_speed = _base_max_speed
	if _effects != null:
		_effects.set("off_track", off)
	# Grass physically bends away from the kart: feed world position to the
	# shared wind shaders once per frame (one uniform, all 5,000 cards).
	for material: ShaderMaterial in _bend_materials:
		material.set_shader_parameter("kart_position", _cart.global_position)

	if not _multiplayer or _is_host:
		_rival_tick_accum += delta
		if _rival_tick_accum >= 1.0 / 30.0:
			_tick_rivals(_rival_tick_accum)
			_rival_tick_accum = 0.0
	_hud_time_accum += delta
	if _hud_time_accum >= 0.05:
		_hud_time_accum = 0.0
		var lap_now: int = mini(_lap, _total_laps)
		if lap_now != _hud_last_lap:
			_hud_last_lap = lap_now
			_hud.call("set_lap", lap_now, _total_laps)
		var place_now: int = _place()
		if place_now != _hud_last_place:
			_hud_last_place = place_now
			_hud.call("set_race_position", place_now, _field_size())
		_hud.call("set_race_time", _race_time, _best_lap_time())
		_hud_standings_accum += 0.05
		if _hud_standings_accum >= 0.25:
			_hud_standings_accum = 0.0
			_hud.call("set_standings", _result_entries())


func _safe_respawn_transform(s: float) -> Transform3D:
	## Respawn on the centreline only if the spot is clear; otherwise search
	## along the track and across the road. A blind centreline respawn can drop
	## a kart inside another kart or a barrier.
	var space_state: PhysicsDirectSpaceState3D = get_world_3d().direct_space_state
	var shape := SphereShape3D.new()
	shape.radius = 1.15
	var query := PhysicsShapeQueryParameters3D.new()
	query.shape = shape
	query.collision_mask = 1 | 2 | 8
	query.exclude = [_cart.get_rid()] if _cart != null else []
	for distance_offset: float in [0.0, 4.0, 8.0, 12.0]:
		for lateral: float in [0.0, 2.5, -2.5, 5.0, -5.0]:
			var candidate: Transform3D = _track_transform(s + distance_offset, lateral, 0.25)
			query.transform = candidate.translated(Vector3.UP * 1.1)
			if space_state.intersect_shape(query, 1).is_empty():
				return candidate
	return _track_transform(s)


func _respawn(s: float) -> void:
	_cart.global_transform = _safe_respawn_transform(s)
	_cart.call("reset_for_respawn")
	_cart.velocity = Vector3.ZERO
	_cart.max_speed = _base_max_speed
	var rig: Node = _cart.get_node_or_null("CameraArm")
	if rig != null:
		rig.call("reset_camera")
	_skip_progress = true
	_off_timer = 0.0
	_toast("BACK ON TRACK", 1.3)


func _complete_lap() -> void:
	var lap_time: float = _race_time - _lap_start
	_lap_times.append(lap_time)
	_lap_start = _race_time
	_sector_flags = 0
	_lap += 1
	if _lap > _total_laps:
		_finish()
		return
	_hud.call("set_lap", _lap, _total_laps)
	_toast("LAP %d / %d   ·   %s" % [_lap, _total_laps, _format_time(lap_time)], 2.0)
	_flash_gate(0)
	if _effects != null:
		_effects.call("lap_burst")
	_play_one_shot(LAP_CHIME, -8.0, 1.0)


func _finish() -> void:
	_phase = Phase.FINISHED
	if Network.is_host:
		Network.set_room_state("finished")
	if _cart != null:
		_cart.set_physics_process(false)
		_cart.velocity = Vector3.ZERO
		_cart.max_speed = _base_max_speed
		# A finished cart must not be a solid obstacle for players still
		# crossing the line, and the host solver must skip it too.
		_cart.collision_layer = 0
		_cart.contact_enabled = false
	# Stop steering the rivals too; otherwise they keep their last AI inputs
	# and drive into the barriers behind the result card.
	for rival: Dictionary in _rivals:
		var rival_node: CartPlayer = rival["node"]
		if is_instance_valid(rival_node):
			rival_node.set_ai_controls(0.0, 0.35, 0.0)
	# Publish the final progress exactly once so every peer's placement is
	# correct even after this cart stops streaming state. This used to sit
	# inside the rival loop: with bots OFF the packet was never sent, and with
	# bots ON it was sent once per rival.
	if _cart != null and _multiplayer and Network.is_session_active() \
			and Network.is_connected_to_server():
		if _is_host:
			_broadcast_race_state(multiplayer.get_unique_id(),
				_cart.global_position, _cart.rotation.y, _unwrapped,
				Time.get_ticks_msec(), _cart.velocity)
		else:
			rpc_id(1, "_net_race_cart_state", multiplayer.get_unique_id(),
				_cart.global_position, _cart.rotation.y, _unwrapped,
				Time.get_ticks_msec(), _cart.velocity)
	CursorController.set_menu_mode(true)
	_offtrack_label.visible = false

	var place: int = _place()
	var suffix: String = _ordinal(place)
	var best: float = _best_lap_time()
	_result_title.text = "YOU WIN!" if place == 1 \
		else ("ON THE PODIUM!" if place <= 3 else "FINISHED")
	_result_total.text = _format_time(_race_time) if not _lap_times.is_empty() else "—"
	_result_best.text = _format_time(best) if best >= 0.0 else "—"
	_result_place.text = "%s / %d" % [suffix, _field_size()]
	_result_laps.text = "%d / %d" % [mini(_lap_times.size(), _total_laps), _total_laps]
	_fill_result_laps()
	_result_standings_section.visible = _multiplayer
	if _multiplayer:
		_refresh_result_standings()
	_result_root.visible = true
	_result_root.modulate.a = 0.0
	var fade := create_tween()
	fade.tween_property(_result_root, "modulate:a", 1.0, 0.22) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	_hud.call("set_race_time", _race_time, best)
	_hud.call("set_lap", _total_laps, _total_laps)
	var pause_open: bool = false
	var pause_menu: Control = get_node_or_null("PauseMenu/Root") as Control
	if pause_menu != null and pause_menu.visible:
		pause_open = true
		_result_root.remove_from_group("nav_scope")
	var menu_nav: Node = get_node_or_null("/root/MenuNav")
	if menu_nav != null:
		menu_nav.call("refresh")
	if not pause_open and _result_primary != null:
		pass
	if _effects != null:
		_effects.call("lap_burst")
	_play_one_shot(FINISH_FANFARE, -6.0, 1.0)


func _start_ambience() -> void:
	_ambient_audio = AudioStreamPlayer.new()
	var ambience: AudioStream = FOREST_AMBIENCE
	if ambience is AudioStreamMP3:
		(ambience as AudioStreamMP3).loop = true
	_ambient_audio.stream = ambience
	_ambient_audio.bus = "SFX"
	_ambient_audio.volume_db = -34.0
	add_child(_ambient_audio)
	_ambient_audio.play()
	var tween := create_tween()
	tween.tween_property(_ambient_audio, "volume_db", -23.0, 1.4)


func _play_one_shot(stream: AudioStream, volume_db: float, pitch: float) -> void:
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = "SFX"
	player.volume_db = volume_db
	player.pitch_scale = pitch
	add_child(player)
	player.play()
	player.finished.connect(player.queue_free)


func _format_time(seconds: float) -> String:
	var minutes: int = int(seconds) / 60
	var remainder: float = fmod(seconds, 60.0)
	return "%d:%s" % [minutes, ("%.3f" % remainder).lpad(6, "0")]


func _ordinal(place: int) -> String:
	var suffix: String = "th"
	if place % 100 < 11 or place % 100 > 13:
		match place % 10:
			1: suffix = "st"
			2: suffix = "nd"
			3: suffix = "rd"
	return "%d%s" % [place, suffix]


# --------------------------------------------------------------------------
# navigation


func _on_race_again() -> void:
	if _multiplayer:
		return
	SceneLoader.go_to(RACE_SCENE, "MEADOW LOOP", "GET READY")


func _on_back_to_lobby() -> void:
	if _multiplayer:
		Network.return_to_lobby_keep_session()
	else:
		SceneLoader.go_to(MINIGAMES_MENU, "MINIGAMES", "PICK AN EVENT")


func _on_main_menu() -> void:
	if Network.is_session_active():
		Network.leave()
	SceneLoader.go_to(MAIN_MENU, "MAIN MENU")
