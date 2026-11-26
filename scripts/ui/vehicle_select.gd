extends Control
## Dynamic Full-Screen 3D Showroom Garage:
## - Full-bleed live 3D garage stage with glowing concentric turntable rings,
##   checkered paddock floor, neon light bars, and interactive drag-to-spin.
## - Dynamic camera FOV/orbit swoosh + vehicle spring squash-and-stretch drop-in
##   & spin flourish whenever you switch rides!
## - Floating left slanted parallelogram telemetry & racing tune panel.
## - Floating bottom slanted horizontal vehicle selector strip + DRIVE / BACK.
## - 100% slanted parallelogram visual language with zero rounded-box focus rings.

const UiAnim := preload("res://scripts/ui/ui_anim.gd")
const StatBar := preload("res://scripts/ui/stat_bar.gd")
const Catalog := preload("res://scripts/vehicles/vehicle_catalog.gd")
const VehicleVisual := preload("res://scripts/vehicles/vehicle_visual.gd")
const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const CandyButton := preload("res://scripts/ui/candy_button.gd")

const TITLE_FONT: Font = preload("res://assets/ui/fonts/LuckiestGuy-Regular.ttf")
const BODY_FONT: Font = preload("res://assets/ui/fonts/Fredoka-Bold.ttf")

const DRIVE_SCENE: String = "res://scenes/sandbox/sandbox.tscn"
const BACK_SCENE: String = "res://scenes/ui/main_menu.tscn"

const STATS: Array[Dictionary] = [
	{"key": "top_speed", "label": "SPEED", "color": UiPalette.YELLOW},
	{"key": "accel", "label": "ACCEL", "color": UiPalette.RED},
	{"key": "steering", "label": "HANDLING", "color": UiPalette.CYAN},
	{"key": "grip", "label": "DRIFT", "color": UiPalette.GRASS},
	{"key": "weight", "label": "WEIGHT", "color": UiPalette.BLUE},
]

const RACING_STATS: Array[Dictionary] = [
	{"key": "top_speed", "label": "SPEED", "color": UiPalette.YELLOW},
	{"key": "accel", "label": "ACCEL", "color": UiPalette.RED},
	{"key": "grip", "label": "HANDLING", "color": UiPalette.CYAN},
	{"key": "weight", "label": "WEIGHT", "color": UiPalette.BLUE},
]

static var _racing_intent: int = -1


static func set_racing_intent(enabled: bool) -> void:
	_racing_intent = 1 if enabled else 0


class _SlashBackdrop extends Control:
	## Slanted parallelogram dark-glass card backing with left accent wedge.
	var fill_color: Color = Color(0.068, 0.078, 0.168, 0.90)
	var accent_color: Color = Color("ffd22e")
	var skew_px: float = 14.0
	var accent_width: float = 12.0

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		if w < 24.0 or h < 18.0:
			return
		var sk: float = minf(skew_px, w * 0.15)
		var bw: float = w - sk - 8.0
		var bh: float = h - 8.0
		var x0: float = 3.0
		var y0: float = 2.0
		var pts := PackedVector2Array([
			Vector2(x0 + sk, y0),
			Vector2(x0 + sk + bw, y0),
			Vector2(x0 + bw, y0 + bh),
			Vector2(x0, y0 + bh),
		])
		var sh := PackedVector2Array([
			pts[0] + Vector2(5.0, 6.0), pts[1] + Vector2(5.0, 6.0),
			pts[2] + Vector2(5.0, 6.0), pts[3] + Vector2(5.0, 6.0),
		])
		draw_colored_polygon(sh, Color(0.02, 0.02, 0.08, 0.65))
		draw_colored_polygon(pts, fill_color)
		# Crisp subtle inner highlight + clean ink outline (zero side/top color stripes!)
		var inner := PackedVector2Array([
			Vector2(x0 + sk + 2.5, y0 + 2.5),
			Vector2(x0 + sk + bw - 2.5, y0 + 2.5),
			Vector2(x0 + bw - 2.5, y0 + bh - 2.5),
			Vector2(x0 + 2.5, y0 + bh - 2.5),
		])
		var icl := inner.duplicate()
		icl.append(inner[0])
		draw_polyline(icl, Color(1.0, 1.0, 1.0, 0.14), 1.5, true)
		var cl := pts.duplicate()
		cl.append(pts[0])
		draw_polyline(cl, UiPalette.INK, 3.8, true)


