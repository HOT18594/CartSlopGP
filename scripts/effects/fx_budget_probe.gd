extends SceneTree
## Headless FX budget probe (WS3 visual-effects workstream).
##
## Boots the real menu and every registered race map headlessly, waits for the
## scene to finish dressing itself, then counts the GPU particle nodes, live
## particle amounts and draw-passes in the scene and inside the AmbientWorld FX
## subtree. Nothing renders in headless, so these are the budgets a real frame
## would ask the renderer for - node, instance and particle counts - not a
## timing benchmark.
##
## Run with:
##   Godot_v4.7.2-stable_win64_console.exe --headless --path godot_project \
##       --script res://scripts/effects/fx_budget_probe.gd
##
## Exit code = number of budget failures. Each printed FXBUDGET line is one
## measured scope, so the before/after table in
## `_audit/reports/ws3-fx-audio.md` can be rebuilt from the output.

const RACE_SCENE: String = "res://scenes/minigames/grass_race.tscn"
const MENU_SCENE: String = "res://scenes/ui/main_menu.tscn"
const AmbientParticles := preload("res://scripts/effects/ambient_particles.gd")
## Which scene to boot. One scene per process: freeing several fully built race
## scenes inside one process makes unrelated autoload teardown code emit a
## "cast a freed object" burst that has nothing to do with FX. The runner
## (see the report) launches one process per scope and collects the lines.
const SCOPE_ENV: String = "CARTSLOP_FX_SCOPE"
## The five race maps from track_defs.gd, in garage order.
const RACE_MAPS: PackedStringArray = ["stadium", "meadow", "canyon", "dockyard", "glacier"]
## The dry-ground palette each map's marks must fall back to (surface_grip 1.0).
const EXPECTED_MAP_SURFACE: Dictionary = {
	"stadium": "normal", "meadow": "dirt", "canyon": "sand",
	"dockyard": "normal", "glacier": "snow",
}
const CART_SCENE: String = "res://scenes/player/cart_player.tscn"
## Settle time: enough for the race scene to build its world and for the FX
## layer to construct its emitters, without waiting for a HUD update.
const SETTLE_SECONDS: float = 0.8
## Budgets for the FX this workstream owns. AmbientWorld is one themed FX node
## per map; the menu backdrop is a 2D overlay. Whole-scene counts are printed as
## context but are not gated here because other workstreams own the karts,
## boost pads and scenery draw calls.
const MAX_AMBIENT_NODES: int = 10
const MAX_AMBIENT_AMOUNT: int = 900
const MAX_AMBIENT_DRAWS: int = 8
const MAX_MENU_PARTICLE_NODES: int = 4
const MAX_MENU_PARTICLE_AMOUNT: int = 160
## Whole-scene ceilings are deliberately loose: they only catch an explosion
## (a per-frame node spawn bug), not the tuning of one kart emitter.
const MAX_SCENE_PARTICLE_NODES: int = 140
const MAX_SCENE_PARTICLE_AMOUNT: int = 4000

var _failures: int = 0
## Wall time of the last `add_child()`; the scene builders run their static
## build path synchronously there, so this is a usable map-build number.
var last_build_ms: int = 0


func _initialize() -> void:
	_run.call_deferred()


func _check(condition: bool, message: String) -> void:
	if condition:
		return
	_failures += 1
	print("FXBUDGET_FAIL %s" % message)


func _run() -> void:
	# Autoloads finish their own _ready inside the first frames; the map pick is
	# read by the race scene from GameSettings, so wait for that first.
	await process_frame
	await process_frame
	_check_biome_table()
	var scope: String = OS.get_environment(SCOPE_ENV).strip_edges()
	if scope == "":
		print("FXBUDGET: no %s set; biome budgets checked only. "
			% SCOPE_ENV + "Set it to 'menu' or a map id for a scene measurement.")
	elif scope == "menu":
		await _measure_menu()
	elif RACE_MAPS.has(scope):
		await _measure_race(scope)
	else:
		_check(false, "unknown scope '%s' (menu or %s)" % [scope,
			", ".join(RACE_MAPS)])
	print("FXBUDGET: %d budget failure(s)" % _failures)
	print("FXBUDGET: %s" % ("PASS" if _failures == 0 else "FAIL"))
	quit(0 if _failures == 0 else _failures)


# --------------------------------------------------------------------------
# pure budget table (every biome x quality tier x platform)
# --------------------------------------------------------------------------


