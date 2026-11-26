extends RefCounted
## Shared quality policy for the WS3 visual-effects layer.
##
## Every ambient emitter, menu overlay and tyre-mark ribbon asks this file how
## much it may spend. The answer is derived from three inputs the game already
## owns:
##
##   * `GameSettings.quality_preset` - PERFORMANCE / BALANCED / QUALITY.
##   * `GameSettings.reduce_motion`  - damps motion-heavy FX (speeds, counts).
##   * the Web build / the `CARTSLOP_FORCE_WEB_QUALITY=1` override - the same
##     condition `WebQuality` uses, so a browser tab is always treated as the
##     weakest target even though this file cannot depend on that autoload's
##     private state.
##
## Nothing here allocates per frame: the values are read once when an FX node is
## built and again only if the player changes a setting.

const QUALITY_PERFORMANCE: int = 0
const QUALITY_BALANCED: int = 1
const QUALITY_QUALITY: int = 2
const WEB_FEATURE: String = "web"
const FORCE_WEB_ENV: String = "CARTSLOP_FORCE_WEB_QUALITY"


static func _autoload(script_name: String) -> Node:
	## Autoload lookup without depending on the identifier (this file is also
	## loaded by headless probes, where a static reference could run before the
	## autoload is ready).
	var loop: MainLoop = Engine.get_main_loop()
	var tree: SceneTree = loop as SceneTree
	if tree == null or tree.root == null:
		return null
	return tree.root.get_node_or_null(script_name)


static func is_web() -> bool:
	## Browser export, or a desktop/headless run pretending to be one.
	return OS.has_feature(WEB_FEATURE) \
		or OS.get_environment(FORCE_WEB_ENV) == "1"


static func is_headless() -> bool:
	return DisplayServer.get_name() == "headless"


static func tier() -> int:
	## 0..2. Web always reports PERFORMANCE regardless of the saved preset: the
	## frame budget there is spent on pixels, not scene content.
	if is_web():
		return QUALITY_PERFORMANCE
	var settings: Node = _autoload("GameSettings")
	if settings == null:
		return QUALITY_BALANCED
	return clampi(int(settings.get("quality_preset")), QUALITY_PERFORMANCE,
		QUALITY_QUALITY)


static func reduce_motion() -> bool:
	var settings: Node = _autoload("GameSettings")
	if settings == null:
		return false
	return bool(settings.get("reduce_motion"))


static func density_scale() -> float:
	## Multiplier applied to a layer's designed particle amount.
	var scale: float = 1.0
	match tier():
		QUALITY_PERFORMANCE:
			scale = 0.62
		QUALITY_QUALITY:
			scale = 1.30
		_:
			scale = 1.0
	if is_web():
		scale *= 0.55
	if reduce_motion():
		scale *= 0.80
	return scale


static func motion_scale() -> float:
	## Multiplier for velocities / angular speeds. Reduced-motion players keep
	## the atmosphere but stop the fast lateral sweep.
	return 0.55 if reduce_motion() else 1.0


static func layer_budget() -> int:
	## Maximum simultaneous ambient emitter layers per world / menu overlay.
	## Web and the low preset fold detail layers away instead of thinning them.
	if is_web():
		return 2
	match tier():
		QUALITY_PERFORMANCE:
			return 2
		_:
			return 3


static func wants_detail_layer() -> bool:
	if is_web():
		return false
	return tier() >= QUALITY_BALANCED


static func wants_sparkle_layer() -> bool:
	if is_web():
		return false
	return tier() >= QUALITY_QUALITY


static func fixed_fps(base: int) -> int:
	## Particle simulation rate. 30 Hz halves the particle update cost and is
	## indistinguishable for slow ambient drift; fast weather keeps the base.
	if is_web():
		return mini(base, 30)
	if tier() == QUALITY_PERFORMANCE:
		return mini(base, 30)
	return base


static func description() -> String:
	return "tier=%d web=%s reduced_motion=%s density=%.2f" % [
		tier(), str(is_web()), str(reduce_motion()), density_scale()]
