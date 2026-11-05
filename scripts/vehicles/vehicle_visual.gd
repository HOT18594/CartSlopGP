extends RefCounted
## Builds a normalised, ground-aligned copy of a vehicle model.
## Scale is chosen so the longest horizontal side matches the catalog length,
## which keeps every model inside the same kart-sized collision box.


static func build(entry: Dictionary) -> Node3D:
	var scene_path: String = str(entry.get("scene", ""))
	var packed: PackedScene = load(scene_path) as PackedScene
	var holder := Node3D.new()
	holder.name = "VehicleVisual"
	if packed == null:
		push_warning("Vehicle model missing: " + scene_path)
		return holder

	var inner := Node3D.new()
	holder.add_child(inner)
	var instance: Node3D = packed.instantiate() as Node3D
	if instance == null:
		return holder
	inner.add_child(instance)

	var acc: Array = []
	_measure(instance, Transform3D.IDENTITY, acc)
	if acc.is_empty():
		return holder
	var bounds: AABB = acc[0]
	var footprint: float = maxf(bounds.size.x, bounds.size.z)
	var target: float = float(entry.get("length", 2.4))
	var scale_factor: float = target / maxf(footprint, 0.01)
	inner.scale = Vector3.ONE * scale_factor

	var center: Vector3 = bounds.get_center() * scale_factor
	inner.position = Vector3(-center.x, -bounds.position.y * scale_factor, -center.z)

	holder.rotation.y = deg_to_rad(float(entry.get("yaw", 180.0)))
	return holder


static func _measure(node: Node, xform: Transform3D, acc: Array) -> void:
	var local: Transform3D = xform
	if node is Node3D:
		local = xform * (node as Node3D).transform
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			var box: AABB = local * mesh_instance.mesh.get_aabb()
			if acc.is_empty():
				acc.append(box)
			else:
				acc[0] = (acc[0] as AABB).merge(box)
	for child in node.get_children():
		_measure(child, local, acc)
