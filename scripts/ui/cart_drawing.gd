extends RefCounted
## Shared vector shopping-cart artwork for menus, loading screens and the icon.
##
## The cart is drawn in a three-quarter side view: a sloped wire basket with a
## deep opening and a readable lattice, a chunky red push handle, a lower rack
## and four casters with spoked rims. Everything is built from CanvasItem
## primitives so it stays sharp at any size.

const INK := Color("1e1b3a")
const METAL := Color("eef1f8")
const METAL_SIDE := Color("cbd2e2")
const METAL_FAR := Color("a8b0c6")
const RED := Color("dd3b41")
const RED_DARK := Color("a9242b")
const TIRE := Color("34324a")
const HUB := Color("737b93")
const OPENING := Color(0.16, 0.15, 0.29, 0.95)


static func draw_cart(ci: CanvasItem, origin: Vector2, scale: float, flip: bool = false) -> void:
	var f: float = -1.0 if flip else 1.0
	var ink_w: float = maxf(2.0, 3.4 * scale)
	var detail_w: float = maxf(1.2, 1.9 * scale)

	_draw_shadow(ci, origin, scale)

	# Far casters first. They sit higher and smaller, which is what sells the
	# three-quarter view without any extra shading.
	_draw_wheel(ci, origin, scale, f, -28.0, -17.0, 9.5, METAL_FAR, true)
	_draw_wheel(ci, origin, scale, f, 38.0, -17.0, 9.5, METAL_FAR, true)

	# Basket opening. The near and far rails are parallel, so the dark inner
	# wall reads as real depth instead of a painted stripe along the top.
	var near_tl := _pt(origin, scale, f, -80.0, -150.0)
	var near_tr := _pt(origin, scale, f, 64.0, -118.0)
	var far_tl := _pt(origin, scale, f, -64.0, -162.0)
	var far_tr := _pt(origin, scale, f, 80.0, -130.0)
	ci.draw_colored_polygon(PackedVector2Array([near_tl, near_tr, far_tr, far_tl]), OPENING)
	# Far rim: one heavy ink edge with a metal face on top.
	ci.draw_line(far_tl, far_tr, INK, ink_w * 1.6, true)
	ci.draw_line(far_tl, far_tr, METAL_SIDE, detail_w * 1.1, true)

	# Near side panel.
	var bottom_r := _pt(origin, scale, f, 54.0, -56.0)
	var bottom_l := _pt(origin, scale, f, -70.0, -74.0)
	var side := PackedVector2Array([near_tl, near_tr, bottom_r, bottom_l])
	ci.draw_colored_polygon(side, METAL)
	_draw_weave(ci, near_tl, near_tr, bottom_r, bottom_l, detail_w)
	ci.draw_polyline(_closed(side), INK, ink_w, true)

	# Front end panel closes the box. It is wider than a painted lip, so the
	# cart keeps its silhouette from every menu scale.
	var far_bottom_r := _pt(origin, scale, f, 72.0, -66.0)
	var front := PackedVector2Array([near_tr, far_tr, far_bottom_r, bottom_r])
	ci.draw_colored_polygon(front, METAL_SIDE)
	ci.draw_polyline(_closed(front), INK, ink_w, true)

	# Near top rail: a deliberate heavy line, then the frosted highlight.
	ci.draw_line(near_tl, near_tr, INK, ink_w * 1.7, true)
	ci.draw_line(near_tl, near_tr, METAL, detail_w * 1.3, true)
	ci.draw_line(near_tl.lerp(near_tr, 0.05) + Vector2(0.0, -detail_w),
		near_tl.lerp(near_tr, 0.92) + Vector2(0.0, -detail_w),
		Color(1, 1, 1, 0.55), maxf(1.4, 2.2 * scale), true)

	# Lower rack between the legs.
	ci.draw_line(_pt(origin, scale, f, -52.0, -38.0),
		_pt(origin, scale, f, 44.0, -26.0), INK, maxf(3.0, 5.0 * scale), true)
	ci.draw_line(_pt(origin, scale, f, -52.0, -38.0),
		_pt(origin, scale, f, 44.0, -26.0), METAL_SIDE, maxf(1.4, 2.4 * scale), true)

	# Near legs run down to the caster hubs; the wheels are drawn last so they
	# cover the joint and the silhouette stays clean.
	for leg: Vector4 in [Vector4(-56.0, -72.0, -50.0, -11.0),
			Vector4(48.0, -56.0, 52.0, -11.0)]:
		var leg_top: Vector2 = _pt(origin, scale, f, leg.x, leg.y)
		var leg_bottom: Vector2 = _pt(origin, scale, f, leg.z, leg.w)
		ci.draw_line(leg_top, leg_bottom, INK, maxf(3.5, 6.5 * scale), true)
		ci.draw_line(leg_top, leg_bottom, METAL_SIDE, maxf(1.6, 3.2 * scale), true)

	# Push handle: two posts rising from the rear rail, joined by one red
	# grip that runs along the cart's width instead of along its side.
	var near_post_top := _pt(origin, scale, f, -90.0, -170.0)
	var far_post_top := _pt(origin, scale, f, -74.0, -184.0)
	for post: Array in [
			[_pt(origin, scale, f, -74.0, -148.0), near_post_top],
			[_pt(origin, scale, f, -58.0, -160.0), far_post_top]]:
		var post_a: Vector2 = post[0] as Vector2
		var post_b: Vector2 = post[1] as Vector2
		ci.draw_line(post_a, post_b, INK, maxf(4.0, 6.5 * scale), true)
		ci.draw_line(post_a, post_b, METAL_SIDE, maxf(1.8, 3.2 * scale), true)
	var grip_a: Vector2 = _pt(origin, scale, f, -95.0, -166.0)
	var grip_b: Vector2 = _pt(origin, scale, f, -69.0, -188.0)
	_draw_grip(ci, grip_a, grip_b, scale)

	# Near casters.
	_draw_wheel(ci, origin, scale, f, -50.0, -11.0, 11.5, METAL, false)
	_draw_wheel(ci, origin, scale, f, 52.0, -11.0, 11.5, METAL, false)