class _RosterSlashTab extends Button:
	## Slanted parallelogram vehicle pill in the bottom showroom carousel.
	var label_text: String = ""
	var selected_now: bool = false
	var accent_color: Color = Color("ffd22e")
	var _hovered: bool = false
	var _hover_t: float = 0.0
	var _shine_t: float = 2.0

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		flat = true
		clip_contents = false
		set_meta("skip_kit", true)
		set_meta("custom_focus", true)
		var empty := StyleBoxEmpty.new()
		for st: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			add_theme_stylebox_override(st, empty)
		var clear := Color(0.0, 0.0, 0.0, 0.0)
		for ck: String in ["font_color", "font_hover_color", "font_focus_color",
				"font_pressed_color", "font_disabled_color"]:
			add_theme_color_override(ck, clear)
		mouse_entered.connect(func() -> void: _hovered = true; _shine_t = -0.35; queue_redraw())
		mouse_exited.connect(func() -> void: _hovered = false; queue_redraw())
		focus_entered.connect(func() -> void: _shine_t = -0.35; queue_redraw())
		focus_exited.connect(queue_redraw)
		resized.connect(func() -> void: pivot_offset = size * 0.5)

	func set_selected(on: bool) -> void:
		if selected_now != on:
			selected_now = on
			if on:
				_shine_t = -0.35
			queue_redraw()

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		var active: bool = selected_now or _hovered or has_focus()
		var target: float = 1.0 if active else 0.0
		_hover_t = UiAnim.damp(_hover_t, target, delta, 18.0)
		scale = Vector2.ONE * lerpf(1.0, 1.055 if selected_now else 1.035, _hover_t)
		z_index = 4 if selected_now else (2 if active else 0)
		if _shine_t < 1.5:
			_shine_t += delta * 2.8
			queue_redraw()
		elif absf(_hover_t - target) > 0.004:
			queue_redraw()

	func _draw() -> void:
		if size.x < 20.0 or size.y < 16.0:
			return
		var focused: bool = has_focus()
		var sk: float = 11.0
		var lift: float = 5.0 if selected_now else (_hover_t * 3.0)
		var bw: float = size.x - sk - 8.0
		var bh: float = size.y - 10.0
		var x0: float = 4.0
		var y0: float = 7.0 - lift
		var pts := PackedVector2Array([
			Vector2(x0 + sk, y0),
			Vector2(x0 + sk + bw, y0),
			Vector2(x0 + bw, y0 + bh),
			Vector2(x0, y0 + bh),
		])
		var sh := PackedVector2Array([
			pts[0] + Vector2(3.0, 5.0), pts[1] + Vector2(3.0, 5.0),
			pts[2] + Vector2(3.0, 5.0), pts[3] + Vector2(3.0, 5.0),
		])
		draw_colored_polygon(sh, Color(0.02, 0.02, 0.09, 0.65))
		if focused:
			var halo := PackedVector2Array([
				Vector2(x0 + sk - 3.0, y0 - 3.0),
				Vector2(x0 + sk + bw + 3.0, y0 - 3.0),
				Vector2(x0 + bw + 3.0, y0 + bh + 3.0),
				Vector2(x0 - 3.0, y0 + bh + 3.0),
			])
			var hcl := halo.duplicate()
			hcl.append(halo[0])
			draw_polyline(hcl, Color.WHITE if selected_now else UiPalette.YELLOW, 3.0, true)
		var fill: Color = accent_color if selected_now else Color(0.09, 0.10, 0.21, 0.92).lerp(Color(0.16, 0.19, 0.34, 0.96), _hover_t)
		draw_colored_polygon(pts, fill)
		# Shine sweep
		if _shine_t >= -0.35 and _shine_t <= 1.35:
			var sx: float = lerpf(x0 - 16.0, x0 + bw + 16.0, _shine_t)
			var sw: float = 20.0
			var x_tl: float = clampf(sx + sk, x0 + sk, x0 + sk + bw)
			var x_tr: float = clampf(sx + sk + sw, x0 + sk, x0 + sk + bw)
			var x_br: float = clampf(sx + sw, x0, x0 + bw)
			var x_bl: float = clampf(sx, x0, x0 + bw)
			if x_tr > x_tl + 2.0 and x_br > x_bl + 2.0:
				draw_colored_polygon(PackedVector2Array([
					Vector2(x_tl, y0 + 2.0), Vector2(x_tr, y0 + 2.0),
					Vector2(x_br, y0 + bh - 2.0), Vector2(x_bl, y0 + bh - 2.0),
				]), Color(1.0, 1.0, 1.0, 0.26))
		var cl := pts.duplicate()
		cl.append(pts[0])
		draw_polyline(cl, UiPalette.INK, 3.5, true)
		var fsz: int = 13
		var ascent: float = BODY_FONT.get_ascent(fsz)
		var ty: float = y0 + (bh + ascent * 0.72) * 0.5
		draw_string(BODY_FONT, Vector2(x0 + sk * 0.5 + 4.0, ty), label_text,
			HORIZONTAL_ALIGNMENT_CENTER, bw - 8.0, fsz,
			UiPalette.INK if selected_now else UiPalette.CREAM)


class _SlashStepper extends Button:
	## Compact slanted parallelogram − / + tuning button.
	var glyph_text: String = "+"
	var _hovered: bool = false
	var _held: bool = false

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		flat = true
		clip_contents = false
		set_meta("skip_kit", true)
		set_meta("custom_focus", true)
		var empty := StyleBoxEmpty.new()
		for st: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			add_theme_stylebox_override(st, empty)
		var clear := Color(0.0, 0.0, 0.0, 0.0)
		for ck: String in ["font_color", "font_hover_color", "font_focus_color",
				"font_pressed_color", "font_disabled_color"]:
			add_theme_color_override(ck, clear)
		mouse_entered.connect(func() -> void: _hovered = true; queue_redraw())
		mouse_exited.connect(func() -> void: _hovered = false; queue_redraw())
		focus_entered.connect(queue_redraw)
		focus_exited.connect(queue_redraw)
		button_down.connect(func() -> void: _held = true; queue_redraw())
		button_up.connect(func() -> void: _held = false; queue_redraw())

	func _draw() -> void:
		var sk: float = 6.0
		var bw: float = maxf(size.x - sk - 4.0, 10.0)
		var bh: float = maxf(size.y - 4.0, 10.0)
		var x0: float = 2.0
		var y0: float = 2.0 + (1.0 if _held else 0.0)
		var pts := PackedVector2Array([
			Vector2(x0 + sk, y0), Vector2(x0 + sk + bw, y0),
			Vector2(x0 + bw, y0 + bh), Vector2(x0, y0 + bh),
		])
		var fill: Color = Color("363a52") if disabled else (UiPalette.YELLOW.lightened(0.14) if _hovered or has_focus() else UiPalette.YELLOW)
		if has_focus() and not disabled:
			var halo := PackedVector2Array([
				Vector2(x0 + sk - 2.5, y0 - 2.5), Vector2(x0 + sk + bw + 2.5, y0 - 2.5),
				Vector2(x0 + bw + 2.5, y0 + bh + 2.5), Vector2(x0 - 2.5, y0 + bh + 2.5),
			])
			var hcl := halo.duplicate()
			hcl.append(halo[0])
			draw_polyline(hcl, Color.WHITE, 2.5, true)
		draw_colored_polygon(pts, fill)
		var cl := pts.duplicate()
		cl.append(pts[0])
		draw_polyline(cl, UiPalette.INK, 2.8, true)
		var fsz: int = 19
		var ascent: float = BODY_FONT.get_ascent(fsz)
		var ty: float = y0 + (bh + ascent * 0.72) * 0.5
		draw_string(BODY_FONT, Vector2(x0 + sk * 0.5, ty), glyph_text,
			HORIZONTAL_ALIGNMENT_CENTER, bw, fsz,
			Color(0.65, 0.68, 0.80, 0.55) if disabled else UiPalette.INK)


