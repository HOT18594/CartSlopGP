extends Node3D
## MEADOW LOOP - a solo 3-lap race on a winding dirt track through a dense,
## low-poly grassy forest. Built at runtime from one closed Catmull-Rom spline.
##
## Pipeline:
##   spline -> road ribbon + curbs + invisible barrier walls + ground plane
##          -> start/finish line + four sector gates
##          -> Kenney Nature Kit foliage, merged into one MultiMesh per model
##          -> three ghost rivals that chase the same centreline
##          -> lap/sector tracking, countdown, HUD badges and a candy result card
##
## The kart, chase camera, boost, drift, HUD and pause menu are the same ones
## the sandbox uses. Nothing here touches multiplayer.

const TrackSpline := preload("res://scripts/minigames/track_spline.gd")
const CART_SCENE := preload("res://scenes/player/cart_player.tscn")
const VehicleCatalog := preload("res://scripts/vehicles/vehicle_catalog.gd")
const FoliageBaker := preload("res://scripts/minigames/foliage_baker.gd")
const RaceScenery := preload("res://scripts/minigames/race_scenery.gd")
const RaceEffects := preload("res://scripts/minigames/race_effects.gd")
const VehicleVisual := preload("res://scripts/vehicles/vehicle_visual.gd")
const UiPalette := preload("res://scripts/ui/ui_palette.gd")

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
const CONFIRM_SOUND: String = "res://assets/audio/sfx/ui/ui_confirm.ogg"
const NET_SYNC_INTERVAL: float = 0.05

const TOTAL_LAPS: int = 3
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

const RIVAL_KARTS: PackedStringArray = ["kart-oobi", "kart-oodi", "kart-ooli"]
const RIVAL_SPEEDS: Array[float] = [11.6, 12.4, 13.2]
const RIVAL_LATERAL: Array[float] = [-2.6, 2.6, 0.0]
const RIVAL_NAMES: PackedStringArray = ["BEEP", "POPPY", "TURBO"]
const RIVAL_COLORS: Array[Color] = [
	Color("45b6f0"), Color("f26ca7"), Color("ffd22e"),
]

enum Phase { COUNTDOWN, RACING, FINISHED }

var _spline: RefCounted
var _cart: CartPlayer
var _hud: Node
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

var _phase: Phase = Phase.COUNTDOWN
var _countdown: float = 3.0
var _go_time: float = 0.0
var _last_count: int = 0
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
var _base_max_speed: float = 19.0
var _saved_vehicle: String = ""
var _toast_timer: float = 0.0
var _multiplayer: bool = false
var _is_host: bool = false
var _remote_carts: Dictionary = {}
var _peer_vehicles: Dictionary = {}
var _name_labels: Dictionary = {}
var _remote_progress: Dictionary = {}
var _net_sync_timer: float = 0.0

var _canvas: CanvasLayer
var _countdown_label: Label
var _toast_label: Label
var _offtrack_label: Label
var _result_root: Control
var _result_title: Label
var _result_stats: Label


# --------------------------------------------------------------------------
# lifecycle


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
	_foliage_material = FoliageBaker.make_material()
	CursorController.set_menu_mode(false)
	_upgrade_graphics()

	_cart = get_tree().get_first_node_in_group("player") as CartPlayer
	_hud = $HUD
	# The result card is built below, so decide the session type first. Without
	# this, multiplayer showed RACE AGAIN (which is a no-op) and BACK TO HUB.
	_multiplayer = Network.is_session_active()
	_is_host = Network.is_host
	if _cart != null:
		_base_max_speed = _cart.max_speed
		_last_cart_pos = _cart.global_position

	_build_ground()
	_build_track()
	_build_barriers()
	_build_start_line()
	_build_gates()
	_build_start_lights()
	_build_boost_pads()
	_build_grid()
	_build_scenery()
	_build_trackside_props()
	_build_rivals()
	_build_overlay()

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
		if Network.is_session_active():
			_setup_multiplayer()

	_hud.call("set_lap", 1, TOTAL_LAPS)
	_hud.call("set_race_position", 1)
	_countdown_label.text = "3"
	_toast("MEADOW LOOP  ·  3 LAPS", 2.2)


