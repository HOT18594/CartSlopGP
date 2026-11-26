extends RefCounted
## One place for every menu motion value and tween. Before this existed each
## screen invented its own durations and easing, so panels snapped while
## buttons bounced. Everything here is frame-rate independent and keeps running
## while the tree is paused (the pause menu is animated too).
##
## The `draw_*` helpers at the bottom are the soft-gradient primitives for
## custom `_draw()` UI: sheen sweeps, gloss fades, focus glows and comic
## shadows. They replace the flat-alpha polygons/polylines that used to end on a
## visible clipped edge mid-animation.

const FADE: float = 0.20
const POP: float = 0.20
const SLIDE: float = 0.28
const PULSE: float = 0.16

const TRANS_SLIDE: int = Tween.TRANS_CUBIC
const TRANS_POP: int = Tween.TRANS_BACK


static func _tracked(target: Node, key: String) -> Tween:
	## A new animation on the same node kills the old one instead of fighting it.
	var previous: Variant = null
	if target.has_meta(key):
		previous = target.get_meta(key)
	if previous is Tween and (previous as Tween).is_valid():
		(previous as Tween).kill()
	var tween: Tween = target.create_tween()
	tween.set_pause_mode(Tween.TWEEN_PAUSE_PROCESS)
	target.set_meta(key, tween)
	return tween


static func fade_in(item: CanvasItem, duration: float = FADE, delay: float = 0.0) -> Tween:
	if not is_instance_valid(item):
		return null
	item.modulate.a = 0.0
	var tween: Tween = _tracked(item, "ui_anim_main")
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_property(item, "modulate:a", 1.0, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	return tween


static func fade_out(item: CanvasItem, duration: float = FADE, delay: float = 0.0) -> Tween:
	if not is_instance_valid(item):
		return null
	var tween: Tween = _tracked(item, "ui_anim_main")
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.tween_property(item, "modulate:a", 0.0, duration) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN)
	return tween


static func pop(item: Control, duration: float = POP, delay: float = 0.0) -> Tween:
	## Scale-and-fade entrance. Used when a panel or a screen first appears.
	if not is_instance_valid(item):
		return null
	item.pivot_offset = item.size * 0.5
	item.scale = Vector2.ONE * 0.94
	item.modulate.a = 0.0
	var tween: Tween = _tracked(item, "ui_anim_main")
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.set_parallel(true)
	tween.tween_property(item, "scale", Vector2.ONE, duration) \
		.set_trans(TRANS_POP).set_ease(Tween.EASE_OUT)
	tween.tween_property(item, "modulate:a", 1.0, duration * 0.65) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	return tween


static func slide_in(item: Control, offset: Vector2, duration: float = SLIDE,
		delay: float = 0.0) -> Tween:
	## Remembers the layout position so containers can resize underneath it.
	if not is_instance_valid(item):
		return null
	var origin: Variant = null
	if item.has_meta("ui_anim_origin"):
		origin = item.get_meta("ui_anim_origin")
	if not (origin is Vector2):
		origin = item.position
		item.set_meta("ui_anim_origin", origin)
	item.position = (origin as Vector2) + offset
	item.modulate.a = 0.0
	var tween: Tween = _tracked(item, "ui_anim_main")
	if delay > 0.0:
		tween.tween_interval(delay)
	tween.set_parallel(true)
	tween.tween_property(item, "position", origin, duration) \
		.set_trans(TRANS_SLIDE).set_ease(Tween.EASE_OUT)
	tween.tween_property(item, "modulate:a", 1.0, duration * 0.72) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	return tween


static func pulse(item: CanvasItem, amount: float = 0.06,
		duration: float = PULSE) -> Tween:
	## Small bump on selection. Never leaves the item scaled.
	if not is_instance_valid(item):
		return null
	var base: Vector2 = item.scale
	var tween: Tween = _tracked(item, "ui_anim_pulse")
	tween.tween_property(item, "scale", base * (1.0 + amount), duration * 0.4) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
	tween.tween_property(item, "scale", base, duration * 0.6) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	return tween