@onready var _viewport_container: SubViewportContainer = %ViewportContainer
@onready var _model_root: Node3D = %ModelRoot
@onready var _camera: Camera3D = %PreviewCamera

var _top_bar: Control
var _left_rail: VBoxContainer
var _name_plate: PanelContainer
var _name_label: Label
var _class_label: Label
var _index_label: Label
var _stats_plate: PanelContainer
var _stats_box: VBoxContainer
var _points_badge: Label
var _paint_box: VBoxContainer
var _paint_swatches: Array[Button] = []
var _bottom_bar: HBoxContainer
var _roster_row: HBoxContainer
var _roster_tabs: Array[_RosterSlashTab] = []
var _prev_button: Button
var _next_button: Button
var _drive_button: Button
var _back_button: Button

var _entries: Array[Dictionary] = []
var _current: int = 0
var _holder: Node3D = null
var _stat_bars: Dictionary = {}
var _stat_ratings: Dictionary = {}
var _ranges: Dictionary = {}
var _time: float = 0.0
var _racing: bool = false
var _allocation: Dictionary = {}
var _alloc_points: Dictionary = {}
var _alloc_minus: Dictionary = {}
var _alloc_plus: Dictionary = {}

# Dynamic showroom turntable & camera juice
var _ring_mat: StandardMaterial3D = null
var _outer_ring_mat: StandardMaterial3D = null
var _ring_flash: float = 0.0
var _spin_velocity: float = 0.42
var _dragging: bool = false
var _cam_fov_target: float = 35.0
var _cam_pos_target: Vector3 = Vector3(2.8, 1.65, -4.4)
var _cam_look_target: Vector3 = Vector3(-0.78, 0.55, 0.0)


func _ready() -> void:
	CursorController.set_menu_mode(true)
	var intent: int = _racing_intent
	_racing_intent = -1
	if OS.get_environment("CART_VEHICLE_RACING") == "1":
		intent = 1
	_racing = GameSettings.racing_mode_active() if intent < 0 else intent == 1
	if _racing:
		_entries = Catalog.racing_all()
		_ranges = Catalog.racing_stat_ranges()
		_allocation = GameSettings.racing_allocation()
	else:
		_entries = Catalog.racing_all()
		_ranges = Catalog.racing_stat_ranges()

	_build_showroom_stage()
	_build_garage_hud()

	if _entries.is_empty():
		_name_label.text = "NO RIDES"
		_drive_button.disabled = true
		_prev_button.disabled = true
		_next_button.disabled = true
		MenuNav.refresh()
		MenuNav.focus(_back_button)
		return

	if _racing:
		_build_racing_stats()
	else:
		_build_stats()
	_build_roster_tabs()

	var current_id: String = ""
	if _racing:
		current_id = GameSettings.racing_vehicle_id()
	elif GameSettings.vehicle_edit_minigame:
		current_id = GameSettings.minigame_vehicle
	else:
		current_id = GameSettings.selected_vehicle
	_current = _entry_index(current_id)
	_show_current(false)
	call_deferred("_enter")
	if OS.get_environment("CART_UI_MEASURE") == "1":
		_report_layout.call_deferred()


