class_name CartFeedback
extends Node3D

const SkidTrailScript := preload("res://scripts/feedback/skid_trail.gd")
const VehicleCatalog := preload("res://scripts/vehicles/vehicle_catalog.gd")
## Every catalog vehicle must leave a visible mark; flavor widths stay wider
## for heavier vehicles but never collapse to zero.
const MIN_SKID_WIDTH: float = 0.12
const MAX_SKID_WIDTH: float = 0.40
## Procedural tread styles authored in scripts/effects/skid_mark.gdshader.
const TREAD_SLICK: int = 0
const TREAD_STREET: int = 1
const TREAD_OFFROAD: int = 2
const TREAD_CASTER: int = 3
## Rubber tints are near-black per class; the surface palette supplies the rest.
const RUBBER_CART := Color(0.11, 0.10, 0.09)
const RUBBER_STREET := Color(0.065, 0.06, 0.055)
const RUBBER_HEAVY := Color(0.075, 0.065, 0.055)
const RUBBER_SPORT := Color(0.10, 0.075, 0.06)
const RUBBER_RACE := Color(0.05, 0.045, 0.04)
## Remote ghost ribbons. The state packet arrives at 20 Hz, so the slide flag
## is rebuilt at that rate and each ribbon samples at 30 Hz; the point buffers
## use the same 128-sample cap as an AI rival. One ribbon pair per ghost, with
## a hard budget for the worst real case - seven peer ghosts plus five
## relay-driven bot ghosts - so nothing can multiply mesh draw calls.
const REMOTE_SKID_INTERVAL: float = 0.05
const REMOTE_MAX_POINTS: int = 128
## Network.MAX_PLAYERS - 1 peers plus Network.MAX_BOT_COUNT relay bot ghosts.
const REMOTE_RIBBON_BUDGET: int = 12
## 3-Tier drift spark & boost flame palette (Tier 1 Cyan, Tier 2 Orange, Tier 3 Magenta).
const DRIFT_TIER_COLORS: Array[Color] = [
	Color("#38e8ff"),
	Color("#ff9f2e"),
	Color("#ff47d8"),
]
const MANUAL_BOOST_FLAME_COLOR: Color = Color(1.0, 0.52, 0.14, 0.84)
const SPARK_STREAK_PATH: String = "res://assets/textures/fx/spark_streak.png"
const CHIME_MIX_RATE: int = 22050
## 4-gear arcade transmission shift thresholds (hysteresis prevents shift chatter).
const GEAR_UPSHIFT_RATIOS: Array[float] = [0.24, 0.48, 0.74]
const GEAR_DOWNSHIFT_RATIOS: Array[float] = [0.17, 0.41, 0.67]
const GEAR_BAND_LOWS: Array[float] = [0.00, 0.15, 0.37, 0.61]
const GEAR_BAND_HIGHS: Array[float] = [0.26, 0.50, 0.76, 1.04]

const IMPACT_LIGHT_PATHS: PackedStringArray = [
	"res://assets/audio/sfx/impacts/metal_light_0.ogg",
	"res://assets/audio/sfx/impacts/metal_light_1.ogg",
	"res://assets/audio/sfx/impacts/impact_light.ogg",
	"res://assets/audio/sfx/impacts/impact_light_2.ogg",
	"res://assets/audio/sfx/impacts/impact_light_3.ogg",
	"res://assets/audio/sfx/impacts/impact_light_plate.ogg",
	"res://assets/audio/sfx/impacts/impact_light_tin.ogg",
]
const IMPACT_HEAVY_PATHS: PackedStringArray = [
	"res://assets/audio/sfx/impacts/metal_heavy_0.ogg",
	"res://assets/audio/sfx/impacts/metal_heavy_1.ogg",
	"res://assets/audio/sfx/impacts/impact_heavy.ogg",
	"res://assets/audio/sfx/impacts/impact_heavy_2.ogg",
	"res://assets/audio/sfx/impacts/impact_heavy_3.ogg",
	"res://assets/audio/sfx/impacts/impact_heavy_plate.ogg",
]
const CRASH_PATHS: PackedStringArray = [
	"res://assets/audio/sfx/impacts/metal_crash_0.ogg",
	"res://assets/audio/sfx/impacts/metal_crash_1.ogg",
	"res://assets/audio/sfx/impacts/crash_flip.ogg",
	"res://assets/audio/sfx/impacts/crash_glass_0.ogg",
	"res://assets/audio/sfx/impacts/crash_glass_1.ogg",
]
const LANDING_PATHS: PackedStringArray = [
	"res://assets/audio/sfx/landing/landing_soft.ogg",
	"res://assets/audio/sfx/landing/landing_thud.ogg",
]
const BOOST_PATHS: PackedStringArray = [
	"res://assets/audio/sfx/boost/boost_ignite.wav",
	"res://assets/audio/sfx/boost/boost_ignite_2.wav",
	"res://assets/audio/sfx/boost/boost_whoosh.wav",
	"res://assets/audio/sfx/boost/boost_start.ogg",
]
const DRIFT_CHIME_PATH: String = "res://assets/audio/sfx/fun/drift_chime.wav"
const HORN_PATH: String = "res://assets/audio/sfx/fun/horn.wav"
## Modular audiovisual feedback for the cart: smoke plumes,
## wind streaks and audio hooks. Reads cart state; impact/landing events
## are pushed in by the player script.

@export_group("Toggles")
@export var enable_dust: bool = true
@export var enable_speed_feedback: bool = true
@export var enable_collision_feedback: bool = true
@export var enable_audio: bool = true

@export_group("Smoke")
@export var smoke_intensity: float = 0.85 ## 0-1: density of drift smoke.
@export var smoke_lifetime: float = 1.4 ## Drift smoke lifetime (s).
@export var launch_dust_speed: float = 3.5 ## Only wisp below this speed when launching.
@export var landing_burst_strength: float = 1.0 ## 0-1 landing smoke burst strength.

@export_group("Speed Feedback")
@export var wind_speed_threshold: float = 12.0 ## Speed (m/s) where wind streaks start.
@export var wind_max_amount_ratio: float = 1.0 ## Max wind streak density (0-1).

@export_group("Audio")
@export var slide_sound_min_speed: float = 4.0 ## Minimum speed (m/s) for the skid sound.
@export var crash_sound_volume: float = 0.8 ## Crash sound volume (0-1 linear).

var dust_active: bool = false ## For the debug HUD.
var speed_feedback_active: bool = false ## For the debug HUD.
var missing_audio: Array[String] = [] ## Streams that could not be loaded (for the HUD/report).

var _cart: CartPlayer
var _mesh_root: Node3D
var _camera_rig: ChaseCamera
var _dust: GPUParticles3D
var _dust_burst: GPUParticles3D
var _wind: GPUParticles3D
var _boost_sparks: GPUParticles3D
var _launch_chips: GPUParticles3D
var _impact_sparks: GPUParticles3D
var _paint_chips: GPUParticles3D
var _camera: Camera3D
var _skid_trails: Array[Node3D] = []
var _drift_sparks: Array[GPUParticles3D] = []
var _drift_spark_mat: ParticleProcessMaterial
var _drift_spark_ramps: Array[GradientTexture1D] = []
var _active_spark_tier: int = 0
var _exhaust_pivot: Node3D
var _exhaust_nozzles: Array[Node3D] = []
var _exhaust_outer_mat: StandardMaterial3D
var _exhaust_inner_mat: StandardMaterial3D
var _exhaust_flame_blend: float = 0.0
var _fx_clock: float = 0.0
var _tier_chime_player: AudioStreamPlayer3D
var _has_engine: bool = true
var _loop_idle: bool = true
var _loop_base_pitch: float = 0.8
var _loop_pitch_span: float = 0.7
var _engine_gear: int = 1
var _engine_rpm: float = 0.15
var _shift_blip_timer: float = 0.0
var _skid_side_cached: float = 0.43
var _skid_back_cached: float = 0.55

@onready var _engine_audio: AudioStreamPlayer3D = $EngineAudio
@onready var _skid_audio: AudioStreamPlayer3D = $SkidAudio
@onready var _impact_audio: AudioStreamPlayer3D = $ImpactAudio
@onready var _thud_audio: AudioStreamPlayer3D = $ThudAudio
@onready var _impact_light_audio: AudioStreamPlayer3D = $ImpactLightAudio
@onready var _impact_heavy_audio: AudioStreamPlayer3D = $ImpactHeavyAudio
@onready var _crash_audio: AudioStreamPlayer3D = $CrashAudio
@onready var _boost_start_audio: AudioStreamPlayer3D = $BoostStartAudio
@onready var _boost_loop_audio: AudioStreamPlayer3D = $BoostLoopAudio
@onready var _drift_chime_audio: AudioStreamPlayer3D = $DriftChimeAudio
@onready var _horn_audio: AudioStreamPlayer3D = $HornAudio

## Time-based cooldowns. Ghost carts have physics disabled, so a per-frame
## float would never tick down for them.
var _horn_ready_ms: int = 0
var _chime_ready_ms: int = 0
## Remote ghost ribbon bookkeeping: rebuild clock and the shared ribbon budget.
var _remote_skid_timer: float = 0.0
var _remote_budget_owner: bool = false
## Which vehicle/mark profile is currently applied to the ribbons. A remote
## ghost learns its owner's vehicle after setup_remote(), so the profile is
## re-synced from the replicated cart state (no extra RPC) at the skid stream's
## own 20 Hz cadence.
var _profile_vehicle_id: String = ""
var _profile_paint_hex: String = ""
## Cached once: DisplayServer.get_name() allocates a String and the answer can
## never change while the process lives, so querying it in the per-frame exhaust
## update was pure per-frame garbage.
var _headless: bool = false
static var _remote_ribbon_owners: int = 0
static var _tier_chime_streams: Array[AudioStreamWAV] = []


func _ready() -> void:
	add_to_group("cart_feedback")
	_headless = DisplayServer.get_name() == "headless"
	_cart = get_parent() as CartPlayer
	if _cart != null:
		_mesh_root = _cart.get_node_or_null("MeshRoot") as Node3D
		_camera_rig = _cart.get_node_or_null("CameraArm") as ChaseCamera
	_dust = $Dust as GPUParticles3D
	_dust_burst = $DustBurst as GPUParticles3D
	_wind = $WindStreaks as GPUParticles3D
	if _wind != null:
		_wind.local_coords = true
	_boost_sparks = $BoostSparks as GPUParticles3D
	_launch_chips = $LaunchChips as GPUParticles3D
	_impact_sparks = $ImpactSparks as GPUParticles3D
	_paint_chips = $PaintChips as GPUParticles3D
	var vp: Viewport = get_viewport()
	_camera = vp.get_camera_3d() if vp != null else null
	# Spawn ribbons before the rival early-out. Every catalog vehicle - cart,
	# racing class, truck, van and the AI drivers of any of them - must mark.
	_spawn_skid_trails()
	if _cart != null and _cart.ai_mode:
		# Rivals need no audio streams or per-frame particle work. Their skid
		# ribbons stay: those only do work while the rival is actually sliding.
		enable_audio = false
		enable_dust = false
		enable_speed_feedback = false
		enable_collision_feedback = false
		set_process(false)
		set_physics_process(false)
		for particle: GPUParticles3D in [_dust, _dust_burst, _wind, _boost_sparks,
				_launch_chips, _impact_sparks, _paint_chips]:
			if particle != null:
				particle.emitting = false
				particle.visible = false
		return
	_spawn_drift_sparks()
	_spawn_exhaust_flames()
	_ensure_tier_chimes()
	_tier_chime_player = AudioStreamPlayer3D.new()
	_tier_chime_player.name = "TierChimeAudio"
	_tier_chime_player.bus = "SFX"
	_tier_chime_player.volume_db = -10.0
	add_child(_tier_chime_player)
	if _cart != null:
		if not _cart.drift_tier_reached.is_connected(_on_drift_tier_reached):
			_cart.drift_tier_reached.connect(_on_drift_tier_reached)
		if not _cart.drift_boost_fired.is_connected(_on_drift_boost_fired):
			_cart.drift_boost_fired.connect(_on_drift_boost_fired)
	_load_audio()
	set_process(true)


func _spawn_skid_trails() -> void:
	## ONE batched mark node per cart: it owns every wheel's ribbon and emits
	## them through a single ImmediateMesh surface, so a cart costs one cheap
	## transparent draw call instead of one per tyre. The per-vehicle width,
	## tread, rubber tint and wheel layout arrive in apply_vehicle_profile():
	## rivals and remote ghosts get the same profile, so their marks match.
	var is_ai: bool = _cart != null and _cart.ai_mode
	var trail: Node3D = SkidTrailScript.new()
	trail.cart = _cart
	if is_ai:
		trail.max_points = 128
		trail.fade_time = 4.5
		trail.sample_distance = 0.26
	add_child(trail)
	_skid_trails.append(trail)


