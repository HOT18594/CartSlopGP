extends Node3D
## Per-vehicle tyre-mark ribbon for every wheel of one cart (WS3).
##
## One node owns every wheel's mark geometry for a cart and emits them through a
## single `ImmediateMesh` surface, so a cart costs ONE transparent draw call no
## matter how many wheels are marking. Each wheel keeps its own fixed ring
## buffer of ground-contact samples (packed arrays, no per-sample allocation),
## so adding a sample is a bounded buffer write and dropping the oldest only
## moves an index.
##
## ## What makes a mark per-vehicle
##
## `tread_style` selects one of four procedural treads in
## `scripts/effects/skid_mark.gdshader` (slick / street / offroad / caster), fed
## by `uv.y` = metres travelled so the pattern scrolls with the tyre. `width`,
## `mark_color` and `flair_color` come from the vehicle catalogue and paint, and
## the ground under the wheel tints/scales the mark: asphalt, dirt, wet, ice,
## snow and grass each have their own colour, width, opacity and fade. Front and
## rear tyres use different widths (front 0.84x) and their catalogue wheelbase /
## track offsets, so the four stripes sit where the wheels actually are.
##
## ## Multiplayer
##
## A remote ghost has no local physics: its slide flag is rebuilt from the
## velocity in the ghost state packet by cart_feedback, which sets
## `remote_ghost` and calls `set_wheels()` from the profile the peer replicated.
## Width, tread, colour, fade, per-wheel placement and the ground ray are the
## same code path, so a ghost's marks match its owner's without any extra RPC.
##
## ## Cost
##
## Samples are gated by distance and only re-tessellated when a point is added,
## pruned or the 10 Hz fade refresh fires. A trail with nothing buffered does no
## mesh work at all. `max_points` is per wheel and trimmed by the quality tier
## (web/performance keeps a shorter mark history).

const MARK_SHADER := preload("res://scripts/effects/skid_mark.gdshader")
const FxQuality := preload("res://scripts/effects/fx_quality.gd")

const MIN_WIDTH: float = 0.12
const MAX_WIDTH: float = 0.40
const MIN_FADE_TIME: float = 0.5
## Samples buffered per wheel. 384 x 4 wheels is far below one frame's vertex
## budget, and the ring buffer drops history rather than growing.
const MAX_POINTS: int = 384
## How often the per-vertex fade is refreshed while a ribbon is on screen (s).
const FADE_REFRESH: float = 0.1
## A remote ghost samples at the state stream's rate; the flag between packets
## is held, not guessed.
const REMOTE_SAMPLE_INTERVAL: float = 1.0 / 30.0
## A wheel this far above the hit surface is airborne (ghost path only; a local
## cart proves contact with is_on_floor()).
const AIRBORNE_LIFT: float = 0.6
## Front tyres are narrower than the driven rears on every road vehicle.
const FRONT_WIDTH_SCALE: float = 0.84
## Default rear-wheel pair used until a vehicle profile arrives.
const DEFAULT_WHEEL_SIDE: float = 0.43
const DEFAULT_WHEEL_BACK: float = 0.55

## Ground palette: colour, opacity multiplier, width multiplier, fade multiplier.
const SURFACES: Dictionary = {
	"normal": {"color": Color(0.052, 0.05, 0.048), "opacity": 0.64, "width": 1.0, "fade": 1.0},
	"asphalt": {"color": Color(0.052, 0.05, 0.048), "opacity": 0.64, "width": 1.0, "fade": 1.0},
	"dirt": {"color": Color(0.17, 0.12, 0.08), "opacity": 0.66, "width": 1.10, "fade": 0.85},
	"sand": {"color": Color(0.20, 0.15, 0.09), "opacity": 0.62, "width": 1.14, "fade": 0.80},
	"wet": {"color": Color(0.05, 0.07, 0.09), "opacity": 0.48, "width": 1.0, "fade": 0.75},
	"ice": {"color": Color(0.34, 0.42, 0.48), "opacity": 0.52, "width": 0.88, "fade": 1.30},
	"snow": {"color": Color(0.13, 0.14, 0.17), "opacity": 0.70, "width": 1.12, "fade": 1.50},
	"grass": {"color": Color(0.10, 0.13, 0.07), "opacity": 0.55, "width": 1.05, "fade": 0.70},
}