func _build_showroom_stage() -> void:
	## Full-screen neon pit garage studio around the spinning vehicle!
	var preview: Node = _camera.get_parent()
	if preview == null:
		return

	# Rich moody garage atmosphere
	var world := WorldEnvironment.new()
	world.name = "ShowroomEnv"
	var env := Environment.new()
	env.background_mode = Environment.BG_SKY
	var sky := Sky.new()
	var sky_mat := ProceduralSkyMaterial.new()
	sky_mat.sky_top_color = Color("0a0d22")
	sky_mat.sky_horizon_color = Color("18244a")
	sky_mat.ground_horizon_color = Color("131b38")
	sky_mat.ground_bottom_color = Color("070916")
	sky.sky_material = sky_mat
	env.sky = sky
	env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	env.ambient_light_color = Color(0.68, 0.80, 1.0)
	env.ambient_light_energy = 0.65
	env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	env.glow_enabled = true
	env.glow_intensity = 0.45
	env.glow_bloom = 0.16
	world.environment = env
	preview.add_child(world)

	# 3-Point Dramatic Studio Lighting (Warm key + Electric Cyan fill + Golden rim)
	var sun := preview.get_node_or_null("Sun") as DirectionalLight3D
	if sun != null:
		sun.light_energy = 1.35
		sun.light_color = Color("fff6e0")
		sun.shadow_enabled = true
		sun.directional_shadow_max_distance = 18.0
	var fill := DirectionalLight3D.new()
	fill.name = "CyanFill"
	fill.rotation_degrees = Vector3(-25.0, -140.0, 0.0)
	fill.light_energy = 1.15
	fill.light_color = Color("38d6ff")
	preview.add_child(fill)
	var rim := DirectionalLight3D.new()
	rim.name = "GoldRim"
	rim.rotation_degrees = Vector3(-16.0, 40.0, 0.0)
	rim.light_energy = 0.95
	rim.light_color = Color("ffd24a")
	preview.add_child(rim)

	# Studio Floor + Concentric Neon Turntable Pedestal + Pit Light Strips
	var stage := Node3D.new()
	stage.name = "GarageStudioStage"
	preview.add_child(stage)

	var floor_mi := MeshInstance3D.new()
	var floor_plane := PlaneMesh.new()
	floor_plane.size = Vector2(44.0, 44.0)
	floor_mi.mesh = floor_plane
	var floor_mat := StandardMaterial3D.new()
	floor_mat.albedo_color = Color("0d1124")
	floor_mat.roughness = 0.24
	floor_mat.metallic = 0.35
	floor_mi.material_override = floor_mat
	floor_mi.position.y = -0.14
	stage.add_child(floor_mi)

	# Sleek dark brushed-metal rotating turntable disc
	var disc := MeshInstance3D.new()
	var cyl := CylinderMesh.new()
	cyl.top_radius = 2.15
	cyl.bottom_radius = 2.42
	cyl.height = 0.14
	cyl.radial_segments = 48
	disc.mesh = cyl
	var disc_mat := StandardMaterial3D.new()
	disc_mat.albedo_color = Color("181d38")
	disc_mat.roughness = 0.22
	disc_mat.metallic = 0.55
	disc.material_override = disc_mat
	disc.position.y = -0.08
	stage.add_child(disc)

	# Glowing inner Gold ring
	var inner_ring := MeshInstance3D.new()
	var t1 := TorusMesh.new()
	t1.inner_radius = 2.08
	t1.outer_radius = 2.22
	t1.rings = 48
	t1.ring_segments = 14
	inner_ring.mesh = t1
	_ring_mat = StandardMaterial3D.new()
	_ring_mat.albedo_color = UiPalette.YELLOW
	_ring_mat.emission_enabled = true
	_ring_mat.emission = UiPalette.YELLOW
	_ring_mat.emission_energy_multiplier = 2.2
	inner_ring.material_override = _ring_mat
	inner_ring.position.y = -0.01
	stage.add_child(inner_ring)

	# Glowing outer Cyan halo ring
	var outer_ring := MeshInstance3D.new()
	var t2 := TorusMesh.new()
	t2.inner_radius = 3.10
	t2.outer_radius = 3.18
	t2.rings = 48
	t2.ring_segments = 10
	outer_ring.mesh = t2
	_outer_ring_mat = StandardMaterial3D.new()
	_outer_ring_mat.albedo_color = UiPalette.CYAN
	_outer_ring_mat.emission_enabled = true
	_outer_ring_mat.emission = UiPalette.CYAN
	_outer_ring_mat.emission_energy_multiplier = 1.6
	outer_ring.material_override = _outer_ring_mat
	outer_ring.position.y = -0.12
	stage.add_child(outer_ring)

	# Background neon garage wall light-bars & columns for real depth!
	var neon_c := StandardMaterial3D.new()
	neon_c.albedo_color = Color("38d6f0")
	neon_c.emission_enabled = true
	neon_c.emission = Color("38d6f0")
	neon_c.emission_energy_multiplier = 2.4
	var neon_y := StandardMaterial3D.new()
	neon_y.albedo_color = Color("ffd22e")
	neon_y.emission_enabled = true
	neon_y.emission = Color("ffd22e")
	neon_y.emission_energy_multiplier = 2.0
	var pillar_mat := StandardMaterial3D.new()
	pillar_mat.albedo_color = Color("161c36")
	pillar_mat.roughness = 0.45
	pillar_mat.metallic = 0.40

	for i in 5:
		var ang: float = lerpf(-0.95, 1.35, float(i) / 4.0)
		var r: float = 8.4
		var px: float = sin(ang) * r
		var pz: float = cos(ang) * r
		var pillar := MeshInstance3D.new()
		var pb := BoxMesh.new()
		pb.size = Vector3(0.55, 6.2, 0.55)
		pillar.mesh = pb
		pillar.material_override = pillar_mat
		pillar.position = Vector3(px, 2.9, pz)
		pillar.rotation.y = ang
		stage.add_child(pillar)

		var strip := MeshInstance3D.new()
		var sb := BoxMesh.new()
		sb.size = Vector3(0.14, 4.4, 0.14)
		strip.mesh = sb
		strip.material_override = neon_c if i % 2 == 0 else neon_y
		strip.position = Vector3(px * 0.96, 2.6, pz * 0.96)
		strip.rotation.y = ang
		stage.add_child(strip)

	# Overhead studio light gantry bar
	for side_x: float in [-2.6, 2.6]:
		var beam := MeshInstance3D.new()
		var bb := BoxMesh.new()
		bb.size = Vector3(0.18, 0.12, 6.5)
		beam.mesh = bb
		beam.material_override = neon_c if side_x < 0.0 else neon_y
		beam.position = Vector3(side_x, 4.8, 1.2)
		stage.add_child(beam)

	_camera.fov = 36.0
	_camera.look_at_from_position(_cam_pos_target, _cam_look_target, Vector3.UP)


