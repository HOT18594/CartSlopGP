extends Node
## Renders the two full-bleed menu hero backgrounds used by the animated
## slideshow in `scripts/ui/menu_background.gd`:
##
##   * `bg_parking.png` — low, dynamic shot of the enhanced Sandbox park: the
##     start grid with real vehicles, pit garages and the handling loop.
##   * `bg_arena.png`  — hero shot of the Skytop Helipad Knockout arena with a
##     kart brawl on the deck and the city skyline behind it.
##
## Run windowed (the headless dummy renderer captures blank frames):
##   Godot_v4.7.2-stable_win64_console.exe --path godot_project \
##       res://scripts/tools/menu_art_render.tscn
##
## Writes 1600x900 PNGs into `res://assets/ui/art/`.

const Catalog := preload("res://scripts/vehicles/vehicle_catalog.gd")
const VehicleVisual := preload("res://scripts/vehicles/vehicle_visual.gd")
const KnockoutMaps := preload("res://scripts/minigames/knockout_maps.gd")
const SceneryKit := preload("res://scripts/minigames/scenery/scenery_kit.gd")

const WIDTH: int = 1600
const HEIGHT: int = 900
const OUT_DIR: String = "res://assets/ui/art/"
const SANDBOX_SCENE: String = "res://scenes/sandbox/sandbox.tscn"
const VEHICLE_IDS: Array[String] = ["shopping_cart", "van", "truck", "sports",
	"taxi"]

var _viewport: SubViewport


func _ready() -> void:
	if DisplayServer.get_name() == "headless":
		push_error("menu_art_render: run windowed, not --headless")
		get_tree().quit(1)
		return
	_viewport = SubViewport.new()
	_viewport.name = "HeroViewport"
	_viewport.size = Vector2i(WIDTH, HEIGHT)
	_viewport.own_world_3d = true
	_viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	_viewport.msaa_3d = Viewport.MSAA_4X
	_viewport.screen_space_aa = Viewport.SCREEN_SPACE_AA_FXAA
	_viewport.use_debanding = true
	add_child(_viewport)
	await get_tree().process_frame
	var ok_park: bool = await _render_park()
	await _wait_frames(2)
	var ok_arena: bool = await _render_arena()
	print("MENU_ART_RENDER: park=%s arena=%s" % [ok_park, ok_arena])
	get_tree().quit(0 if ok_park and ok_arena else 1)


# --------------------------------------------------------------------------
# Sandbox hero
# --------------------------------------------------------------------------


func _render_park() -> bool:
	var stage := Node3D.new()
	stage.name = "Hero_Park"
	_viewport.add_child(stage)
	var packed: PackedScene = load(SANDBOX_SCENE) as PackedScene
	if packed == null:
		return false
	var inst: Node3D = packed.instantiate() as Node3D
	stage.add_child(inst)
	_hide_ui(inst)
	_strip_lighting(stage)
	# Hide the scene's own kart/bots: the hero roster is staged by hand.
	for node: Node in _all_nodes(inst):
		if node is CharacterBody3D:
			(node as Node3D).visible = false
	# Hero roster lined up on the start grid, angled toward the garage block.
	var slots: Array[Transform3D] = [
		Transform3D(Basis(Vector3.UP, deg_to_rad(-18.0)), Vector3(-8.6, 0.0, 6.0)),
		Transform3D(Basis(Vector3.UP, deg_to_rad(-6.0)), Vector3(-2.9, 0.0, 9.6)),
		Transform3D(Basis(Vector3.UP, deg_to_rad(10.0)), Vector3(3.2, 0.0, 11.2)),
		Transform3D(Basis(Vector3.UP, deg_to_rad(24.0)), Vector3(9.4, 0.0, 7.0)),
		Transform3D(Basis(Vector3.UP, deg_to_rad(38.0)), Vector3(14.4, 0.0, 1.4)),
	]
	for index in mini(VEHICLE_IDS.size(), slots.size()):
		var entry: Dictionary = Catalog.find(VEHICLE_IDS[index])
		var vehicle: Node3D = VehicleVisual.build(entry)
		if vehicle == null:
			continue
		stage.add_child(vehicle)
		vehicle.position = slots[index].origin + Vector3.UP * 0.06
		vehicle.rotation.y = slots[index].basis.get_euler().y
		vehicle.scale = Vector3.ONE * 1.15
	var camera := Camera3D.new()
	camera.name = "HeroCamera"
	camera.fov = 58.0
	camera.near = 0.4
	camera.far = 4000.0
	stage.add_child(camera)
	camera.look_at_from_position(Vector3(27.0, 15.0, -58.0),
		Vector3(-1.0, 2.0, 0.0), Vector3.UP)
	camera.current = true
	_install_environment(stage, Color("3d9be0"), Color("d8f4ec"),
		Color("fff4dc"), -46.0, -38.0, 0.00030, 0.26)
	await _wait_frames(22)
	var saved: bool = _save(await _capture(), OUT_DIR + "bg_parking.png")
	stage.queue_free()
	return saved


# --------------------------------------------------------------------------
# Arena hero
# --------------------------------------------------------------------------