## Mark width (m). Clamped so an external profile can never disable the ribbon.
@export var width: float = 0.17:
	set(value):
		width = clampf(value, MIN_WIDTH, MAX_WIDTH)
## Seconds until a mark is gone (before the surface fade multiplier).
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
## Hard cap on buffered samples per wheel.
@export var max_points: int = 320:
	set(value):
		max_points = clampi(value, 8, MAX_POINTS)
		if is_node_ready():
			_rebuild_storage()
## Procedural tread style: 0 slick, 1 street, 2 offroad, 3 caster.
@export var tread_style: int = 1:
	set(value):
		tread_style = clampi(value, 0, 3)
		_apply_style()
## Surface under the wheel: normal/dirt/wet/ice/snow/grass.
@export var surface_kind: String = "normal"
## Base rubber tint from the vehicle profile (near-black, slightly per car).
@export var mark_color: Color = Color(0.06, 0.055, 0.05)
## Optional paint tint: a race car's mark picks up a whisper of its own colour.
@export var flair_color: Color = Color(0.0, 0.0, 0.0, 0.0)

var cart: CartPlayer
## World-space-ish offsets (cart local) for every marking wheel: FL, FR, RL, RR.
var wheel_offsets: Array[Vector3] = []
## Which wheel indices mark while drifting (the rears). Handbraking marks all.
var drift_wheel_indices: PackedInt32Array = PackedInt32Array()
var remote_ghost: bool = false
var remote_sliding: bool = false

var _mesh: ImmediateMesh
var _instance: MeshInstance3D
var _material: ShaderMaterial
var _query: PhysicsRayQueryParameters3D
var _now: float = 0.0
var _remote_clock: float = 0.0
var _needs_rebuild: bool = false
var _fade_timer: float = 0.0

# Per-wheel ring buffers. Every outer array has one entry per wheel.
var _left: Array = []
var _right: Array = []
var _born_at: Array = []
var _segment_of: Array = []
var _lengths: Array = []
var _head: PackedInt32Array = PackedInt32Array()
var _tail: PackedInt32Array = PackedInt32Array()
var _count: PackedInt32Array = PackedInt32Array()
var _last_pos: Array = []
var _has_last: PackedByteArray = PackedByteArray()
var _segment: PackedInt32Array = PackedInt32Array()
var _capacity: int = 0
var _wheel_count: int = 0


func _ready() -> void:
	add_to_group("skid_trails")
	top_level = true
	global_transform = Transform3D.IDENTITY

	_mesh = ImmediateMesh.new()
	_material = ShaderMaterial.new()
	_material.shader = MARK_SHADER
	_apply_style()

	_instance = MeshInstance3D.new()
	_instance.name = "SkidMarks"
	_instance.mesh = _mesh
	_instance.material_override = _material
	_instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_instance.top_level = true
	_instance.global_transform = Transform3D.IDENTITY
	add_child(_instance)
	if wheel_offsets.is_empty():
		set_wheels([
			Vector3(-DEFAULT_WHEEL_SIDE, 0.0, -0.30),
			Vector3(DEFAULT_WHEEL_SIDE, 0.0, -0.30),
			Vector3(-DEFAULT_WHEEL_SIDE, 0.0, DEFAULT_WHEEL_BACK),
			Vector3(DEFAULT_WHEEL_SIDE, 0.0, DEFAULT_WHEEL_BACK),
		], PackedInt32Array([2, 3]))
	else:
		_rebuild_storage()


func set_wheels(offsets: Array, drift_indices: PackedInt32Array) -> void:
	## Called once per vehicle profile (and again for a remote peer when its
	## replicated vehicle arrives). Lays out one ring buffer per wheel; existing
	## marks are cleared because the wheel positions just changed.
	wheel_offsets.clear()
	for raw: Variant in offsets:
		var offset: Vector3 = raw
		wheel_offsets.append(offset)
	drift_wheel_indices = drift_indices.duplicate()
	_rebuild_storage()


func set_remote(sliding: bool, ghost: bool) -> void:
	remote_ghost = ghost
	remote_sliding = sliding


