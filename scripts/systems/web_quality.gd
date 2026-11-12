extends Node
## Web-only quality profile, driven by the `WebQuality` autoload.
##
## A browser tab is the weakest target this game ships to: WebGL2 only, no
## compute, a driver that copies anything it is asked to allocate, and often a
## single-board computer behind the cable. The frame budget there is spent on
## pixels and on render targets, not on scene content: the race scene's engine
## heap is only about 113 MB, but it draws 447 calls over 611k primitives and
## every one of those fills a buffer the driver has to clear.
##
## Two things make this harder than setting a few project options:
##
## 1. The gameplay scenes re-assert their own look in `_ready`.
##    `grass_race.gd` turns 2x MSAA and FXAA back on, `meadow_lobby.gd` turns
##    2x MSAA back on, and `visual_grade.gd` turns the sun's shadow map back on.
##    Setting a value once at boot is therefore not enough: the profile is
##    re-applied (deferred, so it lands *after* every `_ready`) for each node
##    that publishes these settings and for every new scene root.
## 2. `GameSettings` raises the 3D render scale from its dynamic-resolution
##    governor. That governor only picks values between 0.85 and the preset
##    ceiling, so on web it would immediately undo the scale chosen here.
##
## The first scene is already inside the tree before this autoload's `_ready`,
## so its nodes never raise `node_added`; it is swept once instead. Everything
## loaded afterwards is caught as it appears.
##
## Everything in this file is web-only. Desktop builds keep full quality: the
## whole thing returns at once when the `web` feature is absent.
##
## Verification without a browser: set CARTSLOP_FORCE_WEB_QUALITY=1 to apply the
## same profile to a desktop or headless run, e.g.
##     CARTSLOP_FORCE_WEB_QUALITY=1 godot --headless --path godot_project

## Feature tag only the web export sets.
const WEB_FEATURE: String = "web"
## Development override, so the profile can be exercised head-less.
const FORCE_ENV: String = "CARTSLOP_FORCE_WEB_QUALITY"

## 3D-only render scale. The HUD and the menus stay at the canvas resolution,
## so gameplay text keeps its edges while the world gets cheap.
const WEB_RENDER_SCALE: float = 0.65
## A 144 Hz panel asks requestAnimationFrame for 144 frames a second and every
## one of them costs the same as a 60 Hz frame.
const WEB_MAX_FPS: int = 60
## Shadows are off on web (see `_disable_shadows`); the atlas still exists at
## this size so nothing reallocates when a light with shadows does appear.
const WEB_SHADOW_ATLAS: int = 256
## Cameras stop drawing here. The meadow's forest, landmarks and mountains sit
## further out, but the fog below closes over them first, so the cut is not
## visible from the chase camera.
const WEB_FAR_PLANE: float = 420.0
## Depth fog ends just inside the far plane: the cull boundary is hidden in
## haze instead of popping trees in and out.
const WEB_FOG_END: float = 380.0
## Fog starts a little closer than the desktop value; the near field stays crisp.
const WEB_FOG_BEGIN: float = 45.0
## Exponential fog has no end distance, so it gets a density floor instead.
const WEB_FOG_DENSITY: float = 0.0035

var _active: bool = false
var _apply_pending: bool = false


func _ready() -> void:
	_active = OS.has_feature(WEB_FEATURE) \
		or OS.get_environment(FORCE_ENV) == "1"
	if not _active:
		return
	Engine.max_fps = WEB_MAX_FPS
	# Scenes and their lights are created after the autoload, so catch them as
	# they appear instead of polling for them.
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)
	# The render scale lives in GameSettings; re-own it whenever it changes.
	if not GameSettings.changed.is_connected(_on_settings_changed):
		GameSettings.changed.connect(_on_settings_changed)
	_queue_apply()
	# The boot scene is already in the tree and will never raise node_added.
	_sweep.call_deferred()


# --- Applying the profile --------------------------------------------------


func _queue_apply() -> void:
	## One deferred sweep per frame at most: several nodes can ask for it while
	## a scene is loading, and each request would otherwise repeat the work.
	if _apply_pending:
		return
	_apply_pending = true
	_apply.call_deferred()


func _apply() -> void:
	_apply_pending = false
	if not _active or not is_inside_tree():
		return
	_apply_viewport()
	_silence_governor()


func _apply_viewport() -> void:
	var viewport: Viewport = get_viewport()
	if viewport == null:
		return
	# MSAA multiplies every colour and depth target; off is the single biggest
	# saving and barely visible at this render scale.
	viewport.msaa_3d = Viewport.MSAA_DISABLED
	viewport.msaa_2d = Viewport.MSAA_DISABLED
	viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_DISABLED
	viewport.use_taa = false
	viewport.use_debanding = false
	# A 2D HDR buffer is a second full-resolution target that this game's flat
	# cartoon UI does not need.
	viewport.use_hdr_2d = false
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = WEB_RENDER_SCALE
	RenderingServer.directional_shadow_atlas_set_size(WEB_SHADOW_ATLAS, false)
	print("WEB QUALITY: scale ", WEB_RENDER_SCALE, ", fps cap ", WEB_MAX_FPS,
		", MSAA off, shadows off, far plane ", WEB_FAR_PLANE)


func _silence_governor() -> void:
	## Written straight to the property: `apply_quality()` is not called and no
	## signal fires, so this cannot loop back into `_on_settings_changed`.
	if GameSettings.dynamic_resolution:
		GameSettings.dynamic_resolution = false


func _on_settings_changed() -> void:
	## A quality preset change re-applies the preset's scale, so take it back.
	_queue_apply()


# --- Per-node trims --------------------------------------------------------


func _on_node_added(node: Node) -> void:
	if not _active:
		return
	if node.get_parent() == get_tree().root:
		# A scene root. Its `_ready` (and every child's) runs before a deferred
		# call, so this lands after the scene has configured itself.
		_queue_apply()
	if node is WorldEnvironment:
		_trim.call_deferred((node as WorldEnvironment).environment)
	elif node is Light3D:
		_disable_shadows.call_deferred(node as Light3D)
	elif node is Camera3D:
		_clip_camera.call_deferred(node as Camera3D)


func _sweep() -> void:
	## Trim everything already in the tree. Exactly three full walks, once per
	## boot, because the boot scene predates this autoload's `node_added`.
	var root: Node = get_tree().root
	for node in root.find_children("*", "WorldEnvironment", true, false):
		_trim((node as WorldEnvironment).environment)
	for node in root.find_children("*", "Light3D", true, false):
		_disable_shadows(node as Light3D)
	for node in root.find_children("*", "Camera3D", true, false):
		_clip_camera(node as Camera3D)


func _trim(environment: Environment) -> void:
	if environment == null or not _active:
		return
	# Each of these allocates full-resolution buffers per frame, or a compute
	# chain the Compatibility renderer cannot run anyway.
	environment.ssao_enabled = false
	environment.ssil_enabled = false
	environment.sdfgi_enabled = false
	environment.volumetric_fog_enabled = false
	environment.glow_enabled = false
	environment.ssr_enabled = false
	# The sky stays: one prefiltered cubemap draw, and `visual_grade.gd` pins
	# `fog_sky_affect` to 0 so it keeps its colour.
	if not environment.fog_enabled:
		return
	if environment.fog_mode == Environment.FOG_MODE_DEPTH:
		environment.fog_depth_begin = minf(environment.fog_depth_begin,
			WEB_FOG_BEGIN)
		environment.fog_depth_end = minf(environment.fog_depth_end, WEB_FOG_END)
	else:
		# Exponential fog ignores the end distance, so raise the density until
		# the far plane is lost in haze.
		environment.fog_density = maxf(environment.fog_density, WEB_FOG_DENSITY)


func _disable_shadows(light: Light3D) -> void:
	## No shadow map is rendered on web. The sun keeps its colour and energy, so
	## the scene reads as flat, bright cartoon shading rather than going dark,
	## and the track, curbs, gates and karts stay told apart by their albedo.
	if light == null or not _active or not light.shadow_enabled:
		return
	light.shadow_enabled = false


func _clip_camera(camera: Camera3D) -> void:
	if camera == null or not _active or camera.far <= WEB_FAR_PLANE:
		return
	camera.far = WEB_FAR_PLANE