static func shake(item: Control, strength: float = 7.0, duration: float = 0.30) -> void:
	## Rejection feedback for an invalid action (bad room code, offline server).
	if not is_instance_valid(item):
		return
	var parent: Node = item.get_parent()
	if parent is Container:
		# Containers own their children's position (and reset it on every
		# layout), so tweening position here was a no-op. Rotation is not
		# managed by a Container and gives the row a visible wobble.
		item.pivot_offset = item.size * 0.5
		var base_rotation: float = item.rotation
		if item.has_meta("ui_anim_base_rotation"):
			base_rotation = float(item.get_meta("ui_anim_base_rotation"))
		else:
			item.set_meta("ui_anim_base_rotation", base_rotation)
		var angle: float = deg_to_rad(clampf(strength * 0.12, 0.2, 1.2))
		var wobble: Tween = _tracked(item, "ui_anim_shake")
		var steps: int = 6
		for step in steps:
			var fade: float = 1.0 - float(step) / float(steps)
			var direction: float = -1.0 if step % 2 == 0 else 1.0
			wobble.tween_property(item, "rotation",
				base_rotation + angle * fade * direction, duration / float(steps))
		wobble.tween_property(item, "rotation", base_rotation, duration / float(steps))
		wobble.tween_callback(func() -> void:
			if is_instance_valid(item):
				item.remove_meta("ui_anim_base_rotation"))
		return
	var origin: Variant = null
	if item.has_meta("ui_anim_origin"):
		origin = item.get_meta("ui_anim_origin")
	if not (origin is Vector2):
		origin = item.position
		item.set_meta("ui_anim_origin", origin)
	var base: Vector2 = origin as Vector2
	var tween: Tween = _tracked(item, "ui_anim_shake")
	var steps: int = 6
	for step in steps:
		var fade: float = 1.0 - float(step) / float(steps)
		var offset: Vector2 = Vector2(strength * fade * (-1.0 if step % 2 == 0 else 1.0), 0.0)
		tween.tween_property(item, "position", base + offset, duration / float(steps))
	tween.tween_property(item, "position", base, duration / float(steps))


static func _reduce_motion() -> bool:
	var loop: MainLoop = Engine.get_main_loop()
	if loop is SceneTree:
		var gs: Node = (loop as SceneTree).root.get_node_or_null("GameSettings")
		if gs != null:
			return bool(gs.get("reduce_motion"))
	return false


static func stagger_slide(items: Array, offset: Vector2 = Vector2(-28.0, 0.0),
		step: float = 0.045, duration: float = 0.28) -> void:
	## Cascading slide-and-fade entrance for navigation rails, grids, and rows.
	## Container children cannot have their position animated reliably, so we
	## animate scale + modulate + pivot smoothly for container items and use
	## position slide for free Controls.
	var reduced: bool = _reduce_motion()
	var idx: int = 0
	for raw: Variant in items:
		if not (raw is Control):
			continue
		var item := raw as Control
		if not is_instance_valid(item) or not item.visible:
			continue
		var delay: float = 0.0 if reduced else float(idx) * step
		idx += 1
		if reduced:
			fade_in(item, 0.12, 0.0)
			continue
		var parent: Node = item.get_parent()
		if parent is Container:
			item.pivot_offset = item.size * 0.5
			item.scale = Vector2(0.93, 0.93)
			item.modulate.a = 0.0
			var tw: Tween = _tracked(item, "ui_anim_main")
			if delay > 0.0:
				tw.tween_interval(delay)
			tw.set_parallel(true)
			tw.tween_property(item, "scale", Vector2.ONE, duration) \
				.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
			tw.tween_property(item, "modulate:a", 1.0, duration * 0.7) \
				.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)
		else:
			slide_in(item, offset, duration, delay)


static func modal_open(panel: Control, dim: CanvasItem = null,
		duration: float = 0.24) -> void:
	## Crisp racing-sim modal pop + fade-in backdrop.
	if is_instance_valid(dim):
		fade_in(dim, duration * 0.85)
	if not is_instance_valid(panel):
		return
	if _reduce_motion():
		fade_in(panel, 0.12)
		return
	panel.pivot_offset = panel.size * 0.5
	panel.scale = Vector2(0.92, 0.92)
	panel.modulate.a = 0.0
	var tw: Tween = _tracked(panel, "ui_anim_main")
	tw.set_parallel(true)
	tw.tween_property(panel, "scale", Vector2.ONE, duration) \
		.set_trans(Tween.TRANS_BACK).set_ease(Tween.EASE_OUT)
	tw.tween_property(panel, "modulate:a", 1.0, duration * 0.65) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


static func damp(current: float, target: float, delta: float, speed: float = 12.0) -> float:
	## Exponential smoothing that behaves the same at 30 and 240 FPS.
	return lerpf(current, target, 1.0 - exp(-speed * delta))


