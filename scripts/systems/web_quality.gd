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
## 2.0.0 additions, both still web-only:
##  * `Engine.max_physics_steps_per_frame` is capped so a stalled tab (GC,
##    shader compile, backgrounded tab) drops simulation time instead of
##    replaying it in one frame and freezing for several frames.
##  * A very large browser window (above 2560x1440) renders at a 1920x1080
##    internal resolution and upscales, because the 2D HUD and menus would
##    otherwise fill 8 M pixels per frame on an integrated GPU. Windowed and
##    laptop-size browsers keep their native canvas.
##
## 2.1.0 low-spec tier (the "Web Low-Spec" path):
##  * The web profile now has two budgets. `balanced` is the 2.0.0 profile
##    (65 % 3D scale, 60 fps). `low` halves the 3D fill again (50 % scale),
##    caps at 30 fps, shortens the far plane/fog, caps physics catch-up at 3
##    steps, turns anisotropic filtering off and, above 1920x1080, renders the
##    canvas at 1600x900. It is selected explicitly with
##    `CARTSLOP_WEB_QUALITY=low`, or automatically on a browser whose hardware
##    reports at most 4 logical cores, at most 4 GB device memory, a coarse
##    primary pointer (phone/tablet) or a mobile user agent.
##  * The existing FX quality tier already reports PERFORMANCE to every web FX
##    producer (`scripts/effects/fx_quality.gd` forces web to the performance
##    tier, 0.55x particle density, 2 ambient layers, 30 Hz particle sim), so
##    the low tier does not need to edit the effects layer to cap particles.
##  * `CARTSLOP_WEB_MEM_TRACE=1` adds a line per scene root and per freed scene
##    root with object count and static memory, so a scene-swap leak in a browser
##    test run shows up as a climbing number instead of a hunch. It is off by
##    default and costs one comparison per node.
##
## Everything in this file is web-only. Desktop builds keep full quality: the
## whole thing returns at once when the `web` feature is absent (unless the
## force override is set for a headless verification run).
##
## Verification without a browser: set CARTSLOP_FORCE_WEB_QUALITY=1 to apply the
## same profile to a desktop or headless run, and CARTSLOP_WEB_QUALITY=low to
## exercise the low tier, e.g.
##     CARTSLOP_FORCE_WEB_QUALITY=1 CARTSLOP_WEB_QUALITY=low godot --headless --path godot_project

## Feature tag only the web export sets.
const WEB_FEATURE: String = "web"
## Development override, so the profile can be exercised head-less.
const FORCE_ENV: String = "CARTSLOP_FORCE_WEB_QUALITY"
## Tier selector: "balanced" (default) or "low". An unknown value falls back to
## auto-detection instead of failing.
const TIER_ENV: String = "CARTSLOP_WEB_QUALITY"
const TIER_LOW: String = "low"
const TIER_BALANCED: String = "balanced"
## Memory-trace switch (see the docstring); off in production.
const MEM_TRACE_ENV: String = "CARTSLOP_WEB_MEM_TRACE"

