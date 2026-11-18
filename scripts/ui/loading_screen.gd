extends Control
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
## Themed loading overlay: full-bleed concept artwork, smooth rainbow progress
## bar, destination title + hint from SceneLoader.go_to(), and rotating tip
## anchored cleanly above SCREEN_MARGIN = 24 without bar-shadow overlap.

const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const CartDrawing := preload("res://scripts/ui/cart_drawing.gd")
const DISPLAY_FONT := "res://assets/ui/fonts/LuckiestGuy-Regular.ttf"
const ART_PATHS: PackedStringArray = [
	"res://assets/ui/art/bg_parking.png",
	"res://assets/ui/art/scene_track_aerial.png",
	"res://assets/ui/art/scene_road.png",
	"res://assets/ui/art/scene_arena.png",
	"res://assets/ui/art/scene_finish.png",
]

const TIPS: PackedStringArray = [
	"TIP: Hold SPACE to drift and charge a 3-tier speed boost.",
	"TIP: Boost pads refill your meter instantly.",
	"TIP: You can launch off speed bumps — floor it.",
	"TIP: Press R to reset your cart back onto the track.",
	"TIP: Crates and cones are light — smash right through them.",
]

const BAR_X: float = 0.15
const BAR_W: float = 0.70
const SAFE_BOTTOM: float = 24.0
const TIP_HEIGHT: float = 24.0
const BAR_BOTTOM_CLEARANCE: float = 70.0 ## Clears 24 px margin + 24 px tip + 22 px shadow gap.

var progress: float = 0.0
var indeterminate: bool = false

var _time: float = 0.0
var _shown: float = 0.0
var _tip_index: int = 0
var _tip_timer: float = 0.0
var _title_label: Label
var _tip_label: Label
var _percent_label: Label
var _caption_label: Label
var _message_label: Label
var _display: Font
var _art: Texture2D
var _art_index: int = -1
var _task_mode: bool = false
var _task_title: String = ""
var _task_message: String = ""
var _last_percent: int = -1


func _ready() -> void:
	_display = load(DISPLAY_FONT)
	randomize_art()
	mouse_filter = Control.MOUSE_FILTER_STOP
	_title_label = get_node_or_null("Title") as Label
	_tip_label = get_node_or_null("Tip") as Label
	_percent_label = get_node_or_null("Percent") as Label
	_caption_label = get_node_or_null("Caption") as Label
	_message_label = get_node_or_null("Message") as Label
	if _title_label != null:
		_title_label.visible = false
	_place_labels()
	resized.connect(_on_resized)
	_show_tip()
	_refresh_labels()


func _on_resized() -> void:
	_place_labels()
	queue_redraw()


func _bar_rect(area: Vector2) -> Rect2:
	var bar_h: float = clampf(area.y * 0.042, 26.0, 34.0)
	var bar_top: float = maxf(area.y - BAR_BOTTOM_CLEARANCE - bar_h, 64.0)
	return Rect2(area.x * BAR_X, bar_top, area.x * BAR_W, bar_h)


func _place_labels() -> void:
	var area: Vector2 = size if size.y > 1.0 else get_viewport_rect().size
	var bar: Rect2 = _bar_rect(area)
	if _percent_label != null:
		_percent_label.anchor_left = 0.0
		_percent_label.anchor_right = 0.0
		_percent_label.anchor_top = 0.0
		_percent_label.anchor_bottom = 0.0
		_percent_label.offset_left = bar.end.x - 160.0
		_percent_label.offset_right = bar.end.x
		_percent_label.offset_top = bar.position.y - 46.0
		_percent_label.offset_bottom = bar.position.y - 6.0
		_percent_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
		_percent_label.vertical_alignment = VERTICAL_ALIGNMENT_BOTTOM
		_percent_label.add_theme_font_size_override("font_size", 32)
	if _tip_label != null:
		_tip_label.anchor_left = 0.0
		_tip_label.anchor_right = 1.0
		_tip_label.anchor_top = 1.0
		_tip_label.anchor_bottom = 1.0
		_tip_label.offset_left = SAFE_BOTTOM
		_tip_label.offset_right = -SAFE_BOTTOM
		_tip_label.offset_top = -(SAFE_BOTTOM + TIP_HEIGHT)
		_tip_label.offset_bottom = -SAFE_BOTTOM
		_tip_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_tip_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	if _title_label != null:
		_title_label.visible = false
	if _caption_label != null:
		_caption_label.visible = false
	if _message_label != null:
		_message_label.visible = false


func set_progress(value: float, immediate: bool = false) -> void:
	progress = clampf(value, 0.0, 1.0)
	if immediate:
		_shown = progress
		_refresh_labels()
	queue_redraw()