func _spawn_drift_sparks() -> void:
	## Rear-wheel 3-tier colored drift spark emitters (Tier 1 Cyan #38e8ff,
	## Tier 2 Orange #ff9f2e, Tier 3 Magenta #ff47d8).
	_drift_spark_ramps.clear()
	for tier_color: Color in DRIFT_TIER_COLORS:
		var grad := Gradient.new()
		grad.offsets = PackedFloat32Array([0.0, 0.22, 0.72, 1.0])
		var hot_core: Color = Color(1.0, 1.0, 1.0, 1.0).lerp(tier_color, 0.35)
		var mid_col: Color = Color(tier_color.r, tier_color.g, tier_color.b, 0.95)
		var tail_col: Color = Color(tier_color.r, tier_color.g, tier_color.b, 0.0)
		grad.colors = PackedColorArray([hot_core, tier_color, mid_col, tail_col])
		var ramp := GradientTexture1D.new()
		ramp.gradient = grad
		_drift_spark_ramps.append(ramp)

	_drift_spark_mat = ParticleProcessMaterial.new()
	_drift_spark_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	_drift_spark_mat.emission_box_extents = Vector3(0.08, 0.03, 0.06)
	_drift_spark_mat.direction = Vector3(0.0, 0.36, 1.0)
	_drift_spark_mat.spread = 24.0
	_drift_spark_mat.initial_velocity_min = 5.4
	_drift_spark_mat.initial_velocity_max = 10.2
	_drift_spark_mat.gravity = Vector3(0.0, -11.0, 0.0)
	_drift_spark_mat.damping_min = 1.2
	_drift_spark_mat.damping_max = 2.4
	_drift_spark_mat.scale_min = 0.65
	_drift_spark_mat.scale_max = 1.15
	_drift_spark_mat.color_ramp = _drift_spark_ramps[0]

	var draw_mat := StandardMaterial3D.new()
	draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	draw_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	draw_mat.vertex_color_use_as_albedo = true
	draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_PARTICLES
	draw_mat.billboard_keep_scale = true
	draw_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if ResourceLoader.exists(SPARK_STREAK_PATH):
		draw_mat.albedo_texture = load(SPARK_STREAK_PATH) as Texture2D

	var spark_quad := QuadMesh.new()
	spark_quad.size = Vector2(0.09, 0.34)
	spark_quad.material = draw_mat

	for side: float in [-1.0, 1.0]:
		var emitter := GPUParticles3D.new()
		emitter.name = "DriftSparksL" if side < 0.0 else "DriftSparksR"
		emitter.position = Vector3(_skid_side_cached * side, 0.12, _skid_back_cached)
		emitter.amount = 36
		emitter.lifetime = 0.24
		emitter.emitting = false
		emitter.local_coords = false
		emitter.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		emitter.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 4, 8))
		emitter.process_material = _drift_spark_mat
		emitter.draw_pass_1 = spark_quad
		emitter.set_meta("wheel_side", side)
		add_child(emitter)
		_drift_sparks.append(emitter)

	# Sleek non-distracting Nitro Boost Ember Trail streaming behind nozzles during boost!
	var nitro_mat := ParticleProcessMaterial.new()
	nitro_mat.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	nitro_mat.emission_box_extents = Vector3(0.28, 0.06, 0.05)
	nitro_mat.direction = Vector3(0.0, 0.12, 1.0)
	nitro_mat.spread = 14.0
	nitro_mat.initial_velocity_min = 6.5
	nitro_mat.initial_velocity_max = 12.5
	nitro_mat.gravity = Vector3(0.0, 1.2, 0.0)
	nitro_mat.scale_min = 0.45
	nitro_mat.scale_max = 0.95
	var n_grad := Gradient.new()
	n_grad.offsets = PackedFloat32Array([0.0, 0.30, 1.0])
	n_grad.colors = PackedColorArray([Color(1.0, 0.98, 0.85, 0.90), Color(0.28, 0.90, 1.0, 0.72), Color(1.0, 0.48, 0.12, 0.0)])
	var n_ramp := GradientTexture1D.new()
	n_ramp.gradient = n_grad
	nitro_mat.color_ramp = n_ramp

	var nitro_quad := QuadMesh.new()
	nitro_quad.size = Vector2(0.08, 0.28)
	nitro_quad.material = draw_mat

	var nitro_trail := GPUParticles3D.new()
	nitro_trail.name = "NitroEmberTrail"
	nitro_trail.position = Vector3(0.0, 0.42, _skid_back_cached + 0.35)
	nitro_trail.amount = 28
	nitro_trail.lifetime = 0.26
	nitro_trail.emitting = false
	nitro_trail.local_coords = false
	nitro_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	nitro_trail.visibility_aabb = AABB(Vector3(-4, -1, -4), Vector3(8, 4, 8))
	nitro_trail.process_material = nitro_mat
	nitro_trail.draw_pass_1 = nitro_quad
	add_child(nitro_trail)
	set_meta("nitro_ember_trail", nitro_trail)


func _spawn_exhaust_flames() -> void:
	## Twin unshaded Boost Exhaust Flame Cones behind the rear axle.
	_exhaust_pivot = Node3D.new()
	_exhaust_pivot.name = "BoostExhaustFlames"
	_exhaust_pivot.visible = false
	add_child(_exhaust_pivot)

	_exhaust_outer_mat = StandardMaterial3D.new()
	_exhaust_outer_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_exhaust_outer_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_exhaust_outer_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_exhaust_outer_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_exhaust_outer_mat.albedo_color = MANUAL_BOOST_FLAME_COLOR

	_exhaust_inner_mat = StandardMaterial3D.new()
	_exhaust_inner_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	_exhaust_inner_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	_exhaust_inner_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_exhaust_inner_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	_exhaust_inner_mat.albedo_color = Color(0.90, 0.98, 1.0, 0.92)

	var outer_cone := CylinderMesh.new()
	outer_cone.top_radius = 0.0
	outer_cone.bottom_radius = 0.105
	outer_cone.height = 0.78
	outer_cone.radial_segments = 12
	outer_cone.rings = 1

	var inner_cone := CylinderMesh.new()
	inner_cone.top_radius = 0.0
	inner_cone.bottom_radius = 0.052
	inner_cone.height = 0.46
	inner_cone.radial_segments = 10
	inner_cone.rings = 1

	var nozzle_x: float = clampf(_skid_side_cached * 0.52, 0.18, 0.42)
	var nozzle_z: float = _skid_back_cached + 0.26
	for side: float in [-1.0, 1.0]:
		var nozzle := Node3D.new()
		nozzle.name = "FlameNozzleL" if side < 0.0 else "FlameNozzleR"
		nozzle.position = Vector3(nozzle_x * side, 0.22, nozzle_z)
		nozzle.set_meta("nozzle_side", side)

		var outer_mesh := MeshInstance3D.new()
		outer_mesh.mesh = outer_cone
		outer_mesh.material_override = _exhaust_outer_mat
		outer_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		outer_mesh.rotation.x = PI * 0.5
		outer_mesh.position.z = outer_cone.height * 0.5
		nozzle.add_child(outer_mesh)

		var inner_mesh := MeshInstance3D.new()
		inner_mesh.mesh = inner_cone
		inner_mesh.material_override = _exhaust_inner_mat
		inner_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		inner_mesh.rotation.x = PI * 0.5
		inner_mesh.position.z = inner_cone.height * 0.5
		nozzle.add_child(inner_mesh)

		_exhaust_pivot.add_child(nozzle)
		_exhaust_nozzles.append(nozzle)


static func _ensure_tier_chimes() -> void:
	if not _tier_chime_streams.is_empty():
		return
	# Rising synthesized chimes: Tier 1 (C5->G5), Tier 2 (E5->B5), Tier 3 (G5->B5->E6).
	var note_sets: Array[PackedFloat32Array] = [
		PackedFloat32Array([523.25, 783.99]),
		PackedFloat32Array([659.25, 987.77]),
		PackedFloat32Array([783.99, 987.77, 1318.51]),
	]
	var durations: PackedFloat32Array = PackedFloat32Array([0.13, 0.15, 0.19])
	for idx in note_sets.size():
		_tier_chime_streams.append(_synthesize_chime(note_sets[idx], durations[idx]))


