extends Control
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
## AAA slanted arcade transition overlay:
## - Destination-aware full-bleed concept / map preview artwork
## - Chunky 16-cell skewed parallelogram progress bar (`SKEW = 10.0`, thick
##   `#1e1b3a` ink frame + hard `(5, 6)` comic shadow, vibrant gold->cyan->pink
##   slanted cells with a soft vertical-fade top gloss, gradient leading edge)
## - Bold 42px LuckiestGuy destination heading + `%` readout aligned above the
##   bar, with a concise single-line tip centered below.
## - `progress` is monotonic within one load (a lower re-send is clamped up; an
##   explicit immediate 0.0 resets for the next load) and only SceneLoader's
##   final "gameplay is live" step reports 100%, where the heading gains READY.

const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const CartDrawing := preload("res://scripts/ui/cart_drawing.gd")
const ART_DIR: String = "res://assets/ui/art/"
const DISPLAY_FONT: String = "res://assets/ui/fonts/LuckiestGuy-Regular.ttf"

const ART_PATHS: PackedStringArray = [
	"res://assets/ui/art/bg_hero_paddock.png",
	"res://assets/ui/art/bg_hero_canyon.png",
	"res://assets/ui/art/bg_hero_arena.png",
	"res://assets/ui/art/bg_hero_glacier.png",
	"res://assets/ui/art/preview_stadium.png",
	"res://assets/ui/art/preview_canyon.png",
	"res://assets/ui/art/preview_glacier.png",
	"res://assets/ui/art/preview_dockyard.png",
	"res://assets/ui/art/preview_meadow.png",
]

## Ordered specific-first so arena sub-maps match before mode names.
const DESTINATION_PREVIEWS: Array[Array] = [
	["harbour overpass", "preview_harbour.png"],
	["harbour", "preview_harbour.png"],
	["windmill hills", "preview_farmyard.png"],
	["farmyard", "preview_farmyard.png"],
	["glacier bowl", "preview_snowfield.png"],
	["snowfield", "preview_snowfield.png"],
	["skytop helipad", "preview_ko_rooftop.png"],
	["ko_rooftop", "preview_ko_rooftop.png"],
	["helipad", "preview_ko_rooftop.png"],
	["molten foundry", "preview_ko_foundry.png"],
	["ko_foundry", "preview_ko_foundry.png"],
	["foundry", "preview_ko_foundry.png"],
	["fractured iceberg", "preview_ko_iceberg.png"],
	["ko_iceberg", "preview_ko_iceberg.png"],
	["iceberg", "preview_ko_iceberg.png"],
	["terrace plaza", "preview_bt_plaza.png"],
	["bt_plaza", "preview_bt_plaza.png"],
	["canyon labyrinth", "preview_bt_labyrinth.png"],
	["bt_labyrinth", "preview_bt_labyrinth.png"],
	["labyrinth", "preview_bt_labyrinth.png"],
	["twin ferries", "preview_bt_ferries.png"],
	["bt_ferries", "preview_bt_ferries.png"],
	["ferries", "preview_bt_ferries.png"],
	["stadium circuit", "preview_stadium.png"],
	["stadium", "preview_stadium.png"],
	["redwood valley", "preview_meadow.png"],
	["meadow", "preview_meadow.png"],
	["sunset canyon", "preview_canyon.png"],
	["canyon", "preview_canyon.png"],
	["dockyard quay", "preview_dockyard.png"],
	["dockyard", "preview_dockyard.png"],
	["glacier pass", "preview_glacier.png"],
	["glacier", "preview_glacier.png"],
	["cargo_rush", "preview_cargo_rush.png"],
	["cargo rush", "preview_cargo_rush.png"],
	["deliver", "preview_cargo_rush.png"],
	["knockout", "preview_knockout.png"],
	["bomb_tag", "preview_bomb_tag.png"],
	["blast tag", "preview_bomb_tag.png"],
	["bomb tag", "preview_bomb_tag.png"],
	["sandbox", "preview_sandbox.png"],
	["stunt park", "preview_sandbox.png"],
	["let's drive", "preview_sandbox.png"],
]

