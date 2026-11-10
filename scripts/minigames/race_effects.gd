extends Node3D
## MEADOW LOOP effects layer: speed-scaled dirt dust, drift/boost/landing
## bursts, lap confetti, drifting leaves and a pool of animated trackside
## reactions. All particles are GPU-side; nothing spawns per frame.

const CARD: String = "res://assets/textures/foliage/"
const FX: String = "res://assets/textures/fx/"

var cart: CartPlayer
var off_track: bool = false

var _dust: Array[GPUParticles3D] = []
var _boost_burst: GPUParticles3D
var _landing_burst: GPUParticles3D
var _confetti: GPUParticles3D
var _ambient: GPUParticles3D
var _was_boosting: bool = false
var _was_grounded: bool = true
var _air_time: float = 0.0
var _time: float = 0.0


func setup(player_cart: CartPlayer) -> void:
	cart = player_cart
	# Two emitters sit at the rear wheels so dust actually comes off the tyres.
	for side in [-0.44, 0.44]:
		var emitter: GPUParticles3D = _make_particles(CARD + "dust_puff.png", 40, 1.05, false)
		emitter.position = Vector3(side, 0.12, 0.62)
		_configure(emitter.process_material as ParticleProcessMaterial, "dust")
		cart.add_child(emitter)
		_dust.append(emitter)

	_boost_burst = _make_particles(CARD + "dust_puff.png", 36, 0.8, true)
	_configure(_boost_burst.process_material as ParticleProcessMaterial, "boost")
	add_child(_boost_burst)

	_landing_burst = _make_particles(CARD + "dust_puff.png", 30, 0.75, true)
	_configure(_landing_burst.process_material as ParticleProcessMaterial, "landing")
	add_child(_landing_burst)

	_confetti = _make_particles(FX + "confetti.png", 90, 2.4, true)
	_configure(_confetti.process_material as ParticleProcessMaterial, "confetti")
	add_child(_confetti)

	_ambient = _make_particles(CARD + "drifting_leaf.png", 90, 9.0, false)
	_configure(_ambient.process_material as ParticleProcessMaterial, "ambient")
	add_child(_ambient)


func _make_particles(texture_path: String, amount: int, lifetime: float,
		one_shot: bool, additive: bool = false) -> GPUParticles3D:
	var particles := GPUParticles3D.new()
	particles.amount = amount
	particles.lifetime = lifetime
	particles.one_shot = one_shot
	particles.emitting = not one_shot
	particles.explosiveness = 1.0 if one_shot else 0.0
	particles.local_coords = false
	particles.visibility_aabb = AABB(Vector3(-30, -4, -30), Vector3(60, 14, 60))
	particles.process_material = ParticleProcessMaterial.new()
	var quad := QuadMesh.new()
	quad.size = Vector2(0.5, 0.5)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.billboard_keep_scale = true
	mat.vertex_color_use_as_albedo = true
	mat.albedo_texture = load(texture_path)
	if additive:
		mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	quad.material = mat
	particles.draw_pass_1 = quad
	particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return particles


func _gradient(colors: PackedColorArray) -> GradientTexture1D:
	var gradient := Gradient.new()
	gradient.colors = colors
	var texture := GradientTexture1D.new()
	texture.gradient = gradient
	return texture