func _check_biome_table() -> void:
	## The quality tiers decide the layer count and density before a single node
	## is built, so this table can assert every platform combination headlessly
	## even when only one scene is booted per process.
	var checked: int = 0
	for biome: String in AmbientParticles.biome_ids():
		var balanced: Dictionary = AmbientParticles.describe(biome, 1, false)
		var web: Dictionary = AmbientParticles.describe(biome, 0, true)
		var quality: Dictionary = AmbientParticles.describe(biome, 2, false)
		var reduced: Dictionary = AmbientParticles.describe(biome, 1, false, true)
		var balanced_amount: int = int(balanced["amount"])
		var web_amount: int = int(web["amount"])
		var quality_amount: int = int(quality["amount"])
		var reduced_amount: int = int(reduced["amount"])
		_check(int(balanced["layers"]) >= 2,
			"%s: balanced needs at least 2 layers" % biome)
		_check(int(web["layers"]) <= 2,
			"%s: web must stay at 2 layers" % biome)
		_check(int(quality["layers"]) >= int(balanced["layers"]),
			"%s: quality has fewer layers than balanced" % biome)
		_check(web_amount < balanced_amount,
			"%s: web density (%d) is not below balanced (%d)"
			% [biome, web_amount, balanced_amount])
		_check(reduced_amount <= balanced_amount,
			"%s: reduced-motion density grew (%d > %d)"
			% [biome, reduced_amount, balanced_amount])
		_check(quality_amount >= balanced_amount,
			"%s: quality density is not higher" % biome)
		_check(int(balanced["amount"]) <= MAX_AMBIENT_AMOUNT,
			"%s: designed amount %d exceeds the budget %d"
			% [biome, int(balanced["amount"]), MAX_AMBIENT_AMOUNT])
		print("FXBUDGET biome=%s balanced=%d(%.1f layers) quality=%d(%.1f) web=%d(%.1f) reduced=%d"
			% [biome, balanced_amount, float(balanced["layers"]),
			quality_amount, float(quality["layers"]),
			web_amount, float(web["layers"]), reduced_amount])
		checked += 1
	_check(checked == AmbientParticles.biome_ids().size(),
		"biome table covered %d palettes" % checked)
	print("FXBUDGET biome-table: %d palettes x 3 tiers x web/reduced checked" % checked)


# --------------------------------------------------------------------------
# scopes
# --------------------------------------------------------------------------


func _measure_menu() -> void:
	var scene: Node = await _boot(MENU_SCENE)
	if scene == null:
		_check(false, "menu: scene did not instantiate")
		return
	var menu_counts: Dictionary = _count_tree(scene)
	print("FXBUDGET scope=menu %s" % _format(menu_counts))
	_check(int(menu_counts.get("particle_nodes", 0)) <= MAX_MENU_PARTICLE_NODES,
		"menu: %d particle nodes (max %d)"
		% [int(menu_counts.get("particle_nodes", 0)), MAX_MENU_PARTICLE_NODES])
	_check(int(menu_counts.get("particle_amount", 0)) <= MAX_MENU_PARTICLE_AMOUNT,
		"menu: %d particles (max %d)"
		% [int(menu_counts.get("particle_amount", 0)), MAX_MENU_PARTICLE_AMOUNT])
	# Deliberately not freed: one scope per process, and quitting with the scene
	# still in the tree is the teardown path the regular map tests use.


func _measure_race(map_id: String) -> void:
	var settings: Node = root.get_node_or_null("GameSettings")
	if settings != null:
		settings.set("selected_map", map_id)
	var scene: Node = await _boot(RACE_SCENE)
	if scene == null:
		_check(false, "%s: race scene did not instantiate" % map_id)
		return
	var ambient: Node = scene.find_child("AmbientWorld", true, false)
	var ambient_counts: Dictionary = _count_tree(ambient) if ambient != null else {}
	var scene_counts: Dictionary = _count_tree(scene)
	print("FXBUDGET scope=%s ambient %s" % [map_id, _format(ambient_counts)])
	print("FXBUDGET scope=%s scene %s build_ms=%d" % [map_id,
		_format(scene_counts), last_build_ms])
	var fx_stats: Dictionary = {}
	if ambient != null and ambient.has_method("get_fx_stats"):
		fx_stats = ambient.call("get_fx_stats") as Dictionary
	if not fx_stats.is_empty():
		print("FXBUDGET scope=%s stats biome=%s quality=%s web=%s layers=%d settled_mark_trails=%d"
			% [map_id, str(fx_stats.get("biome", "?")),
			str(fx_stats.get("quality", "?")), str(fx_stats.get("web", false)),
			int(fx_stats.get("layers", 0)),
			int(fx_stats.get("skid_trails", 0))])
	_check(ambient_counts.has("particle_nodes"), "%s: no AmbientWorld found" % map_id)
	var nodes: int = int(ambient_counts.get("particle_nodes", 0))
	var amount: int = int(ambient_counts.get("particle_amount", 0))
	var draws: int = int(ambient_counts.get("particle_draws", 0))
	_check(nodes <= MAX_AMBIENT_NODES, "%s: %d ambient particle nodes (max %d)"
		% [map_id, nodes, MAX_AMBIENT_NODES])
	_check(amount <= MAX_AMBIENT_AMOUNT, "%s: %d ambient particles (max %d)"
		% [map_id, amount, MAX_AMBIENT_AMOUNT])
	_check(draws <= MAX_AMBIENT_DRAWS, "%s: %d ambient draw passes (max %d)"
		% [map_id, draws, MAX_AMBIENT_DRAWS])
	_check(int(scene_counts.get("particle_nodes", 0)) <= MAX_SCENE_PARTICLE_NODES,
		"%s: %d scene particle nodes (max %d)"
		% [map_id, int(scene_counts.get("particle_nodes", 0)),
		MAX_SCENE_PARTICLE_NODES])
	_check(int(scene_counts.get("particle_amount", 0)) <= MAX_SCENE_PARTICLE_AMOUNT,
		"%s: %d scene particles (max %d)"
		% [map_id, int(scene_counts.get("particle_amount", 0)),
		MAX_SCENE_PARTICLE_AMOUNT])
	var skid_trails: int = get_nodes_in_group("skid_trails").size()
	print("FXBUDGET scope=%s skid_trails=%d" % [map_id, skid_trails])
	await _probe_remote_marks(map_id)


func _probe_remote_marks(map_id: String) -> void:
	## Proves the multiplayer claim headlessly: a ghost cart is placed from
	## replicated state packets only (set_net_state), with no RPC and no local
	## physics velocity, and its own feedback layer must produce a truck-treaded
	## mark ribbon tinted for this map's surface. This is the same path a remote
	## peer uses in a real race.
	var packed: PackedScene = load(CART_SCENE) as PackedScene
	if packed == null:
		_check(false, "remote: cart scene missing")
		return
	var rig := Node3D.new()
	rig.name = "RemoteMarkProbe"
	root.add_child(rig)
	var ground := StaticBody3D.new()
	ground.name = "Ground"
	ground.collision_layer = 1
	ground.collision_mask = 0
	var box := BoxShape3D.new()
	box.size = Vector3(140.0, 1.0, 140.0)
	var collision := CollisionShape3D.new()
	collision.shape = box
	ground.add_child(collision)
	ground.position = Vector3(0.0, -0.5, 0.0)
	rig.add_child(ground)
	var ghost: Node = packed.instantiate()
	if ghost == null:
		_check(false, "remote: cart scene did not instantiate")
		rig.queue_free()
		return
	ghost.position = Vector3(0.0, 0.35, 0.0)
	rig.add_child(ghost)
	await physics_frame
	await physics_frame
	ghost.call("setup_remote", 99)
	ghost.call("set_vehicle_id", "truck", "2979ff")
	await physics_frame
	# 20 Hz replicated slide: the ghost's owner is moving sideways at 7 m/s.
	var simulated: Vector3 = ghost.global_position
	for step in 60:
		await physics_frame
		simulated += Vector3(0.35, 0.0, 0.15)
		ghost.call("set_net_state", simulated, 0.0, Time.get_ticks_msec(),
			Vector3(7.0, 0.0, 3.0))
	var feedback: Node = ghost.get_node_or_null("Feedback")
	_check(feedback != null, "remote: feedback node missing")
	if feedback == null:
		rig.queue_free()
		await physics_frame
		return
	var trails: Array = feedback.get("_skid_trails")
	_check(trails.size() == 1,
		"remote: %d mark nodes (expected 1 batched)" % trails.size())
	if trails.is_empty():
		rig.queue_free()
		await physics_frame
		return
	var trail: Node3D = trails[0]
	_check(bool(trail.get("remote_ghost")), "remote: ribbon not in ghost mode")
	_check(int(trail.get("tread_style")) == 2,
		"remote: truck tread style %d (expected offroad 2)"
		% int(trail.get("tread_style")))
	var mark_width: float = float(trail.get("width"))
	_check(absf(mark_width - 0.30) < 0.02,
		"remote: truck mark width %.3f (catalogue 0.30)" % mark_width)
	var expected_surface: String = str(EXPECTED_MAP_SURFACE.get(map_id, "normal"))
	_check(str(trail.get("surface_kind")) == expected_surface,
		"remote: surface '%s' (expected %s for %s)"
		% [str(trail.get("surface_kind")), expected_surface, map_id])
	var counts: PackedInt32Array = trail.get("_count")
	var samples: int = samples_of(counts)
	_check(samples >= 4,
		"remote: only %d mark sample(s) from the replicated slide" % samples)
	print("FXBUDGET remote_marks map=%s nodes=%d tread=%d width=%.2f surface=%s samples=%d"
		% [map_id, trails.size(), int(trail.get("tread_style")),
		mark_width, str(trail.get("surface_kind")), samples])
	rig.queue_free()
	await physics_frame
	await physics_frame