func set_indeterminate(value: bool) -> void:
	indeterminate = value
	if value:
		_shown = 0.0
	else:
		_shown = progress
	_refresh_labels()
	queue_redraw()


func set_destination(title: String, hint: String = "") -> void:
	if _title_label != null:
		_title_label.text = title
	if _message_label != null:
		_message_label.text = hint
	queue_redraw()


func _process(delta: float) -> void:
	if not is_visible_in_tree():
		return
	_time += delta
	if not indeterminate:
		_shown = UiAnim.damp(_shown, progress, delta, 14.0)
		if absf(_shown - progress) < 0.001:
			_shown = progress
	_tip_timer += delta
	if _tip_timer >= 4.5:
		_tip_timer = 0.0
		_tip_index = (_tip_index + 1) % TIPS.size()
		_show_tip()
	_refresh_labels()
	queue_redraw()


func _refresh_labels() -> void:
	if _percent_label != null:
		_percent_label.visible = not indeterminate
		if not indeterminate:
			var percent: int = int(round(_shown * 100.0))
			if percent != _last_percent:
				_last_percent = percent
				_percent_label.text = "%d%%" % percent
	if _title_label != null:
		_title_label.visible = false
	if _caption_label != null:
		_caption_label.visible = false
	if _message_label != null:
		_message_label.visible = false
	if _tip_label != null:
		_tip_label.visible = _tip_label.text != ""


func _show_tip() -> void:
	if _tip_label == null or TIPS.is_empty():
		return
	_tip_label.text = TIPS[_tip_index % TIPS.size()]


func _fill_ratio() -> float:
	if indeterminate:
		return 0.5 + 0.32 * sin(_time * 1.5)
	return _shown


func set_task(active: bool, title: String = "", message: String = "") -> void:
	_task_mode = active
	_task_title = title
	_task_message = message
	queue_redraw()


func _resolved_heading() -> String:
	if _task_mode and _task_title.strip_edges() != "":
		return _task_title.strip_edges().to_upper()
	if _title_label != null:
		var dest: String = _title_label.text.strip_edges()
		if dest != "" and dest.to_upper() != "LOADING":
			return dest.to_upper()
	return "LOADING..."


func _resolved_hint() -> String:
	if _task_mode:
		return _task_message.strip_edges()
	if _message_label != null:
		var msg: String = _message_label.text.strip_edges()
		if msg != "":
			return msg
	if _caption_label != null:
		var cap: String = _caption_label.text.strip_edges()
		if cap != "" and cap.to_upper() != "LOADING SCENE":
			return cap
	return ""


func randomize_art() -> void:
	if ART_PATHS.is_empty():
		return
	var next: int = randi_range(0, ART_PATHS.size() - 1)
	if ART_PATHS.size() > 1 and next == _art_index:
		next = (next + 1) % ART_PATHS.size()
	_art_index = next
	var path: String = ART_PATHS[next]
	_art = load(path) as Texture2D if ResourceLoader.exists(path) else null
	queue_redraw()


func _draw() -> void:
	var area: Vector2 = size
	if area.x < 4.0 or area.y < 4.0:
		return
	if _art != null:
		_draw_art(area)
	else:
		_draw_sky(area)
		_draw_sun(area)
		_draw_clouds(area)
		_draw_hills(area)
		_draw_backdrop(area)
	_draw_scrim(area)
	_draw_bar(area)


func _draw_art(area: Vector2) -> void:
	var source: Vector2 = _art.get_size()
	if source.x <= 0.0 or source.y <= 0.0:
		return
	var cover_scale: float = maxf(area.x / source.x, area.y / source.y)
	var drawn: Vector2 = source * cover_scale
	var origin: Vector2 = (area - drawn) * 0.5
	draw_texture_rect(_art, Rect2(origin, drawn), false)


func _draw_sky(area: Vector2) -> void:
	var bands: int = 40
	for band in bands:
		var t: float = float(band) / float(bands - 1)
		var color: Color = UiPalette.SKY_TOP.lerp(UiPalette.SKY_BOTTOM, t)
		draw_rect(Rect2(0.0, area.y * float(band) / float(bands) * 0.62,
			area.x, area.y * 0.62 / float(bands) + 1.0), color)


func _draw_sun(area: Vector2) -> void:
	var center := Vector2(area.x * 0.82, area.y * 0.15)
	var radius: float = area.y * 0.075
	draw_circle(center, radius * 1.5, Color(UiPalette.YELLOW, 0.16))
	draw_circle(center, radius, Color(UiPalette.YELLOW, 0.95))
	for i in 3:
		var y: float = center.y + radius * (0.25 + 0.22 * i)
		var half: float = sqrt(maxf(radius * radius - pow(y - center.y, 2.0), 0.0))
		draw_rect(Rect2(center.x - half, y, half * 2.0, radius * 0.06),
			Color(UiPalette.RED, 0.35))


