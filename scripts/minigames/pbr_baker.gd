extends RefCounted
## Flattens a Poly Haven CC0 glTF ground-cover model into one ArrayMesh per
## material, so it can be drawn thousands of times with MultiMesh WITHOUT
## losing its PBR diffuse / normal / roughness textures.
##
## The existing foliage_baker.gd bakes colours into vertices (right for flat
## Kenney low-poly models). This one keeps the original materials instead.

const MODEL_ROOT: String = "res://assets/models/polyhaven/"


static func bake(model_name: String, max_parts: int = 2) -> Dictionary:
	## Returns {groups: Array[Dictionary {mesh, material}], bounds: AABB}.
	## `max_parts` matters: Poly Haven grass models pack a dozen LOD variants
	## side by side in one glTF. Merging all of them makes one instance cost
	## ~26k vertices; keeping two clumps keeps the look at a sane poly budget.
	var path: String = MODEL_ROOT + model_name + "/" + model_name + "_1k.gltf"
	var packed: PackedScene = load(path) as PackedScene
	if packed == null:
		push_warning("Poly Haven model missing: " + path)
		return {"groups": [], "bounds": AABB()}
	var root: Node = packed.instantiate()
	var found: Array = []
	_collect(root, Transform3D.IDENTITY, found)
	if max_parts > 0 and found.size() > max_parts:
		found.resize(max_parts)

	var groups: Dictionary = {}
	var bounds := AABB()
	var have_bounds: bool = false
	for entry: Array in found:
		var mi: MeshInstance3D = entry[0]
		var xform: Transform3D = entry[1]
		var mesh: Mesh = mi.mesh
		if mesh == null:
			continue
		for surface in mesh.get_surface_count():
			var material: Material = mi.get_surface_override_material(surface)
			if material == null:
				material = mesh.surface_get_material(surface)
			if material == null:
				material = mi.get_active_material(surface)
			var key: String = str(material.get_instance_id()) if material != null else "none"
			if not groups.has(key):
				groups[key] = {
					"material": material,
					"v": PackedVector3Array(), "n": PackedVector3Array(),
					"uv": PackedVector2Array(), "i": PackedInt32Array(),
				}
			# Packed*Array are VALUE types in GDScript: appending directly into
			# dict["v"] silently mutates a copy. Pull out, mutate, write back.
			var verts: PackedVector3Array = groups[key]["v"]
			var normals: PackedVector3Array = groups[key]["n"]
			var uvs: PackedVector2Array = groups[key]["uv"]
			var indices: PackedInt32Array = groups[key]["i"]
			var mdt := MeshDataTool.new()
			if mdt.create_from_surface(mesh, surface) != OK:
				continue
			var base: int = verts.size()
			for vertex in mdt.get_vertex_count():
				var position: Vector3 = xform * mdt.get_vertex(vertex)
				verts.append(position)
				normals.append(xform.basis.orthonormalized() * mdt.get_vertex_normal(vertex))
				uvs.append(mdt.get_vertex_uv(vertex))
				if have_bounds:
					bounds = bounds.expand(position)
				else:
					bounds = AABB(position, Vector3.ZERO)
					have_bounds = true
			for face in mdt.get_face_count():
				indices.append(base + mdt.get_face_vertex(face, 0))
				indices.append(base + mdt.get_face_vertex(face, 1))
				indices.append(base + mdt.get_face_vertex(face, 2))
			groups[key]["v"] = verts
			groups[key]["n"] = normals
			groups[key]["uv"] = uvs
			groups[key]["i"] = indices
	root.free()

	var result: Array[Dictionary] = []
	for key: String in groups:
		var group: Dictionary = groups[key]
		# Some glTF surfaces carry vertices but no triangles (degenerate LOD
		# helpers). Adding those would produce a zero-surface ArrayMesh.
		if (group["v"] as PackedVector3Array).is_empty() \
				or (group["i"] as PackedInt32Array).is_empty():
			continue
		var arrays: Array = []
		arrays.resize(Mesh.ARRAY_MAX)
		arrays[Mesh.ARRAY_VERTEX] = group["v"]
		arrays[Mesh.ARRAY_NORMAL] = group["n"]
		arrays[Mesh.ARRAY_TEX_UV] = group["uv"]
		arrays[Mesh.ARRAY_INDEX] = group["i"]
		var merged := ArrayMesh.new()
		merged.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
		result.append({"mesh": merged, "material": group["material"]})
	return {"groups": result, "bounds": bounds}


static func _collect(node: Node, xform: Transform3D, found: Array) -> void:
	var local: Transform3D = xform
	if node is Node3D:
		local = xform * (node as Node3D).transform
	if node is MeshInstance3D:
		found.append([node as MeshInstance3D, local])
	for child in node.get_children():
		_collect(child, local, found)


## One MultiMeshInstance3D per (model, material) group.
const CHUNK_SIZE: float = 48.0


## Same spatial chunking as FoliageBaker: a MultiMesh covering the whole loop
## can never be culled, so split it into cells and give it a view distance.
static func create_chunked_instances(group: Dictionary, material_override: Material,
		transforms: Array, cast_shadow: bool, view_end: float = 0.0,
		chunk_size: float = CHUNK_SIZE) -> Node3D:
	var holder := Node3D.new()
	var buckets: Dictionary = {}
	for xf: Transform3D in transforms:
		var key := Vector2i(floori(xf.origin.x / chunk_size),
			floori(xf.origin.z / chunk_size))
		if not buckets.has(key):
			buckets[key] = []
		buckets[key].append(xf)
	for key: Vector2i in buckets:
		var instance := create_instances(group, material_override, buckets[key], cast_shadow)
		if view_end > 0.0:
			instance.visibility_range_end = view_end
			instance.visibility_range_end_margin = 10.0
			instance.visibility_range_fade_mode = \
				GeometryInstance3D.VISIBILITY_RANGE_FADE_DISABLED
		holder.add_child(instance)
	return holder


static func create_instances(group: Dictionary, material_override: Material,
		transforms: Array, cast_shadow: bool) -> MultiMeshInstance3D:
	var multi := MultiMesh.new()
	multi.transform_format = MultiMesh.TRANSFORM_3D
	var mesh: ArrayMesh = group["mesh"]
	if material_override == null and group["material"] is Material:
		mesh.surface_set_material(0, group["material"])
	multi.mesh = mesh
	multi.instance_count = transforms.size()
	for i in transforms.size():
		multi.set_instance_transform(i, transforms[i])
	var instance := MultiMeshInstance3D.new()
	instance.multimesh = multi
	if material_override != null:
		instance.material_override = material_override
	if not cast_shadow:
		instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return instance
