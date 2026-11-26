extends Control
## Menu backdrop: a self-timed, shuffled concept-art slideshow driven by
## ArtBackdrop, backed by a crisp procedural vector SlopMart scene when art
## textures are absent, plus a subtle themed 2D particle drift over the artwork
## (WS3). The drift is quality-tiered, reduced-motion aware and faded in behind
## the UI; it is a plain Node2D overlay, so it never registers as a Control and
## cannot affect the UI layout audit or the focus ring.
##
## 0.8.7 correction: the slideshow cycles ON ITS OWN and is independent of the
## menus - no hover/focus/button event reaches this file. Each screen hands over
## its own art pool via `set_slide_pool()` (main menu = all four `bg_hero_*`
## key arts, play menu = its two hero cards, minigames = its mode/map previews),
## and ArtBackdrop then randomizes 8-12 s beats with smooth crossfades.

const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const CartDrawing := preload("res://scripts/ui/cart_drawing.gd")
const DISPLAY_FONT := "res://assets/ui/fonts/LuckiestGuy-Regular.ttf"
const ART_BACKDROP := preload("res://scripts/ui/art_backdrop.gd")
const FxQuality := preload("res://scripts/effects/fx_quality.gd")
const CONFETTI_TEX: String = "res://assets/textures/fx/confetti.png"

## Default menu art pool: every hero key-art plate, in a stable order (the
## slideshow shuffles the playback order itself, never this list). Screens with a
## narrower identity (play menu, minigames select) replace it via
## `set_slide_pool()`.
const HERO_ART_NAMES: Array[String] = [
	"bg_hero_paddock.png",
	"bg_hero_canyon.png",
	"bg_hero_arena.png",
	"bg_hero_glacier.png",
]
const SLIDE_SECONDS_MIN: float = 8.0
const SLIDE_SECONDS_MAX: float = 12.0
const SLIDE_FADE_SECONDS: float = 1.15

## Particle counts at the BALANCED preset; density_scale() trims them for
## performance/web while reduced motion slows the drift and drops the confetti
## layer to a handful of slow flakes.
const FAR_MOTES_BALANCED: int = 30
const NEAR_CONFETTI_BALANCED: int = 16
## Pixel sizes the two layers are scaled to, independent of the source texture.
const FAR_MOTE_PIXELS: float = 5.0
const NEAR_CONFETTI_PIXELS: float = 4.4
## Seconds the drift takes to bloom in, and to disappear when the screen hides.
const FADE_IN_SECONDS: float = 1.6
const FADE_OUT_SECONDS: float = 0.5

@export var show_store: bool = true
@export var show_carts: bool = true
## Ambient drift master switch for future menu screens that want a still hero.
@export var show_particles: bool = true

var _display: FontFile
var _art: Control
var _slide_pool: PackedStringArray = PackedStringArray(HERO_ART_NAMES)
var _particles: Node2D
var _far_motes: CPUParticles2D
var _near_confetti: CPUParticles2D
var _particle_alpha: float = 0.0
var _particle_target: float = 0.0


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	_display = load(DISPLAY_FONT)
	resized.connect(queue_redraw)
	resized.connect(_fit_particles)
	_art = ART_BACKDROP.new()
	_art.name = "ArtBackdrop"
	_art.set("texture_names", _slide_pool)
	_art.set("slide_seconds_min", SLIDE_SECONDS_MIN)
	_art.set("slide_seconds_max", SLIDE_SECONDS_MAX)
	_art.set("fade_seconds", SLIDE_FADE_SECONDS)
	_art.set("shuffle", true)
	_art.set("auto_advance", true)
	_art.set("dim", 0.08)
	_art.set("left_scrim", 0.46)
	add_child(_art)
	_build_particles()
	if GameSettings != null and not GameSettings.changed.is_connected(_on_settings_changed):
		GameSettings.changed.connect(_on_settings_changed)


func _exit_tree() -> void:
	if GameSettings != null and GameSettings.changed.is_connected(_on_settings_changed):
		GameSettings.changed.disconnect(_on_settings_changed)


