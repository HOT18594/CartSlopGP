extends RefCounted
## Rural landmarks and distant woodland for Meadow Loop. All sit beyond the
## physical track barriers, so they add depth without changing lap collision.

const FoliageBaker := preload("res://scripts/minigames/foliage_baker.gd")


static func build(parent: Node3D, spline: RefCounted) -> void:
	_farm(parent, spline, 0.52, 1.0)
	_pond(parent, spline, 0.79, -1.0)
	_rock_cutting(parent, spline, 0.88, 1.0)
	_utility_line(parent, spline)
	_distant_woodland(parent)
	_blimp(parent, spline)


static func is_clearing(spline: RefCounted, position: Vector3) -> bool:
	var sites: Array = [
		[0.52, 34.0, 22.0],
		[0.79, -30.0, 17.0],
		[0.88, 22.0, 18.0],
	]
	for site: Array in sites:
		var frame: Dictionary = spline.sample(spline.total_length * float(site[0]))
		var center: Vector3 = frame["position"] + frame["right"] * float(site[1])
		center.y = position.y
		if center.distance_to(position) < float(site[2]):
			return true
	return false


static func _root_at(parent: Node3D, spline: RefCounted, fraction: float,
		lateral: float, node_name: String) -> Node3D:
	var distance: float = spline.total_length * fraction
	var frame: Dictionary = spline.sample(distance)
	var root := Node3D.new()
	root.name = node_name
	root.position = frame["position"] + frame["right"] * lateral
	root.rotation.y = spline.yaw_at(distance)
	parent.add_child(root)
	return root


static func _material(color: Color, roughness: float = 0.9) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = roughness
	return material