static func _draw_shadow(ci: CanvasItem, origin: Vector2, scale: float) -> void:
	## Two stacked soft ellipses: a wide, faint halo plus a tighter contact
	## patch. The menus draw their own card shadow, so this stays subtle.
	ci.draw_set_transform(origin + Vector2(0.0, 2.0 * scale), 0.0,
		Vector2(1.0, 0.26))
	ci.draw_circle(Vector2.ZERO, 104.0 * scale, Color(0.12, 0.09, 0.20, 0.06))
	ci.draw_circle(Vector2.ZERO, 80.0 * scale, Color(0.12, 0.09, 0.20, 0.08))
	ci.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


static func _draw_weave(ci: CanvasItem, top_left: Vector2, top_right: Vector2,
		bottom_right: Vector2, bottom_left: Vector2, width: float) -> void:
	## Four ribs follow the side panel's taper and three rails cross them. One
	## shared line weight keeps the lattice readable instead of turning into
	## grey mush at icon size.
	for step in range(1, 5):
		var t: float = float(step) / 5.0
		ci.draw_line(top_left.lerp(top_right, t), bottom_left.lerp(bottom_right, t),
			INK, width, true)
	for step in range(1, 4):
		var t2: float = float(step) / 4.0
		ci.draw_line(top_left.lerp(bottom_left, t2), top_right.lerp(bottom_right, t2),
			INK, width, true)


static func _draw_grip(ci: CanvasItem, a: Vector2, b: Vector2, scale: float) -> void:
	## Rounded capsule so the grip gets proper caps at every angle.
	var ink_w: float = maxf(4.5, 11.5 * scale)
	var red_w: float = maxf(3.0, 8.0 * scale)
	ci.draw_line(a, b, INK, ink_w, true)
	ci.draw_circle(a, ink_w * 0.5, INK)
	ci.draw_circle(b, ink_w * 0.5, INK)
	ci.draw_line(a, b, RED, red_w, true)
	ci.draw_circle(a, red_w * 0.5, RED)
	ci.draw_circle(b, red_w * 0.5, RED)
	# Lower shade and a thin top highlight give the grip its candy roundness.
	ci.draw_line(a + Vector2(0.0, red_w * 0.22), b + Vector2(0.0, red_w * 0.22),
		RED_DARK, maxf(1.0, 2.0 * scale), true)
	ci.draw_line(a.lerp(b, 0.10) + Vector2(0.0, -red_w * 0.20),
		a.lerp(b, 0.86) + Vector2(0.0, -red_w * 0.20), Color(1, 1, 1, 0.45),
		maxf(1.0, 1.7 * scale), true)


static func _draw_wheel(ci: CanvasItem, origin: Vector2, scale: float, f: float,
		x: float, y: float, radius: float, rim_colour: Color, far: bool) -> void:
	var center: Vector2 = _pt(origin, scale, f, x, y)
	var r: float = radius * scale
	var outline_w: float = maxf(1.6, 2.6 * scale)
	# Tyre, metal rim, hub. The ink ring is the shared silhouette weight.
	ci.draw_circle(center, r + outline_w, INK)
	ci.draw_circle(center, r, TIRE)
	ci.draw_circle(center, r * 0.62, rim_colour.darkened(0.10) if far else rim_colour)
	ci.draw_circle(center, r * 0.30, HUB)
	if r > 6.0:
		for i in 4:
			var angle: float = TAU * float(i) / 4.0 + 0.4
			var spoke_dir := Vector2(cos(angle), sin(angle))
			ci.draw_line(center + spoke_dir * r * 0.28,
				center + spoke_dir * r * 0.56, HUB,
				maxf(0.9, 1.3 * scale), true)
	ci.draw_circle(center + Vector2(-r * 0.30, -r * 0.30), r * 0.16,
		Color(1, 1, 1, 0.35 if far else 0.62))


static func _pt(origin: Vector2, scale: float, f: float, x: float, y: float) -> Vector2:
	return origin + Vector2(x * f, y) * scale


static func _closed(points: PackedVector2Array) -> PackedVector2Array:
	var out := points.duplicate()
	if out.size() > 0:
		out.append(out[0])
	return out