func _build_garage_hud() -> void:
	var hud := Control.new()
	hud.name = "GarageHUD"
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(hud)

	# ---- Top Header Row ----
	_top_bar = Control.new()
	_top_bar.name = "TopHeader"
	_top_bar.anchor_left = 0.0
	_top_bar.anchor_right = 1.0
	_top_bar.anchor_top = 0.0
	_top_bar.offset_left = 28.0
	_top_bar.offset_right = -28.0
	_top_bar.offset_top = 18.0
	_top_bar.offset_bottom = 74.0
	_top_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_top_bar)

	var left_head := HBoxContainer.new()
	left_head.anchor_left = 0.0
	left_head.anchor_top = 0.0
	left_head.offset_right = 460.0
	left_head.offset_bottom = 54.0
	left_head.add_theme_constant_override("separation", 14)
	left_head.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_bar.add_child(left_head)

	var garage_title := Label.new()
	garage_title.text = "GARAGE"
	garage_title.add_theme_font_override("font", TITLE_FONT)
	garage_title.add_theme_font_size_override("font_size", 42)
	garage_title.add_theme_color_override("font_color", UiPalette.YELLOW)
	garage_title.add_theme_color_override("font_outline_color", UiPalette.INK)
	garage_title.add_theme_constant_override("outline_size", 10)
	garage_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_head.add_child(garage_title)

	_index_label = Label.new()
	_index_label.name = "IndexLabel"
	_index_label.text = "01 / 11"
	_index_label.add_theme_font_override("font", BODY_FONT)
	_index_label.add_theme_font_size_override("font_size", 16)
	_index_label.add_theme_color_override("font_color", UiPalette.CYAN)
	_index_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_index_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	left_head.add_child(_index_label)

	_back_button = CandyButton.new()
	_back_button.name = "BackButton"
	_back_button.text = "CANCEL" if GameSettings.vehicle_return_scene != "" else "BACK"
	_back_button.fill_color = UiPalette.RED
	_back_button.shadow_offset = 5
	_back_button.anchor_left = 1.0
	_back_button.anchor_right = 1.0
	_back_button.anchor_top = 0.0
	_back_button.offset_left = -152.0
	_back_button.offset_right = 0.0
	_back_button.offset_top = 2.0
	_back_button.offset_bottom = 52.0
	_back_button.add_theme_font_size_override("font_size", 18)
	_back_button.pressed.connect(_on_back)
	_top_bar.add_child(_back_button)

	# ---- Left Floating Slanted Telemetry & Tuning Stack ----
	_left_rail = VBoxContainer.new()
	_left_rail.name = "TelemetryRail"
	_left_rail.anchor_left = 0.0
	_left_rail.anchor_top = 0.5
	_left_rail.anchor_bottom = 0.5
	_left_rail.offset_left = 28.0
	_left_rail.offset_right = 472.0
	_left_rail.offset_top = -225.0
	_left_rail.offset_bottom = 178.0
	_left_rail.add_theme_constant_override("separation", 12)
	_left_rail.alignment = BoxContainer.ALIGNMENT_CENTER
	_left_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_left_rail)

	# Vehicle Name Plate (slanted dark ink + gold wedge)
	_name_plate = PanelContainer.new()
	_name_plate.name = "NamePlate"
	_name_plate.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_name_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left_rail.add_child(_name_plate)

	var name_bg := _SlashBackdrop.new()
	name_bg.fill_color = Color(0.068, 0.078, 0.175, 0.92)
	name_bg.accent_color = UiPalette.YELLOW
	name_bg.accent_width = 16.0
	name_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_name_plate.add_child(name_bg)

	var name_pad := MarginContainer.new()
	name_pad.add_theme_constant_override("margin_left", 38)
	name_pad.add_theme_constant_override("margin_right", 24)
	name_pad.add_theme_constant_override("margin_top", 12)
	name_pad.add_theme_constant_override("margin_bottom", 14)
	name_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_name_plate.add_child(name_pad)

	var name_col := VBoxContainer.new()
	name_col.add_theme_constant_override("separation", 2)
	name_col.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_pad.add_child(name_col)

	_class_label = Label.new()
	_class_label.text = "TURBO CART"
	_class_label.add_theme_font_override("font", BODY_FONT)
	_class_label.add_theme_font_size_override("font_size", 13)
	_class_label.add_theme_color_override("font_color", UiPalette.CYAN)
	_class_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_col.add_child(_class_label)

	_name_label = Label.new()
	_name_label.name = "NameLabel"
	_name_label.text = "SHOPPING CART"
	_name_label.add_theme_font_override("font", TITLE_FONT)
	_name_label.add_theme_font_size_override("font_size", 32)
	_name_label.add_theme_color_override("font_color", UiPalette.CREAM)
	_name_label.add_theme_color_override("font_outline_color", UiPalette.INK)
	_name_label.add_theme_constant_override("outline_size", 6)
	_name_label.clip_text = true
	_name_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_col.add_child(_name_label)

	# Stats & Tuning Slanted Plate
	_stats_plate = PanelContainer.new()
	_stats_plate.name = "StatsPlate"
	_stats_plate.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_stats_plate.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_left_rail.add_child(_stats_plate)

	var stats_bg := _SlashBackdrop.new()
	stats_bg.fill_color = Color(0.062, 0.072, 0.158, 0.88)
	stats_bg.accent_color = UiPalette.CYAN
	stats_bg.accent_width = 10.0
	stats_bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	_stats_plate.add_child(stats_bg)

	var stats_pad := MarginContainer.new()
	stats_pad.add_theme_constant_override("margin_left", 32)
	stats_pad.add_theme_constant_override("margin_right", 22)
	stats_pad.add_theme_constant_override("margin_top", 14)
	stats_pad.add_theme_constant_override("margin_bottom", 18)
	stats_pad.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_stats_plate.add_child(stats_pad)

	var stats_wrap := VBoxContainer.new()
	stats_wrap.add_theme_constant_override("separation", 10)
	stats_wrap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_pad.add_child(stats_wrap)

	_points_badge = Label.new()
	_points_badge.text = ""
	_points_badge.add_theme_font_override("font", BODY_FONT)
	_points_badge.add_theme_font_size_override("font_size", 14)
	_points_badge.add_theme_color_override("font_color", UiPalette.YELLOW)
	_points_badge.visible = _racing
	_points_badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_wrap.add_child(_points_badge)

	_stats_box = VBoxContainer.new()
	_stats_box.name = "StatsBox"
	_stats_box.add_theme_constant_override("separation", 10)
	_stats_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_wrap.add_child(_stats_box)

	# PRO RACER Custom Paint Swatch Selector (visible when PRO RACER is selected!)
	_paint_box = VBoxContainer.new()
	_paint_box.name = "PaintSwatchBox"
	_paint_box.add_theme_constant_override("separation", 6)
	_paint_box.visible = false
	stats_wrap.add_child(_paint_box)

	var paint_lbl := Label.new()
	paint_lbl.text = "PAINT COLOR"
	paint_lbl.add_theme_font_override("font", BODY_FONT)
	paint_lbl.add_theme_font_size_override("font_size", 13)
	paint_lbl.add_theme_color_override("font_color", UiPalette.YELLOW)
	paint_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_paint_box.add_child(paint_lbl)

	var swatch_row := HBoxContainer.new()
	swatch_row.add_theme_constant_override("separation", 7)
	_paint_box.add_child(swatch_row)

	_paint_swatches.clear()
	for sw: Dictionary in Catalog.RACER_COLORS:
		var hex: String = str(sw.get("hex", "e63946"))
		var btn := Button.new()
		btn.name = "Paint_" + hex
		btn.text = ""
		btn.custom_minimum_size = Vector2(36, 30)
		btn.focus_mode = Control.FOCUS_ALL
		btn.set_meta("skip_kit", true)
		btn.set_meta("paint_hex", hex)
		btn.pressed.connect(_on_paint_swatch_pressed.bind(hex))
		swatch_row.add_child(btn)
		_paint_swatches.append(btn)
	_refresh_paint_swatches()

	# ---- Bottom Floating Slanted Carousel + DRIVE Launch Button ----
	_bottom_bar = HBoxContainer.new()
	_bottom_bar.name = "BottomDock"
	_bottom_bar.anchor_left = 0.0
	_bottom_bar.anchor_right = 1.0
	_bottom_bar.anchor_top = 1.0
	_bottom_bar.anchor_bottom = 1.0
	_bottom_bar.offset_left = 24.0
	_bottom_bar.offset_right = -24.0
	_bottom_bar.offset_top = -84.0
	_bottom_bar.offset_bottom = -18.0
	_bottom_bar.add_theme_constant_override("separation", 10)
	_bottom_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_bottom_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.add_child(_bottom_bar)

	_prev_button = CandyButton.new()
	_prev_button.name = "PrevButton"
	_prev_button.text = "<"
	_prev_button.fill_color = UiPalette.CYAN
	_prev_button.shadow_offset = 5
	_prev_button.custom_minimum_size = Vector2(56, 56)
	_prev_button.add_theme_font_size_override("font_size", 24)
	_prev_button.pressed.connect(_step.bind(-1))
	_bottom_bar.add_child(_prev_button)

	var scroll := ScrollContainer.new()
	scroll.name = "RosterScroll"
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.follow_focus = true
	_bottom_bar.add_child(scroll)

	_roster_row = HBoxContainer.new()
	_roster_row.add_theme_constant_override("separation", 4)
	_roster_row.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_roster_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	scroll.add_child(_roster_row)

	_next_button = CandyButton.new()
	_next_button.name = "NextButton"
	_next_button.text = ">"
	_next_button.fill_color = UiPalette.CYAN
	_next_button.shadow_offset = 5
	_next_button.custom_minimum_size = Vector2(56, 56)
	_next_button.add_theme_font_size_override("font_size", 24)
	_next_button.pressed.connect(_step.bind(1))
	_bottom_bar.add_child(_next_button)

	_drive_button = CandyButton.new()
	_drive_button.name = "DriveButton"
	_drive_button.text = "SAVE" if GameSettings.vehicle_return_scene != "" else "DRIVE"
	_drive_button.fill_color = UiPalette.YELLOW
	_drive_button.shadow_offset = 6
	_drive_button.custom_minimum_size = Vector2(188, 60)
	_drive_button.add_theme_font_size_override("font_size", 24)
	_drive_button.set_meta("sfx_confirm", true)
	_drive_button.pressed.connect(_on_drive)
	_bottom_bar.add_child(_drive_button)