## 3D-only render scale. The HUD and the menus stay at the canvas resolution,
## so gameplay text keeps its edges while the world gets cheap.
const WEB_RENDER_SCALE: float = 0.65
## Low tier: half the linear resolution, a quarter of the pixels. At 1280x720
## that is a 640x360 internal 3D buffer upscaled by the GPU.
const LOW_RENDER_SCALE: float = 0.5
## A 144 Hz panel asks requestAnimationFrame for 144 frames a second and every
## one of them costs the same as a 60 Hz frame.
const WEB_MAX_FPS: int = 60
## Low tier: 30 fps gives a weak integrated GPU twice the frame time. The game
## is still playable (fixed 60 Hz physics keeps handling identical); browsers
## that can afford 60 keep it because "balanced" is the default.
const LOW_MAX_FPS: int = 30
## Shutdown/restore hint for the resolution cap below (see
## `_apply_canvas_budget`). 2560x1440 keeps a maximised 1440p window native;
## only a 4K-class window is capped, because otherwise the 2D HUD alone fills
## 8.3 M pixels per frame on an integrated GPU.
const WEB_MAX_CANVAS_PIXELS: int = 2560 * 1440
## Internal resolution a capped browser window renders at: 1920x1080 is exactly
## half of 3840x2160 (a clean 2x integer upscale) and the other layout size the
## UI audit already validates, so the anchored UI needs no change.
const WEB_INTERNAL_SIZE := Vector2i(1920, 1080)
## Low tier caps anything above 1080p at 1600x900 (below the native layout
## target, so the UI still scales cleanly; only 1440p/4K windows are affected).
const LOW_MAX_CANVAS_PIXELS: int = 1920 * 1080
const LOW_INTERNAL_SIZE := Vector2i(1600, 900)
## Physics catch-up cap. The engine default is 8 steps per frame; a browser tab
## that stalls (shader compile, GC, tab switch) can otherwise try to replay a
## long wall-clock gap in one frame and freeze the frame instead of dropping
## time. Four steps = 66 ms of simulation per frame, enough to absorb a hitch
## without turning it into a multi-frame stall.
const WEB_MAX_PHYSICS_STEPS: int = 4
## Low tier: three steps (50 ms) because a low-end tab is more likely to stall
## for longer, and dropping simulation time is cheaper than replaying it.
const LOW_MAX_PHYSICS_STEPS: int = 3
## Shadows are off on web (see `_disable_shadows`); the atlas still exists at
## this size so nothing reallocates when a light with shadows does appear.
const WEB_SHADOW_ATLAS: int = 256
const LOW_SHADOW_ATLAS: int = 128
## Cameras stop drawing here. The meadow's forest, landmarks and mountains sit
## further out, but the fog below closes over them first, so the cut is not
## visible from the chase camera.
const WEB_FAR_PLANE: float = 420.0
const LOW_FAR_PLANE: float = 340.0
## Depth fog ends just inside the far plane: the cull boundary is hidden in
## haze instead of popping trees in and out.
const WEB_FOG_END: float = 380.0
const LOW_FOG_END: float = 300.0
## Fog starts a little closer than the desktop value; the near field stays crisp.
const WEB_FOG_BEGIN: float = 45.0
const LOW_FOG_BEGIN: float = 40.0
## Exponential fog has no end distance, so it gets a density floor instead.
const WEB_FOG_DENSITY: float = 0.0035
const LOW_FOG_DENSITY: float = 0.0045

var _active: bool = false
var _low_tier: bool = false
var _mem_trace: bool = false
var _apply_pending: bool = false
var _last_scene: Node = null


func _ready() -> void:
	_active = OS.has_feature(WEB_FEATURE) \
		or OS.get_environment(FORCE_ENV) == "1"
	if not _active:
		return
	_low_tier = _select_low_tier()
	_mem_trace = OS.get_environment(MEM_TRACE_ENV) == "1"
	Engine.max_fps = LOW_MAX_FPS if _low_tier else WEB_MAX_FPS
	Engine.max_physics_steps_per_frame = LOW_MAX_PHYSICS_STEPS if _low_tier \
		else WEB_MAX_PHYSICS_STEPS
	# Scenes and their lights are created after the autoload, so catch them as
	# they appear instead of polling for them.
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)
	# The render scale lives in GameSettings; re-own it whenever it changes.
	if not GameSettings.changed.is_connected(_on_settings_changed):
		GameSettings.changed.connect(_on_settings_changed)
	# A browser window can be resized after load (maximise, fullscreen, 4K
	# display); re-evaluate the canvas budget instead of only at boot.
	var window: Window = get_window()
	if window != null and not window.size_changed.is_connected(
			_on_window_size_changed):
		window.size_changed.connect(_on_window_size_changed)
	_queue_apply()
	# The boot scene is already in the tree and will never raise node_added.
	_sweep.call_deferred()


