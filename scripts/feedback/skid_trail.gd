extends Node3D
## Fading tyre-mark ribbon for one rear wheel.
##
## Samples the wheel's ground contact while the cart drifts or handbrakes and
## builds a triangle strip in world space. Each vertex fades out over
## `fade_time`, so marks slowly disappear. Samples are lifted off the ground
## along the hit normal to avoid z-fighting, and the ribbon breaks on jumps
## instead of drawing a line through the air.

@export var width: float = 0.17 ## Mark width (m).
@export var fade_time: float = 6.0 ## Seconds until a mark is gone.
@export var min_speed: float = 3.0 ## Minimum planar speed (m/s) to leave marks.
@export var sample_distance: float = 0.18 ## Distance between samples (m).
@export var ground_lift: float = 0.025 ## Offset along the ground normal (m).
@export var opacity: float = 0.62
@export var max_points: int = 320

var cart: CartPlayer
var wheel_offset: Vector3 = Vector3(0.0, 0.0, 0.55)

var _mesh: ImmediateMesh
var _instance: MeshInstance3D
var _material: StandardMaterial3D
var _points: Array = [] ## [left: Vector3, right: Vector3, born: float, segment: int]
var _last_pos: Vector3 = Vector3.ZERO
var _has_last: bool = false
var _segment: int = 0
var _now: float = 0.0


func _ready() -> void:
	top_level = true
	global_transform = Transform3D.IDENTITY

	_mesh = ImmediateMesh.new()
	_material = StandardMaterial3D.new()
	_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_material.vertex_color_use_as_albedo = true
	_material.cull_mode = BaseMaterial3D.CULL_DISABLED
	_material.albedo_color = Color(1, 1, 1, 1)

	_instance = MeshInstance3D.new()
	_instance.mesh = _mesh
	_instance.material_override = _material
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_instance.top_level = true
	_instance.global_transform = Transform3D.IDENTITY
	add_child(_instance)


var _needs_rebuild: bool = false
var _fade_timer: float = 0.0


func _physics_process(delta: float) -> void:
	if cart == null:
		return
	_now += delta
	_emit_samples()
	var pruned: bool = _prune()
	# Rebuilding a 320-point ImmediateMesh every physics tick was pure waste
	# while parked or cruising. Geometry changes only when a sample is added;
	# the fade is refreshed at 10 Hz.
	_fade_timer += delta
	if _needs_rebuild or pruned or _fade_timer >= 0.1:
		_needs_rebuild = false
		_fade_timer = 0.0
		_rebuild()


func clear_trail() -> void:
	_points.clear()
	_has_last = false
	_segment += 1
	_rebuild()


func _emit_samples() -> void:
	var handbrake_held: bool = cart.ai_handbrake if cart.ai_mode \
		else Input.is_action_pressed("handbrake")
	var skidding: bool = cart.is_on_floor() \
		and (cart.is_drifting or handbrake_held) \
		and Vector2(cart.velocity.x, cart.velocity.z).length() > min_speed
	if not skidding:
		_break_strip()
		return

	var world: Vector3 = cart.global_transform * wheel_offset
	var query: PhysicsRayQueryParameters3D = PhysicsRayQueryParameters3D.create(
		world + Vector3.UP * 0.7, world + Vector3.DOWN * 1.4, 1, [cart.get_rid()])
	query.collide_with_areas = false
	var hit: Dictionary = cart.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_break_strip()
		return
	var position: Vector3 = (hit.position as Vector3) + (hit.normal as Vector3) * ground_lift
	if _has_last and _last_pos.distance_to(position) < sample_distance:
		return
	_add_point(position)
	_last_pos = position
	_has_last = true


func _break_strip() -> void:
	## End the current ribbon without deleting old marks. A new drift starts a
	## new segment, so the two are never joined by a stripe across the map.
	if _has_last:
		_segment += 1
	_has_last = false


func _add_point(position: Vector3) -> void:
	var direction: Vector3
	if _points.is_empty():
		direction = -cart.global_transform.basis.z
	else:
		var previous: Array = _points[_points.size() - 1]
		direction = position - ((previous[0] as Vector3) + (previous[1] as Vector3)) * 0.5
	direction.y = 0.0
	if direction.length() < 0.001:
		direction = -cart.global_transform.basis.z
	direction = direction.normalized()
	var side: Vector3 = direction.cross(Vector3.UP).normalized() * (width * 0.5)
	_points.append([position - side, position + side, _now, _segment])
	_needs_rebuild = true
	if _points.size() > max_points:
		_points.pop_front()


func _prune() -> bool:
	var changed: bool = false
	while not _points.is_empty() and _now - float(_points[0][2]) > fade_time:
		_points.pop_front()
		changed = true
	return changed


func _rebuild() -> void:
	_mesh.clear_surfaces()
	if _points.size() < 2:
		return
	var has_visible_segment: bool = false
	for index in _points.size() - 1:
		var a: Array = _points[index]
		var b: Array = _points[index + 1]
		if int(a[3]) == int(b[3]) and (_alpha(float(a[2])) > 0.001
				or _alpha(float(b[2])) > 0.001):
			has_visible_segment = true
			break
	if not has_visible_segment:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in _points.size() - 1:
		var a: Array = _points[index]
		var b: Array = _points[index + 1]
		if int(a[3]) != int(b[3]):
			continue # Separate drifts: never bridge the gap.
		var alpha_a: float = _alpha(float(a[2]))
		var alpha_b: float = _alpha(float(b[2]))
		if alpha_a <= 0.001 and alpha_b <= 0.001:
			continue
		var color_a := Color(0.05, 0.045, 0.045, alpha_a)
		var color_b := Color(0.05, 0.045, 0.045, alpha_b)
		var a_left: Vector3 = a[0]
		var a_right: Vector3 = a[1]
		var b_left: Vector3 = b[0]
		var b_right: Vector3 = b[1]
		_mesh.surface_set_color(color_a)
		_mesh.surface_add_vertex(a_left)
		_mesh.surface_set_color(color_a)
		_mesh.surface_add_vertex(a_right)
		_mesh.surface_set_color(color_b)
		_mesh.surface_add_vertex(b_left)
		_mesh.surface_set_color(color_a)
		_mesh.surface_add_vertex(a_right)
		_mesh.surface_set_color(color_b)
		_mesh.surface_add_vertex(b_right)
		_mesh.surface_set_color(color_b)
		_mesh.surface_add_vertex(b_left)
	_mesh.surface_end()


func _alpha(born: float) -> float:
	return clampf(1.0 - (_now - born) / fade_time, 0.0, 1.0) * opacity