func _build_roster_tabs() -> void:
	_roster_tabs.clear()
	for i in _entries.size():
		var entry: Dictionary = _entries[i]
		var tab := _RosterSlashTab.new()
		tab.name = "RideTab_%d" % i
		var raw_name: String = str(entry.get("name", "RIDE")).to_upper()
		tab.label_text = raw_name.replace("SHOPPING ", "").replace(" CRUISER", "")
		tab.accent_color = UiPalette.YELLOW if i == 0 else (UiPalette.PINK if bool(entry.get("racing", false)) else UiPalette.CYAN)
		tab.custom_minimum_size = Vector2(118.0, 56.0)
		var idx: int = i
		tab.pressed.connect(func() -> void:
			if _current != idx:
				_current = idx
				_show_current(true))
		_roster_row.add_child(tab)
		_roster_tabs.append(tab)


func _stat_title_label(text_val: String, width: float, align: HorizontalAlignment,
		color: Color, font_size: int = 14) -> Label:
	var label := Label.new()
	label.text = text_val
	label.custom_minimum_size = Vector2(width, 0)
	label.size_flags_horizontal = 0
	label.horizontal_alignment = align
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.add_theme_font_override("font", BODY_FONT)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", color)
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label


func _make_stat_bar(color: Color, bar_w: float) -> StatBar:
	var bar := StatBar.new()
	bar.fill_color = color
	bar.bar_height = 16.0
	bar.custom_minimum_size = Vector2(bar_w, 22.0)
	bar.size_flags_horizontal = 0
	bar.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return bar


func _build_stats() -> void:
	for stat: Dictionary in STATS:
		var key: String = str(stat["key"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 10)
		_stats_box.add_child(row)

		row.add_child(_stat_title_label(str(stat["label"]), 88.0, HORIZONTAL_ALIGNMENT_RIGHT, UiPalette.CREAM, 14))
		var bar := _make_stat_bar(stat["color"] as Color, 212.0)
		row.add_child(bar)
		var rating := _stat_title_label("5/10", 54.0, HORIZONTAL_ALIGNMENT_LEFT, UiPalette.CYAN, 15)
		row.add_child(rating)

		_stat_bars[key] = bar
		_stat_ratings[key] = rating


func _build_racing_stats() -> void:
	for stat: Dictionary in RACING_STATS:
		var key: String = str(stat["key"])
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 8)
		_stats_box.add_child(row)

		row.add_child(_stat_title_label(str(stat["label"]), 84.0, HORIZONTAL_ALIGNMENT_RIGHT, UiPalette.CREAM, 14))
		var bar := _make_stat_bar(stat["color"] as Color, 178.0)
		row.add_child(bar)

		var ctrl_row := HBoxContainer.new()
		ctrl_row.add_theme_constant_override("separation", 4)
		row.add_child(ctrl_row)

		var minus := _SlashStepper.new()
		minus.glyph_text = "−"
		minus.custom_minimum_size = Vector2(32, 28)
		minus.pressed.connect(_adjust_stat.bind(key, -1))
		ctrl_row.add_child(minus)

		var pts := _stat_title_label("3", 24.0, HORIZONTAL_ALIGNMENT_CENTER, UiPalette.YELLOW, 16)
		ctrl_row.add_child(pts)

		var plus := _SlashStepper.new()
		plus.glyph_text = "+"
		plus.custom_minimum_size = Vector2(32, 28)
		plus.pressed.connect(_adjust_stat.bind(key, 1))
		ctrl_row.add_child(plus)

		_alloc_points[key] = pts
		_alloc_minus[key] = minus
		_alloc_plus[key] = plus
		_stat_bars[key] = bar