func _select_low_tier() -> bool:
	## Explicit env wins, then hardware probing on a real browser. On a
	## desktop/headless forced-web run without the env, stay balanced so the
	## profile stays reproducible.
	var requested: String = OS.get_environment(TIER_ENV).strip_edges().to_lower()
	if requested == TIER_LOW:
		return true
	if requested == TIER_BALANCED:
		return false
	if not OS.has_feature(WEB_FEATURE):
		return false
	return _browser_is_weak()


func _browser_is_weak() -> bool:
	## Conservative browser hardware probe. Everything is wrapped: a browser
	## without deviceMemory/maxTouchPoints simply reports its core count. The
	## singleton is looked up through Engine so a desktop build that never
	## registers a JavaScript bridge can still parse this file.
	if OS.get_processor_count() <= 4:
		return true
	var bridge: Object = Engine.get_singleton("JavaScriptBridge")
	if bridge == null:
		return false
	var probe: Variant = bridge.call("eval",
		"(function(){try{"
		+ "var m=navigator.deviceMemory||0;"
		+ "var coarse=window.matchMedia&&window.matchMedia('(pointer: coarse)').matches;"
		+ "var mobi=/Mobi|Android|iPhone|iPad/i.test(navigator.userAgent||'');"
		+ "return (m>0&&m<=4)||coarse||mobi;"
		+ "}catch(e){return false;}})()", true)
	if probe is bool:
		return probe
	return false


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
	_apply_canvas_budget()
	_silence_governor()


func _render_scale() -> float:
	return LOW_RENDER_SCALE if _low_tier else WEB_RENDER_SCALE


func _far_plane() -> float:
	return LOW_FAR_PLANE if _low_tier else WEB_FAR_PLANE


func _fog_begin() -> float:
	return LOW_FOG_BEGIN if _low_tier else WEB_FOG_BEGIN


func _fog_end() -> float:
	return LOW_FOG_END if _low_tier else WEB_FOG_END


func _fog_density() -> float:
	return LOW_FOG_DENSITY if _low_tier else WEB_FOG_DENSITY


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
	viewport.scaling_3d_scale = _render_scale()
	RenderingServer.directional_shadow_atlas_set_size(
		LOW_SHADOW_ATLAS if _low_tier else WEB_SHADOW_ATLAS, false)
	if _low_tier:
		# Texture quality: anisotropic filtering multiplies the texture samples
		# per pixel on every tilted surface (the whole track). The low tier
		# renders at 50 %, where the difference is invisible, so force it off
		# for the whole 3D pass. (Godot 4.7 exposes this per viewport; there is
		# no RenderingServer force-anisotropic toggle, so set the enum here.)
		viewport.anisotropic_filtering_level = Viewport.ANISOTROPY_DISABLED
	print("WEB QUALITY: tier ", TIER_LOW if _low_tier else TIER_BALANCED,
		", scale ", _render_scale(), ", fps cap ",
		LOW_MAX_FPS if _low_tier else WEB_MAX_FPS,
		", physics steps ", Engine.max_physics_steps_per_frame,
		", MSAA off, shadows off, far plane ", _far_plane())