func _draw_clouds(area: Vector2) -> void:
	var clouds: Array[Vector4] = [
		Vector4(0.10, 0.15, 1.0, 12.0),
		Vector4(0.36, 0.10, 0.7, 18.0),
		Vector4(0.62, 0.20, 0.55, 8.0),
		Vector4(0.90, 0.27, 0.8, 14.0),
	]
	for cloud: Vector4 in clouds:
		var x: float = fposmod(area.x * cloud.x + _time * cloud.w, area.x + 260.0) - 130.0
		var center := Vector2(x, area.y * cloud.y)
		var radius: float = area.y * 0.035 * cloud.z
		var white := Color(1, 1, 1, 0.92)
		draw_circle(center, radius, white)
		draw_circle(center + Vector2(-radius * 1.1, radius * 0.2), radius * 0.75, white)
		draw_circle(center + Vector2(radius * 1.05, radius * 0.25), radius * 0.65, white)


func _draw_hills(area: Vector2) -> void:
	var base_y: float = area.y * 0.46
	for layer in 2:
		var color := Color(0.24, 0.55, 0.34, 0.55) if layer == 0 \
			else Color(0.19, 0.45, 0.29, 0.75)
		var points := PackedVector2Array()
		var steps: int = 32
		var amp: float = area.y * (0.045 - layer * 0.012)
		var phase: float = layer * 1.7
		for step in steps + 1:
			var t: float = float(step) / float(steps)
			var y: float = base_y + layer * 10.0 - sin(t * PI * 2.0 + phase) * amp \
				- sin(t * PI * 5.0 + phase) * amp * 0.25
			points.append(Vector2(t * area.x, y))
		points.append(Vector2(area.x, area.y))
		points.append(Vector2(0.0, area.y))
		draw_colored_polygon(points, color)
	draw_rect(Rect2(0.0, base_y, area.x, area.y - base_y), Color(0.80, 0.75, 0.81, 0.58))


func _draw_backdrop(area: Vector2) -> void:
	var vanish := Vector2(area.x * 0.50, area.y * 0.47)
	for index in range(-4, 5):
		if index == 0:
			continue
		var bottom := vanish + Vector2(float(index) * area.x * 0.18, area.y * 0.30)
		draw_line(vanish, bottom, Color(1, 1, 1, 0.32), 2.0, true)

	var left: float = area.x * 0.79
	var right: float = area.x * 0.975
	var top: float = area.y * 0.315
	var bottom: float = area.y * 0.465
	draw_rect(Rect2(left, top, right - left, bottom - top), Color(0.96, 0.79, 0.76))
	draw_rect(Rect2(left - 5.0, top, right - left + 10.0, area.y * 0.022),
		Color(0.85, 0.50, 0.46))
	draw_rect(Rect2(left, bottom - 4.0, right - left, 4.0), Color(0.72, 0.62, 0.68))
	var sign_box := Rect2(left + (right - left) * 0.10, top + area.y * 0.022,
		(right - left) * 0.80, area.y * 0.040)
	var sign_style := StyleBoxFlat.new()
	sign_style.bg_color = Color(0.91, 0.27, 0.24)
	sign_style.set_corner_radius_all(6)
	sign_style.set_border_width_all(3)
	sign_style.border_color = Color(0.66, 0.16, 0.15)
	draw_style_box(sign_style, sign_box)
	if _display != null:
		draw_string(_display, Vector2(sign_box.position.x,
			sign_box.position.y + sign_box.size.y * 0.82), "SLOPMART",
			HORIZONTAL_ALIGNMENT_CENTER, sign_box.size.x,
			int(sign_box.size.y * 0.62), Color(1, 1, 1))
	for index in 2:
		var window := Rect2(left + (right - left) * (0.15 + float(index) * 0.46),
			top + area.y * 0.085, (right - left) * 0.24, area.y * 0.050)
		draw_rect(window, Color(0.72, 0.88, 0.96))
		draw_rect(window, Color(0.90, 0.55, 0.50), false, 2.0)
	_small_tree(Vector2(area.x * 0.06, area.y * 0.470), area.y * 0.028)
	_small_tree(Vector2(area.x * 0.15, area.y * 0.466), area.y * 0.022)


