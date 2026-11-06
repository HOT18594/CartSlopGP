extends Node3D
## MEADOW LOOP waiting room.
##
## A live 3D preview (PBR ground, procedural PBR trees, drifting leaves and a
## slowly orbiting camera) sits behind the candy UI. Three ghost rivals "join"
## one by one, the player readies up, then a 3-2-1-GO countdown sends everyone
## into the race through SceneLoader. Entirely solo - no network session.

const RealisticTree := preload("res://scripts/minigames/realistic_tree.gd")
const FoliageBaker := preload("res://scripts/minigames/foliage_baker.gd")
const VehicleCatalog := preload("res://scripts/vehicles/vehicle_catalog.gd")
const UiPalette := preload("res://scripts/ui/ui_palette.gd")

const RACE_SCENE: String = "res://scenes/minigames/grass_race.tscn"
const MINIGAMES_MENU: String = "res://scenes/ui/minigames_menu.tscn"
const PBR_SHADER: String = "res://assets/materials/ground_pbr.gdshader"
const WIND_SHADER: String = "res://assets/materials/foliage_wind.gdshader"
const TEX: String = "res://assets/textures/polyhaven/"
const CARD: String = "res://assets/textures/foliage/"
const CANDY_BUTTON: String = "res://scripts/ui/candy_button.gd"
const CHECKER_FLAG: String = "res://scripts/ui/checker_flag.gd"

const RIVAL_NAMES: PackedStringArray = ["BEEP", "POPPY", "TURBO"]
const RIVAL_COLORS: Array[Color] = [
	Color("45b6f0"), Color("f26ca7"), Color("ffd22e"),
]
const STATUS_LINES: PackedStringArray = [
	"Waiting in the meadow...",
	"BEEP is checking its tyres.",
	"POPPY brought snacks.",
	"TURBO is revving something.",
	"Track is dry. 3 laps to win.",
]

enum State { WAITING, STARTING, LEAVING }

var _state: State = State.WAITING
var _time: float = 0.0
var _joined: int = 0
var _join_timer: float = 0.0
var _player_ready: bool = false
var _status_index: int = 0
var _status_timer: float = 0.0
var _countdown: float = 0.0
var _countdown_step: int = 0

var _camera: Camera3D
var _root: Control
var _panel: PanelContainer
var _name_edit: LineEdit
var _vehicle_label: Label
var _ready_button: Button
var _start_button: Button
var _status_label: Label
var _countdown_label: Label
var _rows: Array[Dictionary] = []
var _leaf_sprites: Array[Dictionary] = []


func _ready() -> void:
	CursorController.set_menu_mode(true)
	_camera = $PreviewCamera
	_root = $UI/Root
	get_viewport().msaa_3d = Viewport.MSAA_4X
	_build_preview()
	_build_ui()
	_status_label.text = STATUS_LINES[0]


func _process(delta: float) -> void:
	_time += delta
	_orbit_camera()
	_animate_leaves(delta)
	if _state == State.WAITING:
		_tick_joining(delta)
		_tick_status(delta)
	elif _state == State.STARTING:
		_tick_countdown(delta)


# --------------------------------------------------------------------------
# live 3D preview


