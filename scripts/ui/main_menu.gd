extends Control
## Unified Slanted Parallelogram Racing-Sim Hub Main Menu:
## - Full-bleed living Ken Burns key-art backdrop that shuffles all four hero
##   plates on its own randomized 8-12 s beat (smooth crossfades). It is
##   completely independent of the UI: hovering/focusing any option never
##   retargets or pauses it (0.8.7 user correction), and each option keeps only
##   its own local hover/focus animation.
## - Floating top-left curved-corner icon + slanted version tag (zero redundant title bar)
## - Floating top-right slanted parallelogram utility tabs (UPDATE / SETTINGS / NOTES / QUIT)
## - Left asymmetric hero wordmark + slanted parallelogram launch rail
##   (SINGLEPLAYER / MULTIPLAYER / MAPMAKER / GARAGE). MAPMAKER is a greyed-out
##   lock teaser that stays clickable and opens the "COMING SOON :D" popup with
##   a single one-shot confetti burst (scripts/ui/mapmaker_teaser.gd).
## - Bottom floating row of 5 TRUE slanted parallelogram preview cards (UV-mapped art inside
##   skewed parallelograms, upward hover lift, soft diagonal gloss sweep, slanted focus glow)
## - Zero rectangular focus rings, zero floating spotlight clutter, zero ghost text.

const UiAnim := preload("res://scripts/ui/ui_anim.gd")
const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const CheckerFlag := preload("res://scripts/ui/checker_flag.gd")
const DripLabel := preload("res://scripts/ui/drip_label.gd")
const MinigamesMenu := preload("res://scripts/ui/minigames_menu.gd")
const VehicleSelect := preload("res://scripts/ui/vehicle_select.gd")

const TITLE_FONT: Font = preload("res://assets/ui/fonts/LuckiestGuy-Regular.ttf")
const BODY_FONT: Font = preload("res://assets/ui/fonts/Fredoka-Bold.ttf")
const ICON_TEX: Texture2D = preload("res://assets/ui/cart_icon.png")

const MINIGAMES_SCENE: String = "res://scenes/ui/minigames_menu.tscn"
const LOBBY_SCENE: String = "res://scenes/ui/lobby_menu.tscn"
const VEHICLE_SCENE: String = "res://scenes/ui/vehicle_select.tscn"
const SANDBOX_SCENE: String = "res://scenes/sandbox/sandbox.tscn"
const MAIN_MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"
const ART_DIR: String = "res://assets/ui/art/"
## The main menu cycles the full hero key-art set; ArtBackdrop shuffles this pool
## on its own 8-12 s beat. This is the ONLY handshake with the backdrop.
const BACKGROUND_ART: Array[String] = [
	"bg_hero_paddock.png",
	"bg_hero_canyon.png",
	"bg_hero_arena.png",
	"bg_hero_glacier.png",
]
const MAPMAKER_TEASER_SCENE: String = "res://scenes/ui/mapmaker_teaser.tscn"

## Hero-rail density for the 4-tile layout (0.8.7). At the 1280x720 design box
## the rail is 424 px tall inside the 430 px left column: wordmark + four
## slanted launcher tiles + four UiKit.SPACING_MED gaps. The taller rail still
## clears the bottom dock (top edge 568 px) and the top utility bar (bottom 74
## px), so 1080p and ultrawide only re-centre the same composition.
const HERO_RAIL_OFFSET_TOP: float = -224.0 ## Rail top at 360 - 224 = 136 px.
const HERO_RAIL_OFFSET_BOTTOM: float = 200.0 ## Rail bottom at 560 px (dock at 568).
const HERO_TILE_WIDTH: float = 374.0 ## One shared launcher width for the column.
const HERO_PRIMARY_HEIGHT: float = 70.0 ## SINGLEPLAYER: the one filled primary tile.
const HERO_TILE_HEIGHT: float = 62.0 ## MULTIPLAYER: secondary tile.
const HERO_TEASER_HEIGHT: float = 60.0 ## MAPMAKER: greyed lock teaser.
const HERO_LAST_HEIGHT: float = 58.0 ## GARAGE: quietest launcher of the four.
const WORDMARK_HEIGHT: float = 118.0 ## CART SLOP GP wordmark box above the rail.

## Web builds are solo-only (README): a browser has no raw UDP sockets for ENet,
## cannot close its own tab from script and has no desktop updater. Instead of
## routing the player into a broken flow, the menu turns those entries into
## honest hints (WS5-03). The env override exists so the headless suites can
## measure the web variant: OS.has_feature("web") is only true in a real export.
const WEB_FORCE_ENV: String = "CSGP_FORCE_WEB"


static func is_web_build() -> bool:
	## True in a web export, or when a headless suite forces it through the env.
	if OS.get_environment(WEB_FORCE_ENV) == "1":
		return true
	return OS.has_feature("web")

## The five bottom dock cards are mode shortcuts with their own local hover
## lift/gloss animation. They deliberately carry NO backdrop dependency: the
## background shuffles on its own timer and ignores pointer/focus entirely.
const QUICK_MODES: Array[Dictionary] = [
	{"id": "racing", "name": "RACING", "accent": Color("4fbf52"), "thumb": "preview_stadium.png"},
	{"id": "knockout", "name": "KNOCKOUT", "accent": Color("ff922b"), "thumb": "preview_knockout.png"},
	{"id": "cargo_rush", "name": "DELIVER", "accent": Color("38d6f0"), "thumb": "preview_cargo_rush.png"},
	{"id": "bomb_tag", "name": "BLAST TAG", "accent": Color("f26ca7"), "thumb": "preview_bomb_tag.png"},
	{"id": "sandbox", "name": "SANDBOX", "accent": Color("ffd22e"), "thumb": "preview_sandbox.png"},
]


static func _para(x0: float, y0: float, w: float, h: float, sk: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(x0 + sk, y0),
		Vector2(x0 + sk + w, y0),
		Vector2(x0 + w, y0 + h),
		Vector2(x0, y0 + h),
	])


static func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	if not out.is_empty():
		out.append(out[0])
	return out


