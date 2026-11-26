extends Control
## Floating, text-only pre-game emote overlay for the multiplayer lobby (WS3).
##
## 0.8.6 rendered each lobby reaction as a slanted dark-glass bubble: a
## parallelogram plate, an ink border, a coloured glow and a sender-tinted left
## strip. The owner asked for the exact opposite: stream-chat type, zero boxy
## chrome. 0.8.7 therefore draws ONLY
##
##     bold vibrant emote text  +  a smaller sender-name line
##
## centred on a randomized point, with a dark drop shadow and a tight ink
## outline so the type stays readable over the live map preview or gameplay
## behind it. There is deliberately no background plate, no border and no left
## bar: this file owns no chrome and creates no child nodes at all.
##
## Motion: every emote spawns at a randomized position inside the overlay's safe
## margins, floats upward while a two-harmonic sine wiggle sways it and rocks it
## by a few degrees, pops in with a short scale ease and fades out smoothly over
## the last part of its life. Reduce Motion freezes the rise/sway/rock (a plain
## spawn + fade) but keeps the lifetime and the drop shadow, so the feature
## stays readable without movement.
##
## Multiplayer sync is unchanged: this node consumes the same
## `Network.lobby_reaction_received(peer_id, reaction_id, sender_name,
## color_hex)` payload the old bubble renderer did, `scripts/ui/
## lobby_reactions.gd` stays the shared catalog/rate limiter and the reliable
## host-relayed RPC block lives in `network.gd`. Nothing in this file touches
## the wire protocol or the throttles.

const LobbyReactions := preload("res://scripts/ui/lobby_reactions.gd")
const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const BUBBLE_FONT: Font = preload("res://assets/ui/fonts/Fredoka-Bold.ttf")

## Type scale. The emote is the payload; the sender name stays clearly smaller
## so a wall of overlapping emotes never loses which one is the message.
const TEXT_SIZE: int = 25
const NAME_SIZE: int = 13
const LINE_GAP: float = 5.0

## Readability over ANY background: one soft dark shadow (offset) plus one ink
## outline around both lines. Both are drawn, not boxed, so nothing reads as a
## container.
const SHADOW_OFFSET: Vector2 = Vector2(2.4, 3.4)
const SHADOW_ALPHA: float = 0.78
const TEXT_OUTLINE: int = 5
const NAME_OUTLINE: int = 4

## Safe margins: no emote may spawn (or drift) closer than this to the overlay
## edge. Horizontal is a ratio with a px floor/ceiling so it works at 720p and
## 1080p; vertical leaves room for the rise.
const SAFE_MARGIN_RATIO: float = 0.07
const SAFE_MARGIN_MIN: float = 24.0
const SAFE_MARGIN_MAX: float = 120.0
const SAFE_TOP_MIN: float = 16.0
const SAFE_TOP_RATIO: float = 0.14
const SAFE_TOP_MAX: float = 90.0
const SAFE_BOTTOM_MIN: float = 12.0
const SAFE_BOTTOM_RATIO: float = 0.09
const SAFE_BOTTOM_MAX: float = 64.0
## Emotes spawn in the lower part of the safe area so the whole rise happens
## on-screen; the bottom spawn band starts at this fraction of the safe height.
const SPAWN_BAND_START: float = 0.46

## Motion tuning (all tiny on purpose: stream-chat, not a screensaver).
const SWAY_AMP: float = 15.0 ## px, first-harmonic horizontal sway.
const SWAY_SECOND: float = 0.34 ## weight of the second harmonic.
const SWAY_HZ: float = 0.42 ## sway cycles per second.
const ROCK_RAD: float = 0.07 ## max rotation in radians (~4 degrees).
const WIGGLE_Y: float = 4.0 ## secondary vertical bob in px.
const POP_SECONDS: float = 0.18 ## scale-in time.
const POP_FROM: float = 0.82 ## scale at spawn.
const FADE_IN_SECONDS: float = 0.16
const FADE_OUT_SECONDS: float = 0.55 ## last stretch of the bubble lifetime.