func _boot(scene_path: String) -> Node:
	if not ResourceLoader.exists(scene_path):
		return null
	var packed: PackedScene = load(scene_path) as PackedScene
	if packed == null:
		return null
	var scene: Node = packed.instantiate()
	if scene == null:
		return null
	var build_usec: int = Time.get_ticks_usec()
	root.add_child(scene)
	last_build_ms = int((Time.get_ticks_usec() - build_usec) / 1000)
	current_scene = scene
	var frames: int = maxi(int(SETTLE_SECONDS * 60.0), 2)
	for _frame in frames:
		await process_frame
	return scene


# --------------------------------------------------------------------------
# counting
# --------------------------------------------------------------------------


func _count_tree(node: Node) -> Dictionary:
	var counts: Dictionary = {
		"nodes": 0, "particle_nodes": 0, "particle_amount": 0,
		"particle_draws": 0, "meshes": 0, "multimeshes": 0, "mesh_draws": 0,
		"gpu_particles": 0, "cpu_particles": 0,
	}
	if node == null:
		return counts
	_collect(node, counts)
	return counts


func _collect(node: Node, counts: Dictionary) -> void:
	counts["nodes"] = int(counts["nodes"]) + 1
	if node is GPUParticles3D:
		_count_gpu_particles(node as GPUParticles3D, counts)
	elif node is CPUParticles2D or node is CPUParticles3D:
		var cpu_amount: int = 0
		if node is CPUParticles2D:
			cpu_amount = (node as CPUParticles2D).amount
			counts["cpu_particles"] = int(counts["cpu_particles"]) + 1
		else:
			cpu_amount = (node as CPUParticles3D).amount
			counts["cpu_particles"] = int(counts["cpu_particles"]) + 1
		counts["particle_nodes"] = int(counts["particle_nodes"]) + 1
		counts["particle_amount"] = int(counts["particle_amount"]) + cpu_amount
		counts["particle_draws"] = int(counts["particle_draws"]) + 1
	elif node is MultiMeshInstance3D:
		var mm := node as MultiMeshInstance3D
		counts["multimeshes"] = int(counts["multimeshes"]) + 1
		var surfaces: int = 1
		if mm.multimesh != null and mm.multimesh.mesh != null:
			surfaces = mm.multimesh.mesh.get_surface_count()
			if mm.multimesh.instance_count <= 0 or not mm.visible:
				surfaces = 0
		counts["mesh_draws"] = int(counts["mesh_draws"]) + surfaces
	elif node is MeshInstance3D:
		# Importer-only helper meshes are cheap but still a draw each, so count
		# only visible instances with a mesh.
		var mi := node as MeshInstance3D
		counts["meshes"] = int(counts["meshes"]) + 1
		if mi.mesh != null and mi.is_visible_in_tree():
			counts["mesh_draws"] = int(counts["mesh_draws"]) + mi.mesh.get_surface_count()
	for child: Node in node.get_children():
		_collect(child, counts)


func _count_gpu_particles(particles: GPUParticles3D, counts: Dictionary) -> void:
	counts["gpu_particles"] = int(counts["gpu_particles"]) + 1
	counts["particle_nodes"] = int(counts["particle_nodes"]) + 1
	# A node that is not emitting and has no live particles asks the renderer
	# for nothing, so only bill emitting systems.
	var live: bool = particles.emitting or particles.one_shot
	counts["particle_amount"] = int(counts["particle_amount"]) \
		+ (particles.amount if live else 0)
	# Read only the draw passes that exist. `draw_pass_2/3/4` getters call
	# get_draw_pass_mesh(p_pass) and log "Index p_pass is out of bounds" for every
	# unused pass (freed slots read back as null), which used to flood the probe
	# log with engine errors on every scene.
	var passes: int = 0
	for pass_index in particles.draw_passes:
		var pass_mesh: Mesh = particles.get_draw_pass_mesh(pass_index)
		if pass_mesh != null:
			passes += maxi(pass_mesh.get_surface_count(), 1)
	counts["particle_draws"] = int(counts["particle_draws"]) + (passes if live else 0)


func _format(counts: Dictionary) -> String:
	return "part_nodes=%d amount=%d part_draws=%d gpu3d=%d cpu2d=%d meshes=%d mesh_draws=%d multimeshes=%d nodes=%d" % [
		int(counts.get("particle_nodes", 0)), int(counts.get("particle_amount", 0)),
		int(counts.get("particle_draws", 0)),
		int(counts.get("gpu_particles", 0)), int(counts.get("cpu_particles", 0)),
		int(counts.get("meshes", 0)),
		int(counts.get("mesh_draws", 0)), int(counts.get("multimeshes", 0)),
		int(counts.get("nodes", 0))]


static func samples_of(counts: PackedInt32Array) -> int:
	var total: int = 0
	for per_wheel: int in counts:
		total += per_wheel
	return total