func _upgrade_graphics() -> void:
	# MEADOW LOOP is the deliberately heavy scene: 4x MSAA, filmic tonemapping,
	# gentle bloom and contrast. Everything here is viewport-local, so the
	# sandbox and the menus keep their cheaper settings.
	var viewport: Viewport = get_viewport()
	if viewport != null:
		viewport.msaa_3d = Viewport.MSAA_4X
	var world: WorldEnvironment = $WorldEnvironment
	var env: Environment = world.environment
	if env != null:
		env.tonemap_mode = Environment.TONE_MAPPER_ACES
		env.tonemap_exposure = 1.05
		env.glow_enabled = true
		env.glow_intensity = 0.35
		env.glow_bloom = 0.12
		env.glow_hdr_threshold = 1.05
		env.adjustment_enabled = true
		env.adjustment_saturation = 1.10
		env.adjustment_contrast = 1.04
	var sun: DirectionalLight3D = $Sun
	sun.directional_shadow_max_distance = 165.0
	sun.light_energy = 1.28


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
		"grass_diff", "grass_nor", "grass_rough", GROUND_X / 7.0,
		Color(1.06, 1.10, 0.98), 0.18, 0.075)
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


func _pbr_material(diff: String, nor: String, rough: String, uv_scale: float,
		tint: Color, detail: float, macro: float) -> ShaderMaterial:
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
	return mat


func _build_track() -> void:
	var steps: int = int(ceil(_spline.total_length / ROAD_STEP))

	# Dirt road ribbon. V is arc length / 5 m so the texture tiles along it.
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
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

	var road := ArrayMesh.new()
	road.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES,
		_make_arrays(verts, norms, uvs, PackedColorArray(), indices))
	var road_mesh := MeshInstance3D.new()
	road_mesh.name = "DirtTrack"
	road_mesh.mesh = road
	road_mesh.material_override = _pbr_material(
		"dirt_diff", "dirt_nor", "dirt_rough", 1.0,
		Color(1.0, 0.96, 0.88), 0.24, 0.035)
	add_child(road_mesh)

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
	var beam_mat := StandardMaterial3D.new()
	beam_mat.albedo_color = color
	beam_mat.roughness = 1.0

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


func _build_start_lights() -> void:
	# A five-lamp gantry just ahead of the grid. The countdown drives it:
	# red pairs light up on 3 / 2 / 1, all five snap green on GO.
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
	bar_box.size = Vector3(ROAD_HALF * 2.0 + 1.9, 0.62, 0.3)
	bar.mesh = bar_box
	bar.position = Vector3(0.0, 5.62, 0.0)
	var bar_mat := StandardMaterial3D.new()
	bar_mat.albedo_color = Color(0.16, 0.18, 0.29, 1)
	bar.material_override = bar_mat
	rig.add_child(bar)
	for i in 5:
		var lamp := MeshInstance3D.new()
		var sphere := SphereMesh.new()
		sphere.radius = 0.27
		sphere.height = 0.54
		lamp.mesh = sphere
		# +Z faces the approaching grid; the lamps must be on the near side of
		# the beam or the whole gantry reads as one blank black bar.
		lamp.position = Vector3((float(i) - 2.0) * 0.62, 5.55, 0.24)
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
		pad.transform = _track_transform(distance, lateral, 0.03)
		holder.add_child(pad)


func _build_trackside_props() -> void:
	# Real interactions: cones on the racing line that the kart's PushSensor
	# launches with p = m*v. They are in the "pushable" group so they never
	# slow the kart down, but they do fly, spin and rattle.
	var cone: PackedScene = load(CONE_MODEL) as PackedScene
	if cone == null:
		return
	var holder := Node3D.new()
	holder.name = "TrackCones"
	add_child(holder)
	var rng := RandomNumberGenerator.new()
	rng.seed = 5511
	for i in 34:
		var distance: float = _spline.total_length * rng.randf()
		if absf(fposmod(distance - START_DISTANCE, _spline.total_length)) < 26.0:
			continue # keep the grid clear
		var lateral: float = rng.randf_range(-3.6, 3.6)
		var body := RigidBody3D.new()
		body.add_to_group("pushable")
		body.collision_layer = 4
		body.collision_mask = 5
		body.mass = 0.4
		body.transform = _track_transform(distance, lateral, 0.02)
		var model: Node3D = cone.instantiate() as Node3D
		model.scale = Vector3.ONE * 0.72
		body.add_child(model)
		var shape := BoxShape3D.new()
		shape.size = Vector3(0.45, 0.62, 0.45)
		var collision := CollisionShape3D.new()
		collision.shape = shape
		collision.position = Vector3(0, 0.31, 0)
		body.add_child(collision)
		holder.add_child(body)


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
	# The flat-shaded Kenney forest now only fills the far field: realistic PBR
	# trees own the verge (see RaceScenery), so these stay behind them for cheap
	# depth and a solid horizon.
	_scatter(rng, TREES, 1500, 34.0, 3.0, 6.6, false, "FarForest", true)
	_scatter(rng, BUSHES, 620, 24.0, 1.3, 2.8, false, "FarUnderbrush", true)
	_scatter(rng, GRASSES, 1500, 7.4, 0.9, 2.1, false, "GrassClumps")
	_scatter(rng, FLOWERS, 500, 7.4, 0.8, 1.6, false, "Wildflowers")
	_scatter(rng, ROCKS, 340, 9.0, 0.8, 2.2, false, "Rocks")
	_scatter(rng, WOODLAND, 240, 10.0, 1.0, 2.0, false, "WoodlandProps")
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