func _small_tree(base: Vector2, radius: float) -> void:
	draw_rect(Rect2(base.x - radius * 0.10, base.y - radius * 0.7,
		radius * 0.20, radius * 0.7), Color(0.45, 0.32, 0.25))
	draw_circle(base + Vector2(0.0, -radius), radius, UiPalette.TREE)
	draw_circle(base + Vector2(-radius * 0.65, -radius * 0.75), radius * 0.65,
		UiPalette.TREE)
	draw_circle(base + Vector2(radius * 0.65, -radius * 0.75), radius * 0.65,
		UiPalette.TREE)


func _draw_scrim(area: Vector2) -> void:
	## Soft bottom gradient scrim so destination text, progress bar, and tip
	## stay legible over any bright background illustration.
	var top: float = area.y * 0.62
	var height: float = area.y - top
	var bands: int = 48
	var step: float = height / float(bands)
	for band in bands:
		var t: float = (float(band) + 0.5) / float(bands)
		var alpha: float = 0.46 * pow(t, 1.35)
		draw_rect(Rect2(0.0, top + step * float(band), area.x, step),
			Color(0.05, 0.07, 0.16, alpha))


func _draw_outlined_text(font: Font, pos: Vector2, text_value: String,
		font_size: int, fill: Color, max_w: float = -1.0) -> void:
	for offset: Vector2 in [Vector2(-2, 0), Vector2(2, 0), Vector2(0, -2),
			Vector2(0, 2), Vector2(-1, -1), Vector2(1, 1)]:
		draw_string(font, pos + offset, text_value,
			HORIZONTAL_ALIGNMENT_LEFT, max_w, font_size, UiPalette.OUTLINE)
	draw_string(font, pos, text_value,
		HORIZONTAL_ALIGNMENT_LEFT, max_w, font_size, fill)


func _draw_bar(area: Vector2) -> void:
	var bar: Rect2 = _bar_rect(area)
	var ratio: float = clampf(_fill_ratio(), 0.0, 1.0)
	var radius: float = bar.size.y * 0.5

	var track := StyleBoxFlat.new()
	track.bg_color = Color(0.05, 0.07, 0.15, 0.92)
	track.set_corner_radius_all(int(radius))
	track.set_border_width_all(4)
	track.border_color = UiPalette.CREAM
	track.shadow_color = Color(0.03, 0.03, 0.08, 0.42)
	track.shadow_size = 8
	track.shadow_offset = Vector2(0, 4)
	draw_style_box(track, bar)

	var inner := Rect2(bar.position + Vector2(4, 4), bar.size - Vector2(8, 8))
	var fill_width: float = inner.size.x * ratio
	if fill_width > 1.0:
		var strips: int = 48
		var strip_width: float = inner.size.x / float(strips)
		for strip in strips:
			var t: float = float(strip) / float(strips - 1)
			var x: float = inner.position.x + strip_width * float(strip)
			if x > inner.position.x + fill_width:
				break
			var width: float = minf(strip_width + 1.0,
				inner.position.x + fill_width - x)
			var hue: float = fposmod(t * 0.82 + _time * 0.035, 1.0)
			var color := Color.from_hsv(hue, 0.72, 1.0)
			draw_rect(Rect2(x, inner.position.y, width, inner.size.y), color)
		var shine_x: float = inner.position.x + fposmod(_time * 220.0,
			inner.size.x + 160.0) - 160.0
		for stripe in 2:
			var sx: float = shine_x + float(stripe) * 42.0
			if sx > inner.position.x and sx < inner.position.x + fill_width - 10.0:
				draw_rect(Rect2(sx, inner.position.y + 3.0, 10.0,
					inner.size.y - 6.0), Color(1, 1, 1, 0.22))
		# Glossy top-half specular sheen across the active loading bar.
		draw_rect(Rect2(inner.position.x + 4.0, inner.position.y + 2.0,
			maxf(fill_width - 8.0, 0.0), maxf(inner.size.y * 0.34, 3.0)),
			Color(1.0, 1.0, 1.0, 0.28))

	if _display != null:
		var heading: String = _resolved_heading()
		var hint: String = _resolved_hint()
		var max_text_w: float = maxf(bar.size.x - 160.0, 120.0)
		if hint != "":
			_draw_outlined_text(_display,
				Vector2(bar.position.x + 2.0, bar.position.y - 30.0),
				heading, 26, UiPalette.YELLOW, max_text_w)
			_draw_outlined_text(_display,
				Vector2(bar.position.x + 3.0, bar.position.y - 10.0),
				hint.to_upper(), 15, UiPalette.CREAM, max_text_w)
		else:
			_draw_outlined_text(_display,
				Vector2(bar.position.x + 2.0, bar.position.y - 12.0),
				heading, 26, UiPalette.CREAM, max_text_w)
