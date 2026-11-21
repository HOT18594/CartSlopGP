class_name BoostPad
extends Area3D
## Arcade boost pad: gives a player or AI kart a forward speed burst when it
## drives over the holographic aurora zone, triggering a crisp 0.45 s shader
## surge flash, a 24-spark particle burst and a spatial whoosh sound.

const PAD_SOUND: AudioStream = preload("res://assets/audio/sfx/boost/boost_pad.ogg")
const SURGE_DURATION: float = 0.50
const DEFAULT_INTENSITY: float = 2.6
const SURGE_INTENSITY: float = 4.2
const DEFAULT_WISP_INTENSITY: float = 0.72
const SURGE_WISP_INTENSITY: float = 1.30

@export var cooldown_seconds: float = 1.2 ## Seconds between activations per kart.
@export var burst_speed: float = 11.5 ## Forward speed burst (m/s) applied to the kart.
@export var pad_sound: AudioStream = PAD_SOUND ## One-shot whoosh when a kart hits the pad.

var _cooldowns: Dictionary = {}
var _time: float = 0.0
var _surge_timer: float = 0.0
var _base_intensity: float = DEFAULT_INTENSITY
var _base_wisp_intensity: float = DEFAULT_WISP_INTENSITY
var _base_energy: float = 2.0
var _visual: MeshInstance3D = null
var _puff: GPUParticles3D = null
var _ambient_sparks: GPUParticles3D = null
var _audio: AudioStreamPlayer3D = null
var _aurora_mat: ShaderMaterial = null
var _wisp_mat: ShaderMaterial = null
var _pad_mat: StandardMaterial3D = null
var _frame_root: Node3D = null
var _pad_width: float = 6.4
var _pad_length: float = 4.4


func _ready() -> void:
	add_to_group("boost_pad")
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	_visual = get_node_or_null("SpeedZone") as MeshInstance3D
	if _visual == null:
		_visual = get_node_or_null("Visual") as MeshInstance3D
	_puff = get_node_or_null("Puff") as GPUParticles3D
	_audio = get_node_or_null("PadAudio") as AudioStreamPlayer3D
	if _audio != null:
		_audio.bus = "SFX"
	_bind_visual_materials()
	_build_pad_hardware()
	_build_ambient_sparks()
	_layout_pad()


func set_pad_dimensions(width: float, length: float) -> void:
	_pad_width = maxf(width, 3.0)
	_pad_length = maxf(length, 2.5)
	if is_node_ready():
		_layout_pad()


func _build_pad_hardware() -> void:
	if get_node_or_null("PadHardware") != null:
		_frame_root = get_node_or_null("PadHardware") as Node3D
		return
	_frame_root = Node3D.new()
	_frame_root.name = "PadHardware"
	add_child(_frame_root)

	var frame_mat := StandardMaterial3D.new()
	frame_mat.albedo_color = Color("1f293d")
	frame_mat.roughness = 0.85
	frame_mat.metallic = 0.25

	var trim_mat := StandardMaterial3D.new()
	trim_mat.albedo_color = Color("36e3ff")
	trim_mat.emission_enabled = true
	trim_mat.emission = Color("1ec8ff")
	trim_mat.emission_energy_multiplier = 2.0
	trim_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	var gold_mat := StandardMaterial3D.new()
	gold_mat.albedo_color = Color("ffd22e")
	gold_mat.emission_enabled = true
	gold_mat.emission = Color("ffcf2b")
	gold_mat.emission_energy_multiplier = 2.2
	gold_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED

	for side_name: String in ["RailLeft", "RailRight"]:
		var rail := MeshInstance3D.new()
		rail.name = side_name
		var box := BoxMesh.new()
		box.size = Vector3(0.24, 0.14, 1.0)
		rail.mesh = box
		rail.material_override = frame_mat
		rail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_frame_root.add_child(rail)

		var strip := MeshInstance3D.new()
		strip.name = side_name + "Strip"
		var strip_box := BoxMesh.new()
		strip_box.size = Vector3(0.10, 0.06, 0.92)
		strip.mesh = strip_box
		strip.material_override = trim_mat
		strip.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		strip.position = Vector3(0.0, 0.06, 0.0)
		rail.add_child(strip)

	for corner in 4:
		var pod := MeshInstance3D.new()
		pod.name = "CornerPod%d" % corner
		var cyl := CylinderMesh.new()
		cyl.top_radius = 0.16
		cyl.bottom_radius = 0.22
		cyl.height = 0.28
		cyl.radial_segments = 8
		pod.mesh = cyl
		pod.material_override = frame_mat
		pod.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_frame_root.add_child(pod)

		var beacon := MeshInstance3D.new()
		beacon.name = "Beacon"
		var orb := BoxMesh.new()
		orb.size = Vector3(0.18, 0.10, 0.18)
		beacon.mesh = orb
		beacon.material_override = gold_mat
		beacon.position = Vector3(0.0, 0.16, 0.0)
		beacon.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		pod.add_child(beacon)


func _build_ambient_sparks() -> void:
	if DisplayServer.get_name() == "headless":
		return
	if get_node_or_null("AmbientSparks") != null:
		_ambient_sparks = get_node_or_null("AmbientSparks") as GPUParticles3D
		return
	var sparks := GPUParticles3D.new()
	sparks.name = "AmbientSparks"
	sparks.amount = 14
	sparks.lifetime = 0.95
	sparks.emitting = true
	sparks.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	sparks.position = Vector3(0.0, 0.12, 0.0)

	var proc := ParticleProcessMaterial.new()
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = Vector3(_pad_width * 0.44, 0.05, _pad_length * 0.42)
	proc.direction = Vector3(0.0, 1.0, -0.35)
	proc.spread = 18.0
	proc.initial_velocity_min = 1.2
	proc.initial_velocity_max = 2.6
	proc.gravity = Vector3(0.0, 0.8, 0.0)
	proc.scale_min = 0.55
	proc.scale_max = 1.05
	proc.color = Color(0.55, 0.98, 1.0, 0.85)
	sparks.process_material = proc

	var quad := QuadMesh.new()
	quad.size = Vector2(0.16, 0.16)
	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	mat.albedo_color = Color(0.75, 0.98, 1.0, 0.88)
	mat.emission_enabled = true
	mat.emission = Color(0.32, 0.94, 1.0)
	mat.emission_energy_multiplier = 2.0
	quad.material = mat
	sparks.draw_pass_1 = quad
	add_child(sparks)
	_ambient_sparks = sparks


func _layout_pad() -> void:
	var col := get_node_or_null("CollisionShape3D") as CollisionShape3D
	if col != null and col.shape is BoxShape3D:
		var box := (col.shape as BoxShape3D).duplicate() as BoxShape3D
		box.size = Vector3(_pad_width + 0.2, 0.72, _pad_length + 0.2)
		col.shape = box
	if _visual != null and _visual.mesh is QuadMesh:
		var qm := (_visual.mesh as QuadMesh).duplicate() as QuadMesh
		qm.size = Vector2(_pad_width, _pad_length)
		_visual.mesh = qm
	var half_w: float = _pad_width * 0.5
	var half_l: float = _pad_length * 0.5
	var wisp_map := {
		"WispLeftFront": Vector3(-half_w * 0.80, 0.70, -half_l * 0.50),
		"WispLeftBack": Vector3(-half_w * 0.82, 0.70, half_l * 0.50),
		"WispRightFront": Vector3(half_w * 0.80, 0.70, -half_l * 0.50),
		"WispRightBack": Vector3(half_w * 0.82, 0.70, half_l * 0.50),
	}
	for wname: String in wisp_map:
		var wnode := get_node_or_null(wname) as Node3D
		if wnode != null:
			wnode.position = wisp_map[wname]
	if _frame_root != null:
		var rail_l := _frame_root.get_node_or_null("RailLeft") as Node3D
		var rail_r := _frame_root.get_node_or_null("RailRight") as Node3D
		if rail_l != null:
			rail_l.position = Vector3(-half_w - 0.08, 0.06, 0.0)
			rail_l.scale = Vector3(1.0, 1.0, _pad_length * 0.96)
		if rail_r != null:
			rail_r.position = Vector3(half_w + 0.08, 0.06, 0.0)
			rail_r.scale = Vector3(1.0, 1.0, _pad_length * 0.96)
		var corners := [
			Vector3(-half_w - 0.08, 0.12, -half_l * 0.46),
			Vector3(half_w + 0.08, 0.12, -half_l * 0.46),
			Vector3(-half_w - 0.08, 0.12, half_l * 0.46),
			Vector3(half_w + 0.08, 0.12, half_l * 0.46),
		]
		for i in 4:
			var pod := _frame_root.get_node_or_null("CornerPod%d" % i) as Node3D
			if pod != null:
				pod.position = corners[i]
	if _puff != null and _puff.process_material is ParticleProcessMaterial:
		var pm := (_puff.process_material as ParticleProcessMaterial).duplicate() as ParticleProcessMaterial
		pm.emission_box_extents = Vector3(_pad_width * 0.42, 0.08, _pad_length * 0.42)
		_puff.process_material = pm
	if _ambient_sparks != null and _ambient_sparks.process_material is ParticleProcessMaterial:
		var am := (_ambient_sparks.process_material as ParticleProcessMaterial).duplicate() as ParticleProcessMaterial
		am.emission_box_extents = Vector3(_pad_width * 0.44, 0.05, _pad_length * 0.42)
		_ambient_sparks.process_material = am