func _enter() -> void:
	UiAnim.slide_in(_top_bar, Vector2(0.0, -30.0), 0.28)
	UiAnim.stagger_slide([_name_plate, _stats_plate], Vector2(-42.0, 0.0), 0.06, 0.30)
	UiAnim.slide_in(_bottom_bar, Vector2(0.0, 38.0), 0.30)
	MenuNav.refresh()
	if _entries.is_empty():
		MenuNav.focus(_back_button)
	else:
		MenuNav.focus(_drive_button)


func _report_layout() -> void:
	await UiKit.report_screen(self, "vehicle_select:racing" if _racing else "vehicle_select:roster")


func _input(event: InputEvent) -> void:
	# Drag anywhere on the 3D showroom to spin the vehicle interactively!
	if event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and mb.position.x > 460.0 and mb.position.y > 76.0 and mb.position.y < size.y - 96.0:
				_dragging = true
			elif not mb.pressed:
				_dragging = false
	elif event is InputEventMouseMotion and _dragging:
		var mm := event as InputEventMouseMotion
		if _model_root != null:
			_model_root.rotation.y += mm.relative.x * 0.012
			_spin_velocity = clampf(mm.relative.x * 0.14, -4.5, 4.5)


func _unhandled_input(event: InputEvent) -> void:
	if SceneLoader.is_busy():
		return
	if event.is_action_pressed("ui_cancel"):
		UiKit.consume_input(self)
		_on_back()
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			if key.keycode == KEY_Q or key.keycode == KEY_PAGEUP:
				UiKit.consume_input(self)
				_step(-1)
				return
			elif key.keycode == KEY_E or key.keycode == KEY_PAGEDOWN:
				UiKit.consume_input(self)
				_step(1)
				return
	elif event is InputEventJoypadButton:
		var pad_btn := event as InputEventJoypadButton
		if pad_btn.pressed:
			if pad_btn.button_index == JOY_BUTTON_LEFT_SHOULDER:
				UiKit.consume_input(self)
				_step(-1)
				return
			elif pad_btn.button_index == JOY_BUTTON_RIGHT_SHOULDER:
				UiKit.consume_input(self)
				_step(1)
				return
	var direction: int = 0
	if event.is_action_pressed("ui_left"):
		direction = -1
	elif event.is_action_pressed("ui_right"):
		direction = 1
	if direction != 0 and nav_horizontal(direction):
		UiKit.consume_input(self)


func nav_horizontal(direction: int) -> bool:
	_step(direction)
	return true


func _process(delta: float) -> void:
	_time += delta
	if _model_root != null and not _dragging:
		_spin_velocity = UiAnim.damp(_spin_velocity, 0.44, delta, 3.2)
		_model_root.rotation.y += delta * _spin_velocity
	if _holder != null:
		_holder.position.y = sin(_time * 1.9) * 0.022
	if _camera != null:
		_camera.fov = UiAnim.damp(_camera.fov, _cam_fov_target, delta, 7.5)
		var orbit_sway := Vector3(sin(_time * 0.55) * 0.16, cos(_time * 0.42) * 0.05, 0.0)
		var goal_pos: Vector3 = _cam_pos_target + orbit_sway
		_camera.position = _camera.position.lerp(goal_pos, 1.0 - exp(-delta * 7.0))
		_camera.look_at(_cam_look_target, Vector3.UP)
	if _ring_flash > 0.01:
		_ring_flash = UiAnim.damp(_ring_flash, 0.0, delta, 6.0)
		if _ring_mat != null:
			_ring_mat.emission_energy_multiplier = 2.2 + _ring_flash * 3.8
		if _outer_ring_mat != null:
			_outer_ring_mat.emission_energy_multiplier = 1.6 + _ring_flash * 3.0


func _adjust_stat(key: String, direction: int) -> void:
	if not _racing or _entries.is_empty():
		return
	var points: int = int(_allocation.get(key, 0))
	var total: int = Catalog.allocation_total(_allocation)
	if direction > 0:
		if points >= Catalog.RACING_STAT_MAX or total >= Catalog.RACING_STAT_POINTS:
			return
	elif points <= 0:
		return
	_allocation[key] = points + direction
	_ring_flash = 0.65
	_fill_racing_stats(_composed_current())


func _entry_index(id: String) -> int:
	for index in _entries.size():
		if str(_entries[index].get("id", "")) == id:
			return index
	return 0


func _composed_current() -> Dictionary:
	if _entries.is_empty():
		return {}
	var base: Dictionary = _entries[_current]
	var out: Dictionary = Catalog.compose_racing_entry(str(base.get("id", "")), _allocation) \
		if _racing else base.duplicate()
	if bool(out.get("custom_paint", false)):
		out["paint_color"] = GameSettings.racer_color_value()
	return out


func _vehicle_class_name(entry: Dictionary) -> String:
	var id: String = str(entry.get("id", ""))
	if id == "shopping_cart":
		return "TURBO CART"
	if bool(entry.get("racing", false)) or id == "race_car" or id.begins_with("race_car_"):
		return "PRO GRAND PRIX"
	if id in ["truck", "van"]:
		return "HEAVYWEIGHT"
	return "STREET CLASS"


func _on_paint_swatch_pressed(hex: String) -> void:
	GameSettings.set_racer_color(hex)
	if Network.is_session_active():
		Network.set_local_vehicle_loadout()
	_refresh_paint_swatches()
	_ring_flash = 0.85
	_swap_model(false)


