extends Control
const UiAnim := preload("res://scripts/ui/ui_anim.gd")
## SELECT MODE & SELECT MAP screen:
## - Page 1 (SELECT MODE): All 5 game modes front-and-center in a visual screenshot
##   card grid (RACING, DELIVER, KNOCKOUT, BLAST TAG, SANDBOX) with zero scrolling,
##   plus a compact Solo BOTS pill and GARAGE shortcut in the header.
## - Page 2a (SELECT TRACK): 3-column grid of standalone Racing circuits.
## - Page 2b (SELECT MAP): 3 big side-by-side visual MapCards for DELIVER, KNOCKOUT,
##   and BLAST TAG, each displaying its own 16:9 screenshot, map name, layout
##   description, and "✓ SELECTED" badge.
##
## Background (0.8.7): ArtBackdrop shuffles this screen's own mode/map preview
## pool on its own 8-12 s beat; hovering/focusing cards never changes or pauses
## it (they keep only their local lift/zoom animation). The pool follows the page:
## mode previews on SELECT MODE, the current mode's track/arena previews on SELECT
## TRACK / SELECT MAP.

const TrackDefs := preload("res://scripts/minigames/track_defs.gd")
const Catalog := preload("res://scripts/vehicles/vehicle_catalog.gd")
const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const VehicleSelect := preload("res://scripts/ui/vehicle_select.gd")

const PLAY_MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"
const LOBBY_SCENE: String = "res://scenes/ui/lobby_menu.tscn"
const MINIGAMES_SCENE: String = "res://scenes/ui/minigames_menu.tscn"
const VEHICLE_SCENE: String = "res://scenes/ui/vehicle_select.tscn"
const RACE_SCENE: String = "res://scenes/minigames/grass_race.tscn"
const PREVIEW_DIR: String = "res://assets/ui/minigames/"
const ART_PREVIEW_DIR: String = "res://assets/ui/art/"
const FALLBACK_PREVIEW: String = "meadow_loop.png"

## SELECT MODE background pool: one 16:9 screenshot per mode card.
const BACKGROUND_ART_GAMES: Array[String] = [
	"preview_stadium.png",
	"preview_knockout.png",
	"preview_cargo_rush.png",
	"preview_bomb_tag.png",
	"preview_sandbox.png",
]
## Every page pool falls back to the hero key-art set when a page has fewer than
## two descendant previews (the slideshow must always have something to shuffle).
const BACKGROUND_ART_FALLBACK: Array[String] = [
	"bg_hero_paddock.png",
	"bg_hero_arena.png",
	"bg_hero_canyon.png",
	"bg_hero_glacier.png",
]

const PAGE_GAMES: String = "games"
const GAME_RACING: String = "racing"
const GAME_MINIGAME: String = "minigame"
const GAME_SANDBOX: String = "sandbox"

const MODE_CARD_WIDTH: float = 312.0
const MODE_CARD_HEIGHT: float = 224.0
const MODE_PREVIEW_HEIGHT: float = 158.0

const MAP_CARD_WIDTH: float = 304.0
const MAP_CARD_HEIGHT: float = 220.0
const MAP_PREVIEW_HEIGHT: float = 154.0
const CARD_PAD: int = 10
const SCROLL_OUTER_PAD: int = 12
const GRID_COLUMNS: int = 3
const GRID_GAP: int = 16

const GAMES_SCROLL_HEIGHT: float = 484.0
const MAPS_SCROLL_HEIGHT: float = 476.0
const MINIGAME_MAPS_SCROLL_HEIGHT: float = 248.0
const MAP_GRID_WIDTH: float = MAP_CARD_WIDTH * 3.0 + float(GRID_GAP) * 2.0

const BOT_LABELS: PackedStringArray = ["0", "1", "2", "3", "4", "5"]
const BOT_VALUES: Array[int] = [0, 1, 2, 3, 4, 5]