class _SlashTag extends Control:
	## Compact slanted parallelogram version ribbon (no box clutter).
	var label_text: String = "v0.8.6"
	var fill_color: Color = Color(0.08, 0.09, 0.19, 0.90)
	var accent_color: Color = Color("ffd22e")

	func _init() -> void:
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		custom_minimum_size = Vector2(92.0, 32.0)

	func set_tag(value: String) -> void:
		label_text = value
		queue_redraw()

	func _draw() -> void:
		var sk: float = 9.0
		var bw: float = maxf(size.x - sk - 6.0, 20.0)
		var bh: float = maxf(size.y - 6.0, 16.0)
		var pts := PackedVector2Array([
			Vector2(2.0 + sk, 2.0),
			Vector2(2.0 + sk + bw, 2.0),
			Vector2(2.0 + bw, 2.0 + bh),
			Vector2(2.0, 2.0 + bh),
		])
		var sh := PackedVector2Array([
			pts[0] + Vector2(3.0, 4.0), pts[1] + Vector2(3.0, 4.0),
			pts[2] + Vector2(3.0, 4.0), pts[3] + Vector2(3.0, 4.0),
		])
		draw_colored_polygon(sh, Color(0.03, 0.03, 0.10, 0.60))
		draw_colored_polygon(pts, fill_color)
		var cl := pts.duplicate()
		cl.append(pts[0])
		draw_polyline(cl, UiPalette.INK, 3.0, true)
		var fsz: int = 15
		var ascent: float = BODY_FONT.get_ascent(fsz)
		var ty: float = 2.0 + (bh + ascent * 0.72) * 0.5
		draw_string(BODY_FONT, Vector2(2.0 + sk * 0.5, ty), label_text,
			HORIZONTAL_ALIGNMENT_CENTER, bw, fsz, accent_color)