func _build_rivals() -> void:
	for i in RIVAL_KARTS.size():
		var rival := Node3D.new()
		rival.name = "Rival_" + RIVAL_NAMES[i]
		var entry: Dictionary = {
			"scene": KART_ROOT + RIVAL_KARTS[i] + ".glb",
			"length": 1.9,
			"yaw": 180.0,
		}
		rival.add_child(VehicleVisual.build(entry))
		var body := StaticBody3D.new()
		body.collision_layer = 8
		body.collision_mask = 0
		body.set_meta("vehicle_mass", 900.0)
		body.set_meta("bump_velocity", Vector3.ZERO)
		var shape := CollisionShape3D.new()
		var box := BoxShape3D.new()
		box.size = Vector3(1.7, 1.2, 2.2)
		shape.shape = box
		shape.position = Vector3(0.0, 0.65, 0.0)
		body.add_child(shape)
		rival.add_child(body)
		var label := Label3D.new()
		label.text = RIVAL_NAMES[i]
		label.font = load(TITLE_FONT)
		label.font_size = 56
		label.pixel_size = 0.011
		label.outline_size = 16
		label.outline_modulate = UiPalette.OUTLINE
		label.modulate = RIVAL_COLORS[i]
		label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
		label.no_depth_test = true
		label.position = Vector3(0.0, 2.2, 0.0)
		rival.add_child(label)

		# Each rival kicks up its own small dust plume so the field feels alive.
		var dust := GPUParticles3D.new()
		dust.amount = 18
		dust.lifetime = 0.8
		dust.local_coords = false
		dust.visibility_aabb = AABB(Vector3(-6, -2, -6), Vector3(12, 6, 12))
		var proc := ParticleProcessMaterial.new()
		proc.direction = Vector3(0, 1, 0.4)
		proc.spread = 32.0
		proc.initial_velocity_min = 0.6
		proc.initial_velocity_max = 1.8
		proc.gravity = Vector3(0, 0.7, 0)
		proc.scale_min = 0.35
		proc.scale_max = 0.9
		proc.color = Color(0.84, 0.74, 0.58, 0.7)
		dust.process_material = proc
		var quad := QuadMesh.new()
		quad.size = Vector2(0.4, 0.4)
		var dust_mat := StandardMaterial3D.new()
		dust_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		dust_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		dust_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		dust_mat.albedo_texture = load("res://assets/textures/foliage/dust_puff.png")
		quad.material = dust_mat
		dust.draw_pass_1 = quad
		dust.position = Vector3(0, 0.12, 0.7)
		dust.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		rival.add_child(dust)

		add_child(rival)
		_rivals.append({
			"node": rival,
			"body": body,
			"label": label,
			"dust": dust,
			"progress": START_DISTANCE + 6.0 + float(i) * 6.0,
			"speed": RIVAL_SPEEDS[i],
			"lateral": RIVAL_LATERAL[i],
			"bump": Vector3.ZERO,
		})
		_place_rival(i)