func set_slide_pool(names: PackedStringArray) -> void:
	## Hand this screen's own art set to the slideshow. The backdrop keeps
	## cycling by itself; this is the only screen -> backdrop API (there is no
	## hover/focus entry point by design).
	var filtered: PackedStringArray = PackedStringArray()
	for file_name: String in names:
		if file_name != "" and not filtered.has(file_name):
			filtered.append(file_name)
	if filtered.is_empty():
		return
	_slide_pool = filtered
	if _art != null and is_instance_valid(_art):
		_art.call("set_slides", _slide_pool)


func slide_pool() -> PackedStringArray:
	## Test/audit contract: the art pool this backdrop is cycling.
	return _slide_pool


func art_backdrop_node() -> Control:
	## Test/audit contract: the self-timed ArtBackdrop child that owns the cycle.
	return _art


func set_ambient_strength(value: float) -> void:
	## Public fade hook for a screen that wants the drift dimmed during a modal
	## or a hero moment. 0..1, clamped; fades smoothly.
	_particle_target = clampf(value, 0.0, 1.0) if show_particles else 0.0


# --------------------------------------------------------------------------
# ambient menu drift
# --------------------------------------------------------------------------


func _build_particles() -> void:
	if not show_particles:
		return
	_particles = Node2D.new()
	_particles.name = "AmbientDrift"
	_particles.z_index = 1
	add_child(_particles)
	_far_motes = _far_mote_layer()
	_particles.add_child(_far_motes)
	# Web gets the cheapest single layer: one scroll tick of soft motes.
	if not FxQuality.is_web():
		_near_confetti = _near_confetti_layer()
		_particles.add_child(_near_confetti)
	_fit_particles()
	call_deferred("_fit_particles")
	_particle_target = 1.0
	_particle_alpha = 0.0
	_particles.modulate = Color(1.0, 1.0, 1.0, 0.0)


func _far_mote_layer() -> CPUParticles2D:
	## Soft warm bokeh motes drifting up like brake dust in a sunset paddock.
	var particles := CPUParticles2D.new()
	particles.name = "Motes"
	particles.texture = _soft_mote_texture()
	particles.amount = _scaled_amount(FAR_MOTES_BALANCED, 0.65)
	particles.lifetime = 10.0
	particles.preprocess = 4.0
	particles.local_coords = false
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.position = size * 0.5
	particles.emission_rect_extents = size * 0.62
	particles.direction = Vector2(0.35, -1.0)
	particles.spread = 38.0
	particles.gravity = Vector2(1.5, -5.0)
	particles.initial_velocity_min = 4.0
	particles.initial_velocity_max = 13.0
	particles.damping_min = 0.4
	particles.damping_max = 1.0
	particles.angle_min = -180.0
	particles.angle_max = 180.0
	particles.angular_velocity_min = -18.0
	particles.angular_velocity_max = 18.0
	var source: float = maxf(particles.texture.get_size().x, 1.0)
	var scale_px: float = FAR_MOTE_PIXELS / source
	particles.scale_amount_min = scale_px * 0.6
	particles.scale_amount_max = scale_px * 1.7
	particles.color_ramp = _ramp(PackedColorArray([
		Color(1.0, 0.90, 0.55, 0.0), Color(1.0, 0.88, 0.52, 0.42),
		Color(0.55, 0.86, 1.0, 0.32), Color(0.95, 0.62, 0.85, 0.0)]))
	particles.speed_scale = _drift_speed_scale()
	return particles