static func damp_color(current: Color, target: Color, delta: float,
		speed: float = 12.0) -> Color:
	return current.lerp(target, 1.0 - exp(-speed * delta))


# --------------------------------------------------------------------------
# Soft gradient drawing primitives.
#
# The old sheen sweeps were flat-alpha polygons (and the focus halos were two
# hard polylines), so every animation ended on a visible straight edge. These
# helpers draw the same shapes as vertex-colour gradients: alpha ramps to a
# peak in the middle and fades to zero at both edges, which reads as a moving
# band of light instead of a clipped rectangle. They are pure `_draw` calls and
# cost the same number of primitives as the hard-edged versions.


static func draw_soft_band(canvas: CanvasItem, quad: PackedVector2Array,
		tint: Color = Color(1.0, 1.0, 1.0), peak_alpha: float = 0.24,
		pad: float = 0.0) -> void:
	## One slanted sheen band with a smooth left/right falloff. `quad` is a
	## 4-point parallelogram ordered TL, TR, BR, BL; `pad` insets it vertically.
	if canvas == null or not is_instance_valid(canvas) or quad.size() < 4:
		return
	if peak_alpha <= 0.001:
		return
	var tl: Vector2 = quad[0]
	var tr: Vector2 = quad[1]
	var br: Vector2 = quad[2]
	var bl: Vector2 = quad[3]
	if pad > 0.0:
		var inset := Vector2(0.0, pad)
		tl += inset
		tr += inset
		br -= inset
		bl -= inset
	var mid_top: Vector2 = tl.lerp(tr, 0.5)
	var mid_bottom: Vector2 = bl.lerp(br, 0.5)
	var clear := Color(tint.r, tint.g, tint.b, 0.0)
	var peak := Color(tint.r, tint.g, tint.b, peak_alpha)
	canvas.draw_polygon(PackedVector2Array([tl, mid_top, mid_bottom, bl]),
		PackedColorArray([clear, peak, peak, clear]))
	canvas.draw_polygon(PackedVector2Array([mid_top, tr, br, mid_bottom]),
		PackedColorArray([peak, clear, clear, peak]))


static func draw_vertical_fade(canvas: CanvasItem, quad: PackedVector2Array,
		tint: Color = Color(1.0, 1.0, 1.0), top_alpha: float = 0.22) -> void:
	## Flat-fill replacement for gloss/lip bands: opaque at the top edge, fully
	## transparent at the bottom edge, so the band melts into the plate instead
	## of ending on a hard horizontal line.
	if canvas == null or not is_instance_valid(canvas) or quad.size() < 4:
		return
	if top_alpha <= 0.001:
		return
	var clear := Color(tint.r, tint.g, tint.b, 0.0)
	var top := Color(tint.r, tint.g, tint.b, top_alpha)
	canvas.draw_polygon(quad, PackedColorArray([top, top, clear, clear]))


static func draw_soft_outline(canvas: CanvasItem, closed_pts: PackedVector2Array,
		core_color: Color, core_width: float = 3.4, glow_color: Color = Color.WHITE,
		glow_layers: int = 4, glow_step: float = 2.4, glow_alpha: float = 0.16) -> void:
	## Focus halo as an outward-fading glow: a bright core line plus concentric
	## wider, dimmer passes. No hard polyline ends the halo at full opacity.
	if canvas == null or not is_instance_valid(canvas) or closed_pts.size() < 2:
		return
	for layer in range(glow_layers, 0, -1):
		var width: float = core_width + glow_step * float(layer)
		var alpha: float = glow_alpha / float(layer)
		canvas.draw_polyline(closed_pts,
			Color(glow_color.r, glow_color.g, glow_color.b, alpha * 0.85),
			width, true)
	canvas.draw_polyline(closed_pts, core_color, core_width, true)


static func draw_soft_shadow(canvas: CanvasItem, closed_pts: PackedVector2Array,
		shadow_color: Color = Color(0.03, 0.03, 0.10, 0.55), layers: int = 3,
		step: float = 2.6) -> void:
	## Comic drop shadow with a soft falloff instead of one flat silhouette.
	if canvas == null or not is_instance_valid(canvas) or closed_pts.size() < 2:
		return
	for layer in range(layers, 0, -1):
		var width: float = step * float(layer)
		var alpha: float = shadow_color.a / float(layer + 1)
		canvas.draw_polyline(closed_pts,
			Color(shadow_color.r, shadow_color.g, shadow_color.b, alpha),
			width, true)