func _place_rival(index: int) -> void:
	var rival: Dictionary = _rivals[index]
	var node: Node3D = rival["node"]
	var progress: float = rival["progress"]
	var frame: Dictionary = _spline.sample(progress)
	var ahead: float = _spline.yaw_at(progress + 3.0)
	var yaw: float = _spline.yaw_at(progress)
	node.global_position = frame["position"] \
		+ frame["right"] * float(rival["lateral"]) \
		+ Vector3.UP * (0.05 + sin(_race_time * 7.0 + float(index)) * 0.025) \
		+ (rival["bump"] as Vector3)
	node.rotation.y = yaw
	# Lean into the corner, with a little springy body roll.
	var turn: float = clampf(angle_difference(yaw, ahead) * 3.2, -0.24, 0.24)
	node.rotation.z = lerpf(node.rotation.z, turn, 0.08)
	node.rotation.x = sin(_race_time * 9.0 + float(index) * 2.1) * 0.015
	var label: Label3D = rival["label"]
	var pulse: float = 1.0 + 0.06 * sin(_race_time * 3.4 + float(index))
	label.scale = Vector3.ONE * pulse
	var dust: GPUParticles3D = rival["dust"]
	var stopped: bool = is_equal_approx(progress,
		START_DISTANCE + float(TOTAL_LAPS) * _spline.total_length)
	dust.emitting = not stopped


func _tick_rivals(delta: float) -> void:
	var limit: float = START_DISTANCE + float(TOTAL_LAPS) * _spline.total_length
	for i in _rivals.size():
		var progress: float = minf(float(_rivals[i]["progress"])
			+ float(_rivals[i]["speed"]) * delta, limit)
		_rivals[i]["progress"] = progress
		var body: StaticBody3D = _rivals[i]["body"]
		var bump: Vector3 = body.get_meta("bump_velocity", Vector3.ZERO)
		var offset: Vector3 = _rivals[i]["bump"]
		offset += bump * delta
		offset = offset.move_toward(Vector3.ZERO, 6.0 * delta)
		bump = bump.move_toward(Vector3.ZERO, 9.0 * delta)
		body.set_meta("bump_velocity", bump)
		_rivals[i]["bump"] = offset
		_place_rival(i)


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
	_offtrack_label.text = "OFF TRACK  ·  GET BACK ON THE DIRT"
	_offtrack_label.visible = false

	_result_root = Control.new()
	_result_root.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_root.mouse_filter = Control.MOUSE_FILTER_STOP
	_result_root.visible = false
	root.add_child(_result_root)

	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.06, 0.09, 0.19, 0.62)
	_result_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_result_root.add_child(center)

	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(560, 0)
	center.add_child(panel)

	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 12)
	panel.add_child(body)

	var flag := Control.new()
	flag.custom_minimum_size = Vector2(190, 44)
	flag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	flag.set_script(load(CHECKER_FLAG))
	body.add_child(flag)

	_result_title = Label.new()
	_result_title.theme_type_variation = &"TitleLabel"
	_result_title.add_theme_font_size_override("font_size", 52)
	_result_title.add_theme_color_override("font_color", UiPalette.YELLOW)
	_result_title.add_theme_color_override("font_outline_color", UiPalette.OUTLINE)
	_result_title.add_theme_constant_override("outline_size", 12)
	_result_title.text = "YOU WIN!"
	_result_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_result_title)

	_result_stats = Label.new()
	_result_stats.add_theme_font_size_override("font_size", 19)
	_result_stats.add_theme_color_override("font_color", UiPalette.INK)
	_result_stats.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_result_stats.text = ""
	body.add_child(_result_stats)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 6)
	body.add_child(spacer)

	var again: Button = _make_button("RACE AGAIN", UiPalette.YELLOW)
	again.pressed.connect(_on_race_again)
	body.add_child(again)
	var lobby: Button = _make_button("BACK TO LOBBY", UiPalette.GRASS)
	lobby.pressed.connect(_on_back_to_lobby)
	body.add_child(lobby)
	var menu: Button = _make_button("MAIN MENU", UiPalette.RED)
	menu.pressed.connect(_on_main_menu)
	body.add_child(menu)
	if _multiplayer:
		# Restarting only one peer would desync the field.
		again.visible = false
		lobby.text = "BACK TO LOBBY"
	else:
		lobby.text = "BACK TO HUB"


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


func _make_button(text: String, color: Color) -> Button:
	var button := Button.new()
	button.set_script(load(CANDY_BUTTON))
	button.set("fill_color", color)
	button.text = text
	button.custom_minimum_size = Vector2(0, 52)
	button.add_theme_font_size_override("font_size", 22)
	return button


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
	_peer_vehicles[multiplayer.get_unique_id()] = GameSettings.minigame_vehicle
	_place_local_on_grid()
	for peer_id: int in multiplayer.get_peers():
		_spawn_remote(peer_id)
	multiplayer.peer_connected.connect(_on_net_peer_connected)
	multiplayer.peer_disconnected.connect(_on_net_peer_disconnected)
	Network.names_changed.connect(_refresh_net_names)
	if _is_host:
		rpc("_net_race_vehicle", multiplayer.get_unique_id(), GameSettings.minigame_vehicle)
	else:
		rpc("_net_race_ready", GameSettings.minigame_vehicle)