const TIPS: PackedStringArray = [
	"TIP: Hold SPACE to drift and charge a 3-tier speed boost.",
	"TIP: Drive over boost pads to refill your meter instantly.",
	"TIP: Hit speed bumps at full boost for huge air.",
	"TIP: Press R anytime to reset your cart onto the track.",
	"TIP: Heavy rides resist knockback in arena brawls.",
]

const BAR_SEGMENTS: int = 16
const BAR_SKEW: float = 10.0
const BAR_GAP: float = 5.0
const BAR_W_RATIO: float = 0.72
const SAFE_BOTTOM: float = 24.0
const TIP_HEIGHT: float = 24.0
const BAR_BOTTOM_CLEARANCE: float = 68.0

var progress: float = 0.0
var indeterminate: bool = false

var _time: float = 0.0
var _shown: float = 0.0
var _progress_high: float = 0.0 ## Monotonic floor for one load; reset by 0/immediate.
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
var _dest_title: String = ""
var _dest_hint: String = ""
var _last_percent: int = -1


func _ready() -> void:
	_display = load(DISPLAY_FONT)
	mouse_filter = Control.MOUSE_FILTER_STOP
	_title_label = get_node_or_null("Title") as Label
	_tip_label = get_node_or_null("Tip") as Label
	_percent_label = get_node_or_null("Percent") as Label
	_caption_label = get_node_or_null("Caption") as Label
	_message_label = get_node_or_null("Message") as Label
	randomize_art()
	_place_labels()
	resized.connect(_on_resized)
	_show_tip()
	_refresh_labels()


func _on_resized() -> void:
	_place_labels()
	queue_redraw()


func _bar_rect(area: Vector2) -> Rect2:
	var bar_h: float = clampf(area.y * 0.048, 30.0, 38.0)
	var bar_w: float = clampf(area.x * BAR_W_RATIO, 360.0, 960.0)
	var bar_x: float = (area.x - bar_w) * 0.5
	var bar_top: float = maxf(area.y - BAR_BOTTOM_CLEARANCE - bar_h, 80.0)
	return Rect2(bar_x, bar_top, bar_w, bar_h)


func _place_labels() -> void:
	var area: Vector2 = size if size.y > 1.0 else get_viewport_rect().size
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
		_tip_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		_tip_label.max_lines_visible = 1
		_tip_label.clip_text = true
		_tip_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	if _percent_label != null:
		_percent_label.visible = false
	if _title_label != null:
		_title_label.visible = false
	if _caption_label != null:
		_caption_label.visible = false
	if _message_label != null:
		_message_label.visible = false
	if area.x > 0.0:
		queue_redraw()


func set_progress(value: float, immediate: bool = false) -> void:
	## A load's bar never moves backwards. SceneLoader's weighted phases are
	## monotonic by construction, but a loader that reports a dip (or a caller
	## that re-sends a stale value) must not make the readout jump down.
	var clamped: float = clampf(value, 0.0, 1.0)
	if immediate and clamped <= 0.001:
		_progress_high = 0.0
		progress = 0.0
		_shown = 0.0
		_last_percent = 0
		_refresh_labels()
		queue_redraw()
		return
	clamped = maxf(clamped, _progress_high)
	_progress_high = clamped
	progress = clamped
	if immediate:
		_shown = progress
		_refresh_labels()
	queue_redraw()


func set_indeterminate(value: bool) -> void:
	indeterminate = value
	_shown = 0.0 if value else progress
	_refresh_labels()
	queue_redraw()


func set_destination(title: String, hint: String = "") -> void:
	_dest_title = title
	_dest_hint = hint
	if _title_label != null:
		_title_label.text = title
	if _message_label != null:
		_message_label.text = hint
	_try_apply_destination_art(title, hint)
	queue_redraw()