func _refresh_paint_swatches() -> void:
	var current_hex: String = GameSettings.racer_color.to_lower()
	for btn: Button in _paint_swatches:
		if not is_instance_valid(btn):
			continue
		var hex: String = str(btn.get_meta("paint_hex", "e63946")).to_lower()
		var picked: bool = hex == current_hex
		var st := StyleBoxFlat.new()
		st.bg_color = Color.from_string(hex, Color("e63946"))
		st.set_corner_radius_all(4)
		st.set_border_width_all(3 if picked else 2)
		st.border_color = UiPalette.YELLOW if picked else UiPalette.INK
		st.skew = Vector2(0.18, 0.0)
		st.anti_aliasing = true
		for state_name: String in ["normal", "hover", "pressed"]:
			btn.add_theme_stylebox_override(state_name, st)
		var foc := st.duplicate() as StyleBoxFlat
		foc.border_color = Color.WHITE
		foc.set_border_width_all(3)
		btn.add_theme_stylebox_override("focus", foc)


func _show_current(animate: bool = true) -> void:
	var entry: Dictionary = _composed_current()
	_swap_model(animate)
	_name_label.text = str(entry.get("name", "")).to_upper()
	_class_label.text = _vehicle_class_name(entry)
	_index_label.text = "%02d / %02d" % [_current + 1, _entries.size()]
	if _paint_box != null:
		var has_paint: bool = bool(entry.get("custom_paint", false))
		_paint_box.visible = has_paint
		if has_paint:
			_refresh_paint_swatches()
	for i in _roster_tabs.size():
		_roster_tabs[i].set_selected(i == _current)
	if animate:
		UiAnim.slide_in(_name_plate, Vector2(-22.0, 0.0), 0.22)
	if _racing:
		_fill_racing_stats(entry)
	else:
		_fill_stats(entry)


func _swap_model(animate: bool) -> void:
	if _holder != null:
		_model_root.remove_child(_holder)
		_holder.queue_free()
		_holder = null
	var entry: Dictionary = _composed_current()
	_holder = VehicleVisual.build(entry)
	_model_root.add_child(_holder)
	var vh: float = float(entry.get("height", 1.5))
	var vl: float = float(entry.get("length", 2.4))
	var dist: float = 4.1 + maxf(vh * 0.34, vl * 0.26)
	# Camera sits at -Z looking toward +Z (screen-left is +X, screen-right is -X).
	# Shifting the look target to +X frames the 3D ride squarely in the open right
	# showroom spotlight, completely clear of the left slanted telemetry panel!
	_cam_look_target = Vector3(1.15, vh * 0.44, 0.0)
	_cam_pos_target = Vector3(dist * 0.56 + 1.15, 1.48 + vh * 0.34, -dist)
	_cam_fov_target = 35.0
	if animate:
		_ring_flash = 1.0
		_spin_velocity = 3.6
		if _camera != null:
			_camera.fov = 42.0
		_holder.scale = Vector3(1.14, 0.72, 1.14)
		var tween: Tween = _holder.create_tween()
		tween.tween_property(_holder, "scale", Vector3.ONE, 0.34) \
			.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	else:
		_holder.scale = Vector3.ONE
		if _camera != null:
			_camera.position = _cam_pos_target
			_camera.look_at(_cam_look_target, Vector3.UP)


func _fill_racing_stats(entry: Dictionary) -> void:
	var total: int = Catalog.allocation_total(_allocation)
	var left: int = maxi(Catalog.RACING_STAT_POINTS - total, 0)
	_points_badge.text = "TUNE POINTS: %d" % left
	_points_badge.add_theme_color_override("font_color", UiPalette.YELLOW if left > 0 else UiPalette.CYAN)
	for stat: Dictionary in RACING_STATS:
		var key: String = str(stat["key"])
		var points: int = int(_allocation.get(key, 0))
		(_alloc_points[key] as Label).text = str(points)
		(_stat_bars[key] as StatBar).set_ratio(Catalog.stat_ratio(entry, key, _ranges) * 0.90 + 0.10)
		(_alloc_minus[key] as Button).disabled = points <= 0
		(_alloc_plus[key] as Button).disabled = points >= Catalog.RACING_STAT_MAX \
			or total >= Catalog.RACING_STAT_POINTS


func _fill_stats(entry: Dictionary) -> void:
	for key: String in _stat_bars:
		var ratio: float = Catalog.stat_ratio(entry, key, _ranges)
		var rating: int = clampi(int(round(ratio * 9.0)) + 1, 1, 10)
		(_stat_bars[key] as StatBar).set_ratio(clampf(ratio * 0.90 + 0.10, 0.10, 1.0))
		if _stat_ratings.has(key):
			(_stat_ratings[key] as Label).text = "%d/10" % rating


func _step(direction: int) -> void:
	if _entries.is_empty():
		return
	_current = wrapi(_current + direction, 0, _entries.size())
	_show_current(true)


func _on_drive() -> void:
	if _entries.is_empty():
		return
	var vehicle_id: String = str(_entries[_current].get("id", Catalog.DEFAULT_ID))
	if _racing:
		GameSettings.set_racing_vehicle(vehicle_id)
		GameSettings.set_racing_allocation(_allocation)
	elif GameSettings.vehicle_edit_minigame:
		GameSettings.set_minigame_options(GameSettings.minigame_difficulty,
			GameSettings.minigame_rounds, vehicle_id)
	else:
		GameSettings.set_selected_vehicle(vehicle_id)
	GameSettings.vehicle_edit_minigame = false
	if Network.is_session_active():
		Network.set_local_vehicle_loadout()
	if GameSettings.vehicle_return_scene != "":
		var scene: String = GameSettings.vehicle_return_scene
		var title: String = GameSettings.vehicle_return_title
		GameSettings.vehicle_return_scene = ""
		GameSettings.vehicle_return_title = ""
		SceneLoader.go_to(scene, title, "")
		return
	SceneLoader.go_to(DRIVE_SCENE, "SANDBOX", "")


func _on_back() -> void:
	GameSettings.vehicle_edit_minigame = false
	if GameSettings.vehicle_return_scene != "":
		var scene: String = GameSettings.vehicle_return_scene
		var title: String = GameSettings.vehicle_return_title
		GameSettings.vehicle_return_scene = ""
		GameSettings.vehicle_return_title = ""
		SceneLoader.go_to(scene, title)
		return
	SceneLoader.go_to(BACK_SCENE, "CART SLOP GP")