func _apply_canvas_budget() -> void:
	## Bound the fill rate on a very large browser window. The project stretches
	## with canvas_items, so without this the HUD, the menus and the 3D viewport
	## all render at the browser window's resolution: a maximised 4K window is
	## 8.3 M pixels per frame before the 3D scale even applies, and the
	## integrated GPU most web players have cannot fill that at 60 fps.
	## At or below the budget nothing changes, so ordinary windows and laptops
	## keep their native crispness. The low tier caps at 1080p instead of 1440p.
	var window: Window = get_window()
	if window == null or not is_instance_valid(window):
		return
	var size: Vector2i = window.size
	if size.x <= 0 or size.y <= 0:
		return
	var max_pixels: int = LOW_MAX_CANVAS_PIXELS if _low_tier \
		else WEB_MAX_CANVAS_PIXELS
	var internal_size: Vector2i = LOW_INTERNAL_SIZE if _low_tier \
		else WEB_INTERNAL_SIZE
	if size.x * size.y <= max_pixels:
		# Restore the project's own stretch mode after a shrink (for example
		# leaving fullscreen on a 4K panel).
		if window.content_scale_mode != Window.CONTENT_SCALE_MODE_CANVAS_ITEMS:
			window.content_scale_mode = Window.CONTENT_SCALE_MODE_CANVAS_ITEMS
			window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
		return
	if window.content_scale_mode == Window.CONTENT_SCALE_MODE_VIEWPORT:
		return
	window.content_scale_mode = Window.CONTENT_SCALE_MODE_VIEWPORT
	window.content_scale_size = internal_size
	window.content_scale_aspect = Window.CONTENT_SCALE_ASPECT_EXPAND
	print("WEB QUALITY: canvas ", size, " capped to ", internal_size,
		" (huge browser window)")


func _on_window_size_changed() -> void:
	if _active:
		_apply_canvas_budget()


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
		if _mem_trace:
			_trace_scene_swap(node)
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


# --- Scene-swap memory trace (CARTSLOP_WEB_MEM_TRACE=1) --------------------


func _trace_scene_swap(next_scene: Node) -> void:
	## Scene swaps are where a browser build leaks: the outgoing root is freed,
	## and a resource held by a stray signal/await keeps its images alive in the
	## WASM heap. Printing object count + static memory per swap makes that
	## visible in a normal test log: a number that climbs every swap is the bug.
	var previous: Node = _last_scene
	if previous != null and is_instance_valid(previous) and previous != next_scene:
		# The outgoing root frees itself after this frame; bind its name as a
		# String because reading a property off the freed instance later would
		# be an invalid access. The print is deferred so the counters are
		# post-teardown.
		previous.tree_exited.connect(_on_scene_freed.bind(str(previous.name)),
			CONNECT_ONE_SHOT)
	_last_scene = next_scene
	_print_mem("enter " + next_scene.name)


func _on_scene_freed(previous_name: String) -> void:
	_print_mem.call_deferred("freed " + previous_name)


func _print_mem(label: String) -> void:
	print("WEB MEM: ", label, " objects=",
		Performance.get_monitor(Performance.OBJECT_COUNT),
		" static_mb=", snappedf(
			Performance.get_monitor(Performance.MEMORY_STATIC) / 1048576.0, 0.1),
		" resources=", Performance.get_monitor(Performance.OBJECT_RESOURCE_COUNT))


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
			_fog_begin())
		environment.fog_depth_end = minf(environment.fog_depth_end,
			_fog_end())
	else:
		# Exponential fog ignores the end distance, so raise the density until
		# the far plane is lost in haze.
		environment.fog_density = maxf(environment.fog_density,
			_fog_density())


func _disable_shadows(light: Light3D) -> void:
	## No shadow map is rendered on web. The sun keeps its colour and energy, so
	## the scene reads as flat, bright cartoon shading rather than going dark,
	## and the track, curbs, gates and karts stay told apart by their albedo.
	## These run deferred from node_added, so the node may already be freed by a
	## scene swap in the same frame: a freed instance compares false against
	## null, so only is_instance_valid() may gate the property write.
	if not is_instance_valid(light) or not _active or not light.shadow_enabled:
		return
	light.shadow_enabled = false


func _clip_camera(camera: Camera3D) -> void:
	## Deferred from node_added; same freed-instance contract as above.
	if not is_instance_valid(camera) or not _active \
			or camera.far <= _far_plane():
		return
	camera.far = _far_plane()