class _AnimatedPreviewCanvas extends Control:
	## Animated map/mode preview: gentle Ken Burns pan & zoom at rest, smooth
	## hover zoom boost, subtle accent bar, and diagonal glossy sheen sweep.
	var texture: Texture2D = null
	var accent: Color = Color("38d6f0")
	var phase: float = 0.0
	var _owner_btn: Button = null
	var _time: float = 0.0
	var _hover_t: float = 0.0
	var _shine_t: float = 2.0
	var _was_hot: bool = false

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		clip_contents = true
		phase = randf_range(0.0, TAU)
		resized.connect(queue_redraw)

	func bind_button(btn: Button) -> void:
		_owner_btn = btn

	func _is_reduced() -> bool:
		var gs: Node = get_node_or_null("/root/GameSettings")
		return gs != null and bool(gs.get("reduce_motion"))

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		var reduced: bool = _is_reduced()
		var hot: bool = _owner_btn != null and is_instance_valid(_owner_btn) \
			and (_owner_btn.is_hovered() or _owner_btn.has_focus())
		if hot and not _was_hot:
			_shine_t = -0.35
		_was_hot = hot
		var target: float = 1.0 if hot else 0.0
		_hover_t = UiAnim.damp(_hover_t, target, delta, 14.0)
		if not reduced:
			_time += delta
			queue_redraw()
		elif _shine_t < 1.5 or absf(_hover_t - target) > 0.005:
			queue_redraw()
		if _shine_t < 1.5:
			_shine_t += delta * 2.4

	var title_text: String = ""
	var title_font: Font = preload("res://assets/ui/fonts/LuckiestGuy-Regular.ttf")

	func _draw() -> void:
		var area: Vector2 = size
		if area.x < 24.0 or area.y < 24.0:
			return
		var sk: float = minf(12.0, area.x * 0.14)
		var pad_x: float = 3.0
		var pad_t: float = 2.0
		var drop_y: float = 5.0
		var bw: float = maxf(area.x - sk - pad_x * 2.0 - 3.0, 12.0)
		var bh: float = maxf(area.y - pad_t - drop_y - 2.0, 12.0)
		var x0: float = pad_x
		var y0: float = pad_t
		var pts := PackedVector2Array([
			Vector2(x0 + sk, y0),
			Vector2(x0 + sk + bw, y0),
			Vector2(x0 + bw, y0 + bh),
			Vector2(x0, y0 + bh),
		])
		draw_colored_polygon(pts, Color(0.06, 0.07, 0.16, 1.0))

		if texture != null:
			var src: Vector2 = texture.get_size()
			if src.x > 0.0 and src.y > 0.0:
				var reduced: bool = _is_reduced()
				var card_aspect: float = (bw + sk) / maxf(bh, 1.0)
				var tex_aspect: float = src.x / src.y
				var zoom: float = 1.0 if reduced else (1.06 + 0.025 * sin(_time * 0.65 + phase) + _hover_t * 0.10)
				var uv_w: float = (1.0 / zoom) * minf(card_aspect / tex_aspect, 1.0)
				var uv_h: float = (1.0 / zoom) * minf(tex_aspect / card_aspect, 1.0)
				var du: float = 0.0 if reduced else sin(_time * 0.45 + phase) * 0.022
				var dv: float = 0.0 if reduced else cos(_time * 0.37 + phase) * 0.018
				var u0: float = clampf(0.5 - uv_w * 0.5 + du, 0.0, 1.0 - uv_w)
				var v0: float = clampf(0.5 - uv_h * 0.5 + dv, 0.0, 1.0 - uv_h)
				var skew_u: float = uv_w * (sk / maxf(bw + sk, 1.0)) * 0.5
				var uvs := PackedVector2Array([
					Vector2(clampf(u0 + skew_u, 0.0, 1.0), v0),
					Vector2(clampf(u0 + uv_w, 0.0, 1.0), v0),
					Vector2(clampf(u0 + uv_w - skew_u, 0.0, 1.0), v0 + uv_h),
					Vector2(clampf(u0, 0.0, 1.0), v0 + uv_h),
				])
				var tint := Color(1.0, 1.0, 1.0, lerpf(0.90, 1.0, _hover_t))
				draw_polygon(pts, PackedColorArray([tint, tint, tint, tint]), uvs, texture)

		# Clean dark slanted bottom title band (zero top/side color stripes!)
		var rib_h: float = 46.0
		var rib_sk: float = sk * (rib_h / maxf(bh, 1.0))
		var rib_y: float = y0 + bh - rib_h
		var rib := PackedVector2Array([
			Vector2(x0 + rib_sk, rib_y),
			Vector2(x0 + rib_sk + bw, rib_y),
			Vector2(x0 + bw, y0 + bh),
			Vector2(x0, y0 + bh),
		])
		draw_colored_polygon(rib, Color(0.055, 0.065, 0.16, 0.92))

		# Animated diagonal gloss sweep on hover: soft gradient band, never a
		# clipped straight edge (the old flat-alpha quad ended on a hard line).
		if _shine_t >= -0.35 and _shine_t <= 1.35:
			var sx: float = lerpf(x0 - 24.0, x0 + bw + 24.0, _shine_t)
			var sw: float = 36.0
			var x_tl: float = clampf(sx + sk, x0 + sk, x0 + sk + bw)
			var x_tr: float = clampf(sx + sk + sw, x0 + sk, x0 + sk + bw)
			var x_br: float = clampf(sx + sw, x0, x0 + bw)
			var x_bl: float = clampf(sx, x0, x0 + bw)
			if x_tr > x_tl + 2.0 and x_br > x_bl + 2.0:
				UiAnim.draw_soft_band(self, PackedVector2Array([
					Vector2(x_tl, y0 + 2.0), Vector2(x_tr, y0 + 2.0),
					Vector2(x_br, y0 + bh - 2.0), Vector2(x_bl, y0 + bh - 2.0),
				]), Color.WHITE, 0.24)

		# Crisp bold auto-fitted title inside the slanted ribbon (zero overflow!)
		if not title_text.is_empty() and title_font != null:
			var fsz: int = 23
			var avail_w: float = maxf(bw - 24.0, 40.0)
			while fsz > 14 and title_font.get_string_size(title_text, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x > avail_w:
				fsz -= 1
			var ascent: float = title_font.get_ascent(fsz)
			var ty: float = rib_y + (rib_h + ascent * 0.72) * 0.5
			var txt_col: Color = UiPalette.YELLOW if _hover_t > 0.25 else UiPalette.CREAM
			draw_string(title_font, Vector2(x0 + rib_sk * 0.5, ty + 2.0), title_text,
				HORIZONTAL_ALIGNMENT_CENTER, bw, fsz, Color(0.02, 0.02, 0.08, 0.90))
			draw_string(title_font, Vector2(x0 + rib_sk * 0.5, ty), title_text,
				HORIZONTAL_ALIGNMENT_CENTER, bw, fsz, txt_col)

		# Crisp ink outer parallelogram outline matching CandyButton 1:1
		var cl := pts.duplicate()
		cl.append(pts[0])
		draw_polyline(cl, UiPalette.INK, 3.8, true)


class _ProceduralBanner extends Control:
	## Crisp vector arena fallback rendered only when a map's PNG screenshot is
	## not yet on disk, so party modes never fall back to a grass racing photo.
	var banner_id: String = ""
	var primary: Color = Color("38d6f0")
	var secondary: Color = Color("1e1b3a")

	func _ready() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		if w < 8.0 or h < 8.0:
			return
		var top_col: Color = secondary.darkened(0.18)
		var bot_col: Color = primary.darkened(0.32)
		var bands: int = 16
		for b in bands:
			var t: float = float(b) / float(bands - 1)
			draw_rect(Rect2(0.0, h * float(b) / float(bands), w, h / float(bands) + 1.5),
				top_col.lerp(bot_col, t))
		var center := Vector2(w * 0.5, h * 0.54)
		var r: float = minf(w, h) * 0.34
		if banner_id.begins_with("ko") or banner_id == "knockout":
			for ring in 3:
				var rr: float = r * (1.25 - float(ring) * 0.28)
				draw_arc(center, rr, 0.0, TAU, 36,
					Color(primary.lightened(0.25), 0.28 + float(ring) * 0.18), 3.0, true)
			draw_circle(center, r * 0.38, Color(primary, 0.42))
		elif banner_id.begins_with("bt") or banner_id == "bomb_tag":
			for i in 6:
				var ang: float = TAU * float(i) / 6.0 + 0.25
				var dir := Vector2(cos(ang), sin(ang))
				draw_line(center + dir * (r * 0.42), center + dir * (r * 1.15),
					Color(primary.lightened(0.3), 0.45), 2.5, true)
			draw_circle(center, r * 0.44, Color(0.12, 0.11, 0.22, 0.92))
			draw_arc(center, r * 0.44, 0.0, TAU, 32, primary.lightened(0.25), 2.5, true)
			draw_circle(center + Vector2(r * 0.32, -r * 0.36), 4.5, Color("ffd22e"))
		else:
			for idx in range(-3, 4):
				var ox: float = float(idx) * w * 0.11
				draw_line(Vector2(w * 0.5 + ox * 0.3, h * 0.22),
					Vector2(w * 0.5 + ox * 1.3, h * 0.92),
					Color(1.0, 1.0, 1.0, 0.16), 2.0, true)
			draw_rect(Rect2(center.x - r * 0.55, center.y - r * 0.35, r * 1.1, r * 0.7),
				Color(primary.lightened(0.2), 0.36), false, 2.5)


var _panel: PanelContainer
var _body: VBoxContainer
var _title: Label
var _header_bots_box: HBoxContainer
var _bots_pill: Button
var _header_garage_button: Button
var _back_button: Button

var _page: String = PAGE_GAMES
var _games: Array[Dictionary] = []

var _games_page: VBoxContainer
var _games_scroll: ScrollContainer
var _game_rows_box: VBoxContainer
var _game_cards: Array[Button] = []

var _selector_page: VBoxContainer
var _selector_caption: Label
var _selector_scroll: ScrollContainer
var _selector_list: VBoxContainer
var _arena_empty: Label

var _map_grid: VBoxContainer
var _map_cards: Array[Button] = []
var _map_indexes: Array[int] = []
var _selected: int = 0

var _arena_grid: GridContainer
var _arena_cards: Array[Button] = []
var _arena_entries: Array[Dictionary] = []
var _selected_arena_index: int = 0
var _selected_arena_by_mode: Dictionary = {}
var _selector_game: Dictionary = {}
var _deliver_entry: Dictionary = {}

var _vehicle_button: Button
var _play_button: Button

static var _return_page: String = ""
static var _return_map: String = ""
static var _return_theme: String = ""
static var _direct_lobby_jump: bool = false

var _restored_map_id: String = ""
var _restored_theme: String = ""
var _opened_direct_from_lobby: bool = false

var _background: Control = null


static func open_for_mode(page_id: String) -> void:
	## Allows LobbyMenu or VehicleSelect return flows to open either Page 1
	## (`""` / `"games"`) or jump straight to a specific mode's map selector.
	_return_page = page_id
	_direct_lobby_jump = page_id != "" and page_id != PAGE_GAMES


func _ready() -> void:
	CursorController.set_menu_mode(true)
	_panel = $Center/Panel
	_body = $Center/Panel/Body
	_tune_panel_chrome()
	var resume: String = _consume_return_state()
	_build_ui()
	_background = get_node_or_null("Background")
	_initial_state()
	resized.connect(_fit_panel)
	_fit_panel()
	var resolved_resume: String = _resolve_mode_id(resume)
	if resolved_resume != "" and resolved_resume != PAGE_GAMES \
			and resolved_resume != GAME_SANDBOX \
			and not _game_entry_for(resolved_resume).is_empty():
		_show_selector(resolved_resume)
	else:
		_show_games(false)
	call_deferred("_enter")
	if OS.get_environment("CART_UI_MEASURE") == "1":
		_report_layout.call_deferred()
	if OS.get_environment("CART_MINIGAMES_SELFTEST") == "1":
		_run_selftest.call_deferred()


func _tune_panel_chrome() -> void:
	if _panel == null:
		return
	_panel.add_theme_stylebox_override("panel", UiKit.modal_panel(36.0, 22.0, 0.042))
	if _body != null:
		_body.add_theme_constant_override("separation", UiKit.SPACING_MED)


func _set_background_slides(names: PackedStringArray) -> void:
	## One-way handshake with the backdrop for the page that is becoming visible.
	## The slideshow then shuffles this pool itself; no card event can change it.
	if _background == null:
		return
	if not _background.has_method("set_slide_pool"):
		return
	_background.call("set_slide_pool", _with_slide_fallback(names))


func _with_slide_fallback(names: PackedStringArray) -> PackedStringArray:
	## Guarantee >= 2 real plates so the timer always has something to shuffle.
	var out: PackedStringArray = PackedStringArray()
	for file_name: String in names:
		if file_name != "" and ResourceLoader.exists(ART_PREVIEW_DIR + file_name) \
				and not out.has(file_name):
			out.append(file_name)
	for fallback: String in BACKGROUND_ART_FALLBACK:
		if out.size() >= 2:
			break
		if not out.has(fallback):
			out.append(fallback)
	return out


func _map_slide_pool() -> PackedStringArray:
	## SELECT TRACK: every visible circuit's own 16:9 preview plate.
	var out: PackedStringArray = PackedStringArray()
	for position in _map_indexes.size():
		var art: String = _preview_art_name(_preset_at_map_slot(position))
		if art != "" and not out.has(art):
			out.append(art)
	return out


func _arena_slide_pool() -> PackedStringArray:
	## SELECT MAP: the current mode's 3 arena plates.
	var out: PackedStringArray = PackedStringArray()
	for arena: Dictionary in _arena_entries:
		var arena_id: String = str(arena.get("id", ""))
		if arena_id == "":
			continue
		var candidate: String = "preview_%s.png" % arena_id
		if ResourceLoader.exists(ART_PREVIEW_DIR + candidate) \
				and not out.has(candidate):
			out.append(candidate)
	return out


func _preview_art_name(preset: Dictionary) -> String:
	## `<preview_<id>.png>` first, then the preset's own preview filename.
	var id: String = str(preset.get("id", ""))
	if id != "":
		var candidate: String = "preview_%s.png" % id
		if ResourceLoader.exists(ART_PREVIEW_DIR + candidate):
			return candidate
	var file_name: String = str(preset.get("preview", ""))
	if file_name != "" and ResourceLoader.exists(ART_PREVIEW_DIR + file_name):
		return file_name
	return ""


func _fit_panel() -> void:
	if _panel == null:
		return
	var vp: Vector2 = size if size.x > 1.0 else get_viewport_rect().size
	if vp.x < 1.0:
		return
	_panel.custom_minimum_size.x = 1036.0
	if vp.x < 1084.0 or vp.y < 690.0:
		var rx: float = (vp.x - 32.0) / 1036.0
		var ry: float = (vp.y - 32.0) / 650.0
		var ratio: float = clampf(minf(rx, ry), 0.66, 1.0)
		_panel.scale = Vector2.ONE * ratio
		_panel.pivot_offset = _panel.size * 0.5
	else:
		_panel.scale = Vector2.ONE


func _consume_return_state() -> String:
	var resume: String = _return_page
	_restored_map_id = _return_map
	_restored_theme = _return_theme
	_opened_direct_from_lobby = _direct_lobby_jump
	_return_page = ""
	_return_map = ""
	_return_theme = ""
	_direct_lobby_jump = false
	return resume


func _resolve_mode_id(raw_id: String) -> String:
	var clean: String = raw_id.strip_edges().to_lower()
	match clean:
		"", "games", "modes":
			return PAGE_GAMES
		"racing", "race":
			return GAME_RACING
		"cargo", "cargo_rush", "deliver":
			return "cargo_rush"
		"knockout", "ko":
			return "knockout"
		"bomb_tag", "blast_tag", "bomb":
			return "bomb_tag"
		"sandbox":
			return GAME_SANDBOX
	return raw_id


func _report_layout() -> void:
	await UiKit.report_screen(self, "minigames:modes")
	_report_blocks("minigames:modes")
	if not _map_cards.is_empty():
		_show_selector(GAME_RACING)
		await UiKit.report_screen(self, "minigames:racing")
		_report_blocks("minigames:racing")
	for entry: Dictionary in _games:
		if str(entry.get("kind", "")) == GAME_MINIGAME:
			var gid: String = str(entry.get("id", ""))
			_show_selector(gid)
			await UiKit.report_screen(self, "minigames:" + gid)
			_report_blocks("minigames:" + gid)
	_show_games(false)


func _report_blocks(tag: String) -> void:
	var panel: Control = $Center/Panel
	print("UI_BLOCKS %s panel=%.0fx%.0f body=%.0fx%.0f games_scroll=%.0f selector_scroll=%.0f fits720=%s"
		% [tag, panel.size.x, panel.size.y, _body.size.x, _body.size.y,
		_games_scroll.custom_minimum_size.y,
		_selector_scroll.custom_minimum_size.y,
		str(panel.size.y <= UiKit.SCREEN_HEIGHT - UiKit.SCREEN_MARGIN * 2.0)])


func _fit_page_heights() -> void:
	if _games_scroll != null:
		_games_scroll.custom_minimum_size.y = minf(
			_scroll_content_height(_games_scroll), GAMES_SCROLL_HEIGHT)
	if _selector_scroll != null and _selector_page.visible:
		var cap: float = MAPS_SCROLL_HEIGHT if _page == GAME_RACING \
			else MINIGAME_MAPS_SCROLL_HEIGHT
		_selector_scroll.custom_minimum_size.y = minf(
			_scroll_content_height(_selector_scroll), cap)


func _scroll_content_height(scroll: ScrollContainer) -> float:
	if scroll.get_child_count() == 0:
		return 0.0
	return scroll.get_child(0).get_combined_minimum_size().y


func _padded(scroll: ScrollContainer, pad_name: String, pad_v: int = SCROLL_OUTER_PAD) -> MarginContainer:
	var pad := MarginContainer.new()
	pad.name = pad_name
	pad.add_theme_constant_override("margin_left", SCROLL_OUTER_PAD)
	pad.add_theme_constant_override("margin_right", SCROLL_OUTER_PAD)
	pad.add_theme_constant_override("margin_top", pad_v)
	pad.add_theme_constant_override("margin_bottom", pad_v + 2)
	pad.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(pad)
	return pad


func _enter() -> void:
	_fit_page_heights()
	_refresh_vehicle()
	UiAnim.pop($Center/Panel)
	MenuNav.refresh()
	_focus_page()


func _focus_page() -> void:
	if _page == PAGE_GAMES:
		var first: Button = _game_cards[0] if not _game_cards.is_empty() else _back_button
		MenuNav.focus(first)
	elif _page == GAME_RACING and not _map_cards.is_empty():
		MenuNav.focus(_map_cards[clampi(_selected, 0, _map_cards.size() - 1)])
	elif not _arena_cards.is_empty() and _arena_grid.visible:
		MenuNav.focus(_arena_cards[clampi(_selected_arena_index, 0, _arena_cards.size() - 1)])
	else:
		MenuNav.focus(_play_button)


func _page_in(page: Control) -> void:
	page.pivot_offset = page.size * 0.5
	page.scale = Vector2.ONE * 0.98
	UiAnim.fade_in(page, 0.18)
	var tween: Tween = page.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	tween.tween_property(page, "scale", Vector2.ONE, 0.22) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func _unhandled_input(event: InputEvent) -> void:
	if event.is_action_pressed("ui_cancel") and not SceneLoader.is_busy():
		UiKit.consume_input(self)
		_on_back()


# --------------------------------------------------------------------------
# build


func _build_ui() -> void:
	var header := Control.new()
	header.custom_minimum_size = Vector2(0, 46)
	header.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_body.add_child(header)

	_title = Label.new()
	_title.theme_type_variation = &"TitleLabel"
	_title.add_theme_font_size_override("font_size", 38)
	_title.add_theme_color_override("font_color", UiPalette.YELLOW)
	_title.add_theme_color_override("font_outline_color", UiPalette.INK)
	_title.add_theme_constant_override("outline_size", 6)
	_title.text = "MODES"
	_title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_title.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	header.add_child(_title)

	_header_bots_box = HBoxContainer.new()
	_header_bots_box.add_theme_constant_override("separation", 8)
	_header_bots_box.anchor_left = 0.0
	_header_bots_box.anchor_top = 0.0
	_header_bots_box.anchor_bottom = 1.0
	_header_bots_box.alignment = BoxContainer.ALIGNMENT_BEGIN
	header.add_child(_header_bots_box)

	var bots_lbl := Label.new()
	bots_lbl.text = "AI"
	bots_lbl.theme_type_variation = &"TitleLabel"
	bots_lbl.add_theme_font_size_override("font_size", 15)
	bots_lbl.add_theme_color_override("font_color", UiPalette.YELLOW)
	bots_lbl.add_theme_constant_override("shadow_offset_y", 0)
	bots_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	bots_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_header_bots_box.add_child(bots_lbl)

	_bots_pill = UiKit.segmented(BOT_LABELS, BOT_VALUES,
		GameSettings.effective_bot_count(), 36.0, 42.0)
	_bots_pill.name = "BotsPill"
	_bots_pill.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_bots_pill.tooltip_text = "AI opponents in solo matches."
	_bots_pill.connect("option_changed", _on_bots_changed)
	_header_bots_box.add_child(_bots_pill)

	var right_box := HBoxContainer.new()
	right_box.add_theme_constant_override("separation", 10)
	right_box.anchor_left = 1.0
	right_box.anchor_right = 1.0
	right_box.anchor_top = 0.0
	right_box.anchor_bottom = 1.0
	right_box.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	right_box.alignment = BoxContainer.ALIGNMENT_END
	header.add_child(right_box)

	_header_garage_button = _button("GARAGE", Color("8ed8f6"), 44, 15)
	_header_garage_button.name = "HeaderGarageButton"
	UiKit.cap_button(_header_garage_button, 130.0)
	_header_garage_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_header_garage_button.pressed.connect(_on_header_garage)
	right_box.add_child(_header_garage_button)

	_back_button = _button("BACK", UiPalette.RED, 44, 16)
	_back_button.name = "BackButton"
	UiKit.cap_button(_back_button, 110.0)
	_back_button.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_back_button.pressed.connect(_on_back)
	right_box.add_child(_back_button)

	_build_games()
	_build_games_page()
	_build_selector_page()
	_refresh_header_controls()
	_refresh_vehicle()


func _on_bots_changed(value: Variant) -> void:
	GameSettings.set_bot_total(clampi(int(value), 0, 5))


func _on_header_garage() -> void:
	_return_page = PAGE_GAMES
	_return_map = str(_current_map().get("id", ""))
	_return_theme = _current_arena_id()
	GameSettings.vehicle_return_scene = MINIGAMES_SCENE
	GameSettings.vehicle_return_title = "SELECT MODE"
	GameSettings.vehicle_edit_minigame = false
	VehicleSelect.set_racing_intent(true)
	SceneLoader.go_to(VEHICLE_SCENE, "GARAGE", "Choose your ride")


func _refresh_header_controls() -> void:
	var solo_modes_page: bool = (_page == PAGE_GAMES) and not Network.is_session_active()
	if _header_bots_box != null:
		_header_bots_box.visible = solo_modes_page
	if _header_garage_button != null:
		_header_garage_button.visible = solo_modes_page
	if _bots_pill != null:
		_bots_pill.call("set_index", clampi(GameSettings.effective_bot_count(), 0, 5))


func _live_preset(raw: Dictionary) -> Dictionary:
	var id: String = str(raw.get("id", ""))
	if id != "":
		if TrackDefs.is_minigame(raw):
			var mg: Dictionary = TrackDefs.get_minigame(id)
			if not mg.is_empty():
				return mg
			return raw
		var resolved: Dictionary = TrackDefs.get_preset(id)
		if not resolved.is_empty():
			return resolved
	return raw


func _preset_at_map_slot(slot: int) -> Dictionary:
	if slot < 0 or slot >= _map_indexes.size():
		return {}
	return _live_preset(TrackDefs.PRESETS[_map_indexes[slot]])


func _build_games() -> void:
	_games.clear()
	_map_indexes.clear()
	for index in TrackDefs.PRESETS.size():
		if TrackDefs.is_map(TrackDefs.PRESETS[index]):
			_map_indexes.append(index)
	_selected = 0
	if not _map_indexes.is_empty():
		var saved: String = _restored_map_id if _restored_map_id != "" \
			else GameSettings.selected_map
		var registered: int = TrackDefs.index_of(saved)
		_selected = maxi(_map_indexes.find(registered), 0)
	if not _map_indexes.is_empty():
		_games.append(_racing_entry())
	for index in TrackDefs.PRESETS.size():
		var preset: Dictionary = _live_preset(TrackDefs.PRESETS[index])
		if TrackDefs.is_minigame(preset):
			_games.append(_minigame_entry(preset))
	_games.append(_sandbox_entry())

	_deliver_entry = {}
	for entry: Dictionary in _games:
		if str(entry.get("kind", "")) == GAME_MINIGAME:
			_deliver_entry = entry
			break


func _racing_entry() -> Dictionary:
	var first_map: Dictionary = _preset_at_map_slot(0)
	var current_map: Dictionary = _current_map()
	var preview_tex: Texture2D = _preview_for_preset(
		current_map if not current_map.is_empty() else first_map)
	return {
		"id": GAME_RACING,
		"kind": GAME_RACING,
		"name": "RACING",
		"desc": "3-lap circuit racing with 3-tier drift boosts",
		"accent": UiPalette.GRASS,
		"preview": preview_tex,
	}


func _minigame_entry(preset: Dictionary) -> Dictionary:
	var id: String = str(preset.get("id", "minigame"))
	var game_title: String = str(preset.get("game", preset.get("name", "PARTY MODE"))).to_upper()
	var arenas: Array[Dictionary] = _extract_arenas(preset)

	var hook: String = ""
	var accent: Color = UiPalette.CYAN
	match id:
		"cargo_rush":
			hook = "Capture crates and score at your team base"
			accent = UiPalette.CYAN
		"knockout":
			hook = "Smash rivals off collapsing stages"
			accent = UiPalette.ORANGE
		"bomb_tag":
			hook = "Pass the ticking Mega-Bomb before it blows"
			accent = UiPalette.PINK
		_:
			hook = _trim_line(str(preset.get("tagline", preset.get("desc", "Fast-paced arcade arena mayhem"))))
			accent = UiPalette.BLUE

	var preview_tex: Texture2D = _mode_preview_for_minigame(preset, arenas)
	return {
		"id": id,
		"kind": GAME_MINIGAME,
		"name": game_title,
		"desc": hook,
		"accent": accent,
		"preview": preview_tex,
		"preset": preset,
	}


func _sandbox_entry() -> Dictionary:
	var tex: Texture2D = _first_existing_texture([
		ART_PREVIEW_DIR + "preview_sandbox.png",
		ART_PREVIEW_DIR + "bg_parking.png",
	])
	return {
		"id": GAME_SANDBOX,
		"kind": GAME_SANDBOX,
		"name": "SANDBOX",
		"desc": "Free-roam stunt park with ramps & open play",
		"accent": UiPalette.YELLOW,
		"preview": tex,
	}


func _mode_preview_for_minigame(preset: Dictionary, arenas: Array[Dictionary]) -> Texture2D:
	var pid: String = str(preset.get("id", ""))
	var candidates: Array[String] = [
		ART_PREVIEW_DIR + "preview_" + pid + ".png",
	]
	if not arenas.is_empty():
		var first_arena_id: String = str(arenas[0].get("id", ""))
		if first_arena_id != "":
			candidates.append(ART_PREVIEW_DIR + "preview_" + first_arena_id + ".png")
	var pfile: String = str(preset.get("preview", ""))
	if pfile != "":
		candidates.append(ART_PREVIEW_DIR + pfile)
		candidates.append(PREVIEW_DIR + pfile)
	if pid == "cargo_rush":
		candidates.append(ART_PREVIEW_DIR + "bg_arena.png")
	return _first_existing_texture(candidates)


func _first_existing_texture(paths: Array[String]) -> Texture2D:
	for path: String in paths:
		var tex: Texture2D = _texture_at(path)
		if tex != null:
			return tex
	return null


func _build_games_page() -> void:
	_games_page = VBoxContainer.new()
	_games_page.name = "GamesPage"
	_games_page.add_theme_constant_override("separation", 8)
	_body.add_child(_games_page)

	_games_scroll = ScrollContainer.new()
	_games_scroll.name = "GamesScroll"
	_games_scroll.custom_minimum_size = Vector2(0, GAMES_SCROLL_HEIGHT)
	_games_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_games_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_games_scroll.follow_focus = true
	_games_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_games_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_games_page.add_child(_games_scroll)

	_game_rows_box = VBoxContainer.new()
	_game_rows_box.name = "GameRows"
	_game_rows_box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_game_rows_box.add_theme_constant_override("separation", 14)
	_padded(_games_scroll, "GamesPad", 8).add_child(_game_rows_box)

	_game_cards.clear()
	if _games.is_empty():
		_empty_state(_game_rows_box, "NO GAME MODES REGISTERED YET.")
		return

	# Clean centered rows of up to 3 visual mode cards (3 on top, 2 centered below
	# for the 5 modes — zero scrolling needed at 1280x720!).
	var current_row: HBoxContainer = null
	for i in _games.size():
		if i % 3 == 0:
			current_row = HBoxContainer.new()
			current_row.alignment = BoxContainer.ALIGNMENT_CENTER
			current_row.add_theme_constant_override("separation", GRID_GAP)
			current_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_game_rows_box.add_child(current_row)
		var card: Button = _make_game_card(_games[i])
		current_row.add_child(card)
		_game_cards.append(card)


func _build_selector_page() -> void:
	_selector_page = VBoxContainer.new()
	_selector_page.name = "SelectorPage"
	_selector_page.add_theme_constant_override("separation", 10)
	_selector_page.visible = false
	_body.add_child(_selector_page)

	_selector_caption = UiKit.label("", 14, UiPalette.MUTED)
	_selector_caption.visible = false
	_selector_page.add_child(_selector_caption)

	_selector_scroll = ScrollContainer.new()
	_selector_scroll.name = "SelectorScroll"
	_selector_scroll.custom_minimum_size = Vector2(0, MAPS_SCROLL_HEIGHT)
	_selector_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_selector_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_selector_scroll.follow_focus = true
	_selector_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_selector_scroll.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_selector_page.add_child(_selector_scroll)

	_selector_list = VBoxContainer.new()
	_selector_list.name = "SelectorList"
	_selector_list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_selector_list.add_theme_constant_override("separation", UiKit.SPACING)
	_padded(_selector_scroll, "SelectorPad", 8).add_child(_selector_list)

	# 2a: Racing circuits centered rows (3 on top, 2 centered below — zero scroll at 720p).
	_map_grid = VBoxContainer.new()
	_map_grid.name = "MapGrid"
	_map_grid.custom_minimum_size = Vector2(MAP_GRID_WIDTH, 0)
	_map_grid.add_theme_constant_override("separation", GRID_GAP)
	_selector_list.add_child(_map_grid)
	_map_cards.clear()
	var current_map_row: HBoxContainer = null
	for position in _map_indexes.size():
		if position % GRID_COLUMNS == 0:
			current_map_row = HBoxContainer.new()
			current_map_row.alignment = BoxContainer.ALIGNMENT_CENTER
			current_map_row.add_theme_constant_override("separation", GRID_GAP)
			current_map_row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			_map_grid.add_child(current_map_row)
		var card: Button = _make_map_card(position, _preset_at_map_slot(position))
		current_map_row.add_child(card)
		_map_cards.append(card)
	_update_map_cards()

	# 2b: Minigame maps 3-column visual MapCard grid (DELIVER / KNOCKOUT / BLAST TAG).
	_arena_grid = GridContainer.new()
	_arena_grid.name = "ArenaMapGrid"
	_arena_grid.custom_minimum_size = Vector2(MAP_GRID_WIDTH, 0)
	_arena_grid.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	_arena_grid.columns = GRID_COLUMNS
	_arena_grid.add_theme_constant_override("h_separation", GRID_GAP)
	_arena_grid.add_theme_constant_override("v_separation", GRID_GAP)
	_arena_grid.visible = false
	_selector_list.add_child(_arena_grid)

	_arena_empty = _empty_state(_selector_list, "NO MAPS REGISTERED FOR THIS MODE.")
	_arena_empty.visible = false

	var action_row := HBoxContainer.new()
	action_row.add_theme_constant_override("separation", UiKit.SPACING)
	action_row.alignment = BoxContainer.ALIGNMENT_CENTER
	_selector_page.add_child(action_row)

	_vehicle_button = _button("GARAGE: SHOPPING CART", Color("8ed8f6"), 54, 16)
	_vehicle_button.name = "VehicleButton"
	UiKit.cap_button(_vehicle_button, 260.0)
	_vehicle_button.pressed.connect(_on_change_vehicle)
	_vehicle_button.visible = not Network.is_session_active()
	action_row.add_child(_vehicle_button)

	_play_button = _button("START", UiPalette.YELLOW, 54, 21)
	_play_button.name = "PlayButton"
	UiKit.cap_button(_play_button, 340.0)
	_play_button.pressed.connect(_on_confirm)
	action_row.add_child(_play_button)


func _make_game_card(entry: Dictionary) -> Button:
	var accent: Color = entry.get("accent", UiPalette.GRASS) as Color
	var card: Button = _button("", accent.lightened(0.32), int(MODE_CARD_HEIGHT), 20)
	var gid: String = str(entry.get("id", "game"))
	card.name = "GameCard_%s" % gid
	card.custom_minimum_size = Vector2(MODE_CARD_WIDTH, MODE_CARD_HEIGHT)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	if Network.is_session_active() and not Network.is_host:
		card.disabled = true
	card.pressed.connect(_on_game_pressed.bind(gid))

	_populate_clean_card(
		card,
		entry.get("preview", null) as Texture2D,
		MODE_PREVIEW_HEIGHT,
		gid,
		accent,
		str(entry.get("name", "MODE")),
		str(entry.get("desc", ""))
	)
	return card


func _make_map_card(position: int, preset: Dictionary) -> Button:
	var accent: Color = _accent_for(preset)
	var map_id: String = str(preset.get("id", "map"))
	var card: Button = _button("", accent.lightened(0.35), int(MAP_CARD_HEIGHT), 20)
	card.name = "MapCard_%s" % map_id
	card.custom_minimum_size = Vector2(MAP_CARD_WIDTH, MAP_CARD_HEIGHT)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.pressed.connect(_on_map_pressed.bind(position))

	_populate_clean_card(
		card,
		_preview_for_preset(preset),
		MAP_PREVIEW_HEIGHT,
		map_id,
		accent,
		str(preset.get("name", "MAP")),
		_concise_track_desc(preset)
	)
	return card


func _make_arena_card(slot: int, arena: Dictionary, mode_accent: Color,
		_mode_name: String) -> Button:
	var arena_id: String = str(arena.get("id", "arena_%d" % slot))
	var card_accent: Color = arena.get("accent", mode_accent) as Color
	var card: Button = _button("", card_accent.lightened(0.35), int(MAP_CARD_HEIGHT), 20)
	card.name = "ArenaCard_%s" % arena_id
	card.custom_minimum_size = Vector2(MAP_CARD_WIDTH, MAP_CARD_HEIGHT)
	card.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	card.pressed.connect(_on_arena_pressed.bind(slot))

	_populate_clean_card(
		card,
		arena.get("texture", null) as Texture2D,
		MAP_PREVIEW_HEIGHT,
		arena_id,
		card_accent,
		str(arena.get("name", arena_id.to_upper())),
		str(arena.get("desc", ""))
	)
	return card


func _populate_clean_card(card: Button, texture: Texture2D, _preview_h: float,
		_art_id: String, accent: Color, title_text: String, _desc_text: String) -> void:
	## True full-bleed slanted parallelogram preview card: UV-mapped Ken Burns
	## map art + bold dark title strip flush inside the CandyButton parallelogram!
	var preview := _AnimatedPreviewCanvas.new()
	preview.texture = texture
	preview.accent = accent
	preview.title_text = title_text
	preview.clip_contents = false
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	preview.bind_button(card)
	card.add_child(preview)


func _trim_line(raw: String, max_chars: int = 48) -> String:
	var clean: String = raw.strip_edges()
	if clean.length() <= max_chars:
		return clean
	return clean.substr(0, max_chars - 1).strip_edges() + "…"


func _concise_track_desc(preset: Dictionary) -> String:
	var tid: String = str(preset.get("id", ""))
	match tid:
		"stadium":
			return "857m · 9m sky-bridge & stadium bowl"
		"meadow":
			return "889m · 9m cliff overlook & forest dirt"
		"canyon":
			return "985m · 12m mesa skyway & stone arches"
		"dockyard":
			return "888m · 7.5m crane deck & wet seawall"
		"glacier":
			return "1049m · 13.5m summit jump & ice slides"
	var lap_str: String = _lap_text(preset)
	var tag_str: String = str(preset.get("tagline", preset.get("desc", ""))).strip_edges()
	if lap_str != "" and tag_str != "":
		return _trim_line("%s · %s" % [lap_str, tag_str])
	if tag_str != "":
		return _trim_line(tag_str)
	return _trim_line(lap_str)


func _lap_text(preset: Dictionary) -> String:
	var length: int = int(preset.get("lap_length", 0))
	var climb: int = _climb_metres(preset)
	if length > 0 and climb > 0:
		return "%d M · %dM CLIMB" % [length, climb]
	if length > 0:
		return "%d M" % length
	return ""


func _climb_metres(preset: Dictionary) -> int:
	for key: String in ["climb", "elevation_m"]:
		var raw: Variant = preset.get(key, null)
		if raw is int or raw is float:
			return roundi(float(raw))
		if raw is String and (raw as String).is_valid_float():
			return roundi((raw as String).to_float())
	var raw_elev: Variant = preset.get("elevation", null)
	if raw_elev is int or raw_elev is float:
		return roundi(float(raw_elev))
	if raw_elev is Array:
		var lo: float = INF
		var hi: float = -INF
		for item: Variant in raw_elev as Array:
			if item is Dictionary and (item as Dictionary).has("height"):
				var h: float = float((item as Dictionary)["height"])
				lo = minf(lo, h)
				hi = maxf(hi, h)
		if hi > lo:
			return roundi(hi - lo)
	var rows: PackedStringArray = TrackDefs.heights_of(preset)
	if not rows.is_empty():
		var min_step: int = 99
		var max_step: int = -1
		for row: String in rows:
			for idx in row.length():
				var code: int = row.unicode_at(idx)
				if code >= 48 and code <= 57:
					var digit: int = code - 48
					min_step = mini(min_step, digit)
					max_step = maxi(max_step, digit)
		if max_step > min_step and min_step < 99:
			return roundi(float(max_step - min_step) * 1.5)
	return 0


func _preview_frame(texture: Texture2D, minimum: Vector2, fallback: Color,
		art_id: String = "", accent: Color = UiPalette.CYAN,
		owner_btn: Button = null) -> PanelContainer:
	var frame := PanelContainer.new()
	frame.custom_minimum_size = minimum
	frame.clip_contents = true
	frame.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var style := StyleBoxFlat.new()
	style.bg_color = fallback
	style.set_corner_radius_all(4)
	style.content_margin_left = 3.0
	style.content_margin_right = 3.0
	style.content_margin_top = 3.0
	style.content_margin_bottom = 3.0
	style.anti_aliasing = true
	frame.add_theme_stylebox_override("panel", style)
	if texture != null:
		var preview := _AnimatedPreviewCanvas.new()
		preview.texture = texture
		preview.accent = accent
		preview.bind_button(owner_btn)
		preview.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
		frame.add_child(preview)
	else:
		var banner := _ProceduralBanner.new()
		banner.banner_id = art_id
		banner.primary = accent
		banner.secondary = fallback
		frame.add_child(banner)
	return frame


func _empty_state(parent: Control, text: String) -> Label:
	var label := UiKit.label(text, int(UiKit.CAPTION_SIZE), UiPalette.MUTED)
	label.name = "EmptyState"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.custom_minimum_size = Vector2(680.0, 120.0)
	parent.add_child(label)
	return label


func _button(text: String, color: Color, height: int, font_size: int) -> Button:
	return UiKit.tile(text, color, float(height), font_size)


# --------------------------------------------------------------------------
# data & arena extraction


func _initial_state() -> void:
	if _restored_theme != "":
		for entry: Dictionary in _games:
			if str(entry.get("kind", "")) != GAME_MINIGAME:
				continue
			var preset: Dictionary = _live_preset(entry.get("preset", {}) as Dictionary)
			if TrackDefs.theme_ids(preset).has(_restored_theme):
				_selected_arena_by_mode[str(entry.get("id", ""))] = _restored_theme


func _current_map() -> Dictionary:
	if _map_indexes.is_empty():
		return {}
	return _preset_at_map_slot(clampi(_selected, 0, _map_indexes.size() - 1))


func _active_minigame_preset() -> Dictionary:
	if _selector_game.is_empty():
		_selector_game = _deliver_entry
	var raw: Dictionary = _selector_game.get("preset", {}) as Dictionary
	return _live_preset(raw)


func _extract_arenas(preset: Dictionary) -> Array[Dictionary]:
	## Reads the 3 unique maps from `preset["themes"]` and resolves each map's
	## 16:9 screenshot (`preview_<arena_id>.png` -> `preview_<preset.id>.png`),
	## map name, and layout description.
	var result: Array[Dictionary] = []
	var raw_themes: Variant = preset.get("themes", [])
	var fallback_ids: PackedStringArray = TrackDefs.theme_ids(preset)
	var fallback_names: PackedStringArray = TrackDefs.theme_names(preset)
	var mode_id: String = str(preset.get("id", ""))

	if raw_themes is Array and not (raw_themes as Array).is_empty():
		var arr: Array = raw_themes as Array
		for i in arr.size():
			var item: Variant = arr[i]
			if item is Dictionary:
				var d: Dictionary = item as Dictionary
				var aid: String = str(d.get("id", fallback_ids[i] if i < fallback_ids.size() else ("map_%d" % i)))
				var aname: String = str(d.get("name", d.get("label",
					fallback_names[i] if i < fallback_names.size() else aid.to_upper())))
				var adesc: String = _concise_arena_desc(aid, str(d.get("desc", d.get("tagline", ""))))
				var tex: Texture2D = _arena_screenshot(aid, str(d.get("preview", "")), preset)
				result.append({
					"id": aid,
					"name": aname,
					"desc": adesc,
					"texture": tex,
					"accent": _arena_accent(aid, mode_id),
				})
	elif not fallback_ids.is_empty():
		for i in fallback_ids.size():
			var aid: String = fallback_ids[i]
			var aname: String = fallback_names[i] if i < fallback_names.size() else aid.to_upper()
			result.append({
				"id": aid,
				"name": aname,
				"desc": _concise_arena_desc(aid, ""),
				"texture": _arena_screenshot(aid, "", preset),
				"accent": _arena_accent(aid, mode_id),
			})
	return result


func _arena_screenshot(arena_id: String, custom_file: String,
		preset: Dictionary) -> Texture2D:
	var tex: Texture2D = _texture_at(ART_PREVIEW_DIR + "preview_" + arena_id + ".png")
	if tex != null:
		return tex
	if custom_file != "":
		tex = _texture_at(ART_PREVIEW_DIR + custom_file)
		if tex != null:
			return tex
		tex = _texture_at(PREVIEW_DIR + custom_file)
		if tex != null:
			return tex
	var pid: String = str(preset.get("id", ""))
	if pid != "":
		tex = _texture_at(ART_PREVIEW_DIR + "preview_" + pid + ".png")
		if tex != null:
			return tex
	var pfile: String = str(preset.get("preview", ""))
	if pfile != "":
		tex = _texture_at(ART_PREVIEW_DIR + pfile)
		if tex != null:
			return tex
		tex = _texture_at(PREVIEW_DIR + pfile)
		if tex != null:
			return tex
	return null


func _concise_arena_desc(arena_id: String, raw_desc: String) -> String:
	match arena_id:
		"harbour":
			return "Steel bridge over water & container lanes"
		"farmyard":
			return "Hilltop plateau with mud & timber ramps"
		"snowfield":
			return "Sunken slick-ice rink with 4 snow jumps"
		"ko_rooftop":
			return "Octagon rooftop pad with dropping outer ring"
		"ko_foundry":
			return "Twin smelter islands over a central lava pit"
		"ko_iceberg":
			return "Arctic ice sheet with calving outer shelves"
		"bt_plaza":
			return "Three-tier plaza with ramps & juke tunnels"
		"bt_labyrinth":
			return "Sandstone corridors & high mesa jump-bridge"
		"bt_ferries":
			return "Dual cargo barges linked by bridges & ramps"
	if raw_desc.strip_edges() != "":
		return _trim_line(raw_desc)
	return "High-impact party arena"


func _arena_accent(arena_id: String, mode_id: String) -> Color:
	if arena_id.contains("snow") or arena_id.contains("ice"):
		return UiPalette.CYAN
	if arena_id.contains("farm") or arena_id.contains("rooftop"):
		return UiPalette.ORANGE
	if arena_id.contains("foundry") or arena_id.contains("labyrinth"):
		return UiPalette.RED
	if arena_id.contains("ferries") or arena_id.contains("harbour"):
		return UiPalette.BLUE
	match mode_id:
		"knockout":
			return UiPalette.ORANGE
		"bomb_tag":
			return UiPalette.PINK
	return UiPalette.CYAN


func _accent_for(preset: Dictionary) -> Color:
	if TrackDefs.is_minigame(preset):
		return _arena_accent("", str(preset.get("id", "")))
	var raw: Variant = preset.get("surfaces", [])
	if raw is Array:
		for entry: Variant in raw as Array:
			if not (entry is Dictionary):
				continue
			match str((entry as Dictionary).get("kind", "normal")):
				"wet":
					return UiPalette.BLUE
				"ice":
					return UiPalette.CYAN
				"sand", "dirt":
					return UiPalette.YELLOW_DARK
	return UiPalette.GRASS


func _preview_for_preset(preset: Dictionary) -> Texture2D:
	return _preview_texture(str(preset.get("id", "")),
		str(preset.get("preview", "")))


func _preview_texture(id: String, file: String) -> Texture2D:
	var art: String = ART_PREVIEW_DIR + "preview_" + id + ".png"
	var texture: Texture2D = _texture_at(art)
	if texture != null:
		return texture
	if file != "":
		texture = _texture_at(PREVIEW_DIR + file)
		if texture != null:
			return texture
	return _texture_at(PREVIEW_DIR + FALLBACK_PREVIEW)


func _texture_at(path: String) -> Texture2D:
	if path == "" or not ResourceLoader.exists(path):
		return null
	return load(path) as Texture2D


# --------------------------------------------------------------------------
# pages


func _show_games(animate: bool = true) -> void:
	var came_from: String = _page
	_page = PAGE_GAMES
	_games_page.visible = true
	_selector_page.visible = false
	_title.text = "MODES"
	_refresh_header_controls()
	_fit_page_heights()
	call_deferred("_fit_page_heights")
	_refresh_vehicle()
	_set_background_slides(PackedStringArray(BACKGROUND_ART_GAMES))
	if animate:
		_page_in(_games_page)
		UiAnim.stagger_slide(_game_cards, Vector2(0.0, 20.0), 0.04, 0.24)
	MenuNav.refresh()
	MenuNav.focus(_game_card_for(came_from))


func _show_selector(game_id: String) -> void:
	var entry: Dictionary = _game_entry_for(game_id)
	if entry.is_empty():
		_show_games(true)
		return
	var racing: bool = game_id == GAME_RACING
	_page = game_id
	_games_page.visible = false
	_selector_page.visible = true
	_refresh_header_controls()
	_map_grid.visible = racing
	if racing:
		_arena_grid.visible = false
		_arena_empty.visible = false
		_title.text = "TRACKS"
		_selector_caption.text = ""
		_selector_caption.visible = false
		_set_background_slides(_map_slide_pool())
		UiAnim.stagger_slide(_map_cards, Vector2(0.0, 20.0), 0.04, 0.24)
	else:
		_show_minigame_page(entry)
		_title.text = str(entry.get("name", "ARENAS")).to_upper()
		_selector_caption.text = ""
		_set_background_slides(_arena_slide_pool())
		UiAnim.stagger_slide(_arena_cards, Vector2(0.0, 20.0), 0.045, 0.24)
		_selector_caption.visible = false
	_selector_scroll.scroll_vertical = 0
	_fit_page_heights()
	call_deferred("_fit_page_heights")
	_refresh_vehicle()
	_refresh_play_label()
	_page_in(_selector_page)
	MenuNav.refresh()
	_focus_page()


func _show_minigame_page(entry: Dictionary) -> void:
	_selector_game = entry
	var preset: Dictionary = _active_minigame_preset()
	var mode_id: String = str(entry.get("id", ""))
	var mode_name: String = str(entry.get("name", "ARENA"))
	var mode_accent: Color = entry.get("accent", UiPalette.CYAN) as Color

	for child: Node in _arena_grid.get_children():
		_arena_grid.remove_child(child)
		child.queue_free()
	_arena_cards.clear()

	_arena_entries = _extract_arenas(preset)
	if _arena_entries.is_empty():
		_arena_grid.visible = false
		_arena_empty.visible = true
		return

	_arena_grid.visible = true
	_arena_empty.visible = false
	_arena_grid.columns = mini(_arena_entries.size(), GRID_COLUMNS)

	var wanted_id: String = str(_selected_arena_by_mode.get(mode_id, ""))
	if wanted_id == "":
		if Network.is_session_active() and Network.session_minigame != "":
			wanted_id = Network.session_minigame
		else:
			wanted_id = GameSettings.selected_minigame
	var found_idx: int = -1
	for i in _arena_entries.size():
		if str(_arena_entries[i].get("id", "")) == wanted_id:
			found_idx = i
			break
	_selected_arena_index = maxi(found_idx, 0)
	var active_id: String = str(_arena_entries[_selected_arena_index].get("id", ""))
	_selected_arena_by_mode[mode_id] = active_id

	for i in _arena_entries.size():
		var card: Button = _make_arena_card(i, _arena_entries[i], mode_accent, mode_name)
		_arena_grid.add_child(card)
		_arena_cards.append(card)
	_update_arena_cards(mode_accent)


func _current_arena_id() -> String:
	if _arena_entries.is_empty():
		var preset: Dictionary = _active_minigame_preset()
		return TrackDefs.default_theme(preset) if not preset.is_empty() else ""
	var idx: int = clampi(_selected_arena_index, 0, _arena_entries.size() - 1)
	return str(_arena_entries[idx].get("id", ""))


func _current_arena_name() -> String:
	if _arena_entries.is_empty():
		return "MAP"
	var idx: int = clampi(_selected_arena_index, 0, _arena_entries.size() - 1)
	return str(_arena_entries[idx].get("name", "MAP"))


func _game_entry_for(game_id: String) -> Dictionary:
	for entry: Dictionary in _games:
		if str(entry.get("id", "")) == game_id:
			return entry
	return {}


func _game_card_for(game_id: String) -> Button:
	for index in _games.size():
		if str(_games[index].get("id", "")) == game_id \
				and index < _game_cards.size():
			return _game_cards[index]
	if not _game_cards.is_empty():
		return _game_cards[0]
	return _back_button


func _on_back() -> void:
	if _page != PAGE_GAMES:
		if _opened_direct_from_lobby and Network.is_session_active():
			SceneLoader.go_to(LOBBY_SCENE, "MULTIPLAYER", "Back to the lobby")
			return
		_show_games()
		return
	if Network.is_session_active():
		SceneLoader.go_to(LOBBY_SCENE, "MULTIPLAYER", "Back to the lobby")
	else:
		SceneLoader.go_to(PLAY_MENU_SCENE, "PLAY")


func _on_game_pressed(game_id: String) -> void:
	if game_id == GAME_SANDBOX:
		_on_sandbox_selected()
		return
	_show_selector(game_id)


func _on_sandbox_selected() -> void:
	if Network.is_session_active():
		if not Network.is_host:
			return
		GameSettings.set_multiplayer_mode(GameSettings.GAME_SANDBOX)
		Network.configure_session(GameSettings.GAME_SANDBOX,
			GameSettings.bots_enabled, GameSettings.effective_bot_count(), "",
			Network.GAME_SCENE)
		if Network.has_method("set_host_event") and ("EVENT_SANDBOX" in Network):
			Network.call("set_host_event", str(Network.get("EVENT_SANDBOX")), "")
		SceneLoader.go_to(LOBBY_SCENE, "MULTIPLAYER", "Sandbox selected")
		return
	GameSettings.set_play_mode(GameSettings.MODE_SINGLE)
	GameSettings.vehicle_edit_minigame = false
	GameSettings.vehicle_return_scene = ""
	VehicleSelect.set_racing_intent(false)
	SceneLoader.go_to(VEHICLE_SCENE, "SANDBOX", "Pick your ride")


func _on_map_pressed(position: int) -> void:
	if _map_cards.is_empty():
		return
	_selected = clampi(position, 0, _map_cards.size() - 1)
	var chosen_id: String = str(_current_map().get("id", ""))
	if chosen_id != "" and not Network.is_session_active():
		GameSettings.set_selected_map(chosen_id)
	_update_map_cards()
	_refresh_play_label()
	MenuNav.refresh()


func _on_arena_pressed(slot: int) -> void:
	if _arena_cards.is_empty() or _arena_entries.is_empty():
		return
	_selected_arena_index = clampi(slot, 0, _arena_entries.size() - 1)
	var arena_id: String = _current_arena_id()
	var mode_id: String = str(_selector_game.get("id", ""))
	if mode_id != "" and arena_id != "":
		_selected_arena_by_mode[mode_id] = arena_id
	if arena_id != "":
		GameSettings.set_selected_minigame(arena_id)
	var accent: Color = _selector_game.get("accent", UiPalette.CYAN) as Color
	_update_arena_cards(accent)
	_refresh_play_label()
	MenuNav.refresh()


func _update_map_cards() -> void:
	for index in _map_cards.size():
		var selected: bool = index == _selected
		var preset: Dictionary = _preset_at_map_slot(index)
		var fill: Color = UiPalette.YELLOW if selected \
			else _accent_for(preset).lightened(0.35)
		_map_cards[index].set("fill_color", fill)
		_outline_selected(_map_cards[index], selected)


func _update_arena_cards(mode_accent: Color) -> void:
	for index in _arena_cards.size():
		var selected: bool = index == _selected_arena_index
		var arena_col: Color = mode_accent
		if index < _arena_entries.size():
			arena_col = _arena_entries[index].get("accent", mode_accent) as Color
		var fill: Color = UiPalette.YELLOW if selected else arena_col.lightened(0.35)
		_arena_cards[index].set("fill_color", fill)
		_outline_selected(_arena_cards[index], selected)


func _outline_selected(card: Button, selected: bool) -> void:
	for state: String in ["normal", "hover", "pressed"]:
		var base: StyleBox = card.get_theme_stylebox(state)
		if not (base is StyleBoxFlat):
			continue
		var ring: StyleBoxFlat = (base as StyleBoxFlat).duplicate() as StyleBoxFlat
		ring.set_border_width_all(9 if selected else 6)
		card.add_theme_stylebox_override(state, ring)


func _on_confirm() -> void:
	if _play_button == null or _play_button.disabled:
		return
	if _page == GAME_RACING:
		_launch(_current_map(), false)
	elif _page != PAGE_GAMES:
		_launch(_active_minigame_preset(), true)


func _confirm_target(data: Dictionary, minigame: bool) -> Dictionary:
	if data.is_empty():
		return {}
	if minigame:
		var arena_id: String = _current_arena_id()
		if arena_id == "":
			arena_id = TrackDefs.default_theme(data)
		var arena_name: String = _current_arena_name()
		var game_name: String = str(data.get("game", data.get("name", "MATCH")))
		return {
			"scene": _scene_for(data),
			"title": game_name,
			"hint": arena_name,
			"id": str(data.get("id", "")),
			"theme": arena_id,
		}
	return {
		"scene": _scene_for(data),
		"title": str(data.get("name", "RACE")),
		"hint": str(data.get("hint", "3 LAPS TO WIN")),
		"id": str(data.get("id", TrackDefs.DEFAULT_ID)),
		"theme": "",
	}


func _scene_for(data: Dictionary) -> String:
	return str(data.get("scene", RACE_SCENE))


func _event_id_for(data: Dictionary, minigame: bool) -> String:
	if not minigame:
		if "EVENT_RACE" in Network:
			return str(Network.get("EVENT_RACE"))
		return "race"
	var pid: String = str(data.get("id", ""))
	match pid:
		"cargo_rush", "cargo", "deliver":
			if "EVENT_CARGO" in Network:
				return str(Network.get("EVENT_CARGO"))
			return "cargo_rush"
		"knockout":
			if "EVENT_KNOCKOUT" in Network:
				return str(Network.get("EVENT_KNOCKOUT"))
			return "knockout"
		"bomb_tag":
			if "EVENT_BOMB_TAG" in Network:
				return str(Network.get("EVENT_BOMB_TAG"))
			return "bomb_tag"
	return pid


func _launch(data: Dictionary, minigame: bool) -> void:
	if data.is_empty() or not bool(data.get("available", true)):
		return
	if Network.is_session_active() and not Network.is_host:
		return
	var target: Dictionary = _confirm_target(data, minigame)
	var scene: String = str(target.get("scene", ""))
	if scene == "" or not scene.begins_with("res://"):
		return
	var chosen_arena: String = str(target.get("theme", ""))
	var chosen_map: String = str(target.get("id", TrackDefs.DEFAULT_ID))
	if minigame:
		if chosen_arena != "":
			GameSettings.set_selected_minigame(chosen_arena)
	else:
		GameSettings.set_selected_map(chosen_map)

	if Network.is_session_active():
		if not Network.is_host:
			return
		GameSettings.set_multiplayer_mode(GameSettings.GAME_MINIGAMES)
		var event_id: String = _event_id_for(data, minigame)
		var chosen_target: String = chosen_arena if minigame else chosen_map
		Network.configure_session(GameSettings.GAME_MINIGAMES,
			GameSettings.bots_enabled, GameSettings.effective_bot_count(),
			"" if minigame else chosen_map, scene)
		if minigame and ("session_minigame" in Network):
			Network.set("session_minigame", chosen_arena)
		if Network.has_method("set_host_event"):
			Network.call("set_host_event", event_id, chosen_target)
		SceneLoader.go_to(LOBBY_SCENE, "MULTIPLAYER",
			"Map selected" if minigame else "Track selected")
		return

	GameSettings.set_play_mode(GameSettings.MODE_SINGLE)
	SceneLoader.go_to(scene, str(target["title"]), str(target["hint"]))


func _refresh_play_label() -> void:
	if _play_button == null:
		return
	var data: Dictionary = _current_map() if _page == GAME_RACING \
		else _active_minigame_preset()
	if data.is_empty():
		_play_button.disabled = true
		_play_button.text = "UNAVAILABLE"
		_play_button.fit_text()
		return
	if Network.is_session_active() and not Network.is_host:
		_play_button.disabled = true
		_play_button.text = "HOST PICKS MAP"
		_play_button.fit_text()
		return
	_play_button.disabled = not bool(data.get("available", true))
	if _play_button.disabled:
		_play_button.text = "UNAVAILABLE"
		_play_button.fit_text()
		return
	var minigame: bool = TrackDefs.is_minigame(data)
	var target_name: String = _current_arena_name() if minigame \
		else str(data.get("name", "MAP"))
	if Network.is_session_active():
		_play_button.text = target_name
	else:
		_play_button.text = "RACE" if not minigame else "START"
	_play_button.set_meta("sfx_confirm", true)
	_play_button.fit_text()


# --------------------------------------------------------------------------
# vehicle


func _refresh_vehicle() -> void:
	var racing_now: bool = _page == GAME_RACING or _page == PAGE_GAMES
	var id: String = GameSettings.racing_vehicle_id() \
		if racing_now else GameSettings.minigame_vehicle
	var entry: Dictionary = Catalog.find(id)
	if entry.is_empty():
		entry = Catalog.find(Catalog.DEFAULT_ID)
	var car_name: String = str(entry.get("name", "SHOPPING CART"))
	if _vehicle_button != null:
		_vehicle_button.visible = not Network.is_session_active()
		_vehicle_button.text = car_name
		_vehicle_button.set("fill_color", Color("8ed8f6"))
		_vehicle_button.fit_text()
	if _header_garage_button != null:
		_header_garage_button.text = "GARAGE"
		_header_garage_button.fit_text()


func _on_change_vehicle() -> void:
	_return_page = _page
	_return_map = str(_current_map().get("id", ""))
	_return_theme = _current_arena_id()
	GameSettings.vehicle_return_scene = MINIGAMES_SCENE
	GameSettings.vehicle_return_title = "SELECT TRACK" if _page == GAME_RACING \
		else "SELECT MAP"
	GameSettings.vehicle_edit_minigame = _page != GAME_RACING
	VehicleSelect.set_racing_intent(_page == GAME_RACING)
	SceneLoader.go_to(VEHICLE_SCENE, "GARAGE", "Choose your ride")


# --------------------------------------------------------------------------
# verification


func _run_selftest() -> void:
	if _game_cards.is_empty() or _map_cards.is_empty():
		print("MINIGAMES_SELFTEST missing_cards")
		get_tree().quit(1)
		return
	_game_card_for(GAME_RACING).emit_signal("pressed")
	await get_tree().process_frame
	var racing_page: bool = _page == GAME_RACING and _map_grid.visible
	var pick: int = clampi(1, 0, _map_cards.size() - 1)
	_map_cards[pick].emit_signal("pressed")
	await get_tree().process_frame
	var map_target: Dictionary = _confirm_target(_current_map(), false)
	var focus_ok: bool = MenuNav.focus(_map_cards[pick]) \
		and MenuNav.focused_control() == _map_cards[pick]
	_on_back()
	await get_tree().process_frame
	var back_ok: bool = _page == PAGE_GAMES and _games_page.visible

	var minigames_ok: bool = true
	var minigame_count: int = 0
	var last_mg_target: Dictionary = {}
	for entry: Dictionary in _games:
		if str(entry.get("kind", "")) != GAME_MINIGAME:
			continue
		minigame_count += 1
		var gid: String = str(entry.get("id", ""))
		_game_card_for(gid).emit_signal("pressed")
		await get_tree().process_frame
		if _arena_cards.is_empty() or not _arena_grid.visible:
			minigames_ok = false
			break
		var arena_pick: int = clampi(1, 0, _arena_cards.size() - 1)
		_arena_cards[arena_pick].emit_signal("pressed")
		await get_tree().process_frame
		var mg_preset: Dictionary = _active_minigame_preset()
		last_mg_target = _confirm_target(mg_preset, true)
		var card_focus_ok: bool = MenuNav.focus(_arena_cards[arena_pick]) \
			and MenuNav.focused_control() == _arena_cards[arena_pick]
		if not card_focus_ok or str(last_mg_target.get("theme", "")) == "" \
				or str(last_mg_target.get("scene", "")) == "":
			minigames_ok = false
			break
		_on_back()
		await get_tree().process_frame

	var sandbox_present: bool = not _game_entry_for(GAME_SANDBOX).is_empty()
	var map_ok: bool = str(map_target.get("scene", "")) == RACE_SCENE \
		and str(map_target.get("id", "")) != ""
	var return_map: String = str(_current_map().get("id", ""))
	_return_page = GAME_RACING
	_return_map = return_map
	_return_theme = "farmyard"
	var resume: String = _consume_return_state()
	_build_games()
	_initial_state()
	var restore_ok: bool = resume == GAME_RACING \
		and _restored_theme == "farmyard" \
		and str(_current_map().get("id", "")) == return_map
	print("MINIGAMES_SELFTEST page=%s scene=%s map=%s racing_page=%s back=%s "
		% [_page, str(map_target.get("scene", "")),
		str(map_target.get("id", "")), str(racing_page), str(back_ok)]
		+ "mg_count=%d mg_scene=%s mg_map=%s sandbox=%s focus=%s restore=%s"
		% [minigame_count, str(last_mg_target.get("scene", "")),
		str(last_mg_target.get("theme", "")), str(sandbox_present),
		str(focus_ok), str(restore_ok)])
	get_tree().quit(0 if map_ok and racing_page and back_ok and focus_ok \
		and minigames_ok and minigame_count >= 3 and sandbox_present and restore_ok else 1)