var _bubbles: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()
var _fixed_seed: int = -1


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	if _fixed_seed >= 0:
		_rng.seed = _fixed_seed
	else:
		_rng.randomize()
	resized.connect(_on_resized)
	set_process(false)


func _on_resized() -> void:
	# Keep every live emote inside the new safe margins after a window resize.
	for bubble: Dictionary in _bubbles:
		var width: float = float(bubble["half_width"])
		var center: Vector2 = bubble["pos"] as Vector2
		bubble["pos"] = _clamp_center(center, width)

func push(peer_id: int, reaction_id: String, sender_name: String,
		color_hex: String) -> bool:
	## Add one incoming/local reaction. Invalid ids are dropped here (the
	## network layer already sanitises them); returns false when nothing spawned.
	var entry: Dictionary = LobbyReactions.find(reaction_id)
	if entry.is_empty():
		return false
	var accent: Color = Color(str(entry.get("accent", "ffffff")))
	var sender_color: Color = UiPalette.CYAN
	var hex: String = str(color_hex).strip_edges()
	if hex.length() == 6 and Color.html_is_valid(hex):
		sender_color = Color(hex)
	var label: String = str(entry.get("label", "!"))
	var name_text: String = _display_name(sender_name)
	var half_width: float = maxf(
		BUBBLE_FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1,
			TEXT_SIZE).x,
		BUBBLE_FONT.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			NAME_SIZE).x) * 0.5
	var safe: Rect2 = safe_rect()
	var pos: Vector2 = _random_spawn(safe, half_width)
	_bubbles.append({
		"label": label,
		"name": name_text,
		"accent": _readable(accent),
		"name_color": _readable(sender_color).lightened(0.22),
		"age": 0.0,
		"life": LobbyReactions.BUBBLE_LIFETIME,
		"spawn": pos,
		"pos": pos,
		"half_width": half_width,
		"phase": _rng.randf_range(0.0, TAU),
		"phase2": _rng.randf_range(0.0, TAU),
		"rock_dir": -1.0 if _rng.randf() < 0.5 else 1.0,
		"peer": peer_id,
	})
	while _bubbles.size() > LobbyReactions.MAX_BUBBLES:
		_bubbles.remove_at(0)
	set_process(true)
	queue_redraw()
	return true


func clear() -> void:
	_bubbles.clear()
	set_process(false)
	queue_redraw()


func bubble_count() -> int:
	return _bubbles.size()


func _process(delta: float) -> void:
	if _bubbles.is_empty():
		set_process(false)
		return
	var reduced: bool = is_reduce_motion()
	var index: int = _bubbles.size() - 1
	while index >= 0:
		var bubble: Dictionary = _bubbles[index]
		var age: float = float(bubble["age"]) + delta
		bubble["age"] = age
		if age >= float(bubble["life"]):
			_bubbles.remove_at(index)
			index -= 1
			continue
		bubble["pos"] = _current_center(bubble, reduced)
		index -= 1
	queue_redraw()


func _current_center(bubble: Dictionary, reduced: bool) -> Vector2:
	var spawn: Vector2 = bubble["spawn"] as Vector2
	var half_width: float = float(bubble["half_width"])
	if reduced:
		return _clamp_center(spawn, half_width)
	var age: float = float(bubble["age"])
	var phase: float = float(bubble["phase"])
	# Shared with lobby_reactions.BUBBLE_RISE so the travel distance and the
	# lifetime stay one contract with the catalog/rate-limiter module.
	var rise_t: float = clampf(age / maxf(float(bubble["life"]), 0.01), 0.0, 1.0)
	var rise: float = LobbyReactions.BUBBLE_RISE * rise_t
	var sway: float = sin(age * SWAY_HZ * TAU + phase) \
		+ SWAY_SECOND * sin(age * SWAY_HZ * TAU * 2.3 + float(bubble["phase2"]))
	var bob: float = sin(age * 1.15 + float(bubble["phase2"])) * WIGGLE_Y
	var center: Vector2 = spawn + Vector2(sway * SWAY_AMP * 0.5, -rise + bob)
	return _clamp_center(center, half_width)