class _SimHeroTile extends Button:
	## Slanted racing-sim hero launcher tile with true parallelogram focus halo,
	## zero duplicate Button text, hover slide-right, and diagonal sheen sweep.
	## `teaser` renders the same geometry in a greyed "locked / coming soon" skin
	## with a crisp procedural padlock instead of the launch chevron. It stays a
	## live Button on purpose: the tile must still click, focus and answer the
	## pointer like every other rail option (only the art says "not yet").
	var label_text: String = ""
	var accent_color: Color = Color("ffd22e")
	var primary_fill: bool = false
	var teaser: bool = false
	var _hovered: bool = false
	var _held: bool = false
	var _hover_t: float = 0.0
	var _shine_t: float = 2.0

	func _ready() -> void:
		focus_mode = Control.FOCUS_ALL
		flat = true
		clip_contents = false
		set_meta("skip_kit", true)
		set_meta("custom_focus", true)
		if teaser:
			set_meta("locked_teaser", true)
			tooltip_text = "MAPMAKER - COMING SOON :D"
		var empty := StyleBoxEmpty.new()
		for st: String in ["normal", "hover", "pressed", "disabled", "focus"]:
			add_theme_stylebox_override(st, empty)
		var clear := Color(0.0, 0.0, 0.0, 0.0)
		for ck: String in ["font_color", "font_hover_color", "font_focus_color",
				"font_pressed_color", "font_disabled_color"]:
			add_theme_color_override(ck, clear)
		mouse_entered.connect(_on_hover.bind(true))
		mouse_exited.connect(_on_hover.bind(false))
		focus_entered.connect(_on_focus.bind(true))
		focus_exited.connect(_on_focus.bind(false))
		button_down.connect(func() -> void: _held = true; queue_redraw())
		button_up.connect(func() -> void: _held = false; queue_redraw())
		resized.connect(func() -> void: pivot_offset = size * 0.5)

	func _on_hover(on: bool) -> void:
		_hovered = on
		if on:
			_shine_t = -0.35
		queue_redraw()

	func _on_focus(on: bool) -> void:
		if on:
			_shine_t = -0.35
		queue_redraw()

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		var active: bool = (_hovered or has_focus()) and not disabled
		var target: float = 1.0 if active else 0.0
		_hover_t = UiAnim.damp(_hover_t, target, delta, 16.0)
		var s: float = 0.97 if _held else lerpf(1.0, 1.028, _hover_t)
		scale = Vector2.ONE * s
		z_index = 4 if active else 0
		if _shine_t < 1.5:
			_shine_t += delta * 2.5
			queue_redraw()
		elif absf(_hover_t - target) > 0.004:
			queue_redraw()

	func _draw_lock(center: Vector2, col: Color) -> void:
		## Crisp vector padlock: shackle arc + body plate + keyhole. No assets.
		draw_arc(center + Vector2(0.0, -4.5), 7.0, PI, TAU, 16, col, 3.2, true)
		var body := Rect2(center + Vector2(-9.0, -2.5), Vector2(18.0, 14.0))
		draw_rect(body, col, true)
		draw_rect(body, UiPalette.INK, false, 1.8)
		draw_circle(center + Vector2(0.0, 3.0), 1.9, UiPalette.INK)
		draw_rect(Rect2(center + Vector2(-0.9, 3.5), Vector2(1.8, 4.5)),
			UiPalette.INK, true)

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		if w < 24.0 or h < 20.0:
			return
		var focused: bool = has_focus() and not disabled
		var sk: float = 16.0
		var shift: float = _hover_t * 10.0
		var pad_t: float = 4.0
		var pad_b: float = 8.0
		var bh: float = h - pad_t - pad_b
		var bw: float = w - sk - 18.0
		var x0: float = shift + 4.0
		var y0: float = pad_t + (2.0 if _held else 0.0)

		var pts := PackedVector2Array([
			Vector2(x0 + sk, y0),
			Vector2(x0 + sk + bw, y0),
			Vector2(x0 + bw, y0 + bh),
			Vector2(x0, y0 + bh),
		])

		# Hard comic shadow
		var sh_off := Vector2(4.0, 6.0 if not _held else 2.5)
		var sh := PackedVector2Array([
			pts[0] + sh_off, pts[1] + sh_off, pts[2] + sh_off, pts[3] + sh_off,
		])
		draw_colored_polygon(sh, Color(0.03, 0.03, 0.10, 0.72))

		# Matching SLANTED PARALLELOGRAM focus halo (never a rounded box!)
		if focused:
			var halo := PackedVector2Array([
				Vector2(x0 + sk - 4.0, y0 - 3.5),
				Vector2(x0 + sk + bw + 4.0, y0 - 3.5),
				Vector2(x0 + bw + 4.0, y0 + bh + 3.5),
				Vector2(x0 - 4.0, y0 + bh + 3.5),
			])
			var hcl := halo.duplicate()
			hcl.append(halo[0])
			var ring_col: Color = Color.WHITE if primary_fill \
				else (UiPalette.YELLOW if teaser else accent_color)
			# Soft outer glow instead of two hard polylines: the halo melts into
			# the plate behind it and never shows a clipped edge.
			UiAnim.draw_soft_outline(self, hcl, Color(0.04, 0.04, 0.12, 0.90),
				8.0, Color(0.04, 0.04, 0.12), 3, 1.8, 0.20)
			UiAnim.draw_soft_outline(self, hcl, ring_col, 3.6, ring_col, 4, 2.2, 0.15)

		# Clean unified parallelogram fill (no side accent stripe!)
		var base_col: Color
		if teaser:
			# Greyed "locked" plate: desaturated slate that only warms slightly
			# on hover, so the tile reads unavailable but never dead.
			base_col = Color(0.112, 0.118, 0.178, 0.95) \
				.lerp(Color(0.150, 0.158, 0.238, 0.98), _hover_t)
		elif primary_fill:
			base_col = accent_color.lightened(_hover_t * 0.10)
		else:
			base_col = Color(0.085, 0.095, 0.195, 0.94) \
				.lerp(Color(0.16, 0.18, 0.34, 0.98), _hover_t)
		draw_colored_polygon(pts, base_col)

		# Subtle top glass sheen (vertical alpha fade, no hard bottom edge)
		var gloss_h: float = bh * 0.34
		var gloss := PackedVector2Array([
			Vector2(x0 + sk + 2.0, y0 + 2.0),
			Vector2(x0 + sk + bw - 2.0, y0 + 2.0),
			Vector2(x0 + sk * 0.66 + bw - 2.0, y0 + 2.0 + gloss_h),
			Vector2(x0 + sk * 0.66 + 2.0, y0 + 2.0 + gloss_h),
		])
		UiAnim.draw_vertical_fade(self, gloss, Color.WHITE,
			0.05 if teaser else (0.16 if primary_fill else 0.08))

		# Animated diagonal shine sweep on hover/focus: soft gradient band.
		if _shine_t >= -0.35 and _shine_t <= 1.35:
			var sx: float = lerpf(x0 - 20.0, x0 + bw + 30.0, _shine_t)
			var sw: float = 36.0
			var shine := PackedVector2Array([
				Vector2(clampf(sx + sk, x0 + sk, x0 + sk + bw), y0 + 2.0),
				Vector2(clampf(sx + sk + sw, x0 + sk, x0 + sk + bw), y0 + 2.0),
				Vector2(clampf(sx + sw, x0, x0 + bw), y0 + bh - 2.0),
				Vector2(clampf(sx, x0, x0 + bw), y0 + bh - 2.0),
			])
			if shine[1].x > shine[0].x + 2.0 and shine[2].x > shine[3].x + 2.0:
				UiAnim.draw_soft_band(self, shine, Color.WHITE, 0.25)

		# Bold ink border + subtle active inner stroke
		var closed := pts.duplicate()
		closed.append(pts[0])
		draw_polyline(closed, UiPalette.INK, 4.5, true)
		if _hover_t > 0.08 and not primary_fill and not teaser:
			var inner := PackedVector2Array([
				Vector2(x0 + sk + 2.5, y0 + 2.5),
				Vector2(x0 + sk + bw - 2.5, y0 + 2.5),
				Vector2(x0 + bw - 2.5, y0 + bh - 2.5),
				Vector2(x0 + 2.5, y0 + bh - 2.5),
			])
			var icl := inner.duplicate()
			icl.append(inner[0])
			UiAnim.draw_soft_outline(self, icl,
				Color(1.0, 1.0, 1.0, 0.35 * _hover_t), 2.0,
				Color.WHITE, 2, 1.8, 0.10 * _hover_t)

		# Right-edge glyph: launching chevron on live tiles, crisp padlock on the
		# MAPMAKER teaser (drawn in vector, zero binary assets).
		if teaser:
			var lock_col: Color = UiPalette.TEXT_DIM.lerp(
				Color(1.0, 0.97, 0.90, 0.95), _hover_t * 0.5)
			_draw_lock(Vector2(x0 + bw - 29.0 + _hover_t * 3.0,
				y0 + bh * 0.5 - 1.0), lock_col)
		else:
			var cx: float = x0 + bw - 22.0 + _hover_t * 6.0
			var cy: float = y0 + bh * 0.5
			var arrow_col: Color = UiPalette.INK if primary_fill else UiPalette.CREAM
			var chev := PackedVector2Array([
				Vector2(cx - 5.0, cy - 8.5),
				Vector2(cx + 5.5, cy),
				Vector2(cx - 5.0, cy + 8.5),
			])
			draw_polyline(chev, arrow_col, 3.8, true)

		# Crisp title text with roomier sizing and zero overflow
		var caption: String = label_text if not label_text.is_empty() else text
		var font_sz: int = 33 if primary_fill else 26
		var txt_col: Color
		if teaser:
			txt_col = UiPalette.TEXT_DIM.lerp(UiPalette.CREAM, _hover_t * 0.35)
		elif primary_fill:
			txt_col = UiPalette.INK
		else:
			txt_col = UiPalette.CREAM
		var text_x: float = x0 + sk + 22.0
		var avail_w: float = maxf(bw - 64.0, 40.0)
		while font_sz > 16 and TITLE_FONT.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, font_sz).x > avail_w:
			font_sz -= 1
		var ascent: float = TITLE_FONT.get_ascent(font_sz)
		var baseline_y: float = y0 + (bh + ascent * 0.78) * 0.5
		if not primary_fill:
			draw_string(TITLE_FONT, Vector2(text_x, baseline_y + 2.5), caption,
				HORIZONTAL_ALIGNMENT_LEFT, avail_w, font_sz, Color(0.03, 0.03, 0.09, 0.90))
		draw_string(TITLE_FONT, Vector2(text_x, baseline_y), caption,
			HORIZONTAL_ALIGNMENT_LEFT, avail_w, font_sz, txt_col)


