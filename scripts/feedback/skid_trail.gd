extends Node3D
## Fading tyre-mark ribbon for one rear wheel.
##
## Samples the wheel's ground contact while the cart drifts or handbrakes and
## builds a triangle strip in world space. Each vertex fades out over
## `fade_time`, so marks slowly disappear. Samples are lifted off the ground
## along the hit normal to avoid z-fighting, and the ribbon breaks on jumps
## instead of drawing a line through the air.
##
## A remote ghost has no local physics of its own: cart_feedback rebuilds its
## slide flag from the velocity in the ghost state packet, sets `remote_ghost`
## and drives the ribbon from the interpolated pose. Width, fade and the
## airborne rule stay identical to a local cart, so a ghost's marks look the
## same as everyone else's.
##
## The sample window is a fixed ring buffer over preallocated packed arrays, so
## emitting a point is a bounded buffer write and never an allocation. Old
## samples are dropped by advancing the tail, which also caps the trail length.
## `width` is clamped to a visible minimum: no per-vehicle profile can ever
## produce a zero-width (invisible) mark.

const MIN_WIDTH: float = 0.12
const MAX_WIDTH: float = 0.40
const MIN_FADE_TIME: float = 0.5
const MAX_POINTS: int = 512
## How often the per-vertex fade is refreshed while a ribbon is on screen (s).
const FADE_REFRESH: float = 0.1
## A remote ghost has no local physics: its slide flag is rebuilt from the
## state packet by cart_feedback. The packet arrives at 20 Hz, so sampling the
## ribbon faster only repeats the same sample.
const REMOTE_SAMPLE_INTERVAL: float = 1.0 / 30.0
## A wheel this far above the hit surface is airborne. The ghost is script-
## placed, so there is no is_on_floor() to prove contact; the ground distance
## is the equivalent test, and a jump has to break the ribbon like a local one.
const AIRBORNE_LIFT: float = 0.6

## Mark width (m). Clamped so an external profile can never disable the ribbon.
@export var width: float = 0.17:
	set(value):
		width = clampf(value, MIN_WIDTH, MAX_WIDTH)
## Seconds until a mark is gone.
@export var fade_time: float = 6.0:
	set(value):
		fade_time = maxf(value, MIN_FADE_TIME)
## Minimum planar speed (m/s) to leave marks.
@export var min_speed: float = 3.0
## Distance between samples (m).
@export var sample_distance: float = 0.18:
	set(value):
		sample_distance = maxf(value, 0.05)
## Offset along the ground normal (m).
@export var ground_lift: float = 0.025
## Peak vertex opacity (0-1).
@export var opacity: float = 0.62:
	set(value):
		opacity = clampf(value, 0.0, 1.0)
## Hard cap on buffered samples (and therefore marks on screen).
@export var max_points: int = 320:
	set(value):
		max_points = clampi(value, 8, MAX_POINTS)

var cart: CartPlayer
var wheel_offset: Vector3 = Vector3(0.0, 0.0, 0.55)
## True while this ribbon belongs to a remote ghost. The ghost is placed by
## script and has no velocity/is_on_floor()/is_drifting of its own, so the
## slide flag comes from cart_feedback (rebuilt from the state packet).
var remote_ghost: bool = false
var remote_sliding: bool = false
var _remote_clock: float = 0.0

var _mesh: ImmediateMesh
var _instance: MeshInstance3D
var _material: StandardMaterial3D
var _query: PhysicsRayQueryParameters3D
## Fixed ring buffer. `_head` is the next write slot and `_tail` the oldest
## sample, so dropping the oldest only moves an index.
var _left: PackedVector3Array = PackedVector3Array()
var _right: PackedVector3Array = PackedVector3Array()
var _born_at: PackedFloat32Array = PackedFloat32Array()
var _segment_of: PackedInt32Array = PackedInt32Array()
var _capacity: int = 0
var _head: int = 0
var _tail: int = 0
var _count: int = 0
var _last_pos: Vector3 = Vector3.ZERO
var _has_last: bool = false
var _segment: int = 0
var _now: float = 0.0
var _needs_rebuild: bool = false
var _fade_timer: float = 0.0


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
	_ensure_capacity()


func _physics_process(delta: float) -> void:
	if cart == null:
		return
	_now += delta
	if remote_ghost:
		# Sample at the state stream's own rate; the flag between packets is
		# held, not guessed.
		_remote_clock += delta
		if _remote_clock >= REMOTE_SAMPLE_INTERVAL:
			_remote_clock = 0.0
			_emit_samples()
	else:
		_emit_samples()
	var pruned: bool = _prune()
	# Geometry changes only when a sample is added or pruned; the fade is
	# refreshed at 10 Hz. A trail with nothing buffered does no mesh work.
	_fade_timer += delta
	if _needs_rebuild or pruned \
			or (_fade_timer >= FADE_REFRESH and _count >= 2):
		_needs_rebuild = false
		_fade_timer = 0.0
		_rebuild()


func clear_trail() -> void:
	_head = 0
	_tail = 0
	_count = 0
	_has_last = false
	_segment += 1
	_rebuild()