func set_task(active: bool, title: String = "", message: String = "") -> void:
	_task_mode = active
	_task_title = title
	_task_message = message
	if not active:
		_dest_title = ""
		_dest_hint = ""
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
		_percent_label.visible = false
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
		return 0.5 + 0.34 * sin(_time * 1.6)
	return _shown


func _resolved_heading() -> String:
	if _task_mode and _task_title.strip_edges() != "":
		return _task_title.strip_edges().to_upper()
	if _title_label != null:
		var dest: String = _title_label.text.strip_edges()
		if dest != "" and dest.to_upper() != "LOADING":
			return dest.to_upper()
	if _dest_title.strip_edges() != "" and _dest_title.strip_edges().to_upper() != "LOADING":
		return _dest_title.strip_edges().to_upper()
	return "LOADING..."


func _resolved_hint() -> String:
	if _task_mode:
		return _task_message.strip_edges()
	if _message_label != null:
		var msg: String = _message_label.text.strip_edges()
		if msg != "":
			return msg
	if _dest_hint.strip_edges() != "":
		return _dest_hint.strip_edges()
	if _caption_label != null:
		var cap: String = _caption_label.text.strip_edges()
		if cap != "" and cap.to_upper() != "LOADING SCENE":
			return cap
	return ""


func _try_apply_destination_art(title: String, hint: String) -> bool:
	# Check hint first (more specific arena map), then title (track or mode).
	for candidate: String in [hint, title]:
		var needle: String = candidate.strip_edges().to_lower()
		if needle == "":
			continue
		for pair: Array in DESTINATION_PREVIEWS:
			var token: String = str(pair[0])
			var file_name: String = str(pair[1])
			if needle.contains(token):
				var full_path: String = ART_DIR + file_name
				if ResourceLoader.exists(full_path):
					var tex: Texture2D = load(full_path) as Texture2D
					if tex != null:
						_art = tex
						return true
	return false


func randomize_art() -> void:
	if _try_apply_destination_art(_resolved_heading(), _resolved_hint()):
		queue_redraw()
		return
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
		draw_rect(Rect2(Vector2.ZERO, area), UiPalette.SURFACE_DARK)
	_draw_scrim(area)
	_draw_bar(area)


func _draw_art(area: Vector2) -> void:
	var source: Vector2 = _art.get_size()
	if source.x <= 0.0 or source.y <= 0.0:
		return
	var reduce: bool = GameSettings.reduce_motion if GameSettings != null else false
	var zoom: float = 1.0 if reduce else (1.03 + 0.03 * sin(_time * 0.45))
	var pan_x: float = 0.0 if reduce else (sin(_time * 0.35) * 14.0)
	var cover_scale: float = maxf(area.x / source.x, area.y / source.y) * zoom
	var drawn: Vector2 = (source * cover_scale).round()
	var origin: Vector2 = ((area - drawn) * 0.5 + Vector2(pan_x, 0.0)).round()
	draw_texture_rect(_art, Rect2(origin, drawn), false)


func _draw_scrim(area: Vector2) -> void:
	## Smooth bottom cinematic scrim so the 42px heading, 16-cell parallelogram
	## bar, percentage readout, and tip pop cleanly over bright map previews.
	var top: float = area.y * 0.52
	var height: float = area.y - top
	var bands: int = 44
	var step: float = height / float(bands)
	for band in bands:
		var t: float = (float(band) + 0.5) / float(bands)
		var alpha: float = 0.68 * pow(t, 1.30)
		draw_rect(Rect2(0.0, top + step * float(band), area.x, step + 1.0),
			Color(0.04, 0.05, 0.14, alpha))


func _draw_comic_text(font: Font, pos: Vector2, text_value: String,
		font_size: int, fill: Color, outline_px: float = 4.0,
		shadow_ofs: Vector2 = Vector2(3.0, 4.0), max_w: float = -1.0) -> void:
	# Hard comic shadow in #1e1b3a.
	draw_string(font, pos + shadow_ofs, text_value,
		HORIZONTAL_ALIGNMENT_LEFT, max_w, font_size, Color(UiPalette.INK.r, UiPalette.INK.g, UiPalette.INK.b, 0.85))
	var d: float = outline_px * 0.72
	for offset: Vector2 in [
		Vector2(-outline_px, 0.0), Vector2(outline_px, 0.0),
		Vector2(0.0, -outline_px), Vector2(0.0, outline_px),
		Vector2(-d, -d), Vector2(d, -d), Vector2(-d, d), Vector2(d, d),
	]:
		draw_string(font, pos + offset, text_value,
			HORIZONTAL_ALIGNMENT_LEFT, max_w, font_size, UiPalette.INK)
	draw_string(font, pos, text_value,
		HORIZONTAL_ALIGNMENT_LEFT, max_w, font_size, fill)


func _cell_color(t: float) -> Color:
	if t <= 0.5:
		return UiPalette.YELLOW.lerp(UiPalette.CYAN, t * 2.0)
	return UiPalette.CYAN.lerp(UiPalette.PINK, (t - 0.5) * 2.0)


func _para_poly(x: float, y: float, w: float, h: float, skew_px: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(x + skew_px, y),
		Vector2(x + skew_px + w, y),
		Vector2(x + w, y + h),
		Vector2(x, y + h),
	])