class _TopSlashButton extends Button:
	## Slanted parallelogram utility button along top-right (zero generic rounded SaaS pills!).
	var label_text: String = ""
	var accent_color: Color = Color("45b6f0")
	var _hovered: bool = false
	var _held: bool = false
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
		button_down.connect(func() -> void: _held = true; queue_redraw())
		button_up.connect(func() -> void: _held = false; queue_redraw())
		resized.connect(func() -> void: pivot_offset = size * 0.5)

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		var active: bool = (_hovered or has_focus()) and not disabled
		var target: float = 1.0 if active else 0.0
		_hover_t = UiAnim.damp(_hover_t, target, delta, 18.0)
		scale = Vector2.ONE * (0.96 if _held else lerpf(1.0, 1.045, _hover_t))
		z_index = 3 if active else 0
		if _shine_t < 1.5:
			_shine_t += delta * 2.8
			queue_redraw()
		elif absf(_hover_t - target) > 0.004:
			queue_redraw()

	func _draw() -> void:
		if size.x < 20.0 or size.y < 16.0:
			return
		var focused: bool = has_focus() and not disabled
		var sk: float = 10.0
		var bw: float = maxf(size.x - sk - 8.0, 16.0)
		var bh: float = maxf(size.y - 8.0, 16.0)
		var x0: float = 4.0
		var y0: float = 3.0 + (1.5 if _held else 0.0)
		var pts := PackedVector2Array([
			Vector2(x0 + sk, y0),
			Vector2(x0 + sk + bw, y0),
			Vector2(x0 + bw, y0 + bh),
			Vector2(x0, y0 + bh),
		])
		var sh := PackedVector2Array([
			pts[0] + Vector2(3.0, 4.0), pts[1] + Vector2(3.0, 4.0),
			pts[2] + Vector2(3.0, 4.0), pts[3] + Vector2(3.0, 4.0),
		])
		draw_colored_polygon(sh, Color(0.03, 0.03, 0.10, 0.65))
		if focused:
			var halo := PackedVector2Array([
				Vector2(x0 + sk - 3.5, y0 - 3.0),
				Vector2(x0 + sk + bw + 3.5, y0 - 3.0),
				Vector2(x0 + bw + 3.5, y0 + bh + 3.0),
				Vector2(x0 - 3.5, y0 + bh + 3.0),
			])
			var hcl := halo.duplicate()
			hcl.append(halo[0])
			UiAnim.draw_soft_outline(self, hcl, UiPalette.YELLOW, 3.2,
				UiPalette.YELLOW, 3, 2.0, 0.14)
		var bg: Color = Color(0.085, 0.095, 0.200, 0.92).lerp(accent_color, _hover_t * 0.92)
		draw_colored_polygon(pts, bg)
		# Gloss sweep (soft gradient band, no clipped rectangle edge)
		if _shine_t >= -0.35 and _shine_t <= 1.35:
			var sx: float = lerpf(x0 - 16.0, x0 + bw + 16.0, _shine_t)
			var sw: float = 22.0
			var x_tl: float = clampf(sx + sk, x0 + sk, x0 + sk + bw)
			var x_tr: float = clampf(sx + sk + sw, x0 + sk, x0 + sk + bw)
			var x_br: float = clampf(sx + sw, x0, x0 + bw)
			var x_bl: float = clampf(sx, x0, x0 + bw)
			if x_tr > x_tl + 2.0 and x_br > x_bl + 2.0:
				UiAnim.draw_soft_band(self, PackedVector2Array([
					Vector2(x_tl, y0 + 2.0), Vector2(x_tr, y0 + 2.0),
					Vector2(x_br, y0 + bh - 2.0), Vector2(x_bl, y0 + bh - 2.0),
				]), Color.WHITE, 0.24)
		var cl := pts.duplicate()
		cl.append(pts[0])
		draw_polyline(cl, UiPalette.INK, 3.5, true)
		var caption: String = label_text if not label_text.is_empty() else text
		var fsz: int = 16
		var avail_w: float = maxf(bw - 10.0, 20.0)
		while fsz > 12 and BODY_FONT.get_string_size(caption, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x > avail_w:
			fsz -= 1
		var tc: Color = UiPalette.INK if _hover_t > 0.45 else UiPalette.CREAM
		var ascent: float = BODY_FONT.get_ascent(fsz)
		var ty: float = y0 + (bh + ascent * 0.72) * 0.5
		draw_string(BODY_FONT, Vector2(x0 + sk * 0.5, ty), caption,
			HORIZONTAL_ALIGNMENT_CENTER, bw, fsz, tc)


class _QuickModeTile extends Button:
	## TRUE Slanted Parallelogram Quick-Play Card!
	## Renders UV-mapped Ken Burns preview art directly inside a skewed parallelogram
	## polygon with upward hover lift, colored top accent strip, diagonal sheen sweep,
	## and a matching slanted parallelogram focus outline.
	var mode_id: String = ""
	var mode_name: String = ""
	var accent_color: Color = Color("ffd22e")
	var preview_tex: Texture2D = null
	var _hovered: bool = false
	var _hover_t: float = 0.0
	var _time: float = 0.0
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
		mouse_entered.connect(func() -> void:
			_hovered = true
			_shine_t = -0.30
			queue_redraw())
		mouse_exited.connect(func() -> void:
			_hovered = false
			queue_redraw())
		focus_entered.connect(func() -> void:
			_shine_t = -0.30
			queue_redraw())
		focus_exited.connect(queue_redraw)
		resized.connect(func() -> void: pivot_offset = Vector2(size.x * 0.5, size.y))

	func _process(delta: float) -> void:
		if not is_visible_in_tree():
			return
		_time += delta
		var active: bool = (_hovered or has_focus()) and not disabled
		var target: float = 1.0 if active else 0.0
		_hover_t = UiAnim.damp(_hover_t, target, delta, 16.0)
		scale = Vector2.ONE * lerpf(1.0, 1.045, _hover_t)
		z_index = 5 if active else 1
		if _shine_t < 1.5:
			_shine_t += delta * 2.5
			queue_redraw()
		elif active or absf(_hover_t - target) > 0.004:
			queue_redraw()

	func _draw() -> void:
		var w: float = size.x
		var h: float = size.y
		if w < 30.0 or h < 30.0:
			return
		var focused: bool = has_focus() and not disabled
		var sk: float = 16.0
		var lift: float = _hover_t * 10.0
		var bw: float = w - sk - 8.0
		var bh: float = h - 14.0
		var x0: float = 4.0
		var y0: float = 10.0 - lift

		var pts := PackedVector2Array([
			Vector2(x0 + sk, y0),
			Vector2(x0 + sk + bw, y0),
			Vector2(x0 + bw, y0 + bh),
			Vector2(x0, y0 + bh),
		])

		# Hard drop shadow
		var sh := PackedVector2Array([
			pts[0] + Vector2(5.0, 7.0), pts[1] + Vector2(5.0, 7.0),
			pts[2] + Vector2(5.0, 7.0), pts[3] + Vector2(5.0, 7.0),
		])
		draw_colored_polygon(sh, Color(0.02, 0.02, 0.09, 0.72))

		# Slanted parallelogram focus glow ring (soft outward fade)
		if focused or _hover_t > 0.06:
			var halo := PackedVector2Array([
				Vector2(x0 + sk - 3.5, y0 - 3.5),
				Vector2(x0 + sk + bw + 3.5, y0 - 3.5),
				Vector2(x0 + bw + 3.5, y0 + bh + 3.5),
				Vector2(x0 - 3.5, y0 + bh + 3.5),
			])
			var hcl := halo.duplicate()
			hcl.append(halo[0])
			var ring_col: Color = UiPalette.YELLOW if focused else accent_color
			UiAnim.draw_soft_outline(self, hcl, Color(0.04, 0.04, 0.12, 0.85),
				7.5, Color(0.04, 0.04, 0.12), 3, 1.6, 0.18)
			UiAnim.draw_soft_outline(self, hcl,
				Color(ring_col, 1.0 if focused else _hover_t), 3.4,
				ring_col, 4, 2.0, (0.16 if focused else 0.12 * _hover_t))

		# Base dark fill
		draw_colored_polygon(pts, Color(0.07, 0.08, 0.17, 0.98))

		# UV-mapped live Ken Burns preview image strictly inside the slanted parallelogram!
		if preview_tex != null:
			var tex_sz: Vector2 = preview_tex.get_size()
			if tex_sz.x > 0.0 and tex_sz.y > 0.0:
				var card_aspect: float = (bw + sk) / maxf(bh, 1.0)
				var tex_aspect: float = tex_sz.x / tex_sz.y
				var zoom: float = 1.06 + _hover_t * 0.14
				var uv_w: float = (1.0 / zoom) * (minf(card_aspect / tex_aspect, 1.0))
				var uv_h: float = (1.0 / zoom) * (minf(tex_aspect / card_aspect, 1.0))
				var drift_u: float = sin(_time * 0.9) * 0.022 * _hover_t
				var drift_v: float = cos(_time * 0.75) * 0.018 * _hover_t
				var u0: float = clampf(0.5 - uv_w * 0.5 + drift_u, 0.0, 1.0 - uv_w)
				var v0: float = clampf(0.5 - uv_h * 0.5 + drift_v, 0.0, 1.0 - uv_h)
				var u1: float = u0 + uv_w
				var v1: float = v0 + uv_h
				var skew_u: float = uv_w * (sk / maxf(bw + sk, 1.0)) * 0.5
				var uvs := PackedVector2Array([
					Vector2(clampf(u0 + skew_u, 0.0, 1.0), v0),
					Vector2(clampf(u1, 0.0, 1.0), v0),
					Vector2(clampf(u1 - skew_u, 0.0, 1.0), v1),
					Vector2(clampf(u0, 0.0, 1.0), v1),
				])
				var tint := Color(1.0, 1.0, 1.0, lerpf(0.86, 1.0, _hover_t))
				var cols := PackedColorArray([tint, tint, tint, tint])
				draw_polygon(pts, cols, uvs, preview_tex)

		# Bottom dark slanted title ribbon (clean — zero colored top bar or side notch!)
		var rib_h: float = 38.0
		var rib_sk: float = sk * (rib_h / bh)
		var rib_y: float = y0 + bh - rib_h
		var rib := PackedVector2Array([
			Vector2(x0 + rib_sk, rib_y),
			Vector2(x0 + rib_sk + bw, rib_y),
			Vector2(x0 + bw, y0 + bh),
			Vector2(x0, y0 + bh),
		])
		draw_colored_polygon(rib, Color(0.055, 0.065, 0.155, 0.92))

		# Diagonal sheen sweep across the slanted card (soft gradient band)
		if _shine_t >= -0.30 and _shine_t <= 1.35:
			var sx: float = lerpf(x0 - 24.0, x0 + bw + 24.0, _shine_t)
			var sw: float = 34.0
			var x_tl: float = clampf(sx + sk, x0 + sk, x0 + sk + bw)
			var x_tr: float = clampf(sx + sk + sw, x0 + sk, x0 + sk + bw)
			var x_br: float = clampf(sx + sw, x0, x0 + bw)
			var x_bl: float = clampf(sx, x0, x0 + bw)
			if x_tr > x_tl + 2.0 and x_br > x_bl + 2.0:
				UiAnim.draw_soft_band(self, PackedVector2Array([
					Vector2(x_tl, y0 + 2.0), Vector2(x_tr, y0 + 2.0),
					Vector2(x_br, y0 + bh - 2.0), Vector2(x_bl, y0 + bh - 2.0),
				]), Color.WHITE, 0.24)

		# Mode name only (crisp, larger, auto-fitted so zero overflow)
		var fsz: int = 19
		var avail_w: float = maxf(bw - 18.0, 30.0)
		while fsz > 13 and TITLE_FONT.get_string_size(mode_name, HORIZONTAL_ALIGNMENT_LEFT, -1, fsz).x > avail_w:
			fsz -= 1
		var ascent: float = TITLE_FONT.get_ascent(fsz)
		var ty: float = rib_y + (rib_h + ascent * 0.72) * 0.5
		draw_string(TITLE_FONT, Vector2(x0 + rib_sk * 0.5, ty), mode_name,
			HORIZONTAL_ALIGNMENT_CENTER, bw, fsz,
			UiPalette.YELLOW if _hover_t > 0.25 else UiPalette.CREAM)

		# Thick ink parallelogram outline
		var cl := pts.duplicate()
		cl.append(pts[0])
		draw_polyline(cl, UiPalette.INK, 4.2, true)


@onready var _background: Control = $Background
@onready var _settings_menu: Control = %SettingsMenu
@onready var _update_panel: Control = %UpdatePanel
@onready var _changelog_panel: Control = %ChangelogPanel

var _top_left_bar: HBoxContainer
var _top_right_bar: HBoxContainer
var _hero_rail: VBoxContainer
var _dock_bar: HBoxContainer
var _version_tag: _SlashTag

var _play_button: _SimHeroTile
var _multi_button: _SimHeroTile
var _mapmaker_button: _SimHeroTile
var _garage_button: _SimHeroTile
var _mapmaker_teaser: Control = null
var _settings_button: _TopSlashButton
var _changelog_button: _TopSlashButton
var _quit_button: _TopSlashButton
var _update_button: _TopSlashButton
var _dock_tiles: Array[Button] = []
var _update_auto_opened: bool = false
## Web-only hint line above the hero rail (never built on desktop).
var _web_notice: Label = null
var _web_notice_tween: Tween = null


func _ready() -> void:
	CursorController.set_menu_mode(true)
	_build_hub_ui()
	_configure_background_slides()
	_version_tag.set_tag("v" + UpdateChecker.read_version_file())
	if _update_button != null:
		_update_button.visible = false

	_settings_menu.closed.connect(_on_modal_closed)
	_update_panel.closed.connect(_on_modal_closed)
	_changelog_panel.closed.connect(_on_modal_closed)

	# The updater only exists on desktop: a web build is refreshed with the
	# browser, so checking for a desktop download here would be a dead end.
	if not is_web_build():
		UpdateChecker.update_available.connect(
			func(version: String, _release_url: String, _download_url: String) -> void:
				_on_update_available(version))
		if UpdateChecker.has_update():
			_on_update_available(UpdateChecker.latest_version)

		UpdateChecker.check_for_updates()
	call_deferred("_enter")


func _build_hub_ui() -> void:
	var web: bool = is_web_build()
	var shell := Control.new()
	shell.name = "HubShell"
	shell.set_anchors_preset(Control.PRESET_FULL_RECT)
	shell.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(shell)
	move_child(shell, 1)

	# ------------------------------------------------------------------
	# 1. Floating Top-Left Clean Curved-Corner App Icon + Slanted Version Tag
	_top_left_bar = HBoxContainer.new()
	_top_left_bar.name = "TopLeftBar"
	_top_left_bar.anchor_left = 0.0
	_top_left_bar.anchor_top = 0.0
	_top_left_bar.offset_left = 34.0
	_top_left_bar.offset_top = 20.0
	_top_left_bar.offset_right = 240.0
	_top_left_bar.offset_bottom = 74.0
	_top_left_bar.add_theme_constant_override("separation", 12)
	_top_left_bar.alignment = BoxContainer.ALIGNMENT_BEGIN
	_top_left_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shell.add_child(_top_left_bar)

	var icon_rect := TextureRect.new()
	icon_rect.texture = ICON_TEX
	icon_rect.custom_minimum_size = Vector2(52, 52)
	icon_rect.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	icon_rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_top_left_bar.add_child(icon_rect)

	_version_tag = _SlashTag.new()
	_version_tag.name = "VersionTag"
	_version_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_top_left_bar.add_child(_version_tag)

	# ------------------------------------------------------------------
	# 2. Floating Top-Right Slanted Parallelogram Utility Tabs
	_top_right_bar = HBoxContainer.new()
	_top_right_bar.name = "TopRightBar"
	_top_right_bar.anchor_left = 1.0
	_top_right_bar.anchor_right = 1.0
	_top_right_bar.anchor_top = 0.0
	_top_right_bar.offset_left = -580.0
	_top_right_bar.offset_right = -26.0
	_top_right_bar.offset_top = 20.0
	_top_right_bar.offset_bottom = 70.0
	_top_right_bar.add_theme_constant_override("separation", 8)
	_top_right_bar.alignment = BoxContainer.ALIGNMENT_END
	_top_right_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shell.add_child(_top_right_bar)

	_update_button = _TopSlashButton.new()
	_update_button.name = "UpdateButton"
	_update_button.label_text = "UPDATE"
	_update_button.accent_color = UiPalette.GRASS
	_update_button.custom_minimum_size = Vector2(138, 46)
	_update_button.pressed.connect(_on_update_pressed)
	# A browser build has no desktop updater to offer: refresh the tab instead.
	if not web:
		_top_right_bar.add_child(_update_button)

	_settings_button = _TopSlashButton.new()
	_settings_button.name = "SettingsButton"
	_settings_button.label_text = "SETTINGS"
	_settings_button.accent_color = UiPalette.BLUE
	_settings_button.custom_minimum_size = Vector2(138, 46)
	_settings_button.pressed.connect(_on_settings_pressed)
	_top_right_bar.add_child(_settings_button)

	_changelog_button = _TopSlashButton.new()
	_changelog_button.name = "ChangelogButton"
	_changelog_button.label_text = "NOTES"
	_changelog_button.accent_color = UiPalette.PINK
	_changelog_button.custom_minimum_size = Vector2(114, 46)
	_changelog_button.pressed.connect(_on_changelog_pressed)
	_top_right_bar.add_child(_changelog_button)

	_quit_button = _TopSlashButton.new()
	_quit_button.name = "QuitButton"
	_quit_button.label_text = "QUIT"
	_quit_button.accent_color = UiPalette.RED
	_quit_button.custom_minimum_size = Vector2(106, 46)
	_quit_button.pressed.connect(_on_quit_pressed)
	# A web page cannot close itself: show a WEB tag instead of a dead QUIT.
	if web:
		var web_tag := _SlashTag.new()
		web_tag.name = "WebTag"
		web_tag.set_tag("WEB")
		web_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		_top_right_bar.add_child(web_tag)
	else:
		_top_right_bar.add_child(_quit_button)

	# ------------------------------------------------------------------
	# 3. Left Asymmetric Hero Title + Slanted Parallelogram Launch Rail
	#    Four tiles share one width and the kit's related-row gap, so the rail
	#    reads as one column at every aspect ratio instead of four drifting
	#    button sizes. Sizes cascade 70 -> 62 -> 60 -> 58 (hero hierarchy).
	_hero_rail = VBoxContainer.new()
	_hero_rail.name = "HeroRail"
	_hero_rail.anchor_left = 0.0
	_hero_rail.anchor_top = 0.5
	_hero_rail.anchor_bottom = 0.5
	_hero_rail.offset_left = 38.0
	_hero_rail.offset_right = 468.0
	_hero_rail.offset_top = HERO_RAIL_OFFSET_TOP
	_hero_rail.offset_bottom = HERO_RAIL_OFFSET_BOTTOM
	_hero_rail.add_theme_constant_override("separation", UiKit.SPACING_MED)
	_hero_rail.alignment = BoxContainer.ALIGNMENT_CENTER
	_hero_rail.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shell.add_child(_hero_rail)

	var logo_box := Control.new()
	logo_box.custom_minimum_size = Vector2(420, WORDMARK_HEIGHT)
	logo_box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hero_rail.add_child(logo_box)

	var flag := Control.new()
	flag.set_script(CheckerFlag)
	flag.set("wave_amount", 3.5)
	flag.position = Vector2(280.0, -4.0)
	flag.size = Vector2(118.0, 68.0)
	flag.rotation = -0.10
	flag.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo_box.add_child(flag)

	var word_row := HBoxContainer.new()
	word_row.add_theme_constant_override("separation", 8)
	word_row.position = Vector2(0.0, 20.0)
	word_row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	logo_box.add_child(word_row)

	word_row.add_child(_word_label("CART", 68, UiPalette.TEXT, -0.04))
	var w_slop := _word_label("SLOP", 68, UiPalette.PINK, 0.025)
	w_slop.set_script(DripLabel)
	word_row.add_child(w_slop)
	word_row.add_child(_word_label("GP", 76, UiPalette.YELLOW, -0.04))

	_play_button = _SimHeroTile.new()
	_play_button.name = "SingleplayerButton"
	_play_button.label_text = "SINGLEPLAYER"
	_play_button.accent_color = UiPalette.YELLOW
	_play_button.primary_fill = true
	_play_button.custom_minimum_size = Vector2(HERO_TILE_WIDTH, HERO_PRIMARY_HEIGHT)
	_play_button.set_meta("sfx_confirm", true)
	_play_button.pressed.connect(_on_solo_pressed)
	_hero_rail.add_child(_play_button)

	_multi_button = _SimHeroTile.new()
	_multi_button.name = "MultiplayerButton"
	_multi_button.label_text = "MULTIPLAYER"
	_multi_button.accent_color = UiPalette.CYAN
	_multi_button.primary_fill = false
	_multi_button.custom_minimum_size = Vector2(HERO_TILE_WIDTH, HERO_TILE_HEIGHT)
	_multi_button.set_meta("sfx_confirm", true)
	_multi_button.pressed.connect(_on_multiplayer_pressed)
	if web:
		_multi_button.tooltip_text = "MULTIPLAYER NEEDS THE DESKTOP DOWNLOAD"
	_hero_rail.add_child(_multi_button)

	# MAPMAKER teaser: deliberately greyed / padlocked, but a live Button. It
	# opens the "COMING SOON :D" popup instead of a scene (single-scope teaser).
	_mapmaker_button = _SimHeroTile.new()
	_mapmaker_button.name = "MapmakerButton"
	_mapmaker_button.label_text = "MAPMAKER"
	_mapmaker_button.accent_color = Color(0.72, 0.76, 0.90)
	_mapmaker_button.primary_fill = false
	_mapmaker_button.teaser = true
	_mapmaker_button.custom_minimum_size = Vector2(HERO_TILE_WIDTH, HERO_TEASER_HEIGHT)
	_mapmaker_button.pressed.connect(_on_mapmaker_pressed)
	_hero_rail.add_child(_mapmaker_button)

	_garage_button = _SimHeroTile.new()
	_garage_button.name = "GarageButton"
	_garage_button.label_text = "GARAGE"
	_garage_button.accent_color = UiPalette.PINK
	_garage_button.primary_fill = false
	_garage_button.custom_minimum_size = Vector2(HERO_TILE_WIDTH, HERO_LAST_HEIGHT)
	_garage_button.pressed.connect(_on_garage_pressed)
	_hero_rail.add_child(_garage_button)

	# ------------------------------------------------------------------
	# 4. Floating Bottom Row of 5 TRUE Slanted Parallelogram Event Cards
	_dock_bar = HBoxContainer.new()
	_dock_bar.name = "QuickDock"
	_dock_bar.anchor_left = 0.0
	_dock_bar.anchor_right = 1.0
	_dock_bar.anchor_top = 1.0
	_dock_bar.anchor_bottom = 1.0
	_dock_bar.offset_left = 26.0
	_dock_bar.offset_right = -26.0
	_dock_bar.offset_top = -152.0
	_dock_bar.offset_bottom = -14.0
	_dock_bar.add_theme_constant_override("separation", 6)
	_dock_bar.alignment = BoxContainer.ALIGNMENT_CENTER
	_dock_bar.mouse_filter = Control.MOUSE_FILTER_IGNORE
	shell.add_child(_dock_bar)

	_dock_tiles.clear()
	for mode: Dictionary in QUICK_MODES:
		var tile := _QuickModeTile.new()
		tile.name = "Dock_" + str(mode["id"])
		tile.mode_id = str(mode["id"])
		tile.mode_name = str(mode["name"])
		tile.accent_color = mode["accent"] as Color
		var thumb_path: String = ART_DIR + str(mode["thumb"])
		if ResourceLoader.exists(thumb_path):
			tile.preview_tex = load(thumb_path) as Texture2D
		tile.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		tile.size_flags_vertical = Control.SIZE_EXPAND_FILL
		tile.set_meta("sfx_confirm", true)
		var m_id: String = str(mode["id"])
		tile.pressed.connect(_on_quick_mode_pressed.bind(m_id))
		_dock_bar.add_child(tile)
		_dock_tiles.append(tile)

	# Web-only hint line, directly under the hero rail so it reads as part of the
	# launch rail. It uses the same title font / ink outline as the rest of the
	# menu (no legacy dialog) and never steals a click.
	if web:
		_web_notice = Label.new()
		_web_notice.name = "WebNotice"
		_web_notice.anchor_left = 0.0
		_web_notice.anchor_right = 0.0
		_web_notice.anchor_top = 0.5
		_web_notice.anchor_bottom = 0.5
		_web_notice.offset_left = 38.0
		_web_notice.offset_right = 468.0
		# Sit the hint between the top-left bar and the taller (4-tile) hero rail.
		_web_notice.offset_top = HERO_RAIL_OFFSET_TOP - 62.0
		_web_notice.offset_bottom = HERO_RAIL_OFFSET_TOP - 28.0
		_web_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_web_notice.add_theme_font_override("font", TITLE_FONT)
		_web_notice.add_theme_font_size_override("font_size", 18)
		_web_notice.add_theme_color_override("font_color", UiPalette.YELLOW)
		_web_notice.add_theme_color_override("font_outline_color", UiPalette.INK)
		_web_notice.add_theme_constant_override("outline_size", 6)
		_web_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_web_notice.visible = false
		shell.add_child(_web_notice)


func _configure_background_slides() -> void:
	## One-way handshake with the backdrop: hand it the full hero key-art set and
	## let ArtBackdrop shuffle/cycle it on its own 8-12 s beat. Nothing here (or
	## anywhere else in the menu) follows hover or focus - button-local hover
	## animation stays entirely inside the tiles.
	if _background != null and _background.has_method("set_slide_pool"):
		_background.call("set_slide_pool", PackedStringArray(BACKGROUND_ART))


func _word_label(text_val: String, fsz: int, col: Color, rot: float) -> Label:
	var lbl := Label.new()
	lbl.text = text_val
	lbl.rotation = rot
	lbl.add_theme_font_override("font", TITLE_FONT)
	lbl.add_theme_font_size_override("font_size", fsz)
	lbl.add_theme_color_override("font_color", col)
	lbl.add_theme_color_override("font_outline_color", UiPalette.INK)
	lbl.add_theme_color_override("font_shadow_color", Color(0.05, 0.04, 0.14, 0.65))
	lbl.add_theme_constant_override("outline_size", 14)
	lbl.add_theme_constant_override("shadow_offset_y", 7)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return lbl


func _enter() -> void:
	UiAnim.slide_in(_top_left_bar, Vector2(-28.0, -18.0), 0.28)
	UiAnim.slide_in(_top_right_bar, Vector2(28.0, -18.0), 0.28)
	UiAnim.stagger_slide([_play_button, _multi_button, _mapmaker_button,
		_garage_button], Vector2(-42.0, 0.0), 0.055, 0.30)
	UiAnim.stagger_slide(_dock_tiles, Vector2(0.0, 34.0), 0.045, 0.28)
	MenuNav.refresh()
	MenuNav.focus(_play_button)


func _on_solo_pressed() -> void:
	if Network.is_session_active():
		Network.leave()
	GameSettings.set_play_mode(GameSettings.MODE_SINGLE)
	MinigamesMenu.open_for_mode("")
	SceneLoader.go_to(MINIGAMES_SCENE, "SOLO", "")


func _on_multiplayer_pressed() -> void:
	if is_web_build():
		# Browsers cannot open raw UDP sockets for ENet, so entering the lobby
		# would dead-end in a generic join error. Say so instead (WS5-03).
		_show_web_notice("MULTIPLAYER NEEDS THE DESKTOP DOWNLOAD")
		return
	GameSettings.set_play_mode(GameSettings.MODE_MULTIPLAYER)
	SceneLoader.go_to(LOBBY_SCENE, "MULTIPLAYER", "")


func _on_mapmaker_pressed() -> void:
	## Teaser only: stays on this screen and says so, no scene change.
	open_mapmaker_teaser()


func open_mapmaker_teaser() -> Control:
	## Lazy-build the "COMING SOON :D" overlay once, then open it (confetti is
	## fired by the overlay itself, exactly one burst per open). Public so the
	## headless UI audit / WS2 checks can open the same real path the tile uses.
	if _mapmaker_teaser == null or not is_instance_valid(_mapmaker_teaser):
		if not ResourceLoader.exists(MAPMAKER_TEASER_SCENE):
			return null
		var packed: PackedScene = load(MAPMAKER_TEASER_SCENE) as PackedScene
		if packed == null:
			return null
		_mapmaker_teaser = packed.instantiate() as Control
		if _mapmaker_teaser == null:
			return null
		_mapmaker_teaser.name = "MapmakerTeaser"
		_mapmaker_teaser.closed.connect(_on_mapmaker_closed)
		add_child(_mapmaker_teaser)
	_mapmaker_teaser.call("open")
	return _mapmaker_teaser


func mapmaker_teaser_node() -> Control:
	## Stable test/audit contract: the lazily built teaser overlay (may be null).
	return _mapmaker_teaser


func hero_option_buttons() -> Array[Button]:
	## Stable test/audit contract: the four launch-rail options in display order.
	var buttons: Array[Button] = []
	buttons.append(_play_button)
	buttons.append(_multi_button)
	buttons.append(_mapmaker_button)
	buttons.append(_garage_button)
	return buttons


func _on_mapmaker_closed() -> void:
	MenuNav.refresh()
	MenuNav.focus(_mapmaker_button)


func _on_garage_pressed() -> void:
	GameSettings.vehicle_return_scene = MAIN_MENU_SCENE
	GameSettings.vehicle_return_title = "CART SLOP GP"
	GameSettings.vehicle_edit_minigame = false
	VehicleSelect.set_racing_intent(true)
	SceneLoader.go_to(VEHICLE_SCENE, "GARAGE", "")


func _on_quick_mode_pressed(mode_id: String) -> void:
	if Network.is_session_active():
		Network.leave()
	GameSettings.set_play_mode(GameSettings.MODE_SINGLE)
	if mode_id == "sandbox":
		GameSettings.set_session_config(GameSettings.MODE_SINGLE,
			GameSettings.GAME_SANDBOX, GameSettings.bots_enabled,
			GameSettings.effective_bot_count())
		SceneLoader.go_to(SANDBOX_SCENE, "SANDBOX", "")
		return
	MinigamesMenu.open_for_mode(mode_id)
	SceneLoader.go_to(MINIGAMES_SCENE, mode_id.to_upper().replace("_", " "), "")


func _on_settings_pressed() -> void:
	_settings_menu.open()


func _on_changelog_pressed() -> void:
	_changelog_panel.open()


func _on_quit_pressed() -> void:
	if is_web_build():
		# The QUIT tab is not built on web; this guard is the belt-and-braces
		# path if anything else calls it.
		_show_web_notice("CLOSE THIS TAB TO EXIT")
		return
	get_tree().quit()


func _on_update_pressed() -> void:
	if is_web_build():
		return
	_update_panel.open()


func _show_web_notice(message: String) -> void:
	## Web-only hint line above the hero rail. Soft fade out, reduced-motion aware
	## through UiAnim's own tween defaults; never a modal, so navigation keeps
	## working behind it.
	if _web_notice == null:
		return
	_web_notice.text = message
	_web_notice.visible = true
	_web_notice.modulate.a = 1.0
	if _web_notice_tween != null and _web_notice_tween.is_valid():
		_web_notice_tween.kill()
	_web_notice_tween = create_tween()
	_web_notice_tween.tween_interval(2.6)
	_web_notice_tween.tween_property(_web_notice, "modulate:a", 0.0, 0.5)
	_web_notice_tween.tween_callback(func() -> void:
		if _web_notice != null:
			_web_notice.visible = false)


func _on_modal_closed() -> void:
	MenuNav.refresh()
	MenuNav.focus(_play_button)


func _on_update_available(version: String) -> void:
	if _update_button == null:
		# Web builds never create the updater tab.
		return
	_update_button.label_text = "v%s" % version
	_update_button.tooltip_text = "Install v%s" % version
	_update_button.visible = true
	_update_button.queue_redraw()
	MenuNav.refresh()
	if not _update_auto_opened:
		_update_auto_opened = true
		_update_panel.open()
