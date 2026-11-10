extends RefCounted
## Shared far backdrop for Meadow Loop and the sandbox park. The scenery is
## decoration only: no collision, no shadow casting, and no per-frame work.


static func add_mountains(parent: Node3D, rng: RandomNumberGenerator,
		count: int = 10) -> void:
	var material := StandardMaterial3D.new()
	material.vertex_color_use_as_albedo = true
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	for i in count:
		var angle: float = TAU * float(i) / float(count) + rng.randf_range(-0.12, 0.12)
		var radius: float = rng.randf_range(700.0, 950.0)
		var base_radius: float = rng.randf_range(120.0, 190.0)
		var height: float = rng.randf_range(180.0, 280.0)
		var mountain := MeshInstance3D.new()
		mountain.name = "Mountain_%02d" % i
		mountain.mesh = _mountain_mesh(rng, base_radius, height)
		mountain.material_override = material
		mountain.position = Vector3(cos(angle) * radius, -12.0, sin(angle) * radius)
		mountain.rotation.y = rng.randf_range(0.0, TAU)
		mountain.scale = Vector3(rng.randf_range(0.85, 1.25), 1.0,
			rng.randf_range(0.85, 1.25))
		mountain.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		parent.add_child(mountain)


static func _mountain_mesh(rng: RandomNumberGenerator, radius: float,
		height: float) -> ArrayMesh:
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()
	var segments: int = 11
	var rings: int = 7
	var ridge: Array[float] = []
	for j in segments:
		ridge.append(rng.randf_range(0.78, 1.16))
	for ring in rings:
		var t: float = float(ring) / float(rings - 1)
		var ring_radius: float = radius * pow(1.0 - t, 0.82)
		for j in segments:
			var angle: float = TAU * float(j) / float(segments)
			var crag: float = ridge[j] * (1.0 + 0.08 * sin(float(ring * 3 + j)))
			var p := Vector3(cos(angle) * ring_radius * crag,
				height * t + (1.0 - t) * rng.randf_range(-8.0, 8.0),
				sin(angle) * ring_radius * crag)
			if ring == rings - 1:
				p = Vector3(rng.randf_range(-4.0, 4.0), height,
					rng.randf_range(-4.0, 4.0))
			verts.append(p)
			norms.append(Vector3.UP)
			var snow_line: float = 0.68 + 0.08 * sin(angle * 3.0 + float(ring))
			var rock := Color(0.32, 0.39, 0.43).lerp(Color(0.50, 0.55, 0.57), t)
			var moss := Color(0.25, 0.37, 0.30)
			var color: Color = moss.lerp(rock, smoothstep(0.05, 0.38, t))
			if t > snow_line:
				color = color.lerp(Color(0.93, 0.95, 0.97),
					smoothstep(snow_line, minf(snow_line + 0.13, 1.0), t))
			colors.append(color)
	for ring in rings - 1:
		for j in segments:
			var next: int = (j + 1) % segments
			var a: int = ring * segments + j
			var b: int = ring * segments + next
			var c: int = (ring + 1) * segments + j
			var d: int = (ring + 1) * segments + next
			indices.append_array([a, c, b, b, c, d])
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


static func add_clouds(parent: Node3D, rng: RandomNumberGenerator,
		count: int = 16) -> void:
	var cloud_mat := StandardMaterial3D.new()
	cloud_mat.albedo_color = Color(0.97, 0.98, 1.0)
	cloud_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var puff := SphereMesh.new()
	puff.radius = 1.0
	puff.height = 0.7
	puff.radial_segments = 10
	puff.rings = 6
	var transforms: Array = []
	for i in count:
		var angle: float = TAU * float(i) / float(count) + rng.randf_range(-0.2, 0.2)
		var radius: float = rng.randf_range(350.0, 700.0)
		var base := Vector3(cos(angle) * radius, rng.randf_range(120.0, 190.0),
			sin(angle) * radius)
		var size: float = rng.randf_range(22.0, 46.0)
		for j in 4:
			var offset := Vector3(rng.randf_range(-0.8, 0.8) * size,
				rng.randf_range(-0.1, 0.18) * size, rng.randf_range(-0.35, 0.35) * size)
			var s: float = size * rng.randf_range(0.45, 1.0)
			transforms.append(Transform3D(Basis.IDENTITY.scaled(Vector3(s, s * 0.55, s * 0.8)),
				base + offset))
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = puff
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = "Clouds"
	instance.multimesh = multi
	instance.material_override = cloud_mat
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	parent.add_child(instance)