func _build_preview() -> void:
	var preview: Node3D = $PreviewRoot
	var plane := PlaneMesh.new()
	plane.size = Vector2(190, 190)
	var ground := MeshInstance3D.new()
	ground.mesh = plane
	ground.material_override = _pbr("grass_diff", "grass_nor", "grass_rough",
		26.0, Color(1.05, 1.09, 0.98))
	preview.add_child(ground)

	var road := MeshInstance3D.new()
	road.mesh = _arc_ribbon()
	road.material_override = _pbr("dirt_diff", "dirt_nor", "dirt_rough",
		1.0, Color(1.0, 0.96, 0.88))
	preview.add_child(road)

	var leaf_broad := _wind("leaf_broad", Color(0.93, 1.0, 0.88), 9.0, 0.26)
	var leaf_frond := _wind("leaf_frond", Color(0.68, 0.88, 0.64), 11.0, 0.30)
	var bark := _bark("bark_diff", "bark_nor")
	var pine := _bark("pinebark_diff", "pinebark_nor")
	var builder := RealisticTree.new()
	var rng := RandomNumberGenerator.new()
	rng.seed = 3311
	var buckets: Dictionary = {}
	for v in RealisticTree.variant_count():
		buckets[v] = []
	for i in 30:
		var angle: float = rng.randf() * TAU
		var radius: float = rng.randf_range(27.0, 68.0)
		var variant: int = rng.randi_range(0, RealisticTree.variant_count() - 1)
		var scale: float = rng.randf_range(0.8, 1.35)
		buckets[variant].append(Transform3D(
			Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * scale),
			Vector3(cos(angle) * radius, 0.02, sin(angle) * radius)))
	for variant: int in buckets:
		var transforms: Array = buckets[variant]
		if transforms.is_empty():
			continue
		var tree: Dictionary = builder.build(variant, 880 + variant * 77)
		var frond: bool = str(tree["atlas"]) == "frond"
		preview.add_child(FoliageBaker.create_instances(
			tree["bark"], pine if frond else bark, transforms, true))
		preview.add_child(FoliageBaker.create_instances(
			tree["leaf"], leaf_frond if frond else leaf_broad, transforms, true))

	# A few drifting leaves in front of the camera.
	var leaves := GPUParticles3D.new()
	leaves.amount = 70
	leaves.lifetime = 8.0
	leaves.local_coords = false
	leaves.visibility_aabb = AABB(Vector3(-40, -4, -40), Vector3(80, 18, 80))
	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = Vector3(30, 6, 30)
	proc.direction = Vector3(0.5, -0.15, 0.2)
	proc.spread = 60.0
	proc.gravity = Vector3(0.5, -0.15, 0.1)
	proc.initial_velocity_min = 0.2
	proc.initial_velocity_max = 1.0
	proc.scale_min = 0.25
	proc.scale_max = 0.6
	proc.angular_velocity_min = -80.0
	proc.angular_velocity_max = 80.0
	proc.turbulence_enabled = true
	proc.turbulence_noise_strength = 0.8
	leaves.process_material = proc
	var quad := QuadMesh.new()
	quad.size = Vector2(0.4, 0.4)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.albedo_texture = load(CARD + "drifting_leaf.png")
	quad.material = mat
	leaves.draw_pass_1 = quad
	leaves.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	leaves.position = Vector3(0, 6, 0)
	preview.add_child(leaves)


func _arc_ribbon() -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	var indices := PackedInt32Array()
	var steps: int = 48
	for i in steps + 1:
		var t: float = float(i) / float(steps)
		var angle: float = lerpf(-0.9, 3.6, t)
		var radius: float = 17.0 + 3.0 * sin(t * PI)
		var centre := Vector3(cos(angle) * radius, 0.05, sin(angle) * radius)
		var tangent := Vector3(-sin(angle), 0, cos(angle)).normalized()
		var right := tangent.cross(Vector3.UP).normalized()
		verts.append(centre - right * 4.6)
		verts.append(centre + right * 4.6)
		norms.append(Vector3.UP)
		norms.append(Vector3.UP)
		uvs.append(Vector2(0, t * 22.0))
		uvs.append(Vector2(1, t * 22.0))
	for i in steps:
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
	return mesh