func _configure(mat: ParticleProcessMaterial, kind: String) -> void:
	mat.direction = Vector3(0, 1, 0)
	mat.spread = 30.0
	mat.gravity = Vector3(0, 0.8, 0)
	mat.lifetime_randomness = 0.3
	match kind:
		"dust":
			mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			mat.emission_box_extents = Vector3(0.22, 0.04, 0.18)
			mat.initial_velocity_min = 0.7
			mat.initial_velocity_max = 2.1
			mat.scale_min = 0.55
			mat.scale_max = 1.35
			# Cream dust reads against the tan dirt; the old brown-on-brown
			# puff was almost invisible at speed.
			mat.color = Color(0.98, 0.95, 0.88, 1)
			mat.color_ramp = _gradient(PackedColorArray([
				Color(0.98, 0.95, 0.88, 0.0), Color(0.98, 0.95, 0.88, 0.55),
				Color(0.94, 0.89, 0.80, 0.30), Color(0.90, 0.85, 0.76, 0.0)]))
		"boost":
			mat.direction = Vector3(0.0, 0.35, 0.0)
			mat.spread = 42.0
			mat.gravity = Vector3(0, 0.7, 0)
			mat.initial_velocity_min = 2.0
			mat.initial_velocity_max = 4.2
			mat.scale_min = 0.8
			mat.scale_max = 1.9
			mat.color_ramp = _gradient(PackedColorArray([
				Color(0.48, 0.46, 0.42, 0.0), Color(0.55, 0.52, 0.47, 0.75),
				Color(0.62, 0.58, 0.52, 0.38), Color(0.68, 0.63, 0.56, 0.0)]))
		"landing":
			# A low, warm dust cloud instead of a neon shockwave ring.
			mat.spread = 75.0
			mat.gravity = Vector3(0, 0.5, 0)
			mat.initial_velocity_min = 1.2
			mat.initial_velocity_max = 2.8
			mat.scale_min = 1.0
			mat.scale_max = 2.4
			mat.color_ramp = _gradient(PackedColorArray([
				Color(0.62, 0.57, 0.48, 0.0), Color(0.68, 0.62, 0.52, 0.7),
				Color(0.58, 0.53, 0.45, 0.32), Color(0.52, 0.47, 0.40, 0.0)]))
		"confetti":
			mat.spread = 55.0
			mat.gravity = Vector3(0, -2.2, 0)
			mat.initial_velocity_min = 6.0
			mat.initial_velocity_max = 13.0
			mat.scale_min = 0.5
			mat.scale_max = 1.3
			mat.angular_velocity_min = -420.0
			mat.angular_velocity_max = 420.0
			mat.color_ramp = _gradient(PackedColorArray([
				Color(1.0, 0.85, 0.2, 1), Color(0.27, 0.71, 0.94, 1),
				Color(0.95, 0.33, 0.36, 1), Color(0.31, 0.75, 0.32, 1)]))
		"ambient":
			mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
			mat.emission_box_extents = Vector3(28, 5, 28)
			mat.direction = Vector3(0.4, -0.2, 0.2)
			mat.spread = 55.0
			mat.gravity = Vector3(0.5, -0.12, 0.1)
			mat.initial_velocity_min = 0.25
			mat.initial_velocity_max = 1.1
			mat.scale_min = 0.22
			mat.scale_max = 0.5
			mat.angular_velocity_min = -90.0
			mat.angular_velocity_max = 90.0
			mat.color_ramp = _gradient(PackedColorArray([
				Color(0.42, 0.58, 0.24, 0.0), Color(0.55, 0.68, 0.30, 0.85),
				Color(0.78, 0.62, 0.28, 0.7), Color(0.45, 0.55, 0.25, 0.0)]))
	mat.turbulence_enabled = kind == "ambient" or kind == "dust"
	mat.turbulence_noise_strength = 0.9 if kind == "ambient" else 0.35
	mat.turbulence_noise_scale = 1.4
	mat.turbulence_influence_min = 0.1
	mat.turbulence_influence_max = 0.5


func _process(delta: float) -> void:
	if cart == null:
		return
	_time += delta
	var speed: float = Vector2(cart.velocity.x, cart.velocity.z).length()
	var grounded: bool = cart.is_on_floor()
	var ratio: float = clampf(speed / maxf(cart.max_speed, 1.0), 0.0, 1.0)
	var density: float = 0.10 + ratio * 0.72
	if cart.is_drifting:
		density += 0.45
	if off_track:
		density += 0.35
	var emitting: bool = grounded and speed > 1.6
	for emitter: GPUParticles3D in _dust:
		emitter.emitting = emitting
		emitter.amount_ratio = clampf(density, 0.0, 1.0)

	if cart.boost_active and not _was_boosting:
		_puff(_boost_burst)
		if _boost_burst != null:
			_boost_burst.global_position = cart.global_position + Vector3.UP * 0.55 \
				- cart.global_transform.basis.z * 1.0
	_was_boosting = cart.boost_active

	if not grounded:
		_air_time += delta
	elif not _was_grounded and _air_time > 0.18:
		_puff(_landing_burst)
		if _landing_burst != null:
			_landing_burst.global_position = cart.global_position + Vector3.UP * 0.08
		_air_time = 0.0
	elif grounded:
		_air_time = 0.0
	_was_grounded = grounded

	if _ambient != null:
		_ambient.global_position = cart.global_position + Vector3.UP * 4.0


func _puff(particles: GPUParticles3D) -> void:
	if particles == null:
		return
	particles.global_position = cart.global_position + Vector3.UP * 0.3
	particles.restart()
	particles.emitting = true


func lap_burst() -> void:
	_puff(_confetti)