func _near_confetti_layer() -> CPUParticles2D:
	## A handful of SlopMart confetti flakes tumbling through the foreground.
	var particles := CPUParticles2D.new()
	particles.name = "Confetti"
	particles.texture = load(CONFETTI_TEX) if ResourceLoader.exists(CONFETTI_TEX) else _soft_mote_texture()
	particles.amount = _scaled_amount(NEAR_CONFETTI_BALANCED, 0.6)
	particles.lifetime = 12.0
	particles.preprocess = 5.0
	particles.local_coords = false
	particles.emission_shape = CPUParticles2D.EMISSION_SHAPE_RECTANGLE
	particles.position = size * 0.5
	particles.emission_rect_extents = size * 0.58
	particles.direction = Vector2(0.6, -0.35)
	particles.spread = 65.0
	particles.gravity = Vector2(2.5, 3.0)
	particles.initial_velocity_min = 3.0
	particles.initial_velocity_max = 10.0
	particles.angular_velocity_min = -140.0
	particles.angular_velocity_max = 140.0
	var source: float = maxf(particles.texture.get_size().x, 1.0)
	var scale_px: float = NEAR_CONFETTI_PIXELS / source
	particles.scale_amount_min = scale_px * 0.7
	particles.scale_amount_max = scale_px * 1.5
	particles.color_ramp = _ramp(PackedColorArray([
		Color(1.0, 0.90, 0.45, 0.0), Color(1.0, 0.84, 0.32, 0.65),
		Color(0.34, 0.80, 0.96, 0.55), Color(0.96, 0.48, 0.72, 0.0)]))
	particles.speed_scale = _drift_speed_scale()
	return particles


func _tiered_amount(base: int, platform_scale: float) -> int:
	return maxi(int(round(float(base) * FxQuality.density_scale()
		* platform_scale)), 2)


func _scaled_amount(base: int, platform_scale: float) -> int:
	var amount: int = _tiered_amount(base, platform_scale)
	if FxQuality.reduce_motion():
		amount = maxi(int(round(float(amount) * 0.6)), 2)
	return amount


func _drift_speed_scale() -> float:
	if FxQuality.reduce_motion():
		return 0.35
	return 1.0


func _fit_particles() -> void:
	if _particles == null:
		return
	for raw: Variant in [_far_motes, _near_confetti]:
		var layer: CPUParticles2D = raw as CPUParticles2D
		if layer == null:
			continue
		layer.position = size * 0.5
		layer.emission_rect_extents = size * 0.62


func _on_settings_changed() -> void:
	## A quality preset change while the menu is open re-tunes the drift in
	## place instead of rebuilding the scene.
	if not show_particles:
		return
	if _far_motes != null:
		_far_motes.amount = _scaled_amount(FAR_MOTES_BALANCED, 0.65)
		_far_motes.speed_scale = _drift_speed_scale()
	if _near_confetti != null:
		_near_confetti.amount = _scaled_amount(NEAR_CONFETTI_BALANCED, 0.6)
		_near_confetti.speed_scale = _drift_speed_scale()


func _ramp(colors: PackedColorArray) -> Gradient:
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.25, 0.72, 1.0])
	gradient.colors = colors
	return gradient


static func _soft_mote_texture() -> GradientTexture2D:
	## Procedural soft dot: one shared 8x8 radial gradient, no image asset and no
	## import step, so the menu drift costs one small texture and one draw call
	## per layer on every platform.
	var gradient := Gradient.new()
	gradient.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	gradient.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0), Color(1.0, 1.0, 1.0, 0.45),
		Color(1.0, 1.0, 1.0, 0.0)])
	var texture := GradientTexture2D.new()
	texture.gradient = gradient
	texture.fill = GradientTexture2D.FILL_RADIAL
	texture.fill_from = Vector2(0.5, 0.5)
	texture.fill_to = Vector2(1.0, 0.5)
	texture.width = 8
	texture.height = 8
	return texture


func _process(delta: float) -> void:
	if _particles == null:
		return
	var target: float = _particle_target if is_visible_in_tree() else 0.0
	var rate: float = 1.0 / maxf(FADE_IN_SECONDS if target > _particle_alpha
		else FADE_OUT_SECONDS, 0.05)
	_particle_alpha = move_toward(_particle_alpha, target, delta * rate)
	_particles.modulate = Color(1.0, 1.0, 1.0, _particle_alpha)
	_particles.visible = _particle_alpha > 0.01
	if _far_motes != null:
		_far_motes.emitting = _particle_alpha > 0.01
	if _near_confetti != null:
		_near_confetti.emitting = _particle_alpha > 0.01


