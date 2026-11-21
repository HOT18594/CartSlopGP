extends Control
## Clean Slanted Parallelogram Bottom-Center Action & Controls Dock for party
## minigames (Knockout, Blast Tag, Deliver).
## - Shows an unmistakable [E] keycap + thick slanted recharge bar + live state
## - Optionally shows YOUR Damage % (Knockout only — zero clutter from other players!)
## - Crisp minimal single-line controls strip beneath.

const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const TITLE_FONT: Font = preload("res://assets/ui/fonts/LuckiestGuy-Regular.ttf")
const BODY_FONT: Font = preload("res://assets/ui/fonts/Fredoka-Bold.ttf")

var show_damage: bool = false
var damage_text: String = "0%"
var damage_color: Color = Color("f8f7f2")

var show_ability: bool = true
var key_text: String = "E"
var ability_title: String = "SLAM READY"
var ability_sub: String = ""
var ability_ratio: float = 1.0
var ability_color: Color = Color("ffd22e")
var controls_hint: String = "WASD DRIVE  ·  SPACE DRIFT  ·  SHIFT BOOST  ·  E SLAM"


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	anchor_left = 0.5
	anchor_right = 0.5
	anchor_top = 1.0
	anchor_bottom = 1.0
	offset_left = -225.0
	offset_right = 225.0
	offset_top = -102.0
	offset_bottom = -12.0


func _para(x0: float, y0: float, w: float, h: float, sk: float) -> PackedVector2Array:
	return PackedVector2Array([
		Vector2(x0 + sk, y0),
		Vector2(x0 + sk + w, y0),
		Vector2(x0 + w, y0 + h),
		Vector2(x0, y0 + h),
	])


func _closed(pts: PackedVector2Array) -> PackedVector2Array:
	var out := pts.duplicate()
	if not out.is_empty():
		out.append(out[0])
	return out


