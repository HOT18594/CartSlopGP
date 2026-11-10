extends RefCounted
## Turns a Kenney Nature Kit GLB into one vertex-coloured ArrayMesh that can be
## drawn thousands of times by a single MultiMeshInstance3D.
##
## glTF models often have several surfaces (bark + leaves, grass + petals) with
## different flat colours. MultiMesh is happiest with one surface, so every
## surface is flattened into one mesh and its base colour is baked into
## ARRAY_COLOR. Lighting still comes from the scene's directional light.

const NATURE_ROOT: String = "res://assets/models/kenney_nature-kit/Models/GLB format/"


## All materials used by the scattered foliage share this one material.
static func make_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.roughness = 1.0
	mat.metallic = 0.0
	mat.specular_mode = BaseMaterial3D.SPECULAR_DISABLED
	mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	return mat


## Load `model_name` (without .glb) and merge every mesh surface into one.
static func bake(model_name: String) -> ArrayMesh:
	var path: String = NATURE_ROOT + model_name + ".glb"
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		push_warning("Nature model missing: " + path)
		return null
	var root: Node = packed.instantiate()

	var found: Array = []
	_collect(root, Transform3D.IDENTITY, found)

	var verts := PackedVector3Array()
	var normals := PackedVector3Array()
	var colors := PackedColorArray()
	var indices := PackedInt32Array()

	for entry: Array in found:
		var mesh_instance: MeshInstance3D = entry[0]
		var xform: Transform3D = entry[1]
		var mesh: Mesh = mesh_instance.mesh
		if mesh == null:
			continue
		var normal_basis: Basis = xform.basis.orthonormalized()
		for surface in mesh.get_surface_count():
			var mdt := MeshDataTool.new()
			if mdt.create_from_surface(mesh, surface) != OK:
				continue
			var color: Color = _surface_color(mesh_instance, mesh, surface)
			var base: int = verts.size()
			for vertex in mdt.get_vertex_count():
				verts.append(xform * mdt.get_vertex(vertex))
				normals.append(normal_basis * mdt.get_vertex_normal(vertex))
				colors.append(color)
			for face in mdt.get_face_count():
				indices.append(base + mdt.get_face_vertex(face, 0))
				indices.append(base + mdt.get_face_vertex(face, 1))
				indices.append(base + mdt.get_face_vertex(face, 2))

	root.free()
	if verts.is_empty():
		return null
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = normals
	arrays[Mesh.ARRAY_COLOR] = colors
	arrays[Mesh.ARRAY_INDEX] = indices
	var merged := ArrayMesh.new()
	merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return merged


static func _collect(node: Node, xform: Transform3D, found: Array) -> void:
	var local: Transform3D = xform
	if node is Node3D:
		local = xform * (node as Node3D).transform
	if node is MeshInstance3D:
		found.append([node as MeshInstance3D, local])
	for child in node.get_children():
		_collect(child, local, found)


static func _surface_color(mi: MeshInstance3D, mesh: Mesh, surface: int) -> Color:
	var material: Material = mi.get_surface_override_material(surface)
	if material == null:
		material = mesh.surface_get_material(surface)
	if material == null:
		material = mi.get_active_material(surface)
	if material is BaseMaterial3D:
		var color: Color = (material as BaseMaterial3D).albedo_color
		# Kenney Nature Kit 2.1 ships teal/cyan "leafsGreen" and "leafsDark"
		# materials. They read as blue plastic under a blue sky, so warm them
		# into real foliage greens. Brown bark and yellow flowers are untouched.
		if color.b > color.r * 1.25 and color.g > color.b * 0.9:
			color = Color(color.r * 0.95 + 0.05, color.g * 0.96, color.b * 0.42)
		return color
	return Color(0.45, 0.68, 0.32)


## Spatial chunking for the big scatter layers.
##
## A single MultiMesh spanning the whole 510 m loop can never be culled: its
## AABB is always on screen, so every tree/grass instance is submitted every
## frame. Splitting into ~48 m cells lets the renderer reject off-screen cells
## and lets us give each layer a visibility range. Draw calls rise by roughly
## 10-20 per layer, far below the cost of drawing everything.
const CHUNK_SIZE: float = 48.0


static func create_chunked_instances(model: ArrayMesh, material: Material,
		transforms: Array, cast_shadow: bool, view_end: float = 0.0,
		colors: Array = [], chunk_size: float = CHUNK_SIZE) -> Node3D:
	var holder := Node3D.new()
	var buckets: Dictionary = {}
	for xf: Transform3D in transforms:
		var key := Vector2i(floori(xf.origin.x / chunk_size),
			floori(xf.origin.z / chunk_size))
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(xf)
	for key: Vector2i in buckets:
		var instance := create_instances(model, material, buckets[key], cast_shadow, colors)
		if view_end > 0.0:
			instance.visibility_range_end = view_end
			instance.visibility_range_end_margin = 10.0
			instance.visibility_range_fade_mode = \
				GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		holder.add_child(instance)
	return holder


## One draw call per model. `transforms[i]` places instance i in world space.
static func create_instances(model: ArrayMesh, material: Material,
		transforms: Array, cast_shadow: bool, colors: Array = []) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	multi.mesh = model
	if not colors.is_empty() and colors.size() == transforms.size():
		multi.use_colors = true
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, transforms[i])
	if multi.use_colors:
		for i in colors.size():
			multi.set_instance_color(i, colors[i])
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multi
	instance.material_override = material
	if not cast_shadow:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance
