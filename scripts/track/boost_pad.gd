class_name BoostPad
extends Area3D
## Arcade boost pad: gives a player or AI kart a forward speed burst when it
## drives over the holographic aurora zone, triggering a crisp 0.45 s shader
## surge flash, a 24-spark particle burst and a spatial whoosh sound.

const PAD_SOUND: AudioStream = preload("res://assets/audio/sfx/boost/boost_pad.ogg")
const SURGE_DURATION: float = 0.45
const DEFAULT_INTENSITY: float = 1.9
const SURGE_INTENSITY: float = 3.0
const DEFAULT_WISP_INTENSITY: float = 0.52
const SURGE_WISP_INTENSITY: float = 0.95

@export var cooldown_seconds: float = 1.5 ## Seconds between activations per kart.
@export var burst_speed: float = 8.0 ## Forward speed burst (m/s) applied to the kart.
@export var pad_sound: AudioStream = PAD_SOUND ## One-shot whoosh when a kart hits the pad.

var _cooldowns: Dictionary = {}
var _time: float = 0.0
var _surge_timer: float = 0.0
var _base_intensity: float = DEFAULT_INTENSITY
var _base_wisp_intensity: float = DEFAULT_WISP_INTENSITY
var _base_energy: float = 2.0
var _visual: MeshInstance3D = null
var _puff: GPUParticles3D = null
var _audio: AudioStreamPlayer3D = null
var _aurora_mat: ShaderMaterial = null
var _wisp_mat: ShaderMaterial = null
var _pad_mat: StandardMaterial3D = null


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