func _draw() -> void:
	if _art != null and _art.has_art():
		return
	var area: Vector2 = size
	if area.x < 4.0 or area.y < 4.0:
		return
	var horizon: float = area.y * 0.60
	_draw_sky(area, horizon)
	_draw_sun_glow(area, horizon)
	_draw_clouds(area)
	_draw_skyline(area, horizon)
	_draw_lot(area, horizon)
	if show_store:
		_draw_store(area, horizon)
	_draw_trees(area, horizon)
	_draw_lamps(area, horizon)
	if show_carts:
		_draw_carts(area)
	_draw_speed_marks(area)


func _draw_sky(area: Vector2, horizon: float) -> void:
	var bands: int = 56
	var mid_sky := Color("4fb6f6")
	var warm_horizon := Color("ffe8c2")
	for band in bands:
		var t: float = float(band) / float(bands - 1)
		var color: Color = UiPalette.SKY_TOP.lerp(mid_sky, clampf(t * 1.45, 0.0, 1.0))
		if t > 0.55:
			color = color.lerp(warm_horizon, (t - 0.55) / 0.45 * 0.72)
		draw_rect(Rect2(0.0, horizon * float(band) / float(bands),
			area.x, horizon / float(bands) + 1.5), color)


func _draw_sun_glow(area: Vector2, horizon: float) -> void:
	var sun_pos := Vector2(area.x * 0.22, horizon * 0.36)
	var base_r: float = area.y * 0.075
	draw_circle(sun_pos, base_r * 2.4, Color(1.0, 0.90, 0.45, 0.10))
	draw_circle(sun_pos, base_r * 1.6, Color(1.0, 0.88, 0.36, 0.18))
	draw_circle(sun_pos, base_r, Color(1.0, 0.95, 0.72, 0.88))


func _draw_clouds(area: Vector2) -> void:
	var clouds: Array[Vector3] = [
		Vector3(0.10, 0.12, 1.0),
		Vector3(0.36, 0.08, 0.72),
		Vector3(0.62, 0.15, 0.88),
		Vector3(0.86, 0.09, 1.08),
		Vector3(0.94, 0.28, 0.62),
	]
	for cloud: Vector3 in clouds:
		_cloud(Vector2(area.x * cloud.x, area.y * cloud.y), area.y * 0.048 * cloud.z)


func _cloud(center: Vector2, radius: float) -> void:
	var shadow := Color(0.76, 0.86, 0.98, 0.55)
	var white := Color(1.0, 0.99, 0.97, 0.95)
	draw_circle(center + Vector2(0.0, radius * 0.22), radius * 0.96, shadow)
	draw_circle(center + Vector2(-radius * 1.1, radius * 0.15), radius * 0.75, white)
	draw_circle(center + Vector2(radius * 1.05, radius * 0.2), radius * 0.68, white)
	draw_circle(center, radius, white)
	draw_circle(center + Vector2(-radius * 0.55, -radius * 0.35), radius * 0.62, white)
	draw_circle(center + Vector2(radius * 0.5, -radius * 0.4), radius * 0.58, white)


func _draw_skyline(area: Vector2, horizon: float) -> void:
	var far_color := Color(0.32, 0.52, 0.74, 0.38)
	var near_color := Color(0.24, 0.40, 0.62, 0.52)
	var buildings: Array[Vector4] = [
		Vector4(0.02, 0.09, 0.09, 0.0),
		Vector4(0.10, 0.14, 0.055, 1.0),
		Vector4(0.16, 0.085, 0.11, 0.0),
		Vector4(0.26, 0.15, 0.065, 1.0),
		Vector4(0.34, 0.07, 0.08, 0.0),
		Vector4(0.56, 0.10, 0.07, 0.0),
	]
	for building: Vector4 in buildings:
		var x: float = area.x * building.x
		var w: float = area.x * building.z
		var h: float = area.y * building.y
		var col: Color = near_color if building.w > 0.5 else far_color
		draw_rect(Rect2(x, horizon - h, w, h), col)