func _apply_style() -> void:
	## A new style only changes uniforms: no shader recompile, no new material.
	if _material == null:
		return
	_material.set_shader_parameter("tread_style", tread_style)
	match tread_style:
		0:
			_material.set_shader_parameter("tread_period", 0.55)
			_material.set_shader_parameter("tread_contrast", 0.20)
			_material.set_shader_parameter("grit_strength", 0.06)
		1:
			_material.set_shader_parameter("tread_period", 0.34)
			_material.set_shader_parameter("tread_contrast", 0.40)
			_material.set_shader_parameter("grit_strength", 0.10)
		2:
			_material.set_shader_parameter("tread_period", 0.30)
			_material.set_shader_parameter("tread_contrast", 0.55)
			_material.set_shader_parameter("grit_strength", 0.16)
		_:
			_material.set_shader_parameter("tread_period", 0.22)
			_material.set_shader_parameter("tread_contrast", 0.35)
			_material.set_shader_parameter("grit_strength", 0.22)


func _physics_process(delta: float) -> void:
	if cart == null:
		return
	_now += delta
	if remote_ghost:
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
	if _needs_rebuild or pruned or (_fade_timer >= FADE_REFRESH and _has_samples()):
		_needs_rebuild = false
		_fade_timer = 0.0
		_rebuild()


func clear_trail() -> void:
	## Drops every wheel's buffered marks (cart reset / respawn).
	for wheel in _wheel_count:
		_head[wheel] = 0
		_tail[wheel] = 0
		_count[wheel] = 0
		_has_last[wheel] = 0
		_segment[wheel] = int(_segment[wheel]) + 1
	_rebuild()


func _emit_samples() -> void:
	var sliding: bool = false
	var handbrake: bool = false
	if remote_ghost:
		# A ghost never reports floor contact or a physics velocity: the flag was
		# rebuilt from the streamed velocity by cart_feedback, and the ground ray
		# below still has to hit a surface so a jump breaks the ribbon.
		sliding = remote_sliding
		handbrake = remote_sliding
	else:
		handbrake = cart.is_handbraking()
		var velocity: Vector3 = cart.velocity
		var planar_speed_sq: float = velocity.x * velocity.x + velocity.z * velocity.z
		sliding = cart.is_on_floor() and planar_speed_sq > min_speed * min_speed \
			and (cart.is_drifting or handbrake)
	for wheel in _wheel_count:
		var wheel_active: bool = sliding \
			and (handbrake or drift_wheel_indices.has(wheel))
		if not wheel_active:
			_break_strip(wheel)
			continue
		_emit_wheel(wheel)


func _emit_wheel(wheel: int) -> void:
	var offset: Vector3 = wheel_offsets[wheel]
	var world: Vector3 = cart.global_transform * offset
	# The ray is only needed once the wheel moved far enough to make a new
	# sample; at drift speed this skips two out of three physics ticks.
	var last_valid: bool = _has_last[wheel] != 0
	if last_valid:
		var last: Vector3 = _last_pos[wheel]
		var moved_x: float = world.x - last.x
		var moved_z: float = world.z - last.z
		var gate: float = sample_distance * 0.6
		if moved_x * moved_x + moved_z * moved_z < gate * gate:
			return
	var query: PhysicsRayQueryParameters3D = _ensure_query()
	query.from = world + Vector3.UP * 0.7
	query.to = world + Vector3.DOWN * 1.4
	var hit: Dictionary = cart.get_world_3d().direct_space_state.intersect_ray(query)
	if hit.is_empty():
		_break_strip(wheel)
		return
	var hit_position: Vector3 = hit["position"]
	var hit_normal: Vector3 = hit["normal"]
	var position: Vector3 = hit_position + hit_normal * ground_lift
	if remote_ghost and world.y - position.y > AIRBORNE_LIFT:
		# A hop shorter than the ray still finds the road beneath it.
		_break_strip(wheel)
		return
	if last_valid:
		var last_point: Vector3 = _last_pos[wheel]
		if last_point.distance_to(position) < sample_distance:
			return
	_add_point(wheel, position)
	_last_pos[wheel] = position
	_has_last[wheel] = 1


func _ensure_query() -> PhysicsRayQueryParameters3D:
	if _query == null:
		_query = PhysicsRayQueryParameters3D.new()
		_query.collision_mask = 1
		_query.collide_with_areas = false
		if cart != null:
			_query.exclude = [cart.get_rid()]
	return _query


func _break_strip(wheel: int) -> void:
	if _has_last[wheel] != 0:
		_segment[wheel] = int(_segment[wheel]) + 1
	_has_last[wheel] = 0