static func _synthesize_chime(notes: PackedFloat32Array, duration: float) -> AudioStreamWAV:
	var sample_count: int = maxi(int(duration * float(CHIME_MIX_RATE)), 64)
	var bytes := PackedByteArray()
	bytes.resize(sample_count * 2)
	var note_count: int = maxi(notes.size(), 1)
	var phase: float = 0.0
	for i: int in sample_count:
		var norm_t: float = float(i) / float(sample_count)
		var note_idx: int = clampi(int(norm_t * float(note_count)), 0, note_count - 1)
		var local_t: float = norm_t * float(note_count) - float(note_idx)
		var freq: float = notes[note_idx]
		phase = fmod(phase + TAU * freq / float(CHIME_MIX_RATE), TAU)
		var attack: float = clampf(local_t / 0.08, 0.0, 1.0)
		var decay: float = exp(-3.4 * local_t) * (1.0 - norm_t * 0.35)
		var env: float = attack * decay
		var wave: float = sin(phase) * 0.68 + sin(phase * 2.0) * 0.22 + sin(phase * 3.0) * 0.10
		var sample_i16: int = clampi(int(wave * env * 18500.0), -32767, 32767)
		bytes.encode_s16(i * 2, sample_i16)
	var wav := AudioStreamWAV.new()
	wav.format = AudioStreamWAV.FORMAT_16_BITS
	wav.mix_rate = CHIME_MIX_RATE
	wav.stereo = false
	wav.loop_mode = AudioStreamWAV.LOOP_DISABLED
	wav.data = bytes
	return wav


func set_remote_mode(remote: bool) -> void:
	## A ghost cannot read local physics, but its owner's velocity already
	## travels in the ghost state packet. Keep the ribbons ticking and rebuild
	## the slide flag from that packet in _update_remote_skid(); audio, smoke
	## and wind stay off for a ghost.
	if remote:
		set_process(false)
		for spark: GPUParticles3D in _drift_sparks:
			if is_instance_valid(spark):
				spark.emitting = false
				spark.visible = false
		if _exhaust_pivot != null:
			_exhaust_pivot.visible = false
	if not remote:
		_release_remote_ribbons()
		set_physics_process(true)
		set_process(true)
		for spark: GPUParticles3D in _drift_sparks:
			if is_instance_valid(spark):
				spark.visible = true
		for trail: Node3D in _skid_trails:
			if is_instance_valid(trail):
				trail.call("set_remote", false, false)
		return
	if not _claim_remote_ribbons():
		set_physics_process(false)
		for trail: Node3D in _skid_trails:
			if is_instance_valid(trail):
				trail.call("set_remote", false, false)
				trail.set_physics_process(false)
		return
	set_physics_process(true)
	for trail: Node3D in _skid_trails:
		if is_instance_valid(trail):
			trail.call("set_remote", false, true)
			trail.set("max_points", REMOTE_MAX_POINTS)
			trail.set_physics_process(true)
	_refresh_remote_mark_profile()
	_remote_skid_timer = REMOTE_SKID_INTERVAL


func _claim_remote_ribbons() -> bool:
	## One ribbon pair per remote ghost. The budget is a safety net: the worst
	## real session (seven peer ghosts plus five relay bot ghosts) still fits,
	## so only a duplicated spawn or a stale peer is refused.
	if _remote_budget_owner:
		return true
	if _remote_ribbon_owners >= REMOTE_RIBBON_BUDGET:
		return false
	_remote_ribbon_owners += 1
	_remote_budget_owner = true
	return true


func _release_remote_ribbons() -> void:
	if not _remote_budget_owner:
		return
	_remote_budget_owner = false
	_remote_ribbon_owners = maxi(_remote_ribbon_owners - 1, 0)


func _exit_tree() -> void:
	# A ghost freed on a disconnect has to hand its ribbon slot back.
	_release_remote_ribbons()


func apply_vehicle_profile(entry: Dictionary) -> void:
	## Per-vehicle feel: smoke volume, skid width/track/tread and its own sound
	## loop. AI carts take the mark values too; their audio stays disabled. A
	## remote ghost re-runs this when its replicated vehicle arrives, so a peer's
	## truck marks like a truck on every client without a new RPC.
	if entry.is_empty():
		return
	var is_ai: bool = _cart != null and _cart.ai_mode
	var is_ghost: bool = _cart != null and _cart.remote_mode
	smoke_intensity = clampf(float(entry.get("smoke", smoke_intensity)), 0.05, 1.0)
	smoke_lifetime = 1.15 + smoke_intensity * 0.55
	_has_engine = bool(entry.get("has_engine", true))
	_loop_idle = bool(entry.get("loop_idle", _has_engine))
	_loop_base_pitch = float(entry.get("loop_pitch", 0.8))
	_loop_pitch_span = float(entry.get("loop_pitch_span", 0.7))
	if not is_ai and not is_ghost:
		var loop_sound: String = str(entry.get("loop_sound", ""))
		if loop_sound != "" and ResourceLoader.exists(loop_sound):
			_set_stream(_engine_audio, loop_sound, "")
			_loop_stream(_engine_audio.stream)
			if not _has_engine and _engine_audio != null:
				_engine_audio.stop()
	var side: float = float(entry.get("skid_side", 0.43))
	var back: float = float(entry.get("skid_back", 0.55))
	var track: float = maxf(float(entry.get("track", side * 2.0)), 0.5)
	var wheelbase: float = maxf(float(entry.get("wheelbase", back * 2.0)), 0.5)
	# The front axle sits forward of the origin; clamp it so a future catalogue
	# entry with a short wheelbase still places four distinct stripes.
	var front: float = -maxf(wheelbase - back, 0.30)
	_skid_side_cached = side
	_skid_back_cached = back
	var mark_width: float = _profile_skid_width(entry)
	var vehicle_id: String = str(entry.get("id", ""))
	var tread: int = _profile_tread_style(vehicle_id)
	var rubber: Color = _profile_rubber_color(vehicle_id)
	var flair: Color = _profile_flair_color(vehicle_id)
	_profile_vehicle_id = vehicle_id
	_profile_paint_hex = str(_cart.custom_paint_hex) if _cart != null else ""
	var wheel_offsets: Array[Vector3] = [
		Vector3(-track * 0.5, 0.0, front), Vector3(track * 0.5, 0.0, front),
		Vector3(-side, 0.0, back), Vector3(side, 0.0, back)]
	var drift_indices := PackedInt32Array([2, 3])
	for trail: Node3D in _skid_trails:
		if not is_instance_valid(trail):
			continue
		trail.call("set_wheels", wheel_offsets, drift_indices)
		trail.set("width", mark_width)
		trail.set("tread_style", tread)
		trail.set("mark_color", rubber)
		trail.set("flair_color", flair)
		trail.set("opacity", clampf(0.55 + smoke_intensity * 0.10, 0.58, 0.68))
	for spark: GPUParticles3D in _drift_sparks:
		if is_instance_valid(spark):
			var spark_side: float = float(spark.get_meta("wheel_side", 1.0))
			spark.position = Vector3(side * spark_side, 0.12, back)
	var nozzle_x: float = clampf(side * 0.52, 0.18, 0.42)
	var nozzle_y: float = 0.22
	var nozzle_z: float = back + 0.26
	var nozzle_pitch: float = 0.0
	var custom_tips: Array = []
	if _mesh_root != null and is_instance_valid(_mesh_root):
		for child: Node in _mesh_root.get_children():
			if child.has_meta("exhaust_nozzles"):
				custom_tips = child.get_meta("exhaust_nozzles") as Array
				break
	if custom_tips.size() >= 2:
		for idx in mini(_exhaust_nozzles.size(), 2):
			var nozzle: Node3D = _exhaust_nozzles[idx]
			if is_instance_valid(nozzle):
				nozzle.position = custom_tips[idx] as Vector3
				nozzle.rotation = Vector3(deg_to_rad(-6.0), 0.0, 0.0)
	else:
		var vid: String = str(entry.get("id", ""))
		if vid == "shopping_cart":
			var scale_k: float = float(entry.get("length", 1.8)) / 1.80
			nozzle_x = 0.24 * scale_k
			nozzle_y = 0.608 * scale_k
			nozzle_z = 0.985 * scale_k
			nozzle_pitch = deg_to_rad(-6.0)
		for nozzle: Node3D in _exhaust_nozzles:
			if is_instance_valid(nozzle):
				var nozzle_side: float = float(nozzle.get_meta("nozzle_side", 1.0))
				nozzle.position = Vector3(nozzle_x * nozzle_side, nozzle_y, nozzle_z)
				nozzle.rotation = Vector3(nozzle_pitch, 0.0, 0.0)
	# Seed the ground palette for carts that never run the feedback physics pass
	# (AI rivals keep it disabled); the local cart and ghosts refresh it per tick.
	_apply_surface_to_trails()