func _closed_poly(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	if not out.is_empty():
		out.append(out[0])
	return out


func _draw_bar(area: Vector2) -> void:
	var bar: Rect2 = _bar_rect(area)
	var ratio: float = clampf(_fill_ratio(), 0.0, 1.0)

	# Outer slanted parallelogram frame + hard (5, 6) comic shadow.
	var outer_skew: float = BAR_SKEW + 2.0
	var frame_body_w: float = maxf(bar.size.x - outer_skew, 40.0)
	var frame_pts: PackedVector2Array = _para_poly(
		bar.position.x, bar.position.y, frame_body_w, bar.size.y, outer_skew)
	var shadow_pts: PackedVector2Array = _para_poly(
		bar.position.x + 5.0, bar.position.y + 6.0, frame_body_w, bar.size.y, outer_skew)
	draw_colored_polygon(shadow_pts, Color(UiPalette.INK.r, UiPalette.INK.g, UiPalette.INK.b, 0.80))
	draw_colored_polygon(frame_pts, UiPalette.INK)

	var recess_inset: float = 4.0
	var recess_pts: PackedVector2Array = _para_poly(
		bar.position.x + recess_inset, bar.position.y + recess_inset,
		maxf(frame_body_w - recess_inset * 2.0, 20.0),
		maxf(bar.size.y - recess_inset * 2.0, 10.0), BAR_SKEW)
	draw_colored_polygon(recess_pts, Color(0.06, 0.08, 0.17, 0.96))
	draw_polyline(_closed_poly(frame_pts), UiPalette.INK, 4.0, true)

	# 16 inner skewed parallelogram power cells centered inside the frame.
	var pad_v: float = 6.0
	var cell_y: float = bar.position.y + pad_v
	var cell_h: float = maxf(bar.size.y - pad_v * 2.0, 10.0)
	var usable_span: float = bar.size.x - 16.0
	var cell_w: float = (usable_span - BAR_SKEW - BAR_GAP * float(BAR_SEGMENTS - 1)) / float(BAR_SEGMENTS)
	if cell_w > 2.0:
		var total_span: float = float(BAR_SEGMENTS) * cell_w + float(BAR_SEGMENTS - 1) * BAR_GAP + BAR_SKEW
		var start_x: float = (area.x - total_span) * 0.5
		var filled: float = ratio * float(BAR_SEGMENTS)

		for i in BAR_SEGMENTS:
			var cx: float = start_x + float(i) * (cell_w + BAR_GAP)
			var slot_pts: PackedVector2Array = _para_poly(cx, cell_y, cell_w, cell_h, BAR_SKEW)
			draw_colored_polygon(slot_pts, Color(0.13, 0.16, 0.28, 0.92))

			var amount: float = clampf(filled - float(i), 0.0, 1.0)
			if amount > 0.003:
				var t: float = float(i) / float(BAR_SEGMENTS - 1)
				var seg_col: Color = _cell_color(t)
				var lit_w: float = cell_w * amount
				var soft_w: float = minf(14.0, lit_w)
				var solid_w: float = maxf(lit_w - soft_w, 0.0)
				if solid_w > 0.5:
					var solid_pts: PackedVector2Array = _para_poly(cx, cell_y, solid_w, cell_h, BAR_SKEW)
					draw_colored_polygon(solid_pts, seg_col)
				# Soft leading edge: the partially filled cell fades into the empty
				# slot instead of ending on a hard vertical line.
				if soft_w > 0.5:
					var lead_pts: PackedVector2Array = _para_poly(
						cx + solid_w, cell_y, soft_w, cell_h, BAR_SKEW)
					draw_polygon(lead_pts, PackedColorArray([
						seg_col, Color(seg_col.r, seg_col.g, seg_col.b, 0.0),
						Color(seg_col.r, seg_col.g, seg_col.b, 0.0), seg_col,
					]))

				if lit_w > 2.0:
					var gloss_h: float = maxf(cell_h * 0.36, 3.0)
					var gloss_pts: PackedVector2Array = _para_poly(
						cx + BAR_SKEW * 0.62, cell_y + 1.5,
						maxf(solid_w + soft_w * 0.5 - 1.5, 0.8), gloss_h, BAR_SKEW * 0.34)
					UiAnim.draw_vertical_fade(self, gloss_pts, Color.WHITE, 0.38)

			draw_polyline(_closed_poly(slot_pts), UiPalette.INK, 2.0, true)

	# Zipping mini turbo shopping cart riding atop the leading edge of the bar.
	var cart_x: float = clampf(bar.position.x + 28.0 + (bar.size.x - 56.0) * ratio,
		bar.position.x + 28.0, bar.end.x - 28.0)
	var bounce_y: float = absf(sin(_time * 12.0)) * 3.0 if not (GameSettings != null and GameSettings.reduce_motion) else 0.0
	CartDrawing.draw_cart(self, Vector2(cart_x, bar.position.y - 2.0 - bounce_y), 0.24, false)

	if _display == null:
		return

	var heading: String = _resolved_heading()
	var hint: String = _resolved_hint().to_upper()
	if not indeterminate and _shown >= 0.999 and heading != "LOADING..." \
			and not _task_mode:
		heading += "  ·  READY"
	if hint == heading:
		hint = ""

	# Right-aligned percentage readout above the bar's right edge.
	var pct_reserved_w: float = 0.0
	if not indeterminate:
		var pct_text: String = "%d%%" % int(round(_shown * 100.0))
		var pct_font_size: int = 38
		var pct_w: float = _display.get_string_size(pct_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, pct_font_size).x
		pct_reserved_w = pct_w + 24.0
		var pct_x: float = bar.end.x - pct_w - 2.0
		_draw_comic_text(_display, Vector2(pct_x, bar.position.y - 16.0),
			pct_text, pct_font_size, UiPalette.YELLOW, 4.0, Vector2(3.0, 4.0))

	# Destination heading (42px LuckiestGuy) + optional concise subtitle above left edge.
	var max_heading_w: float = maxf(bar.size.x - pct_reserved_w - 16.0, 180.0)
	var heading_x: float = bar.position.x + BAR_SKEW
	var heading_color: Color = UiPalette.YELLOW if heading != "LOADING..." else UiPalette.CREAM
	if hint != "":
		_draw_comic_text(_display, Vector2(heading_x, bar.position.y - 38.0),
			heading, 42, heading_color, 4.5, Vector2(3.5, 4.5), max_heading_w)
		_draw_comic_text(_display, Vector2(heading_x + 2.0, bar.position.y - 13.0),
			hint, 18, UiPalette.CREAM, 3.0, Vector2(2.0, 3.0), max_heading_w)
	else:
		_draw_comic_text(_display, Vector2(heading_x, bar.position.y - 16.0),
			heading, 42, heading_color, 4.5, Vector2(3.5, 4.5), max_heading_w)