static func _box(parent: Node3D, at: Vector3, size: Vector3,
		material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = size
	mesh.mesh = box
	mesh.material_override = material
	mesh.position = at
	parent.add_child(mesh)
	return mesh


static func _cylinder(parent: Node3D, at: Vector3, radius: float, height: float,
		material: Material, segments: int = 16) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var cylinder := CylinderMesh.new()
	cylinder.top_radius = radius
	cylinder.bottom_radius = radius
	cylinder.height = height
	cylinder.radial_segments = segments
	mesh.mesh = cylinder
	mesh.material_override = material
	mesh.position = at
	parent.add_child(mesh)
	return mesh


static func _sphere(parent: Node3D, at: Vector3, radius: float,
		material: Material) -> MeshInstance3D:
	var mesh := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = radius
	sphere.height = radius * 2.0
	sphere.radial_segments = 12
	sphere.rings = 6
	mesh.mesh = sphere
	mesh.material_override = material
	mesh.position = at
	parent.add_child(mesh)
	return mesh


static func _farm(parent: Node3D, spline: RefCounted, fraction: float,
		side: float) -> void:
	var root := _root_at(parent, spline, fraction, side * 34.0, "RiversideFarm")
	var red := _material(Color(0.46, 0.16, 0.12))
	var cream := _material(Color(0.86, 0.82, 0.70))
	var roof_mat := _material(Color(0.19, 0.22, 0.24))
	var metal := _material(Color(0.48, 0.55, 0.56), 0.55)
	_box(root, Vector3(0, 3.4, 0), Vector3(12, 6.8, 13), red)
	for sign_z: float in [-1.0, 1.0]:
		var roof := _box(root, Vector3(sign_z * 3.25, 8.0, 0),
			Vector3(7.8, 0.30, 14.0), roof_mat)
		roof.rotation.z = -sign_z * deg_to_rad(34.0)
	_box(root, Vector3(0, 2.1, 6.53), Vector3(4.2, 4.2, 0.12), roof_mat)
	for x: float in [-2.2, 2.2]:
		_box(root, Vector3(x, 2.1, 6.62), Vector3(0.18, 4.4, 0.10), cream)
	_box(root, Vector3(0, 4.2, 6.62), Vector3(4.6, 0.18, 0.10), cream)
	for x: float in [-4.3, 4.3]:
		_box(root, Vector3(x, 4.4, 6.60), Vector3(1.8, 1.7, 0.10), cream)
		_box(root, Vector3(x, 4.4, 6.67), Vector3(1.45, 1.35, 0.06), metal)
	_cylinder(root, Vector3(-10, 5.5, -2), 3.0, 11.0, metal, 24)
	var cap := _cylinder(root, Vector3(-10, 11.8, -2), 3.15, 2.4, roof_mat, 24)
	cap.mesh.top_radius = 0.0
	for i in 5:
		var bale := _box(root, Vector3(8.0 + float(i % 3) * 1.5,
			0.55 + floorf(float(i) / 3.0) * 1.1, 6.0), Vector3(1.35, 1.0, 1.9),
			_material(Color(0.72, 0.57, 0.28)))
		bale.rotation.y = 0.08 * float(i)
	_wind_pump(root, Vector3(12, 0, -7), metal, cream)


static func _wind_pump(parent: Node3D, at: Vector3, metal: Material,
		cream: Material) -> void:
	var root := Node3D.new()
	root.position = at
	parent.add_child(root)
	for x: float in [-0.65, 0.65]:
		for z: float in [-0.65, 0.65]:
			var leg := _box(root, Vector3(x * 0.5, 5.0, z * 0.5),
				Vector3(0.10, 10.0, 0.10), metal)
			leg.rotation.z = -x * 0.065
			leg.rotation.x = z * 0.065
	_cylinder(root, Vector3(0, 10.2, 0), 0.18, 1.0, metal, 10).rotation.x = PI * 0.5
	for i in 10:
		var blade := _box(root, Vector3.ZERO, Vector3(0.40, 2.5, 0.08), cream)
		blade.position = Vector3(sin(float(i) * TAU / 10.0) * 1.25,
			10.2 + cos(float(i) * TAU / 10.0) * 1.25, 0.65)
		blade.rotation.z = -float(i) * TAU / 10.0
	_box(root, Vector3(0, 10.2, -1.1), Vector3(0.12, 0.9, 2.4), red_material())


static func red_material() -> StandardMaterial3D:
	return _material(Color(0.62, 0.20, 0.14))


static func _pond(parent: Node3D, spline: RefCounted, fraction: float,
		side: float) -> void:
	var root := _root_at(parent, spline, fraction, side * 30.0, "MeadowPond")
	var water := _material(Color(0.18, 0.43, 0.52, 0.88), 0.16)
	water.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	water.metallic = 0.25
	var surface := _cylinder(root, Vector3(0, 0.025, 0), 13.0, 0.05, water, 48)
	surface.scale.z = 0.68
	surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var shore := _material(Color(0.42, 0.43, 0.31))
	var rocks: Array = []
	var reeds: Array = []
	for i in 42:
		var angle: float = TAU * float(i) / 42.0
		var radius: float = 13.4 + sin(float(i) * 2.3) * 0.6
		var at := Vector3(cos(angle) * radius, 0.15, sin(angle) * radius * 0.68)
		rocks.append(Transform3D(Basis(Vector3.UP, angle).scaled(Vector3.ONE * (0.65 + 0.25 * sin(i))), at))
		if i % 2 == 0:
			reeds.append(Transform3D(Basis(Vector3.UP, angle).scaled(Vector3.ONE * 1.4),
				at + Vector3.UP * 0.1))
	_add_model_instances(root, "rock_largeB", shore, rocks, 100.0)
	_add_model_instances(root, "plant_flatTall", null, reeds, 85.0)
	for i in 5:
		var pad := _cylinder(root, Vector3(-6.0 + float(i) * 2.8, 0.075,
			sin(float(i) * 2.0) * 2.5), 0.65, 0.025,
			_material(Color(0.24, 0.46, 0.25)), 16)
		pad.scale.z = 0.72

	# A short wooden dock and three ducks make the pond a destination rather
	# than a blue disc in the distance.
	var wood := _material(Color(0.38, 0.26, 0.16))
	var cream := _material(Color(0.93, 0.90, 0.82))
	var orange := _material(Color(0.95, 0.55, 0.12))
	_box(root, Vector3(0.0, 0.16, 10.2), Vector3(2.4, 0.14, 3.8), wood)
	for x: float in [-1.0, 1.0]:
		for z: float in [8.7, 11.7]:
			_box(root, Vector3(x, 0.0, z), Vector3(0.14, 0.8, 0.14), wood)
	for i in 3:
		var duck_at := Vector3(-4.2 + float(i) * 3.6, 0.22,
			4.0 + sin(float(i) * 1.7) * 2.0)
		var body := _sphere(root, duck_at, 0.20, cream)
		body.scale = Vector3(1.55, 0.75, 1.0)
		var head := _sphere(root, duck_at + Vector3(0.0, 0.17, 0.16), 0.10, cream)
		head.scale = Vector3(1.0, 1.15, 1.0)
		var beak := _box(root, duck_at + Vector3(0.0, 0.15, 0.29),
			Vector3(0.10, 0.05, 0.16), orange)
		beak.rotation.x = -0.1


static func _rock_cutting(parent: Node3D, spline: RefCounted, fraction: float,
		side: float) -> void:
	var root := _root_at(parent, spline, fraction, side * 22.0, "RockCutting")
	var stone := _material(Color(0.55, 0.54, 0.48))
	var transforms: Array = []
	for i in 24:
		var at := Vector3((float(i % 6) - 2.5) * 3.0,
			0.4 + floorf(float(i) / 6.0) * 1.1, (floorf(float(i) / 6.0)) * 2.0)
		var scale := Vector3(2.0 + 0.3 * sin(i), 1.8 + 0.4 * cos(i), 2.1)
		transforms.append(Transform3D(Basis(Vector3.UP, float(i) * 1.7).scaled(scale), at))
	_add_model_instances(root, "rock_tallA", stone, transforms, 150.0)


static func _utility_line(parent: Node3D, spline: RefCounted) -> void:
	var wood := _material(Color(0.30, 0.23, 0.16))
	var wire := _material(Color(0.12, 0.13, 0.14), 0.7)
	var tops: Array[Vector3] = []
	for i in 7:
		var distance: float = spline.total_length * (0.43 + float(i) * 0.022)
		var frame: Dictionary = spline.sample(distance)
		var at: Vector3 = frame["position"] + frame["right"] * 19.0
		_cylinder(parent, at + Vector3.UP * 4.2, 0.13, 8.4, wood, 8)
		var cross := _box(parent, at + Vector3.UP * 8.1, Vector3(2.4, 0.14, 0.14), wood)
		cross.rotation.y = spline.yaw_at(distance)
		tops.append(at + Vector3.UP * 8.2)
	for i in tops.size() - 1:
		for side: float in [-0.8, 0.8]:
			var a: Vector3 = tops[i] + Vector3.RIGHT * side
			var b: Vector3 = tops[i + 1] + Vector3.RIGHT * side
			_wire_span(parent, a, b, wire)


static func _wire_span(parent: Node3D, a: Vector3, b: Vector3,
		material: Material) -> void:
	var previous: Vector3 = a
	for i in range(1, 7):
		var t: float = float(i) / 6.0
		var point: Vector3 = a.lerp(b, t) - Vector3.UP * sin(t * PI) * 0.65
		var direction: Vector3 = point - previous
		var line := _box(parent, (previous + point) * 0.5,
			Vector3(0.035, 0.035, direction.length()), material)
		line.quaternion = Quaternion(Vector3.FORWARD, direction.normalized())
		previous = point


static func _blimp(parent: Node3D, spline: RefCounted) -> void:
	## One cheap branded blimp above the far side of the loop. No collision, no
	## shadow, and the label faces the camera so it reads from several corners.
	var frame: Dictionary = spline.sample(spline.total_length * 0.42)
	var root := Node3D.new()
	root.name = "SlopBlimp"
	root.position = frame["position"] + frame["right"] * 95.0 + Vector3.UP * 52.0
	root.rotation.y = spline.yaw_at(spline.total_length * 0.42)
	parent.add_child(root)
	var cream := _material(Color(0.93, 0.90, 0.82), 0.7)
	var red := _material(Color(0.62, 0.20, 0.14), 0.7)
	var body := _sphere(root, Vector3.ZERO, 1.0, cream)
	body.scale = Vector3(9.0, 3.1, 3.1)
	var gondola := _box(root, Vector3(0.0, -3.1, 0.0),
		Vector3(2.4, 0.85, 1.3), red)
	gondola.rotation.y = 0.0
	for z: float in [-2.2, 0.0, 2.2]:
		var fin := _box(root, Vector3(-8.2, 0.0, z),
			Vector3(2.2, 1.8, 0.10), red)
		fin.rotation.x = 0.0
	var label := Label3D.new()
	label.text = "SLOP"
	label.font = load("res://assets/ui/fonts/LuckiestGuy-Regular.ttf")
	label.font_size = 96
	label.pixel_size = 0.055
	label.outline_size = 14
	label.outline_modulate = Color(0.12, 0.10, 0.23, 0.9)
	label.modulate = Color(1.0, 0.82, 0.18, 1.0)
	label.billboard = BaseMaterial3D.BILLBOARD_ENABLED
	label.position = Vector3(0.0, 0.3, 3.2)
	root.add_child(label)


static func _distant_woodland(parent: Node3D) -> void:
	var rng := RandomNumberGenerator.new()
	rng.seed = 73190
	var material: Material = FoliageBaker.make_material()
	var transforms: Array = []
	for i in 650:
		var angle: float = rng.randf() * TAU
		var radius: float = rng.randf_range(145.0, 300.0)
		var at := Vector3(cos(angle) * radius, -0.1, sin(angle) * radius)
		var scale: float = rng.randf_range(2.0, 3.8)
		transforms.append(Transform3D(Basis(Vector3.UP, rng.randf() * TAU)
			.scaled(Vector3.ONE * scale), at))
	_add_model_instances(parent, "tree_pineTallA", material, transforms, 430.0)


static func _add_model_instances(parent: Node3D, model: String,
		material: Material, transforms: Array, view_end: float) -> void:
	var mesh: ArrayMesh = FoliageBaker.bake(model)
	if mesh == null or transforms.is_empty():
		return
	if material == null:
		material = FoliageBaker.make_material()
	parent.add_child(FoliageBaker.create_chunked_instances(
		mesh, material, transforms, false, view_end, [], 96.0))
