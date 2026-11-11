extends RefCounted
## Shared building blocks for the Meadow Loop scenery layers.
##
## Everything here runs once, at race build time: no per-frame work and no
## allocation in a hot path. Props that repeat are handed to a MultiMesh and
## everything else is merged into one vertex-coloured ArrayMesh, so a whole
## layer of posts, rails and panels costs a single draw call.


## Opaque vertex-coloured surface shared by every merged structure.
static func vertex_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


## Material for MultiMeshes that carry a per-instance tint.
static func instance_material(roughness: float = 0.95) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.roughness = roughness
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	return mat


## One MultiMeshInstance3D for `transforms`, with optional per-instance tint.
static func multimesh(mesh: Mesh, material: Material, transforms: Array,
		node_name: String, cast_shadow: bool = false,
		colors: Array = []) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = mesh
	if not colors.is_empty() and colors.size() == transforms.size():
		multi.use_colors = true
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, transforms[i])
	if multi.use_colors:
		for i in colors.size():
			multi.set_instance_color(i, colors[i])
	var instance := MultiMeshInstance3D.new()
	instance.name = node_name
	instance.multimesh = multi
	instance.material_override = material
	if not cast_shadow:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance


## Culls `instance` outside a distance band. Used as a cheap two-step LOD: a
## detailed mesh near the camera and a blocky stand-in further out.
static func set_view(instance: GeometryInstance3D, begin: float, end: float) -> void:
	if instance == null:
		return
	instance.visibility_range_begin = begin
	instance.visibility_range_end = end
	instance.visibility_range_begin_margin = 6.0
	instance.visibility_range_end_margin = 10.0
	instance.visibility_range_fade_mode = \
		GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED


## Merges vertices, colours and indices into an ArrayMesh.
##
## `flat` gives every triangle its own face normal, which is what makes cliffs
## and crags read as rock instead of a smooth blob. Smooth normals are used for
## the rounded grass ridges.
static func mesh_from(verts: PackedVector3Array, colors: PackedColorArray,
		indices: PackedInt32Array, flat: bool) -> ArrayMesh:
	if verts.is_empty() or indices.size() < 3:
		return null
	var mesh := ArrayMesh.new()
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	if flat:
		var count: int = indices.size()
		var out_verts := PackedVector3Array()
		var out_norms := PackedVector3Array()
		var out_colors := PackedColorArray()
		out_verts.resize(count)
		out_norms.resize(count)
		out_colors.resize(count)
		for i in range(0, count, 3):
			var a: int = indices[i]
			var b: int = indices[i + 1]
			var c: int = indices[i + 2]
			var normal: Vector3 = (verts[b] - verts[a]).cross(verts[c] - verts[a])
			normal = normal.normalized() if normal.length_squared() > 0.0000001 \
				else Vector3.UP
			for k in 3:
				var source: int = indices[i + k]
				out_verts[i + k] = verts[source]
				out_norms[i + k] = normal
				out_colors[i + k] = colors[source]
		arrays[Mesh.ARRAY_VERTEX] = out_verts
		arrays[Mesh.ARRAY_NORMAL] = out_norms
		arrays[Mesh.ARRAY_COLOR] = out_colors
	else:
		var norms := PackedVector3Array()
		norms.resize(verts.size())
		for i in range(0, indices.size(), 3):
			var a: int = indices[i]
			var b: int = indices[i + 1]
			var c: int = indices[i + 2]
			var normal: Vector3 = (verts[b] - verts[a]).cross(verts[c] - verts[a])
			norms[a] += normal
			norms[b] += normal
			norms[c] += normal
		for i in norms.size():
			norms[i] = norms[i].normalized() if norms[i].length_squared() > 0.0000001 \
				else Vector3.UP
		arrays[Mesh.ARRAY_VERTEX] = verts
		arrays[Mesh.ARRAY_NORMAL] = norms
		arrays[Mesh.ARRAY_COLOR] = colors
		arrays[Mesh.ARRAY_INDEX] = indices
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


## Adds to a scenery stats dictionary without forcing callers to pre-seed keys.
static func bump(stats: Dictionary, key: String, amount: int = 1) -> void:
	stats[key] = int(stats.get(key, 0)) + amount