func _place_local_on_grid() -> void:
	if _cart == null:
		return
	var ids: Array[int] = Network.participants()
	var index: int = maxi(ids.find(multiplayer.get_unique_id()), 0)
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
	var cart: CartPlayer = _remote_carts.get(peer_id)
	if cart != null:
		cart.queue_free()
		_remote_carts.erase(peer_id)
	_peer_vehicles.erase(peer_id)
	_name_labels.erase(peer_id)
	_remote_progress.erase(peer_id)


func _spawn_remote(peer_id: int) -> void:
	if _remote_carts.has(peer_id) or peer_id == multiplayer.get_unique_id():
		return
	var cart: CartPlayer = CART_SCENE.instantiate() as CartPlayer
	add_child(cart)
	cart.setup_remote(peer_id)
	var ids: Array[int] = Network.participants()
	var index: int = maxi(ids.find(peer_id), 0)
	var row: int = index / 2
	var column: int = index % 2
	cart.global_transform = _track_transform(START_DISTANCE - float(row) * 4.5,
		-2.6 + float(column) * 5.2)
	cart.net_position = cart.global_position
	cart.net_yaw = cart.rotation.y
	if _peer_vehicles.has(peer_id):
		cart.set_vehicle_id(str(_peer_vehicles[peer_id]))
	var label := Label3D.new()
	label.text = Network.name_of(peer_id)
	label.font = load(TITLE_FONT)
	label.font_size = 56
	label.pixel_size = 0.011
	label.outline_size = 16
	label.outline_modulate = UiPalette.OUTLINE
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


@rpc("any_peer", "reliable")
func _net_race_ready(vehicle_id: String) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if OS.get_environment("CART_DEBUG_NET") == "1":
		print("RACE_NET ready from=", sender, " vehicle=", vehicle_id)
	if sender <= 1 or sender == multiplayer.get_unique_id():
		return
	_store_net_vehicle(sender, vehicle_id)
	if not _is_host:
		return
	rpc("_net_race_vehicle", sender, vehicle_id)
	for peer_id: Variant in _peer_vehicles.keys():
		rpc_id(sender, "_net_race_vehicle", int(peer_id), str(_peer_vehicles[peer_id]))


@rpc("authority", "reliable")
func _net_race_vehicle(peer_id: int, vehicle_id: String) -> void:
	_store_net_vehicle(peer_id, vehicle_id)


func _store_net_vehicle(peer_id: int, vehicle_id: String) -> void:
	if OS.get_environment("CART_DEBUG_NET") == "1":
		print("RACE_NET store peer=", peer_id, " vehicle=", vehicle_id)
	if VehicleCatalog.find(vehicle_id).is_empty():
		return
	_peer_vehicles[peer_id] = vehicle_id
	var cart: CartPlayer = _remote_carts.get(peer_id)
	if cart != null:
		cart.set_vehicle_id(vehicle_id)


@rpc("any_peer", "unreliable")
func _net_race_cart_state(peer_id: int, position: Vector3, yaw: float, progress: float) -> void:
	var sender: int = multiplayer.get_remote_sender_id()
	if sender != 1 and peer_id != sender:
		return
	var cart: CartPlayer = _remote_carts.get(peer_id)
	if cart != null and cart.remote_mode:
		cart.net_position = position
		cart.net_yaw = yaw
		_remote_progress[peer_id] = clampf(progress, 0.0,
			float(TOTAL_LAPS + 1) * _spline.total_length)
	if _is_host and sender != 1:
		rpc("_net_race_cart_state", peer_id, position, yaw, progress)


# --------------------------------------------------------------------------
# race loop


func _process(delta: float) -> void:
	if _toast_timer > 0.0:
		_toast_timer -= delta
		if _toast_timer <= 0.0:
			_toast_label.visible = false
	if _multiplayer and _cart != null and _phase != Phase.FINISHED \
			and Network.is_session_active() and Network.is_connected_to_server():
		_net_sync_timer += delta
		if _net_sync_timer >= NET_SYNC_INTERVAL:
			_net_sync_timer = 0.0
			rpc("_net_race_cart_state", multiplayer.get_unique_id(),
				_cart.global_position, _cart.rotation.y, _unwrapped)
	match _phase:
		Phase.COUNTDOWN:
			_tick_countdown(delta)
		Phase.RACING:
			_tick_race(delta)
		Phase.FINISHED:
			pass


