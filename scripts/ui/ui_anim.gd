extends RefCounted
## One place for every menu motion value and tween. Before this existed each
## screen invented its own durations and easing, so panels snapped while
## buttons bounced. Everything here is frame-rate independent and keeps running
## while the tree is paused (the pause menu is animated too).

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


static func damp(current: float, target: float, delta: float, speed: float = 12.0) -> float:
	## Exponential smoothing that behaves the same at 30 and 240 FPS.
	return lerpf(current, target, 1.0 - exp(-speed * delta))


static func damp_color(current: Color, target: Color, delta: float,
		speed: float = 12.0) -> Color:
	return current.lerp(target, 1.0 - exp(-speed * delta))
