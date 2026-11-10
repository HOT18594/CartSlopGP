extends RefCounted
## Shared vector shopping-cart artwork for menus, loading screens and the icon.
##
## The cart is drawn in a three-quarter side view: a sloped wire basket, a
## proper red handle, a child-seat flap and two pairs of casters. Everything is
## built from CanvasItem primitives so it stays sharp at any size.

const INK := Color("1e1b3a")
const METAL := Color("eef1f8")
const METAL_SIDE := Color("cbd2e2")
const METAL_FAR := Color("a8b0c6")
const METAL_HILIGHT := Color("ffffff")
const RED := Color("dd3b41")
const RED_DARK := Color("a9242b")
const HUB := Color("737b93")


static func draw_cart(ci: CanvasItem, origin: Vector2, scale: float, flip: bool = false) -> void:
	var f: float = -1.0 if flip else 1.0
	var ink_w: float = maxf(1.5, 3.0 * scale)
	var thin_w: float = maxf(1.0, 1.7 * scale)

	# Ground shadow.
	ci.draw_set_transform(origin + Vector2(0.0, 2.0 * scale), 0.0,
		Vector2(1.0, 0.30))
	ci.draw_circle(Vector2.ZERO, 88.0 * scale, Color(0.12, 0.09, 0.20, 0.16))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# Far side of the basket, then the top opening. These sit behind the grid.
	var far := _poly(origin, scale, f, [
		Vector2(-70, -150), Vector2(72, -116),
		Vector2(66, -64), Vector2(-62, -82),
	])
	ci.draw_colored_polygon(far, METAL_FAR)
	var opening := _poly(origin, scale, f, [
		Vector2(-78, -142), Vector2(74, -110),
		Vector2(72, -118), Vector2(-70, -150),
	])
	ci.draw_colored_polygon(opening, Color(0.16, 0.15, 0.29, 0.92))

	# Near side panel.
	var side := _poly(origin, scale, f, [
		Vector2(-78, -140), Vector2(74, -108),
		Vector2(68, -58), Vector2(-70, -72),
	])
	ci.draw_colored_polygon(side, METAL)
	ci.draw_polyline(_closed(side), INK, ink_w, true)

	# The thin front lip makes the basket read as a box, not a flat sticker.
	var front_lip := _poly(origin, scale, f, [
		Vector2(74, -108), Vector2(82, -105),
		Vector2(76, -55), Vector2(68, -58),
	])
	ci.draw_colored_polygon(front_lip, METAL_SIDE)
	ci.draw_polyline(_closed(front_lip), INK, ink_w, true)

	# Wire grid on the near side.
	for step in range(1, 6):
		var t: float = float(step) / 6.0
		var top: Vector2 = _pt(origin, scale, f,
			lerpf(-78.0, 74.0, t), lerpf(-140.0, -108.0, t))
		var bottom: Vector2 = _pt(origin, scale, f,
			lerpf(-70.0, 68.0, t), lerpf(-72.0, -58.0, t))
		ci.draw_line(top, bottom, INK, thin_w, true)
	for step in range(1, 4):
		var t2: float = float(step) / 4.0
		var left: Vector2 = _pt(origin, scale, f,
			lerpf(-78.0, 74.0, t2), lerpf(-140.0, -108.0, t2))
		var right: Vector2 = _pt(origin, scale, f,
			lerpf(-70.0, 68.0, t2), lerpf(-72.0, -58.0, t2))
		ci.draw_line(left, right, INK, thin_w, true)

	# Frosted highlight along the top rail.
	ci.draw_line(_pt(origin, scale, f, -74.0, -136.0),
		_pt(origin, scale, f, 66.0, -106.0), Color(1, 1, 1, 0.55),
		maxf(1.5, 2.6 * scale), true)
	# Lower rack between the legs.
	ci.draw_line(_pt(origin, scale, f, -50.0, -34.0),
		_pt(origin, scale, f, 55.0, -28.0), INK, maxf(2.0, 4.0 * scale), true)
	ci.draw_line(_pt(origin, scale, f, -50.0, -34.0),
		_pt(origin, scale, f, 55.0, -28.0), METAL_SIDE, maxf(1.0, 1.8 * scale), true)

	# Child-seat flap at the back, in the same red as the handle.
	var flap := _poly(origin, scale, f, [
		Vector2(-70, -138), Vector2(-47, -131),
		Vector2(-51, -115), Vector2(-71, -122),
	])
	ci.draw_colored_polygon(flap, RED)
	ci.draw_polyline(_closed(flap), INK, ink_w, true)

	# Handle: two short supports and a chunky red grip. A single long red
	# stroke used to look like a flag stuck to the side of the basket.
	var supports: Array[Vector4] = [
		Vector4(-78.0, -140.0, -96.0, -159.0),
		Vector4(-68.0, -134.0, -82.0, -153.0),
	]
	for support: Vector4 in supports:
		var support_a: Vector2 = _pt(origin, scale, f, support.x, support.y)
		var support_b: Vector2 = _pt(origin, scale, f, support.z, support.w)
		ci.draw_line(support_a, support_b, INK, maxf(3.0, 6.0 * scale), true)
		ci.draw_line(support_a, support_b, METAL_SIDE, maxf(1.5, 3.0 * scale), true)
	var grip_a: Vector2 = _pt(origin, scale, f, -101.0, -161.0)
	var grip_b: Vector2 = _pt(origin, scale, f, -77.0, -154.0)
	ci.draw_line(grip_a, grip_b, INK, maxf(5.0, 13.0 * scale), true)
	ci.draw_line(grip_a, grip_b, RED, maxf(3.0, 8.0 * scale), true)
	ci.draw_line(grip_a + Vector2(0.0, 2.0 * scale), grip_b + Vector2(0.0, 2.0 * scale),
		RED_DARK, maxf(1.5, 3.0 * scale), true)

	# Far casters first, then the near pair.
	for x: float in [-38.0, 47.0]:
		_draw_wheel(ci, origin, scale, f, x, -18.0, 8.2, METAL_FAR, true)
	for x: float in [-54.0, 58.0]:
		_draw_wheel(ci, origin, scale, f, x, -11.0, 11.0, METAL, false)

	# Near legs, drawn over the wheels' forks.
	for x: float in [-54.0, 58.0]:
		var leg_top: Vector2 = _pt(origin, scale, f, x, -64.0 if x < 0.0 else -54.0)
		var leg_bottom: Vector2 = _pt(origin, scale, f, x, -16.0)
		ci.draw_line(leg_top, leg_bottom, INK, maxf(3.0, 7.0 * scale), true)
		ci.draw_line(leg_top, leg_bottom, METAL_SIDE, maxf(1.5, 3.8 * scale), true)