func _draw_lot(area: Vector2, horizon: float) -> void:
	var lot_top := Color("bdb3c8")
	var lot_bot := Color("8d839e")
	var bands: int = 24
	var lot_h: float = area.y - horizon
	for b in bands:
		var t: float = float(b) / float(bands - 1)
		draw_rect(Rect2(0.0, horizon + lot_h * float(b) / float(bands),
			area.x, lot_h / float(bands) + 1.5), lot_top.lerp(lot_bot, t))

	var vanish := Vector2(area.x * 0.52, horizon)
	var line_color := Color(1.0, 0.98, 0.92, 0.52)
	for index in range(-7, 6):
		var offset: float = float(index) * area.x * 0.045
		draw_line(vanish + Vector2(offset * 0.12, 0.0),
			vanish + Vector2(offset * 2.6, area.y - horizon), line_color, 4.5, true)
	draw_line(Vector2(area.x * 0.06, area.y * 0.88), Vector2(area.x * 0.15, area.y * 0.83),
		Color(1, 0.83, 0.18, 0.9), 7.0, true)
	draw_line(Vector2(area.x * 0.10, area.y * 0.90), Vector2(area.x * 0.19, area.y * 0.855),
		Color(1, 0.83, 0.18, 0.9), 7.0, true)
	draw_rect(Rect2(0.0, horizon - area.y * 0.014, area.x, area.y * 0.014), Color(0.68, 0.63, 0.74))


func _draw_store(area: Vector2, horizon: float) -> void:
	var left: float = area.x * 0.68
	var right: float = area.x * 0.94
	var top: float = horizon - area.y * 0.30
	var bottom: float = horizon + area.y * 0.06
	draw_rect(Rect2(left, top, right - left, bottom - top), Color(0.96, 0.81, 0.77))
	draw_rect(Rect2(left - 8.0, top, right - left + 16.0, area.y * 0.036), Color(0.85, 0.46, 0.42))
	draw_rect(Rect2(left, bottom - 6.0, right - left, 6.0), Color(0.68, 0.58, 0.66))

	var sign_box := Rect2(left + (right - left) * 0.12, top + area.y * 0.035,
		(right - left) * 0.76, area.y * 0.065)
	var sign_style := StyleBoxFlat.new()
	sign_style.bg_color = Color(0.92, 0.26, 0.24)
	sign_style.set_corner_radius_all(8)
	sign_style.set_border_width_all(4)
	sign_style.border_color = Color(0.58, 0.14, 0.14)
	sign_style.shadow_color = Color(1.0, 0.42, 0.30, 0.28)
	sign_style.shadow_size = 6
	draw_style_box(sign_style, sign_box)
	if _display != null:
		draw_string(_display, Vector2(sign_box.position.x, sign_box.position.y + sign_box.size.y * 0.82),
			"SlopMart", HORIZONTAL_ALIGNMENT_CENTER, sign_box.size.x, int(sign_box.size.y * 0.58),
			Color(1, 1, 1))

	var window_color := Color(0.68, 0.88, 0.98)
	var frame_color := Color(0.88, 0.52, 0.48)
	for index in 3:
		var wx: float = left + area.x * 0.015 + float(index) * (right - left) * 0.22
		var wy: float = top + area.y * 0.14
		draw_rect(Rect2(wx, wy, (right - left) * 0.16, area.y * 0.09), window_color)
		draw_rect(Rect2(wx, wy, (right - left) * 0.16, area.y * 0.09), frame_color, false, 3.0)
	var door := Rect2(left + (right - left) * 0.38, bottom - area.y * 0.115,
		(right - left) * 0.24, area.y * 0.115)
	draw_rect(door, Color(0.58, 0.82, 0.94))
	draw_rect(door, frame_color, false, 4.0)
	draw_line(Vector2(door.position.x + door.size.x * 0.5, door.position.y),
		Vector2(door.position.x + door.size.x * 0.5, door.end.y), frame_color, 3.0)


