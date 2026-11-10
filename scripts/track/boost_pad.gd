class_name BoostPad
extends Area3D
## Arcade boost pad: gives the player kart a forward speed burst when it
## drives over the pad, plus a one-shot particle puff and optional sound.
## All interaction with the kart is defensive (group + has_method checks).

const PAD_SOUND: AudioStream = preload("res://assets/audio/sfx/boost/boost_pad.ogg")

@export var cooldown_seconds: float = 1.5 ## Seconds between activations.
@export var burst_speed: float = 8.0 ## Forward speed burst (m/s) applied to the kart.
@export var pad_sound: AudioStream = PAD_SOUND ## One-shot whoosh when a kart hits the pad.

var _cooldowns: Dictionary = {}
var _time: float = 0.0
var _base_energy: float = 2.0
var _visual: MeshInstance3D = null
var _puff: GPUParticles3D = null
var _audio: AudioStreamPlayer3D = null
var _pad_mat: StandardMaterial3D = null


func _ready() -> void:
	add_to_group("boost_pad")
	if not body_entered.is_connected(_on_body_entered):
		body_entered.connect(_on_body_entered)
	_visual = get_node_or_null("Visual") as MeshInstance3D
	_puff = get_node_or_null("Puff") as GPUParticles3D
	_audio = get_node_or_null("PadAudio") as AudioStreamPlayer3D
	if _audio != null:
		_audio.bus = "SFX"
	if _visual != null and _visual.mesh != null:
		var mat: Material = _visual.get_surface_override_material(0)
		if mat is StandardMaterial3D:
			_pad_mat = mat.duplicate() as StandardMaterial3D
			_visual.set_surface_override_material(0, _pad_mat)
			_base_energy = _pad_mat.emission_energy_multiplier


func _process(delta: float) -> void:
	_time += delta
	if _pad_mat != null:
		var pulse: float = 1.0 + 0.25 * sin(_time * TAU * 1.5)
		_pad_mat.emission_energy_multiplier = _base_energy * pulse


## Cooldown-gated trigger: boosts a player or AI cart that implements
## on_boost_pad(speed), then restarts the puff and plays pad_sound if present.
func _on_body_entered(body: Node3D) -> void:
	if not (body.is_in_group("player") or body.is_in_group("ai_player")):
		return
	if not body.has_method("on_boost_pad"):
		return
	# Per-cart cooldown: one car must not deny the pad to another car.
	var id: int = body.get_instance_id()
	var now_ms: int = Time.get_ticks_msec()
	if now_ms < int(_cooldowns.get(id, 0)):
		return
	_cooldowns[id] = now_ms + int(cooldown_seconds * 1000.0)
	body.call("on_boost_pad", burst_speed)
	if _puff != null:
		_puff.emitting = true
		_puff.restart()
	if _audio != null and pad_sound != null:
		_audio.stream = pad_sound
		_audio.play()


## Clears the cooldown and stops any lingering puff; the track calls this when
## the kart resets (e.g. get_tree().call_group("boost_pad", "reset_pad")).
func reset_pad() -> void:
	_cooldowns.clear()
	if _puff != null:
		_puff.emitting = false