func _pbr(diff: String, nor: String, rough: String, uv_scale: float,
		tint: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(PBR_SHADER) as Shader
	mat.set_shader_parameter("albedo_tex", load(TEX + diff + ".jpg"))
	mat.set_shader_parameter("normal_tex", load(TEX + nor + ".jpg"))
	mat.set_shader_parameter("rough_tex", load(TEX + rough + ".jpg"))
	mat.set_shader_parameter("uv_scale", uv_scale)
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("detail_strength", 0.2)
	mat.set_shader_parameter("macro_variation", 0.07)
	mat.set_shader_parameter("roughness_min", 0.55)
	return mat


func _wind(card: String, tint: Color, height: float, strength: float) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(WIND_SHADER) as Shader
	mat.set_shader_parameter("card_tex", load(CARD + card + ".png"))
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("sway_height", height)
	mat.set_shader_parameter("wind_strength", strength)
	mat.set_shader_parameter("wind_speed", 1.1)
	mat.set_shader_parameter("alpha_cutoff", 0.42)
	mat.set_shader_parameter("bend_radius", 0.0)
	mat.set_shader_parameter("kart_position", Vector3(0, -1000, 0))
	return mat


func _bark(diff: String, nor: String) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(PBR_SHADER) as Shader
	mat.set_shader_parameter("albedo_tex", load(TEX + diff + ".jpg"))
	mat.set_shader_parameter("normal_tex", load(TEX + nor + ".jpg"))
	mat.set_shader_parameter("rough_tex", load(TEX + "grass_rough.jpg"))
	mat.set_shader_parameter("uv_scale", 1.0)
	mat.set_shader_parameter("detail_strength", 0.28)
	mat.set_shader_parameter("macro_variation", 0.03)
	mat.set_shader_parameter("roughness_min", 0.82)
	return mat


func _orbit_camera() -> void:
	var angle: float = 0.35 + _time * 0.055
	var radius: float = 37.0
	_camera.global_position = Vector3(
		sin(angle) * radius, 10.5 + sin(_time * 0.22) * 1.6, cos(angle) * radius)
	_camera.look_at(Vector3(0, 3.2, 0), Vector3.UP)
	_camera.fov = 58.0 + sin(_time * 0.3) * 1.5


# --------------------------------------------------------------------------
# UI


func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.color = Color(0.05, 0.09, 0.19, 0.36)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_root.add_child(dim)

	var center := CenterContainer.new()
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	_root.add_child(center)
	_panel = PanelContainer.new()
	_panel.custom_minimum_size = Vector2(860, 0)
	center.add_child(_panel)
	var body := VBoxContainer.new()
	body.add_theme_constant_override("separation", 10)
	_panel.add_child(body)

	var flag := Control.new()
	flag.custom_minimum_size = Vector2(170, 40)
	flag.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	flag.set_script(load(CHECKER_FLAG))
	body.add_child(flag)

	var title := Label.new()
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_size_override("font_size", 46)
	title.add_theme_color_override("font_color", UiPalette.YELLOW)
	title.add_theme_color_override("font_outline_color", UiPalette.OUTLINE)
	title.add_theme_constant_override("outline_size", 12)
	title.text = "MEADOW LOOP"
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(title)

	var subtitle := Label.new()
	subtitle.add_theme_font_size_override("font_size", 16)
	subtitle.add_theme_color_override("font_color", UiPalette.BLUE_DARK)
	subtitle.text = "WAITING ROOM   ·   3 LAPS   ·   YOU VS 3 GHOST RIVALS"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(subtitle)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 18)
	body.add_child(columns)

	# --- left: the player ---
	var left := _column(columns, "YOU")
	_name_edit = LineEdit.new()
	_name_edit.text = GameSettings.player_name
	_name_edit.max_length = 16
	_name_edit.placeholder_text = "YOUR NAME"
	_name_edit.custom_minimum_size = Vector2(0, 46)
	_name_edit.add_theme_font_size_override("font_size", 20)
	left.add_child(_name_edit)
	_vehicle_label = Label.new()
	var entry: Dictionary = VehicleCatalog.find(GameSettings.minigame_vehicle)
	_vehicle_label.text = "VEHICLE   " + str(entry.get("name", "SHOPPING CART"))
	_vehicle_label.add_theme_font_size_override("font_size", 15)
	_vehicle_label.add_theme_color_override("font_color", UiPalette.INK)
	left.add_child(_vehicle_label)
	_ready_button = _button("READY UP", UiPalette.YELLOW, 58, 24)
	_ready_button.pressed.connect(_on_ready_pressed)
	left.add_child(_ready_button)
	var hint := Label.new()
	hint.text = "Pick your vehicle on the MINIGAMES screen."
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	left.add_child(hint)

	# --- right: racer slots ---
	var right := _column(columns, "RACERS")
	_rows.append(_row(right, "YOU", UiPalette.YELLOW, "NOT READY"))
	for i in RIVAL_NAMES.size():
		_rows.append(_row(right, RIVAL_NAMES[i], RIVAL_COLORS[i], "JOINING..."))

	_status_label = Label.new()
	_status_label.custom_minimum_size = Vector2(0, 24)
	_status_label.add_theme_font_size_override("font_size", 16)
	_status_label.add_theme_color_override("font_color", UiPalette.BLUE_DARK)
	_status_label.text = "Waiting in the meadow..."
	_status_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.add_child(_status_label)

	_start_button = _button("START RACE", UiPalette.GRASS, 64, 28)
	_start_button.disabled = true
	_start_button.pressed.connect(_on_start_pressed)
	body.add_child(_start_button)
	var back := _button("BACK", UiPalette.RED, 48, 20)
	back.pressed.connect(_on_back_pressed)
	body.add_child(back)

	# Big countdown on top of everything.
	_countdown_label = Label.new()
	_countdown_label.set_anchors_preset(Control.PRESET_FULL_RECT)
	_countdown_label.theme_type_variation = &"TitleLabel"
	_countdown_label.add_theme_font_size_override("font_size", 150)
	_countdown_label.add_theme_color_override("font_color", UiPalette.YELLOW)
	_countdown_label.add_theme_color_override("font_outline_color", UiPalette.OUTLINE)
	_countdown_label.add_theme_constant_override("outline_size", 20)
	_countdown_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_countdown_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_countdown_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_countdown_label.pivot_offset = Vector2(640, 360)
	_countdown_label.visible = false
	_root.add_child(_countdown_label)

	# Drifting leaf stickers over the panel.
	var leaf_tex: Texture2D = load(CARD + "drifting_leaf.png")
	var rng := RandomNumberGenerator.new()
	rng.seed = 991
	for i in 11:
		var sprite := TextureRect.new()
		sprite.texture = leaf_tex
		sprite.mouse_filter = Control.MOUSE_FILTER_IGNORE
		sprite.modulate.a = 0.55
		var size: float = rng.randf_range(14.0, 30.0)
		sprite.custom_minimum_size = Vector2(size, size)
		sprite.size = Vector2(size, size)
		sprite.position = Vector2(rng.randf_range(0.0, 1280.0), rng.randf_range(-720.0, 0.0))
		_root.add_child(sprite)
		_leaf_sprites.append({
			"node": sprite,
			"speed": rng.randf_range(28.0, 70.0),
			"sway": rng.randf_range(12.0, 42.0),
			"phase": rng.randf() * TAU,
		})