func _tick_countdown(delta: float) -> void:
	if _countdown > 0.0:
		_countdown -= delta
		var count: int = int(ceil(maxf(_countdown, 0.0)))
		if count != _last_count:
			_last_count = count
			_countdown_label.text = str(count) if count > 0 else "GO!"
			_pop_label(_countdown_label)
			_set_start_lights([0, 2, 4, 5][clampi(3 - count, 0, 3)], false)
		return
	if not _go_shown:
		_go_shown = true
		_countdown_label.text = "GO!"
		_countdown_label.add_theme_color_override("font_color", UiPalette.GRASS)
		_pop_label(_countdown_label)
		_set_start_lights(5, true)
		_flash_gate(0)
	_go_time += delta
	if _go_time >= 0.7:
		_countdown_label.visible = false
		_phase = Phase.RACING
		if _cart != null:
			_cart.set_physics_process(true)
		_toast("GO!", 1.0)


func _tick_race(delta: float) -> void:
	_race_time += delta
	if _cart == null:
		return

	var info: Dictionary = _spline.closest(_cart.global_position)
	var s: float = info["s"]
	var distance: float = info["distance"]

	# A reset (R) or a respawn is a teleport: resync, never bank the jump.
	if _cart.global_position.distance_squared_to(_last_cart_pos) > 100.0:
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
	if _unwrapped >= float(_lap) * _spline.total_length and _sector_flags == 0b1111:
		_complete_lap()

	# Barriers do the real work; this is a fallback for anything that slips out.
	var off: bool = distance > ROAD_HALF + 1.2
	if off:
		_off_timer += delta
		_offtrack_label.visible = true
		_cart.max_speed = _base_max_speed * 0.55
		if _off_timer > 3.0 or distance > 32.0:
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

	_tick_rivals(delta)
	_hud.call("set_lap", mini(_lap, TOTAL_LAPS), TOTAL_LAPS)
	_hud.call("set_race_position", _place())


func _respawn(s: float) -> void:
	_cart.global_transform = _track_transform(s)
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
	if _lap > TOTAL_LAPS:
		_finish()
		return
	_hud.call("set_lap", _lap, TOTAL_LAPS)
	_toast("LAP %d / %d   ·   %s" % [_lap, TOTAL_LAPS, _format_time(lap_time)], 2.0)
	_flash_gate(0)
	if _effects != null:
		_effects.call("lap_burst")
	_play_confirm()


func _finish() -> void:
	_phase = Phase.FINISHED
	if _cart != null:
		_cart.set_physics_process(false)
		_cart.velocity = Vector3.ZERO
		_cart.max_speed = _base_max_speed
		# Publish the final progress once so every peer's placement is correct
		# even after this cart stops streaming state.
		if _multiplayer and Network.is_session_active() and Network.is_connected_to_server():
			rpc("_net_race_cart_state", multiplayer.get_unique_id(),
				_cart.global_position, _cart.rotation.y, _unwrapped)
	CursorController.set_menu_mode(true)
	_offtrack_label.visible = false

	var best: float = _lap_times[0] if not _lap_times.is_empty() else 0.0
	for time: float in _lap_times:
		best = minf(best, time)
	var place: int = _place()
	var suffix: String = _ordinal(place)
	_result_title.text = "YOU WIN!" if place == 1 \
		else ("ON THE PODIUM!" if place <= 3 else "FINISHED")
	var lines: PackedStringArray = [
		"TOTAL  %s" % _format_time(_race_time),
		"BEST LAP  %s" % _format_time(best),
		"FINISHED  %s OF %d" % [suffix, _field_size()],
		"",
	]
	for i in _lap_times.size():
		lines.append("LAP %d  %s" % [i + 1, _format_time(_lap_times[i])])
	_result_stats.text = "\n".join(lines)
	_result_root.visible = true
	_hud.call("set_lap", TOTAL_LAPS, TOTAL_LAPS)
	if _effects != null:
		_effects.call("lap_burst")
	_play_confirm()


func _play_confirm() -> void:
	var stream: AudioStream = load(CONFIRM_SOUND) as AudioStream
	if stream == null:
		return
	var player := AudioStreamPlayer.new()
	player.stream = stream
	player.bus = "SFX"
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
