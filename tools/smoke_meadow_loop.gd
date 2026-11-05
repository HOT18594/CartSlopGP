extends SceneTree
## Headless validation for the MEADOW LOOP minigame.
##
## Run from godot_project/:
##   godot --headless --path . --script res://tools/smoke_meadow_loop.gd
##
## Builds the whole race scene, checks the generated geometry and foliage,
## then walks the kart around the spline three times to prove the lap counter,
## sector gates and finish overlay all fire.

const RACE_SCENE: String = "res://scenes/minigames/grass_race.tscn"

var _stats: Dictionary = {"instances": 0, "meshes": 0}
var _race: Node
var _checked: bool = false


func _initialize() -> void:
	print("--- MEADOW LOOP SMOKE ---")
	var packed: PackedScene = load(RACE_SCENE) as PackedScene
	if packed == null:
		print("FAIL  scene did not load")
		quit(1)
		return
	_race = packed.instantiate()
	root.add_child(_race)


func _process(_delta: float) -> bool:
	if _checked:
		return true
	_checked = true
	return _run_checks()


func _run_checks() -> bool:
	var spline: RefCounted = _race.get("_spline")
	if spline == null:
		print("FAIL  spline missing (scene _ready did not run?)")
		quit(1)
		return true
	print("spline length      %.1f m, %d samples" % [spline.total_length, spline.points.size()])
	if spline.total_length < 400.0 or spline.total_length > 650.0:
		print("FAIL  implausible track length")
		quit(1)
		return true

	_count_instances(_race)
	print("foliage instances  %d across %d multimeshes" % [
		int(_stats["instances"]), int(_stats["meshes"])])
	if int(_stats["instances"]) < 3000:
		print("FAIL  scenery is not dense enough")
		quit(1)
		return true

	var cart: Node3D = _race.get("_cart")
	if cart == null:
		print("FAIL  player cart missing")
		quit(1)
		return true

	# Walk the centreline for three laps. The controller is driven directly so
	# the test does not depend on real physics or input.
	_race.set("_phase", 1)
	cart.set("velocity", Vector3(0, 0, -20))
	var step: float = 1.2
	var total_steps: int = int(ceil(spline.total_length / step)) * 3 + 12
	for i in total_steps:
		var s: float = fmod(float(i) * step, spline.total_length)
		cart.global_position = spline.sample(s)["position"]
		_race.call("_tick_race", 0.06)

	var laps: int = int(_race.get("_lap"))
	var phase: int = int(_race.get("_phase"))
	var lap_times: Array = _race.get("_lap_times")
	print("laps completed     %d (recorded times: %d), phase=%d" % [
		laps - 1, lap_times.size(), phase])
	if lap_times.size() != 3 or phase != 2:
		print("FAIL  three laps did not finish the race")
		quit(1)
		return true
	var result_root: Control = _race.get("_result_root")
	if result_root == null or not result_root.visible:
		print("FAIL  result card not shown")
		quit(1)
		return true

	print("PASS  meadow loop builds and completes 3 laps")
	quit(0)
	return true


func _count_instances(node: Node) -> void:
	if node is MultiMeshInstance3D and node.multimesh != null:
		_stats["meshes"] = int(_stats["meshes"]) + 1
		_stats["instances"] = int(_stats["instances"]) + node.multimesh.instance_count
	for child in node.get_children():
		_count_instances(child)