func _column(parent: Control, caption: String) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.custom_minimum_size = Vector2(380, 0)
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", 9)
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0, 210)
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.97, 0.94, 0.85, 1)
	style.border_color = UiPalette.OUTLINE
	style.border_width_left = 3
	style.border_width_right = 3
	style.border_width_top = 3
	style.border_width_bottom = 3
	style.corner_radius_top_left = 16
	style.corner_radius_top_right = 16
	style.corner_radius_bottom_left = 16
	style.corner_radius_bottom_right = 16
	style.content_margin_left = 16
	style.content_margin_right = 16
	style.content_margin_top = 12
	style.content_margin_bottom = 12
	panel.add_theme_stylebox_override("panel", style)
	parent.add_child(panel)
	panel.add_child(box)
	var head := Label.new()
	head.theme_type_variation = &"TitleLabel"
	head.add_theme_font_size_override("font_size", 20)
	head.add_theme_color_override("font_color", UiPalette.INK)
	head.text = caption
	box.add_child(head)
	return box


func _row(parent: Control, text: String, color: Color, status: String) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var dot := Panel.new()
	dot.custom_minimum_size = Vector2(20, 20)
	var style := StyleBoxFlat.new()
	style.bg_color = Color("b9b2c9")
	style.corner_radius_top_left = 10
	style.corner_radius_top_right = 10
	style.corner_radius_bottom_left = 10
	style.corner_radius_bottom_right = 10
	dot.add_theme_stylebox_override("panel", style)
	row.add_child(dot)
	var name_label := Label.new()
	name_label.text = text
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_label.add_theme_font_size_override("font_size", 16)
	name_label.add_theme_color_override("font_color", UiPalette.INK)
	row.add_child(name_label)
	var status_label := Label.new()
	status_label.text = status
	status_label.add_theme_font_size_override("font_size", 13)
	status_label.add_theme_color_override("font_color", UiPalette.BLUE_DARK)
	row.add_child(status_label)
	return {"dot": dot, "status": status_label, "color": color, "style": style}