func _draw_trees(area: Vector2, horizon: float) -> void:
	var spots: Array[Vector3] = [
		Vector3(0.015, 0.0, 1.0), Vector3(0.07, 0.01, 0.8), Vector3(0.98, 0.02, 1.1),
		Vector3(0.93, 0.0, 0.9), Vector3(0.24, 0.0, 0.55),
	]
	for spot: Vector3 in spots:
		_tree(Vector2(area.x * spot.x, horizon + area.y * 0.02), area.y * 0.06 * spot.z)
	_bush(Vector2(area.x * 0.06, area.y * 1.02), area.y * 0.14)
	_bush(Vector2(area.x * 0.93, area.y * 1.04), area.y * 0.16)


func _tree(base: Vector2, radius: float) -> void:
	draw_rect(Rect2(base.x - radius * 0.12, base.y - radius * 0.7, radius * 0.24, radius * 0.7),
		Color(0.45, 0.32, 0.25))
	draw_circle(base + Vector2(0.0, -radius * 1.05), radius, UiPalette.TREE)
	draw_circle(base + Vector2(-radius * 0.7, -radius * 0.75), radius * 0.7, UiPalette.TREE)
	draw_circle(base + Vector2(radius * 0.7, -radius * 0.75), radius * 0.7, UiPalette.TREE)
	draw_circle(base + Vector2(-radius * 0.22, -radius * 1.22), radius * 0.45, UiPalette.GRASS)


func _bush(center: Vector2, radius: float) -> void:
	var color := Color(0.28, 0.64, 0.30)
	draw_circle(center + Vector2(-radius * 0.9, 0.0), radius * 0.7, color)
	draw_circle(center + Vector2(radius * 0.9, 0.0), radius * 0.75, color)
	draw_circle(center, radius, color)


func _draw_lamps(area: Vector2, horizon: float) -> void:
	_lamp(Vector2(area.x * 0.045, horizon + area.y * 0.03), area.y * 0.30)
	_lamp(Vector2(area.x * 0.955, horizon + area.y * 0.09), area.y * 0.34)


func _lamp(base: Vector2, height: float) -> void:
	var pole_color := Color(0.50, 0.54, 0.66)
	var lamp_color := Color(0.95, 0.94, 0.82)
	draw_line(base, base + Vector2(0.0, -height), pole_color, maxf(height * 0.035, 4.0))
	var head := base + Vector2(0.0, -height)
	draw_line(head + Vector2(-height * 0.16, 0.0), head + Vector2(height * 0.16, 0.0),
		pole_color, maxf(height * 0.03, 3.0))
	for side: float in [-1.0, 1.0]:
		var lamp_center := head + Vector2(side * height * 0.16, 0.0)
		draw_circle(lamp_center, height * 0.10, Color(1.0, 0.92, 0.55, 0.16))
		var lamp := Rect2(lamp_center + Vector2(-height * 0.07, -height * 0.02),
			Vector2(height * 0.14, height * 0.05))
		draw_rect(lamp, lamp_color)
		draw_rect(lamp, pole_color, false, 2.0)


func _draw_carts(area: Vector2) -> void:
	CartDrawing.draw_cart(self, Vector2(area.x * 0.115, area.y * 0.945),
		area.y * 0.00195, false)
	CartDrawing.draw_cart(self, Vector2(area.x * 0.885, area.y * 0.88),
		area.y * 0.00170, true)


func _draw_speed_marks(area: Vector2) -> void:
	var marks: Array[Vector4] = [
		Vector4(0.26, 0.10, 0.055, -0.25),
		Vector4(0.285, 0.155, 0.04, -0.25),
		Vector4(0.735, 0.14, 0.05, 0.25),
		Vector4(0.755, 0.195, 0.035, 0.25),
	]
	for mark: Vector4 in marks:
		var center := Vector2(area.x * mark.x, area.y * mark.y)
		var half: float = area.x * mark.z * 0.5
		draw_set_transform(center, mark.w, Vector2.ONE)
		draw_line(Vector2(-half, 0.0), Vector2(half, 0.0), UiPalette.YELLOW, area.y * 0.020, true)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