static func _profile_skid_width(entry: Dictionary) -> float:
	## The authored per-vehicle width is used when sane. A missing, zero or
	## non-finite value falls back to a share of the body width, and every
	## result is clamped so a save, a composed racing car or a future catalog
	## entry can never emit an invisible zero-width ribbon. The shopping cart's
	## authored 0.09 m is lifted to the visible floor; heavier vehicles keep
	## their wider marks.
	var mark_width: float = float(entry.get("skid_width", 0.0))
	if not is_finite(mark_width) or mark_width <= 0.0:
		mark_width = float(entry.get("width", 1.4)) * 0.16
	if not is_finite(mark_width) or mark_width <= 0.0:
		mark_width = MIN_SKID_WIDTH
	return clampf(mark_width, MIN_SKID_WIDTH, MAX_SKID_WIDTH)


static func _profile_tread_style(vehicle_id: String) -> int:
	## Per-vehicle tread identity, derived from the (read-only) catalogue id:
	## casters for the signature cart, chunky offroad blocks for the heavy vans
	## and truck, racing slicks for the sports car / PRO RACER, street tyres for
	## everything else. A missing or future id gets the street pattern.
	match vehicle_id:
		"shopping_cart":
			return TREAD_CASTER
		"van", "truck":
			return TREAD_OFFROAD
		"sports", "race_car":
			return TREAD_SLICK
		_:
			return TREAD_STREET


static func _profile_rubber_color(vehicle_id: String) -> Color:
	match vehicle_id:
		"shopping_cart":
			return RUBBER_CART
		"van", "truck":
			return RUBBER_HEAVY
		"sports":
			return RUBBER_SPORT
		"race_car":
			return RUBBER_RACE
		_:
			return RUBBER_STREET


func _profile_flair_color(vehicle_id: String) -> Color:
	## The PRO RACER picks up a whisper of its own paint in the tyre mark, so the
	## same chassis reads differently per player. Every other vehicle leaves bare
	## rubber (alpha 0 disables the blend in the ribbon).
	if vehicle_id != "race_car":
		return Color(0.0, 0.0, 0.0, 0.0)
	var hex: String = ""
	if _cart != null:
		hex = str(_cart.custom_paint_hex)
	if hex == "":
		hex = GameSettings.racer_color
	var color: Color = Color.from_string(hex, Color("e63946"))
	return Color(color.r, color.g, color.b, 0.6)


func _refresh_remote_mark_profile() -> void:
	## A remote ghost's owner streams its vehicle id and paint in the replicated
	## cart state (player_cart.set_vehicle_id runs after setup_remote), and the
	## ghost's own feedback node keeps the default profile until then. Re-sync at
	## the skid stream's 20 Hz cadence: a string compare per tick, no RPC.
	if _cart == null or not _cart.remote_mode:
		return
	var vehicle_id: String = str(_cart.get("_current_vehicle_id"))
	var paint_hex: String = str(_cart.get("custom_paint_hex"))
	if vehicle_id == "" or (vehicle_id == _profile_vehicle_id
			and paint_hex == _profile_paint_hex):
		return
	var entry: Dictionary = VehicleCatalog.find(vehicle_id)
	if not entry.is_empty():
		apply_vehicle_profile(entry)


func _resolve_surface_kind() -> String:
	## The modes write the exact TrackDefs grip multiplier onto the cart each
	## frame (0.45 ice, 0.80 wet, 0.86 dirt). A ghost is never written, so a grip
	## that is still the untouched 1.0 falls back to the scene's visual surface.
	var grip: float = 1.0
	if _cart != null and is_finite(_cart.surface_grip):
		grip = _cart.surface_grip
	if absf(grip - 0.45) < 0.06:
		return "ice"
	if absf(grip - 0.80) < 0.05:
		return "wet"
	if absf(grip - 0.86) < 0.05:
		return "dirt"
	return _scene_surface_fallback()


func _scene_surface_fallback() -> String:
	## Map-level mark palette, used on dry (grip 1.0) ground and for remote
	## ghosts. The arena modes use artificial floors, so they stay asphalt.
	var scene_path: String = ""
	var tree: SceneTree = get_tree()
	if tree != null and tree.current_scene != null:
		scene_path = tree.current_scene.scene_file_path
	if scene_path.ends_with("grass_race.tscn"):
		match str(GameSettings.selected_map):
			"glacier":
				return "snow"
			"canyon":
				return "sand"
			"meadow":
				return "dirt"
			_:
				return "normal"
	return "normal"


func _apply_surface_to_trails() -> void:
	var surface: String = _resolve_surface_kind()
	for trail: Node3D in _skid_trails:
		if is_instance_valid(trail):
			trail.set("surface_kind", surface)


func _load_audio() -> void:
	## Assign downloaded CC0 streams where present and fall back to the bundled
	## synthesized sounds; anything unavailable is logged, never fatal.
	for child in get_children():
		if child is AudioStreamPlayer3D:
			(child as AudioStreamPlayer3D).bus = "SFX"
	_set_stream($EngineAudio, "res://assets/audio/sfx/engine/engine_loop.wav", "res://assets/audio/engine_loop.wav")
	_set_stream($SkidAudio, "res://assets/audio/sfx/skid/skid_loop.wav", "res://assets/audio/skid_loop.wav")
	_set_stream($ImpactLightAudio, "res://assets/audio/sfx/impacts/impact_light.ogg", "res://assets/audio/impact.wav")
	_set_stream($ImpactHeavyAudio, "res://assets/audio/sfx/impacts/impact_heavy.ogg", "res://assets/audio/impact.wav")
	_set_stream($CrashAudio, "res://assets/audio/sfx/impacts/crash_flip.ogg", "res://assets/audio/impact.wav")
	_set_stream($ThudAudio, "res://assets/audio/sfx/landing/landing_thud.ogg", "res://assets/audio/landing_thud.wav")
	_set_stream($BoostStartAudio, "res://assets/audio/sfx/boost/boost_start.ogg", "")
	_set_stream($BoostLoopAudio, "res://assets/audio/sfx/engine/engine_boost.wav", "")
	_set_stream($DriftChimeAudio, DRIFT_CHIME_PATH, "")
	_set_stream($HornAudio, HORN_PATH, "")
	_loop_stream($EngineAudio.stream)
	_loop_stream($SkidAudio.stream)
	_loop_stream($BoostLoopAudio.stream)