func _button(text: String, color: Color, height: int, font_size: int) -> Button:
	var button := Button.new()
	button.set_script(load(CANDY_BUTTON))
	button.set("fill_color", color)
	button.text = text
	button.custom_minimum_size = Vector2(0, height)
	button.add_theme_font_size_override("font_size", font_size)
	return button


func _set_row(index: int, status: String, ready: bool) -> void:
	var row: Dictionary = _rows[index]
	(row["status"] as Label).text = status
	var style: StyleBoxFlat = row["style"]
	style.bg_color = UiPalette.GRASS if ready else Color("b9b2c9")
	(row["dot"] as Panel).scale = Vector2.ONE * 1.35
	var tween := create_tween()
	tween.tween_property(row["dot"], "scale", Vector2.ONE, 0.35) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)


# --------------------------------------------------------------------------
# waiting logic


func _tick_joining(delta: float) -> void:
	if _joined >= RIVAL_NAMES.size():
		return
	_join_timer += delta
	if _join_timer < 1.05 + float(_joined) * 0.95:
		return
	_joined += 1
	_set_row(_joined, "READY", true)
	_status_label.text = "%s joined the lobby." % RIVAL_NAMES[_joined - 1]
	_status_timer = 0.0
	_refresh_start()


func _tick_status(delta: float) -> void:
	_status_timer += delta
	if _status_timer < 3.4:
		return
	_status_timer = 0.0
	_status_index = (_status_index + 1) % STATUS_LINES.size()
	_status_label.text = STATUS_LINES[_status_index]


func _refresh_start() -> void:
	_start_button.disabled = not (_player_ready and _joined >= RIVAL_NAMES.size())
	if not _start_button.disabled and _state == State.WAITING:
		_status_label.text = "All racers ready. Hit START RACE!"


func _on_ready_pressed() -> void:
	_player_ready = not _player_ready
	_ready_button.text = "READY  ✓" if _player_ready else "READY UP"
	_ready_button.set("fill_color", UiPalette.GRASS if _player_ready else UiPalette.YELLOW)
	_set_row(0, "READY" if _player_ready else "NOT READY", _player_ready)
	_refresh_start()


func _on_start_pressed() -> void:
	if _start_button.disabled or _state != State.WAITING:
		return
	GameSettings.set_player_name(_name_edit.text)
	_state = State.LEAVING
	# The race scene owns the 3-2-1 countdown, after the world has loaded.
	SceneLoader.go_to(RACE_SCENE, "MEADOW LOOP", "3 LAPS TO WIN")


func _tick_countdown(delta: float) -> void:
	_countdown -= delta
	var step: int = clampi(4 - int(ceil(_countdown)), 0, 4)
	if step != _countdown_step:
		_countdown_step = step
		_countdown_label.text = ["3", "2", "1", "GO!", "GO!"][mini(step, 4)]
		_countdown_label.scale = Vector2.ONE * 1.3
		var tween := create_tween()
		tween.tween_property(_countdown_label, "scale", Vector2.ONE, 0.3) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
		if step == 3:
			_countdown_label.add_theme_color_override("font_color", UiPalette.GRASS)
	if _countdown <= 0.0 and _state != State.LEAVING:
		_state = State.LEAVING
		SceneLoader.go_to(RACE_SCENE, "MEADOW LOOP", "3 LAPS TO WIN")


func _animate_leaves(delta: float) -> void:
	for item: Dictionary in _leaf_sprites:
		var sprite: TextureRect = item["node"]
		sprite.position.y += float(item["speed"]) * delta
		sprite.position.x += sin(_time * 1.1 + float(item["phase"])) \
			* float(item["sway"]) * delta
		sprite.rotation = sin(_time * 0.8 + float(item["phase"])) * 0.9
		if sprite.position.y > 740.0:
			sprite.position.y = -40.0
			sprite.position.x = randf() * 1280.0


func _on_back_pressed() -> void:
	if _state != State.WAITING:
		return
	SceneLoader.go_to(MINIGAMES_MENU, "MINIGAMES")