func _clamp_center(center: Vector2, half_width: float) -> Vector2:
	var safe: Rect2 = safe_rect()
	var half_height: float = _half_height()
	var lo: float = safe.position.x + half_width
	var hi: float = safe.end.x - half_width
	if hi < lo:
		lo = safe.get_center().x
		hi = lo
	var out := Vector2(clampf(center.x, lo, hi), center.y)
	var top_limit: float = safe.position.y + half_height
	var bottom_limit: float = maxf(safe.end.y - half_height, top_limit)
	out.y = clampf(out.y, top_limit, bottom_limit)
	return out


func _random_spawn(safe: Rect2, half_width: float) -> Vector2:
	var half_height: float = _half_height()
	var lo: float = safe.position.x + half_width
	var hi: float = safe.end.x - half_width
	if hi <= lo:
		lo = safe.get_center().x
		hi = lo
	var band_top: float = maxf(
		safe.position.y + safe.size.y * SPAWN_BAND_START,
		safe.position.y + half_height)
	var band_bottom: float = maxf(safe.end.y - half_height, band_top)
	return Vector2(_rng.randf_range(lo, hi),
		_rng.randf_range(band_top, band_bottom))


func _half_height() -> float:
	## Half the drawn type block (plus a little descender slack) so spawning and
	## clamping keep the WHOLE text inside the safe margins, not just its centre.
	return (float(TEXT_SIZE) + LINE_GAP + float(NAME_SIZE)) * 0.5 + 3.0


func safe_rect() -> Rect2:
	## Safe margin box in local coordinates. The audit harness asserts every
	## emote spawns/drifts inside this rect.
	var w: float = maxf(size.x, 1.0)
	var h: float = maxf(size.y, 1.0)
	var margin_x: float = clampf(w * SAFE_MARGIN_RATIO, SAFE_MARGIN_MIN,
		SAFE_MARGIN_MAX)
	var margin_top: float = clampf(h * SAFE_TOP_RATIO + h * 0.02, SAFE_TOP_MIN,
		SAFE_TOP_MAX)
	var margin_bottom: float = clampf(h * SAFE_BOTTOM_RATIO, SAFE_BOTTOM_MIN,
		SAFE_BOTTOM_MAX)
	return Rect2(margin_x, margin_top, maxf(w - margin_x * 2.0, 1.0),
		maxf(h - margin_top - margin_bottom, 1.0))


func is_reduce_motion() -> bool:
	var settings: Node = get_node_or_null("/root/GameSettings")
	return settings != null and bool(settings.get("reduce_motion"))


func set_spawn_seed(seed_value: int) -> void:
	## Test hook: make randomized spawn points deterministic for assertions.
	_fixed_seed = seed_value
	_rng.seed = seed_value


func _display_name(raw_name: String) -> String:
	var clean: String = raw_name.strip_edges()
	if clean.length() > 18:
		clean = clean.substr(0, 18)
	return clean


func _readable(color: Color) -> Color:
	## Keep the catalog's vibrant hue but guarantee it survives a bright map
	## preview behind it; the ink outline covers the rest.
	var luminance: float = color.get_luminance()
	if luminance < 0.32:
		return color.lightened(0.30)
	if luminance > 0.90:
		return color.darkened(0.06)
	return color


# --------------------------------------------------------------------------
# debug / audit API (headless assertions; no gameplay code calls these)
# --------------------------------------------------------------------------


func debug_bubbles() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	var half_height: float = _half_height()
	for bubble: Dictionary in _bubbles:
		var pos: Vector2 = bubble["pos"] as Vector2
		var half_width: float = float(bubble["half_width"])
		out.append({
			"label": str(bubble["label"]),
			"name": str(bubble["name"]),
			"age": float(bubble["age"]),
			"pos": pos,
			"rect": Rect2(pos - Vector2(half_width, half_height),
				Vector2(half_width * 2.0, half_height * 2.0)),
			"peer": int(bubble["peer"]),
		})
	return out


func debug_rects() -> Array[Rect2]:
	var rects: Array[Rect2] = []
	for entry: Dictionary in debug_bubbles():
		rects.append(entry["rect"] as Rect2)
	return rects


# --------------------------------------------------------------------------
# drawing: type only, no chrome
# --------------------------------------------------------------------------