func _emit_samples() -> void:
	var sliding: bool = false
	if remote_ghost:
		# A ghost never reports floor contact or a physics velocity. The flag
		# was rebuilt from its streamed velocity by cart_feedback; the ground
		# ray below still has to hit a surface, so a jump breaks the ribbon.
		sliding = remote_sliding
	else:
		var handbrake_held: bool = cart.is_handbraking()
		var velocity: Vector3 = cart.velocity
		var planar_speed_sq: float = velocity.x * velocity.x + velocity.z * velocity.z
		sliding = cart.is_on_floor() and planar_speed_sq > min_speed * min_speed \
			and (cart.is_drifting or handbrake_held)
	if not sliding:
		_break_strip()
		return

	var world: Vector3 = cart.global_transform * wheel_offset
	# The ray is only needed once the wheel has moved far enough to make a new
	# sample; at drift speed this skips two out of three physics ticks.
	if _has_last:
		var moved_x: float = world.x - _last_pos.x
		var moved_z: float = world.z - _last_pos.z
		var gate: float = sample_distance * 0.6
		if moved_x * moved_x + moved_z * moved_z < gate * gate:
			return
	var query: PhysicsRayQueryParameters3D = _ensure_query()
	query.from = world + Vector3.UP * 0.7
	query.to = world + Vector3.DOWN * 1.4
	var hit: Dictionary = cart.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_break_strip()
		return
	var position: Vector3 = (hit.position as Vector3) + (hit.normal as Vector3) * ground_lift
	if remote_ghost and world.y - position.y > AIRBORNE_LIFT:
		# A hop shorter than the ray still finds the road beneath it. A local
		# cart proves contact with is_on_floor(); a ghost only has this gap.
		_break_strip()
		return
	if _has_last and _last_pos.distance_to(position) < sample_distance:
		return
	_add_point(position)
	_last_pos = position
	_has_last = true


func _ensure_query() -> PhysicsRayQueryParameters3D:
	## One reusable query: creating it every physics tick was wasted work.
	if _query == null:
		_query = PhysicsRayQueryParameters3D.new()
		_query.collision_mask = 1
		_query.collide_with_areas = false
		if cart != null:
			_query.exclude = [cart.get_rid()]
	return _query


func _break_strip() -> void:
	## End the current ribbon without deleting old marks. A new drift starts a
	## new segment, so the two are never joined by a stripe across the map.
	if _has_last:
		_segment += 1
	_has_last = false


func _ensure_capacity() -> void:
	## Only resizes when a profile changes `max_points`; the steady-state emit
	## path never touches this.
	var wanted: int = maxi(max_points, 2)
	if _capacity == wanted:
		return
	_capacity = wanted
	_left.resize(_capacity)
	_right.resize(_capacity)
	_born_at.resize(_capacity)
	_segment_of.resize(_capacity)
	_head = 0
	_tail = 0
	_count = 0


func _add_point(position: Vector3) -> void:
	_ensure_capacity()
	var direction: Vector3
	if _count == 0:
		direction = -cart.global_transform.basis.z
	else:
		var previous: int = (_head - 1 + _capacity) % _capacity
		direction = position - (_left[previous] + _right[previous]) * 0.5
	direction.y = 0.0
	if direction.length_squared() < 0.000001:
		direction = Vector3.FORWARD
	else:
		direction = direction.normalized()
	var side: Vector3 = direction.cross(Vector3.UP).normalized() * (width * 0.5)
	_left[_head] = position - side
	_right[_head] = position + side
	_born_at[_head] = _now
	_segment_of[_head] = _segment
	_head = (_head + 1) % _capacity
	_count += 1
	if _count > _capacity:
		_count = _capacity
		_tail = (_tail + 1) % _capacity
	_needs_rebuild = true


func _prune() -> bool:
	var changed: bool = false
	while _count > 0 and _now - _born_at[_tail] > fade_time:
		_tail = (_tail + 1) % _capacity
		_count -= 1
		changed = true
	return changed


func _rebuild() -> void:
	_mesh.clear_surfaces()
	if _count < 2:
		return
	var has_visible_segment: bool = false
	for index in _count - 1:
		var a: int = (_tail + index) % _capacity
		var b: int = (_tail + index + 1) % _capacity
		if _segment_of[a] == _segment_of[b] and (_alpha(_born_at[a]) > 0.001
				or _alpha(_born_at[b]) > 0.001):
			has_visible_segment = true
			break
	if not has_visible_segment:
		return
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in _count - 1:
		var a: int = (_tail + index) % _capacity
		var b: int = (_tail + index + 1) % _capacity
		if _segment_of[a] != _segment_of[b]:
			continue # Separate drifts: never bridge the gap.
		var alpha_a: float = _alpha(_born_at[a])
		var alpha_b: float = _alpha(_born_at[b])
		if alpha_a <= 0.001 and alpha_b <= 0.001:
			continue
		var color_a := Color(0.05, 0.045, 0.045, alpha_a)
		var color_b := Color(0.05, 0.045, 0.045, alpha_b)
		_mesh.surface_set_color(color_a)
		_mesh.surface_add_vertex(_left[a])
		_mesh.surface_set_color(color_a)
		_mesh.surface_add_vertex(_right[a])
		_mesh.surface_set_color(color_b)
		_mesh.surface_add_vertex(_left[b])
		_mesh.surface_set_color(color_a)
		_mesh.surface_add_vertex(_right[a])
		_mesh.surface_set_color(color_b)
		_mesh.surface_add_vertex(_right[b])
		_mesh.surface_set_color(color_b)
		_mesh.surface_add_vertex(_left[b])
	_mesh.surface_end()


func _alpha(born: float) -> float:
	return clampf(1.0 - (_now - born) / fade_time, 0.0, 1.0) * opacity