func _set_stream(player: AudioStreamPlayer3D, primary: String, fallback: String) -> void:
	if player == null:
		return
	if ResourceLoader.exists(primary):
		player.stream = load(primary)
	elif fallback != "" and ResourceLoader.exists(fallback):
		player.stream = load(fallback)
	else:
		missing_audio.append(primary)
		push_warning("Missing audio: " + primary)


func _pick_stream(paths: PackedStringArray) -> AudioStream:
	## Random variation stops repeated wall/car hits sounding mechanical.
	var available: Array[String] = []
	for path: String in paths:
		if ResourceLoader.exists(path):
			available.append(path)
	if available.is_empty():
		return null
	return load(available[randi() % available.size()]) as AudioStream


func _loop_stream(stream: AudioStream) -> void:
	## WAV loop settings can be lost when a stream is imported with QOA
	## compression; force the loop at runtime so engines and skids never stop.
	if stream is AudioStreamWAV:
		var wav := stream as AudioStreamWAV
		wav.loop_mode = AudioStreamWAV.LOOP_FORWARD
		wav.loop_begin = 0
		# 0 can mean a zero-length loop on some imports; use the real frame
		# count so engines and skids never stop after one pass.
		wav.loop_end = maxi(int(wav.get_length() * wav.mix_rate), 1)


func _process(delta: float) -> void:
	if _cart == null or _cart.remote_mode or _cart.ai_mode:
		return
	_fx_clock += delta
	if _camera == null or not is_instance_valid(_camera):
		var vp: Viewport = get_viewport()
		_camera = vp.get_camera_3d() if vp != null else null
	if _wind != null and _camera != null:
		_wind.global_transform = _camera.global_transform
	_update_exhaust_flames(delta)


func _physics_process(delta: float) -> void:
	if _cart == null:
		return
	if _cart.remote_mode:
		_update_remote_skid(delta)
		return
	# A freed camera still compares unequal to null, so test validity too.
	if _camera == null or not is_instance_valid(_camera):
		var vp: Viewport = get_viewport()
		_camera = vp.get_camera_3d() if vp != null else null
	var speed: float = _cart.velocity.length()
	var grounded: bool = _cart.is_on_floor()
	var drifting: bool = _cart.is_drifting
	var handbraking: bool = _cart.is_handbraking()
	var throttle: float = _cart.get_throttle_input()
	var accelerating: bool = throttle > 0.05
	_apply_surface_to_trails()
	_update_smoke(speed, grounded, drifting, handbraking, accelerating)
	_update_speed_feedback(speed)
	_update_audio(delta, speed, grounded, drifting, handbraking, throttle)


func _update_remote_skid(delta: float) -> void:
	## Remote ghosts used to leave no marks: their body has no local physics, so
	## velocity, is_on_floor() and is_drifting are all empty. The ghost state
	## packet already carries the owner's velocity, so rebuild the bounded
	## lateral slip from it and let every ribbon know whether to mark. The slip
	## threshold is the cart's own drift_detection_threshold, so a ghost smears
	## exactly when its owner's local drift test would. The vehicle profile and
	## the surface palette are re-synced from the replicated cart state here too,
	## which is why remote marks need no new RPC.
	_refresh_remote_mark_profile()
	_apply_surface_to_trails()
	_remote_skid_timer += delta
	if _remote_skid_timer < REMOTE_SKID_INTERVAL:
		return
	_remote_skid_timer = 0.0
	# Prefer the ghost's placed heading; fall back to the yaw in the packet.
	var yaw: float = _cart.rotation.y
	if not is_finite(yaw):
		yaw = _cart.net_yaw
	var slide: Vector2 = Network.ghost_slide_state(yaw, _cart.net_velocity)
	var skidding: bool = Network.ghost_skid_active(
		slide, _cart.drift_detection_threshold)
	for trail: Node3D in _skid_trails:
		if is_instance_valid(trail):
			trail.call("set_remote", skidding, true)


func _update_smoke(speed: float, grounded: bool, drifting: bool, handbraking: bool, accelerating: bool) -> void:
	dust_active = false
	if _boost_sparks != null:
		# A short, soft spark trail only while the boost is actually firing.
		_boost_sparks.emitting = enable_dust and _cart != null and _cart.boost_active
	# 3-Tier Colored Drift Sparks at both rear wheels.
	var drift_tier: int = _cart.get_drift_tier() if _cart != null else 0
	var want_drift_sparks: bool = enable_dust and grounded \
		and (drifting or handbraking) and drift_tier >= 1
	if want_drift_sparks and _drift_spark_mat != null \
			and drift_tier <= _drift_spark_ramps.size():
		if _active_spark_tier != drift_tier:
			_active_spark_tier = drift_tier
			_drift_spark_mat.color_ramp = _drift_spark_ramps[drift_tier - 1]
			_drift_spark_mat.scale_min = 0.80 + float(drift_tier - 1) * 0.18
			_drift_spark_mat.scale_max = 1.30 + float(drift_tier - 1) * 0.25
		var spark_ratio: float = clampf(0.55 + float(drift_tier - 1) * 0.22, 0.55, 1.0)
		for spark: GPUParticles3D in _drift_sparks:
			if is_instance_valid(spark):
				spark.amount_ratio = spark_ratio
				spark.emitting = true
	else:
		_active_spark_tier = 0
		for spark: GPUParticles3D in _drift_sparks:
			if is_instance_valid(spark):
				spark.emitting = false
	if _launch_chips != null:
		var launch: bool = enable_dust and grounded and accelerating \
			and not drifting and not handbraking and speed < 6.0
		_launch_chips.emitting = launch
		if launch:
			_launch_chips.amount_ratio = clampf(1.0 - speed / 6.0, 0.18, 1.0)
	if _dust == null:
		return
	if not (enable_dust and grounded):
		_dust.emitting = false
		return
	if drifting or handbraking:
		dust_active = true
		_dust.emitting = true
		_dust.amount_ratio = clampf(smoke_intensity, 0.05, 1.0)
		_dust.lifetime = smoke_lifetime
	elif accelerating and speed < launch_dust_speed:
		dust_active = true
		_dust.emitting = true
		_dust.amount_ratio = clampf(smoke_intensity * 0.08, 0.02, 0.14)
		_dust.lifetime = smoke_lifetime * 0.55
	else:
		_dust.emitting = false


func _update_speed_feedback(speed: float) -> void:
	speed_feedback_active = false
	if _wind == null or _cart == null:
		return
	if _camera != null:
		_wind.global_transform = _camera.global_transform
	var top_threshold: float = maxf(_cart.max_speed * 0.85, wind_speed_threshold)
	var boosting_now: bool = _cart.boost_active
	if enable_speed_feedback and (boosting_now or speed > top_threshold):
		speed_feedback_active = true
		_wind.emitting = true
		var motion_scale: float = 0.35 if GameSettings.reduce_motion else 1.0
		var streak_ratio: float = 0.0
		if boosting_now:
			streak_ratio = clampf(0.72 + 0.28 * _cart.boost_visual, 0.5, 1.0)
		else:
			streak_ratio = clampf(
				(speed - top_threshold) / maxf(_cart.max_speed * 0.15, 1.0),
				0.22, 0.85)
		_wind.amount_ratio = clampf(
			streak_ratio * wind_max_amount_ratio * motion_scale, 0.15, 1.0)
	else:
		_wind.emitting = false