func _render_arena() -> bool:
	var stage := Node3D.new()
	stage.name = "Hero_Arena"
	_viewport.add_child(stage)
	var arena: Dictionary = KnockoutMaps.build_arena(stage, "ko_rooftop")
	if arena.is_empty():
		return false
	_strip_lighting(stage)
	var spawns: Array[Transform3D] = arena.get("spawns", []) as Array[Transform3D]
	for index in mini(VEHICLE_IDS.size(), spawns.size()):
		var entry: Dictionary = Catalog.find(VEHICLE_IDS[index])
		var vehicle: Node3D = VehicleVisual.build(entry)
		if vehicle == null:
			continue
		stage.add_child(vehicle)
		var xform: Transform3D = spawns[(index * 2) % spawns.size()]
		vehicle.position = xform.origin + Vector3.UP * 0.05
		vehicle.rotation.y = atan2(xform.basis.z.x, xform.basis.z.z)
		vehicle.scale = Vector3.ONE * 1.25
	var camera := Camera3D.new()
	camera.name = "HeroCamera"
	camera.fov = 56.0
	camera.near = 0.4
	camera.far = 4000.0
	stage.add_child(camera)
	camera.look_at_from_position(Vector3(36.0, 19.0, 40.0),
		Vector3(-2.0, 1.0, 0.0), Vector3.UP)
	camera.current = true
	_install_environment(stage, Color("2f58a8"), Color("f3bd99"),
		Color("ffe5c4"), -42.0, -44.0, 0.00030, 0.38)
	await _wait_frames(22)
	var saved: bool = _save(await _capture(), OUT_DIR + "bg_arena.png")
	stage.queue_free()
	return saved


# --------------------------------------------------------------------------
# shared helpers
# --------------------------------------------------------------------------


func _install_environment(stage: Node3D, sky_top: Color, horizon: Color,
		sun_color: Color, sun_x: float, sun_y: float, fog_density: float,
		ambient: float) -> void:
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(sun_x, sun_y, 0.0)
	sun.light_color = sun_color
	sun.light_energy = 0.92
	sun.shadow_enabled = true
	sun.directional_shadow_mode = DirectionalLight3D.SHADOW_PARALLEL_2_SPLITS
	sun.directional_shadow_max_distance = 520.0
	stage.add_child(sun)
	var sky_material := ProceduralSkyMaterial.new()
	sky_material.sky_top_color = sky_top
	sky_material.sky_horizon_color = horizon
	sky_material.sky_curve = 0.38
	sky_material.ground_horizon_color = horizon
	sky_material.ground_bottom_color = sky_top.darkened(0.18)
	sky_material.sky_energy_multiplier = 0.9
	var sky := Sky.new()
	sky.sky_material = sky_material
	var environment := Environment.new()
	environment.background_mode = Environment.BG_SKY
	environment.sky = sky
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = horizon.lightened(0.05)
	environment.ambient_light_energy = ambient
	environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	environment.tonemap_exposure = 0.74
	environment.tonemap_white = 1.55
	environment.fog_enabled = true
	environment.fog_light_color = horizon
	environment.fog_light_energy = 0.85
	environment.fog_density = fog_density
	environment.fog_sky_affect = 0.12
	environment.adjustment_enabled = true
	environment.adjustment_brightness = 0.98
	environment.adjustment_contrast = 1.16
	environment.adjustment_saturation = 1.24
	var world := WorldEnvironment.new()
	world.environment = environment
	stage.add_child(world)


## The instantiated map scene ships its own sun and environment; two of each
## stack their exposure and blow the hero shot out to white.
func _strip_lighting(stage: Node3D) -> void:
	for node: Node in _all_nodes(stage):
		if node is WorldEnvironment:
			node.get_parent().remove_child(node)
			node.free()
		elif node is DirectionalLight3D:
			node.get_parent().remove_child(node)
			node.free()


func _hide_ui(root: Node) -> void:
	for node: Node in _all_nodes(root):
		if node is CanvasLayer:
			(node as CanvasLayer).visible = false
			node.process_mode = Node.PROCESS_MODE_DISABLED
		elif node is Control and node.get_parent() != null \
				and not (node.get_parent() is Control):
			(node as Control).visible = false


func _all_nodes(root: Node) -> Array[Node]:
	var found: Array[Node] = []
	for child: Node in root.get_children():
		found.append(child)
		found.append_array(_all_nodes(child))
	return found


func _wait_frames(count: int) -> void:
	for _step in count:
		await get_tree().process_frame


func _capture() -> Image:
	await RenderingServer.frame_post_draw
	var texture: ViewportTexture = _viewport.get_texture()
	if texture == null:
		return null
	return texture.get_image()


func _save(image: Image, path: String) -> bool:
	if image == null:
		return false
	var absolute: String = ProjectSettings.globalize_path(path)
	var error: Error = image.save_png(absolute)
	if error != OK:
		push_error("menu_art_render: could not save %s (%s)" % [
			absolute, error_string(error)])
		return false
	print("MENU_ART_RENDER: wrote %s (%d x %d)" % [path,
		image.get_width(), image.get_height()])
	return image.get_width() == WIDTH and image.get_height() == HEIGHT