func _rebuild_storage() -> void:
	## (Re)allocates all per-wheel ring buffers. Only runs when a vehicle profile
	## changes `max_points` or the wheel set - the steady state never touches it.
	_wheel_count = maxi(wheel_offsets.size(), 1)
	var wanted: int = clampi(max_points, 8, MAX_POINTS)
	if FxQuality.is_web():
		wanted = mini(wanted, 192)
	_capacity = wanted
	_left.clear()
	_right.clear()
	_born_at.clear()
	_segment_of.clear()
	_lengths.clear()
	_last_pos.clear()
	for _wheel in _wheel_count:
		var left_buf := PackedVector3Array()
		var right_buf := PackedVector3Array()
		var born_buf := PackedFloat32Array()
		var segment_buf := PackedInt32Array()
		var length_buf := PackedFloat32Array()
		left_buf.resize(_capacity)
		right_buf.resize(_capacity)
		born_buf.resize(_capacity)
		segment_buf.resize(_capacity)
		length_buf.resize(_capacity)
		_left.append(left_buf)
		_right.append(right_buf)
		_born_at.append(born_buf)
		_segment_of.append(segment_buf)
		_lengths.append(length_buf)
		_last_pos.append(Vector3.ZERO)
	_head.resize(_wheel_count)
	_tail.resize(_wheel_count)
	_count.resize(_wheel_count)
	_segment.resize(_wheel_count)
	_has_last.resize(_wheel_count)
	for wheel in _wheel_count:
		_head[wheel] = 0
		_tail[wheel] = 0
		_count[wheel] = 0
		_segment[wheel] = 0
		_has_last[wheel] = 0
	_needs_rebuild = true
	_rebuild()


func _add_point(wheel: int, position: Vector3) -> void:
	var capacity: int = _capacity
	var head: int = _head[wheel]
	var left_buf: PackedVector3Array = _left[wheel]
	var right_buf: PackedVector3Array = _right[wheel]
	var born_buf: PackedFloat32Array = _born_at[wheel]
	var segment_buf: PackedInt32Array = _segment_of[wheel]
	var length_buf: PackedFloat32Array = _lengths[wheel]
	var direction: Vector3
	var along: float = 0.0
	if _count[wheel] == 0:
		direction = -cart.global_transform.basis.z
	else:
		var previous: int = (head - 1 + capacity) % capacity
		direction = position - (left_buf[previous] + right_buf[previous]) * 0.5
		along = float(length_buf[previous]) + maxf(
			position.distance_to((left_buf[previous] + right_buf[previous]) * 0.5),
			sample_distance)
	direction.y = 0.0
	if direction.length_squared() < 0.000001:
		direction = Vector3.FORWARD
	else:
		direction = direction.normalized()
	var wheel_scale: float = 1.0 if wheel >= 2 else FRONT_WIDTH_SCALE
	var surface: Dictionary = surface_profile()
	var half_width: float = width * wheel_scale \
		* float(surface.get("width", 1.0)) * 0.5
	var side: Vector3 = direction.cross(Vector3.UP).normalized() * half_width
	left_buf[head] = position - side
	right_buf[head] = position + side
	born_buf[head] = _now
	segment_buf[head] = _segment[wheel]
	length_buf[head] = along
	_left[wheel] = left_buf
	_right[wheel] = right_buf
	_born_at[wheel] = born_buf
	_segment_of[wheel] = segment_buf
	_lengths[wheel] = length_buf
	_head[wheel] = (head + 1) % capacity
	_count[wheel] = _count[wheel] + 1
	if _count[wheel] > capacity:
		_count[wheel] = capacity
		_tail[wheel] = (_tail[wheel] + 1) % capacity
	_needs_rebuild = true


func _prune() -> bool:
	var changed: bool = false
	var effective_fade: float = fade_time * float(surface_profile().get("fade", 1.0))
	for wheel in _wheel_count:
		var count: int = _count[wheel]
		var tail: int = _tail[wheel]
		var born_buf: PackedFloat32Array = _born_at[wheel]
		while count > 0 and _now - float(born_buf[tail]) > effective_fade:
			tail = (tail + 1) % _capacity
			count -= 1
			changed = true
		_tail[wheel] = tail
		_count[wheel] = count
	return changed


func _has_samples() -> bool:
	for wheel in _wheel_count:
		if _count[wheel] >= 2:
			return true
	return false