func _update_exhaust_flames(delta: float) -> void:
	if _exhaust_pivot == null or _cart == null:
		return
	if _mesh_root != null and is_instance_valid(_mesh_root):
		_exhaust_pivot.position = _mesh_root.position - Vector3(0.0, 0.32, 0.0)
		_exhaust_pivot.rotation = _mesh_root.rotation
	var want_flame: bool = enable_speed_feedback and _cart.boost_active
	var ember_trail: GPUParticles3D = get_meta("nitro_ember_trail", null) as GPUParticles3D
	if ember_trail != null and is_instance_valid(ember_trail):
		ember_trail.emitting = want_flame and not _headless
	var target_blend: float = 1.0 if want_flame else 0.0
	var rate: float = 22.0 if want_flame else 14.0
	_exhaust_flame_blend = lerpf(_exhaust_flame_blend, target_blend, 1.0 - exp(-rate * delta))
	if _exhaust_flame_blend < 0.04:
		_exhaust_pivot.visible = false
		return
	_exhaust_pivot.visible = true
	var active_tier: int = _cart.get_active_drift_boost_tier()
	var flame_col: Color = MANUAL_BOOST_FLAME_COLOR
	var tier_len_bonus: float = 1.0
	if active_tier >= 1 and active_tier <= DRIFT_TIER_COLORS.size():
		var tc: Color = DRIFT_TIER_COLORS[active_tier - 1]
		flame_col = Color(tc.r, tc.g, tc.b, 0.86)
		tier_len_bonus = 0.92 + float(active_tier) * 0.18
	if _exhaust_outer_mat != null:
		flame_col.a *= _exhaust_flame_blend
		_exhaust_outer_mat.albedo_color = flame_col
	if _exhaust_inner_mat != null:
		_exhaust_inner_mat.albedo_color = Color(0.90, 0.98, 1.0, 0.92 * _exhaust_flame_blend)
	for idx in _exhaust_nozzles.size():
		var nozzle: Node3D = _exhaust_nozzles[idx]
		if not is_instance_valid(nozzle):
			continue
		var phase_offset: float = float(idx) * 2.1
		var flicker_len: float = 1.0 + 0.20 * sin(_fx_clock * 47.0 + phase_offset) \
			+ 0.10 * cos(_fx_clock * 73.0 + phase_offset)
		var flicker_rad: float = 1.0 + 0.12 * cos(_fx_clock * 39.0 + phase_offset)
		var width_s: float = _exhaust_flame_blend * flicker_rad
		var len_s: float = _exhaust_flame_blend * flicker_len * tier_len_bonus
		nozzle.scale = Vector3(width_s, width_s, len_s)


func _update_audio(delta: float, speed: float, grounded: bool, drifting: bool,
		handbraking: bool, throttle: float) -> void:
	var sliding: bool = grounded and (drifting or handbraking) and speed > slide_sound_min_speed
	_shift_blip_timer = maxf(_shift_blip_timer - delta, 0.0)
	if _engine_audio != null:
		var want_loop: bool = enable_audio and _engine_audio.stream != null and (_loop_idle or speed > 0.4)
		if want_loop and not _engine_audio.playing:
			_engine_audio.play()
		_engine_audio.stream_paused = not want_loop
		if want_loop:
			var speed_ratio: float = clampf(speed / maxf(_cart.max_speed, 1.0), 0.0, 1.40)
			if _has_engine:
				# 4-gear arcade transmission with hysteresis, upshift blip and
				# drift wheelspin flare so engines rev and bark through the gears!
				var next_gear: int = _engine_gear
				while next_gear < 4 and speed_ratio >= GEAR_UPSHIFT_RATIOS[next_gear - 1]:
					next_gear += 1
				while next_gear > 1 and speed_ratio <= GEAR_DOWNSHIFT_RATIOS[next_gear - 2]:
					next_gear -= 1
				if next_gear > _engine_gear and (throttle > 0.05 or _cart.boost_active):
					_shift_blip_timer = 0.085
				_engine_gear = next_gear

				var g_idx: int = clampi(_engine_gear - 1, 0, 3)
				var low_r: float = GEAR_BAND_LOWS[g_idx]
				var high_r: float = GEAR_BAND_HIGHS[g_idx]
				var raw_gear_rpm: float = clampf(
					(speed_ratio - low_r) / maxf(high_r - low_r, 0.05), 0.0, 1.25)
				var load_flare: float = throttle * 0.08
				var wheelspin_flare: float = 0.0
				if grounded and (drifting or handbraking) and throttle > 0.08:
					wheelspin_flare = clampf(
						_cart.slide_amount * 0.28 + float(_cart.get_drift_tier()) * 0.05,
						0.0, 0.38) * throttle
				var target_rpm: float = clampf(
					0.12 + raw_gear_rpm * 0.88 + load_flare + wheelspin_flare, 0.10, 1.28)
				var rpm_rate: float = 18.0 if target_rpm > _engine_rpm else 11.0
				_engine_rpm = lerpf(_engine_rpm, target_rpm, 1.0 - exp(-rpm_rate * delta))

				var flutter: float = 0.0
				if _engine_rpm > 0.94 and (wheelspin_flare > 0.05 or _cart.boost_active):
					flutter = sin(float(Time.get_ticks_msec()) * 0.055) * 0.025
				var gear_register: float = float(g_idx) * (_loop_pitch_span * 0.13)
				var pitch: float = _loop_base_pitch + gear_register \
					+ (_engine_rpm + flutter) * (_loop_pitch_span * 0.78)
				var shift_vol_offset: float = 0.0
				if _shift_blip_timer > 0.0:
					if _shift_blip_timer > 0.050:
						pitch *= 0.91
						shift_vol_offset = -3.2
					else:
						pitch *= 1.06
						shift_vol_offset = 1.8
				pitch *= 1.0 + 0.15 * _cart.boost_visual
				_engine_audio.pitch_scale = clampf(pitch, 0.45, 2.55)
				_engine_audio.volume_db = clampf(
					-12.5 + _engine_rpm * 3.8 + throttle * 1.3 + shift_vol_offset,
					-18.0, -5.5)
			else:
				# Shopping Cart caster rattle: lively speed curve + drift wheelspin chatter.
				var spin_flare: float = _cart.slide_amount * 0.18 if sliding else 0.0
				var rattle_pitch: float = _loop_base_pitch \
					+ pow(clampf(speed_ratio, 0.0, 1.2), 0.85) * _loop_pitch_span \
					+ spin_flare
				_engine_audio.pitch_scale = clampf(
					rattle_pitch * (1.0 + 0.16 * _cart.boost_visual), 0.5, 2.4)
				_engine_audio.volume_db = lerpf(
					-32.0, -10.0, clampf(speed / 7.5 + spin_flare, 0.0, 1.0))
	if _skid_audio != null:
		var want_skid: bool = enable_audio and sliding and _skid_audio.stream != null
		if want_skid and not _skid_audio.playing:
			_skid_audio.play()
		_skid_audio.stream_paused = not want_skid
		_skid_audio.volume_db = lerpf(-18.0, -8.0, clampf(_cart.slide_amount, 0.0, 1.0))
	var boosting: bool = _cart.boost_active or _cart.boost_visual > 0.5
	if _boost_loop_audio != null:
		var want_boost_loop: bool = enable_audio and boosting and _boost_loop_audio.stream != null
		if want_boost_loop and not _boost_loop_audio.playing:
			_boost_loop_audio.play()
		_boost_loop_audio.stream_paused = not want_boost_loop