func _bind_visual_materials() -> void:
	if _visual != null and _visual.mesh != null:
		var mat: Material = _visual.get_active_material(0)
		if mat is ShaderMaterial:
			_aurora_mat = (mat as ShaderMaterial).duplicate() as ShaderMaterial
			_visual.set_surface_override_material(0, _aurora_mat)
			var raw: Variant = _aurora_mat.get_shader_parameter("intensity")
			if raw is float or raw is int:
				_base_intensity = float(raw)
		elif mat is StandardMaterial3D:
			_pad_mat = (mat as StandardMaterial3D).duplicate() as StandardMaterial3D
			_visual.set_surface_override_material(0, _pad_mat)
			_base_energy = _pad_mat.emission_energy_multiplier

	var wisp_names: Array[String] = [
		"WispLeftFront", "WispLeftBack", "WispRightFront", "WispRightBack",
		"WispLeft", "WispRight",
	]
	for wisp_name: String in wisp_names:
		var wisp := get_node_or_null(wisp_name) as MeshInstance3D
		if wisp == null or wisp.mesh == null:
			continue
		if _wisp_mat == null:
			var wmat: Material = wisp.get_active_material(0)
			if wmat is ShaderMaterial:
				_wisp_mat = (wmat as ShaderMaterial).duplicate() as ShaderMaterial
				var wraw: Variant = _wisp_mat.get_shader_parameter("intensity")
				if wraw is float or wraw is int:
					_base_wisp_intensity = float(wraw)
		if _wisp_mat != null:
			wisp.set_surface_override_material(0, _wisp_mat)


func _process(delta: float) -> void:
	if _surge_timer > 0.0:
		_surge_timer = maxf(_surge_timer - delta, 0.0)
		var t: float = _surge_timer / SURGE_DURATION
		var ease_t: float = t * t
		if _aurora_mat != null:
			_aurora_mat.set_shader_parameter("intensity",
				lerpf(_base_intensity, SURGE_INTENSITY, ease_t))
		if _wisp_mat != null:
			_wisp_mat.set_shader_parameter("intensity",
				lerpf(_base_wisp_intensity, SURGE_WISP_INTENSITY, ease_t))
	if _pad_mat != null:
		_time += delta
		var pulse: float = 1.0 + 0.25 * sin(_time * TAU * 1.5)
		_pad_mat.emission_energy_multiplier = _base_energy * pulse


## Cooldown-gated trigger: boosts a player or AI kart that implements
## on_boost_pad(speed), triggers the 0.45 s aurora surge flash, restarts the
## spark puff and plays pad_sound if present.
func _on_body_entered(body: Node3D) -> void:
	if not (body.is_in_group("player") or body.is_in_group("ai_player")):
		return
	if not body.has_method("on_boost_pad"):
		return
	# Per-kart cooldown: one car must not deny the pad to another car.
	var id: int = body.get_instance_id()
	var now_ms: int = Time.get_ticks_msec()
	if now_ms < int(_cooldowns.get(id, 0)):
		return
	_cooldowns[id] = now_ms + int(cooldown_seconds * 1000.0)
	body.call("on_boost_pad", burst_speed)
	_trigger_surge()
	if _puff != null:
		_puff.emitting = true
		_puff.restart()
	if _audio != null and pad_sound != null:
		_audio.stream = pad_sound
		_audio.play()


func _trigger_surge() -> void:
	_surge_timer = SURGE_DURATION
	if _aurora_mat != null:
		_aurora_mat.set_shader_parameter("intensity", SURGE_INTENSITY)
	if _wisp_mat != null:
		_wisp_mat.set_shader_parameter("intensity", SURGE_WISP_INTENSITY)


## Clears the cooldown, stops any lingering puff and restores idle intensity.
func reset_pad() -> void:
	_cooldowns.clear()
	_surge_timer = 0.0
	if _aurora_mat != null:
		_aurora_mat.set_shader_parameter("intensity", _base_intensity)
	if _wisp_mat != null:
		_wisp_mat.set_shader_parameter("intensity", _base_wisp_intensity)
	if _puff != null:
		_puff.emitting = false