static func _draw_wheel(ci: CanvasItem, origin: Vector2, scale: float, f: float,
		x: float, y: float, radius: float, colour: Color, far: bool) -> void:
	var center: Vector2 = _pt(origin, scale, f, x, y)
	var r: float = radius * scale
	# Fork.
	ci.draw_line(_pt(origin, scale, f, x, y - radius - 10.0), center, INK,
		maxf(2.0, 4.5 * scale), true)
	ci.draw_circle(center, r + maxf(1.2, 2.6 * scale), INK)
	ci.draw_circle(center, r, colour)
	ci.draw_circle(center, r * 0.34, HUB)
	if not far:
		ci.draw_circle(center + Vector2(-r * 0.28, -r * 0.28), r * 0.20,
			Color(1, 1, 1, 0.7))


static func _pt(origin: Vector2, scale: float, f: float, x: float, y: float) -> Vector2:
	return origin + Vector2(x * f, y) * scale


static func _poly(origin: Vector2, scale: float, f: float,
		points: Array) -> PackedVector2Array:
	var out := PackedVector2Array()
	for point: Vector2 in points:
		out.append(_pt(origin, scale, f, point.x, point.y))
	return out


static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var out := points.duplicate()
	if out.size() > 0:
		out.append(out[0])
	return out
