extends Node
## Web-only quality and memory profile.
##
## A browser tab renders at the window's native resolution, and on a HiDPI
## display the canvas is scaled by the device pixel ratio, which multiplies
## every render target's memory. Combined with MSAA and post-processing that is
## where the browser build's gigabytes go: the scene content itself is small
## (the race scene's engine heap is about 113 MB).
##
## Everything here is web-only. Desktop builds keep full quality.

const WEB_RENDER_SCALE: float = 0.8
const WEB_SHADOW_SIZE: int = 1024


func _ready() -> void:
	if not OS.has_feature("web"):
		return
	# Scenes are loaded after the autoload, so catch environments as they appear.
	if not get_tree().node_added.is_connected(_on_node_added):
		get_tree().node_added.connect(_on_node_added)
	_apply_viewport.call_deferred()
	_scan_environments.call_deferred()


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
	viewport.scaling_3d_mode = Viewport.SCALING_3D_MODE_BILINEAR
	viewport.scaling_3d_scale = WEB_RENDER_SCALE
	RenderingServer.directional_shadow_atlas_set_size(WEB_SHADOW_SIZE, false)
	print("WEB QUALITY: scale ", WEB_RENDER_SCALE, ", MSAA off, shadow atlas ",
		WEB_SHADOW_SIZE)


func _on_node_added(node: Node) -> void:
	if node is WorldEnvironment:
		_trim((node as WorldEnvironment).environment)


func _scan_environments() -> void:
	for node in get_tree().root.find_children("*", "WorldEnvironment", true, false):
		_trim((node as WorldEnvironment).environment)


func _trim(environment: Environment) -> void:
	if environment == null:
		return
	# Each of these allocates full-resolution buffers per frame. They are the
	# most expensive things a browser tab can be asked to do.
	environment.ssao_enabled = false
	environment.ssil_enabled = false
	environment.sdfgi_enabled = false
	environment.volumetric_fog_enabled = false
	environment.glow_enabled = false
	environment.screen_space_reflection_enabled = false
	if environment.fog_enabled:
		# Cheap depth fog stays: it hides the horizon and costs almost nothing.
		environment.fog_enabled = true