func on_collision(impact_factor: float) -> void:
	## Called by the player when hitting something solid: crash smoke + sound.
	if not enable_collision_feedback:
		return
	if _dust_burst != null and enable_dust:
		var smoke_scale: float = clampf(0.70 + smoke_intensity * 0.50, 0.70, 1.20)
		_dust_burst.amount_ratio = clampf((0.6 + impact_factor * 0.5) * smoke_scale, 0.25, 1.0)
		_dust_burst.restart()
	if _impact_sparks != null and enable_collision_feedback:
		_impact_sparks.amount_ratio = clampf(0.45 + impact_factor * 0.55, 0.3, 1.0)
		_impact_sparks.restart()
	if _paint_chips != null and enable_collision_feedback:
		_paint_chips.amount_ratio = clampf(0.35 + impact_factor * 0.65, 0.25, 1.0)
		_paint_chips.restart()
	var player: AudioStreamPlayer3D = _impact_heavy_audio if impact_factor > 0.55 else _impact_light_audio
	if player != null and player.stream == null:
		player = _impact_audio # Legacy synthesized fallback.
	if player != null and enable_audio:
		var paths: PackedStringArray = IMPACT_HEAVY_PATHS if impact_factor > 0.55 \
			else IMPACT_LIGHT_PATHS
		var stream: AudioStream = _pick_stream(paths)
		if stream != null:
			player.stream = stream
		if player.stream != null:
			player.pitch_scale = randf_range(0.92, 1.08)
			player.play()


func on_landing(fall_speed: float) -> void:
	## Called by the player on touchdown after a jump: landing puff + thud.
	## Gentle touchdowns use the soft tyre sound; a big drop gets the thud.
	if _dust_burst != null and enable_dust:
		var smoke_scale: float = clampf(0.70 + smoke_intensity * 0.50, 0.70, 1.20)
		_dust_burst.amount_ratio = clampf(landing_burst_strength * clampf(fall_speed * 0.12, 0.35, 1.0) * smoke_scale, 0.2, 1.0)
		_dust_burst.restart()
	if _thud_audio != null and enable_audio:
		var stream: AudioStream = _pick_stream(LANDING_PATHS)
		if stream != null:
			_thud_audio.stream = stream
		if _thud_audio.stream != null:
			_thud_audio.pitch_scale = randf_range(0.95, 1.05)
			_thud_audio.volume_db = clampf(-14.0 + fall_speed * 0.45, -14.0, -4.0)
			_thud_audio.play()


func on_crash(intensity: float) -> void:
	## Called by the player when it lands badly: heavy burst + crash sound.
	if not enable_collision_feedback:
		return
	if _dust_burst != null and enable_dust:
		_dust_burst.amount_ratio = 1.0
		_dust_burst.restart()
	if _crash_audio != null and enable_audio:
		var stream: AudioStream = _pick_stream(CRASH_PATHS)
		if stream != null:
			_crash_audio.stream = stream
		if _crash_audio.stream != null:
			_crash_audio.volume_db = linear_to_db(crash_sound_volume)
			_crash_audio.pitch_scale = randf_range(0.9, 1.05)
			_crash_audio.play()


func on_boost_started() -> void:
	## Called by the player on the rising edge of manual boost: FOV kick + ignite audio.
	if enable_speed_feedback and _camera_rig != null and is_instance_valid(_camera_rig):
		_camera_rig.punch_fov(4.5)
	if _boost_start_audio != null and enable_audio:
		var stream: AudioStream = _pick_stream(BOOST_PATHS)
		if stream != null:
			_boost_start_audio.stream = stream
		if _boost_start_audio.stream != null:
			_boost_start_audio.pitch_scale = randf_range(0.96, 1.05)
			_boost_start_audio.play()


func _on_drift_tier_reached(tier: int) -> void:
	## Synthesized rising tier-up chime on Tier 1, Tier 2 and Tier 3 charge thresholds.
	if not enable_audio or _tier_chime_player == null:
		return
	_ensure_tier_chimes()
	var idx: int = clampi(tier - 1, 0, _tier_chime_streams.size() - 1)
	if idx < 0 or idx >= _tier_chime_streams.size():
		return
	_tier_chime_player.stream = _tier_chime_streams[idx]
	_tier_chime_player.pitch_scale = 1.0
	_tier_chime_player.volume_db = -10.5 + float(idx) * 1.2
	_tier_chime_player.play()


func _on_drift_boost_fired(tier: int) -> void:
	## FOV punch + whoosh + reward chime scaled by mini-turbo tier (1..3).
	var clamped_tier: int = clampi(tier, 1, 3)
	if enable_speed_feedback and _camera_rig != null and is_instance_valid(_camera_rig):
		var fov_kick: float = 4.2 + float(clamped_tier - 1) * 2.3
		_camera_rig.punch_fov(fov_kick)
	if _boost_start_audio != null and enable_audio:
		var stream: AudioStream = _pick_stream(BOOST_PATHS)
		if stream != null:
			_boost_start_audio.stream = stream
		if _boost_start_audio.stream != null:
			_boost_start_audio.pitch_scale = 0.98 + float(clamped_tier - 1) * 0.08
			_boost_start_audio.play()
	on_drift_reward(float(clamped_tier))


func on_drift_reward(level: float = 1.0) -> void:
	## A small, bright chime when a drift releases its mini-turbo.
	var now: int = Time.get_ticks_msec()
	if not enable_audio or now < _chime_ready_ms:
		return
	if _drift_chime_audio != null and _drift_chime_audio.stream != null:
		_chime_ready_ms = now + 350
		_drift_chime_audio.pitch_scale = clampf(0.95 + level * 0.10, 0.9, 1.35)
		_drift_chime_audio.volume_db = -12.0
		_drift_chime_audio.play()


func on_horn() -> void:
	## Short, friendly honk. Rate-limited so holding the key cannot spam it.
	## Ghost carts keep enable_audio off to silence their engine loop, but a
	## remote horn is a one-shot and must still be heard by everyone.
	var now: int = Time.get_ticks_msec()
	if now < _horn_ready_ms:
		return
	if _horn_audio != null and _horn_audio.stream != null:
		_horn_ready_ms = now + 550
		_horn_audio.pitch_scale = randf_range(0.95, 1.05)
		_horn_audio.volume_db = -7.0
		_horn_audio.play()


func reset_feedback() -> void:
	## Clears every effect and audio state (used by the cart reset).
	if _dust != null:
		_dust.emitting = false
	if _dust_burst != null:
		_dust_burst.emitting = false
	if _wind != null:
		_wind.emitting = false
	if _boost_sparks != null:
		_boost_sparks.emitting = false
	for spark: GPUParticles3D in _drift_sparks:
		if is_instance_valid(spark):
			spark.emitting = false
	_active_spark_tier = 0
	_exhaust_flame_blend = 0.0
	if _exhaust_pivot != null:
		_exhaust_pivot.visible = false
	_engine_gear = 1
	_engine_rpm = 0.15
	_shift_blip_timer = 0.0
	for trail: Node3D in _skid_trails:
		if is_instance_valid(trail):
			trail.call("clear_trail")
	if _skid_audio != null:
		_skid_audio.stream_paused = true
	if _boost_loop_audio != null:
		_boost_loop_audio.stream_paused = true
	dust_active = false
	speed_feedback_active = false