func surface_profile() -> Dictionary:
	var key: String = surface_kind.to_lower()
	if SURFACES.has(key):
		var profile: Dictionary = SURFACES[key]
		return profile
	var fallback: Dictionary = SURFACES["normal"]
	return fallback


func _mark_color() -> Color:
	## Surface colour dominates (snow and ice marks are visibly lighter), with a
	## third of the vehicle's rubber tint kept for per-car identity, plus a
	## whisper of the race car's paint as flair.
	var surface: Dictionary = surface_profile()
	var base: Color = surface.get("color", Color(0.05, 0.05, 0.05))
	var color: Color = base.lerp(mark_color, 0.30)
	if flair_color.a > 0.0:
		color = color.lerp(Color(flair_color.r, flair_color.g, flair_color.b),
			clampf(flair_color.a, 0.0, 1.0) * 0.14)
	return color


func _rebuild() -> void:
	if _mesh == null:
		return
	_mesh.clear_surfaces()
	if not _has_samples():
		return
	var effective_fade: float = fade_time * float(surface_profile().get("fade", 1.0))
	var peak_opacity: float = opacity * float(surface_profile().get("opacity", 1.0))
	var tint: Color = _mark_color()
	_mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	# Every candidate quad can be skipped (a drift gap, or both ends already
	# faded). ImmediateMesh logs "No vertices were added, surface can't be
	# created." when the surface is ended empty, so count what was emitted.
	var emitted_segments: int = 0
	for wheel in _wheel_count:
		var capacity: int = _capacity
		var count: int = _count[wheel]
		if count < 2:
			continue
		var left_buf: PackedVector3Array = _left[wheel]
		var right_buf: PackedVector3Array = _right[wheel]
		var born_buf: PackedFloat32Array = _born_at[wheel]
		var segment_buf: PackedInt32Array = _segment_of[wheel]
		var length_buf: PackedFloat32Array = _lengths[wheel]
		var tail: int = _tail[wheel]
		for index in count - 1:
			var a: int = (tail + index) % capacity
			var b: int = (tail + index + 1) % capacity
			if segment_buf[a] != segment_buf[b]:
				continue # Separate drifts: never bridge the gap.
			var alpha_a: float = _alpha(float(born_buf[a]), _now, effective_fade,
				peak_opacity)
			var alpha_b: float = _alpha(float(born_buf[b]), _now, effective_fade,
				peak_opacity)
			if alpha_a <= 0.002 and alpha_b <= 0.002:
				continue
			var color_a := Color(tint.r, tint.g, tint.b, alpha_a)
			var color_b := Color(tint.r, tint.g, tint.b, alpha_b)
			var uv_a := Vector2(0.0, float(length_buf[a]))
			var uv_b := Vector2(1.0, float(length_buf[a]))
			var uv_c := Vector2(0.0, float(length_buf[b]))
			var uv_d := Vector2(1.0, float(length_buf[b]))
			_mesh.surface_set_color(color_a)
			_mesh.surface_set_uv(uv_a)
			_mesh.surface_add_vertex(left_buf[a])
			_mesh.surface_set_color(color_a)
			_mesh.surface_set_uv(uv_b)
			_mesh.surface_add_vertex(right_buf[a])
			_mesh.surface_set_color(color_b)
			_mesh.surface_set_uv(uv_c)
			_mesh.surface_add_vertex(left_buf[b])
			_mesh.surface_set_color(color_a)
			_mesh.surface_set_uv(uv_b)
			_mesh.surface_add_vertex(right_buf[a])
			_mesh.surface_set_color(color_b)
			_mesh.surface_set_uv(uv_d)
			_mesh.surface_add_vertex(right_buf[b])
			_mesh.surface_set_color(color_b)
			_mesh.surface_set_uv(uv_c)
			_mesh.surface_add_vertex(left_buf[b])
			emitted_segments += 1
	if emitted_segments == 0:
		# Nothing survived the gap/fade filters: drop the empty surface instead
		# of ending it (an empty ImmediateMesh surface is an engine error).
		_mesh.clear_surfaces()
		return
	_mesh.surface_end()


static func _alpha(born: float, now: float, fade: float, peak: float) -> float:
	var life: float = clampf(1.0 - (now - born) / maxf(fade, 0.01), 0.0, 1.0)
	# Ease-in near the end so a mark dissolves instead of popping out.
	return life * life * peak