func _draw() -> void:
	var area: Vector2 = size
	if area.x < 40.0 or area.y < 40.0:
		return
	var reduced: bool = is_reduce_motion()
	for bubble: Dictionary in _bubbles:
		_draw_bubble(bubble, reduced)


func _draw_bubble(bubble: Dictionary, reduced: bool) -> void:
	var age: float = float(bubble["age"])
	var life: float = maxf(float(bubble["life"]), 0.01)
	var fade_in: float = clampf(age / FADE_IN_SECONDS, 0.0, 1.0)
	var fade_out: float = clampf((life - age) / FADE_OUT_SECONDS, 0.0, 1.0)
	var alpha: float = minf(fade_in, fade_out)
	if alpha <= 0.01:
		return
	var scale: float = 1.0
	if not reduced and age < POP_SECONDS:
		var pop_t: float = clampf(age / POP_SECONDS, 0.0, 1.0)
		# Ease-out-back pop: overshoots ~4% then settles at 1.0.
		var back: float = 1.0 - pow(1.0 - pop_t, 3.0)
		scale = lerpf(POP_FROM, 1.0 + 0.04 * sin(pop_t * PI), back)
	var rotation: float = 0.0
	if not reduced:
		rotation = sin(age * 0.85 + float(bubble["phase"])) * ROCK_RAD \
			* float(bubble["rock_dir"])
	var center: Vector2 = bubble["pos"] as Vector2
	var text_color: Color = bubble["accent"] as Color
	var name_color: Color = bubble["name_color"] as Color
	var label: String = str(bubble["label"])
	var name_text: String = str(bubble["name"])
	var line_h: float = float(TEXT_SIZE) + LINE_GAP + float(NAME_SIZE)
	var top: float = -line_h * 0.5
	var label_width: float = maxf(
		BUBBLE_FONT.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1,
			TEXT_SIZE).x, 1.0)
	var name_width: float = maxf(
		BUBBLE_FONT.get_string_size(name_text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			NAME_SIZE).x, 1.0)
	draw_set_transform(center, rotation, Vector2(scale, scale))
	var shadow := Color(0.02, 0.03, 0.09, SHADOW_ALPHA * alpha * 0.60)
	if name_text != "":
		var name_pos := Vector2(-name_width * 0.5 + SHADOW_OFFSET.x,
			top + float(NAME_SIZE) + SHADOW_OFFSET.y)
		draw_string(BUBBLE_FONT, name_pos, name_text,
			HORIZONTAL_ALIGNMENT_LEFT, -1, NAME_SIZE, shadow)
		var name_outline := Color(UiPalette.OUTLINE.r, UiPalette.OUTLINE.g,
			UiPalette.OUTLINE.b, alpha * 0.85)
		var name_fill := Color(name_color.r, name_color.g, name_color.b, alpha * 0.92)
		draw_string_outline(BUBBLE_FONT, Vector2(-name_width * 0.5,
			top + float(NAME_SIZE)), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			NAME_SIZE, NAME_OUTLINE, name_outline)
		draw_string(BUBBLE_FONT, Vector2(-name_width * 0.5,
			top + float(NAME_SIZE)), name_text, HORIZONTAL_ALIGNMENT_LEFT, -1,
			NAME_SIZE, name_fill)
	var label_baseline: float = line_h * 0.5 - 1.0
	var label_pos := Vector2(-label_width * 0.5, label_baseline)
	draw_string(BUBBLE_FONT, label_pos + SHADOW_OFFSET, label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE, shadow)
	var label_outline := Color(UiPalette.OUTLINE.r, UiPalette.OUTLINE.g,
		UiPalette.OUTLINE.b, alpha * 0.95)
	var label_fill := Color(text_color.r, text_color.g, text_color.b, alpha)
	draw_string_outline(BUBBLE_FONT, label_pos, label,
		HORIZONTAL_ALIGNMENT_LEFT, -1, TEXT_SIZE, TEXT_OUTLINE, label_outline)
	draw_string(BUBBLE_FONT, label_pos, label, HORIZONTAL_ALIGNMENT_LEFT, -1,
		TEXT_SIZE, label_fill)
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