func _draw() -> void:
	var w: float = size.x
	var h: float = size.y
	if w < 120.0 or h < 48.0:
		return

	var sk: float = 11.0
	var card_h: float = 64.0
	var y0: float = 2.0
	var gap: float = 10.0

	var dmg_w: float = 136.0 if show_damage else 0.0
	var ab_w: float = 266.0 if show_ability else 0.0
	var total_w: float = dmg_w + ab_w + (gap if (show_damage and show_ability) else 0.0)
	var cur_x: float = (w - total_w - sk) * 0.5

	# 1. Optional YOUR DAMAGE % Slanted Card (Knockout)
	if show_damage:
		var pts: PackedVector2Array = _para(cur_x, y0, dmg_w, card_h, sk)
		var sh := PackedVector2Array([
			pts[0] + Vector2(3.0, 4.0), pts[1] + Vector2(3.0, 4.0),
			pts[2] + Vector2(3.0, 4.0), pts[3] + Vector2(3.0, 4.0),
		])
		draw_colored_polygon(sh, Color(0.02, 0.02, 0.08, 0.65))
		draw_colored_polygon(pts, Color(0.07, 0.08, 0.17, 0.92))
		draw_polyline(_closed(pts), UiPalette.INK, 3.2, true)
		# Small "DAMAGE" caption + big bold percentage
		draw_string(BODY_FONT, Vector2(cur_x + sk * 0.6, y0 + 18.0), "DAMAGE",
			HORIZONTAL_ALIGNMENT_CENTER, dmg_w, 12, Color(0.76, 0.80, 0.92, 0.88))
		var dfsz: int = 34
		draw_string(TITLE_FONT, Vector2(cur_x + sk * 0.35, y0 + 54.0 + 2.0), damage_text,
			HORIZONTAL_ALIGNMENT_CENTER, dmg_w, dfsz, Color(0.02, 0.02, 0.08, 0.92))
		draw_string(TITLE_FONT, Vector2(cur_x + sk * 0.35, y0 + 54.0), damage_text,
			HORIZONTAL_ALIGNMENT_CENTER, dmg_w, dfsz, damage_color)
		cur_x += dmg_w + gap

	# 2. Primary [E] Ability Recharge / Mode Status Slanted Card
	if show_ability:
		var pts: PackedVector2Array = _para(cur_x, y0, ab_w, card_h, sk)
		var sh := PackedVector2Array([
			pts[0] + Vector2(3.0, 4.0), pts[1] + Vector2(3.0, 4.0),
			pts[2] + Vector2(3.0, 4.0), pts[3] + Vector2(3.0, 4.0),
		])
		var ready: bool = ability_ratio >= 0.995
		draw_colored_polygon(sh, Color(0.02, 0.02, 0.08, 0.65))
		draw_colored_polygon(pts, Color(0.07, 0.08, 0.17, 0.92))
		draw_polyline(_closed(pts), ability_color if ready else UiPalette.INK, 3.2, true)

		var content_x: float = cur_x + sk + 10.0
		var content_w: float = ab_w - 22.0

		# Big unmistakable [E] Keycap badge on left (when key_text is non-empty)
		if not key_text.is_empty():
			var kw: float = 42.0
			var kh: float = 42.0
			var ky: float = y0 + (card_h - kh) * 0.5
			var kpts: PackedVector2Array = _para(cur_x + sk * 0.5 + 8.0, ky, kw, kh, 6.0)
			var kfill: Color = ability_color if ready else Color(0.18, 0.21, 0.34, 0.96)
			draw_colored_polygon(kpts, kfill)
			draw_polyline(_closed(kpts), UiPalette.INK, 2.8, true)
			var kcol: Color = UiPalette.INK if ready else Color(0.82, 0.86, 0.95, 0.92)
			draw_string(TITLE_FONT, Vector2(cur_x + sk * 0.5 + 11.0, ky + 32.0), key_text,
				HORIZONTAL_ALIGNMENT_CENTER, kw, 25, kcol)
			content_x = cur_x + sk * 0.5 + kw + 22.0
			content_w = ab_w - kw - 34.0

		# Title line ("SLAM READY!" / "RECHARGING 2.1S" / "PASS THE BOMB!")
		var tcol: Color = ability_color if ready else UiPalette.CREAM
		var tfsz: int = 19
		while tfsz > 13 and TITLE_FONT.get_string_size(ability_title, HORIZONTAL_ALIGNMENT_LEFT, -1, tfsz).x > content_w:
			tfsz -= 1
		draw_string(TITLE_FONT, Vector2(content_x, y0 + 27.0 + 1.5), ability_title,
			HORIZONTAL_ALIGNMENT_LEFT, content_w, tfsz, Color(0.02, 0.02, 0.08, 0.85))
		draw_string(TITLE_FONT, Vector2(content_x, y0 + 27.0), ability_title,
			HORIZONTAL_ALIGNMENT_LEFT, content_w, tfsz, tcol)

		# Thick slanted recharge progress bar (or secondary status line)
		if ability_ratio >= 0.0:
			var bar_y: float = y0 + 36.0
			var bar_h: float = 17.0
			var bar_sk: float = 5.0
			var bar_w: float = maxf(content_w - bar_sk, 40.0)
			var bg_pts: PackedVector2Array = _para(content_x - 3.0, bar_y, bar_w, bar_h, bar_sk)
			draw_colored_polygon(bg_pts, Color(0.14, 0.16, 0.28, 0.95))
			var fill_r: float = clampf(ability_ratio, 0.0, 1.0)
			if fill_r > 0.01:
				var fw: float = maxf(bar_w * fill_r, 4.0)
				var fpts: PackedVector2Array = _para(content_x - 3.0, bar_y, fw, bar_h, bar_sk)
				var fcol: Color = ability_color if ready else Color("38d6f0")
				draw_colored_polygon(fpts, fcol)
			draw_polyline(_closed(bg_pts), UiPalette.INK, 2.2, true)
		elif not ability_sub.is_empty():
			draw_string(BODY_FONT, Vector2(content_x, y0 + 50.0), ability_sub,
				HORIZONTAL_ALIGNMENT_LEFT, content_w, 14, Color(0.84, 0.88, 0.96, 0.92))

	# 3. Crisp single-line controls hint beneath the dock
	if not controls_hint.is_empty():
		var hint_y: float = y0 + card_h + 18.0
		draw_string(BODY_FONT, Vector2(0.0, hint_y + 1.5), controls_hint,
			HORIZONTAL_ALIGNMENT_CENTER, w, 13, Color(0.02, 0.02, 0.08, 0.88))
		draw_string(BODY_FONT, Vector2(0.0, hint_y), controls_hint,
			HORIZONTAL_ALIGNMENT_CENTER, w, 13, Color(0.92, 0.94, 0.98, 0.84))
