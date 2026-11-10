extends RefCounted
## Builds a normalised, ground-aligned copy of a vehicle model.
## Scale is chosen so the longest horizontal side matches the catalog length,
## which keeps every model inside the same kart-sized collision box.

const OUTLINE_SHADER := preload("res://assets/materials/toon_outline.gdshader")


static func build(entry: Dictionary) -> Node3D:
	var scene_path: String = str(entry.get("scene", ""))
	var packed: PackedScene = load(scene_path) as PackedScene
	var holder := Node3D.new()
	holder.name = "VehicleVisual"
	if packed == null:
		push_warning("Vehicle model missing: " + scene_path)
		_add_fallback_body(holder, entry)
		return holder

	var inner := Node3D.new()
	holder.add_child(inner)
	var instance: Node3D = packed.instantiate() as Node3D
	if instance == null:
		_add_fallback_body(holder, entry)
		return holder
	inner.add_child(instance)

	var acc: Array = []
	_measure(instance, Transform3D.IDENTITY, acc)
	if acc.is_empty():
		_add_fallback_body(holder, entry)
		return holder
	var bounds: AABB = acc[0]
	var footprint: float = maxf(bounds.size.x, bounds.size.z)
	var target: float = float(entry.get("length", 2.4))
	var scale_factor: float = target / maxf(footprint, 0.01)
	inner.scale = Vector3.ONE * scale_factor

	var center: Vector3 = bounds.get_center() * scale_factor
	inner.position = Vector3(-center.x, -bounds.position.y * scale_factor, -center.z)

	holder.rotation.y = deg_to_rad(float(entry.get("yaw", 180.0)))
	# Imported GLBs occasionally carry an alpha-blend material or a material
	# with no usable texture. On the low-end renderer that read as a
	# transparent/ghost vehicle while the collider still worked. Force every
	# vehicle surface opaque and two-sided so the body is always visible.
	_force_visible_materials(instance)
	_hide_legacy_shadow_mesh(instance, scene_path)
	return holder


static func _hide_legacy_shadow_mesh(node: Node, scene_path: String) -> void:
	## The Poly Pizza shopping-cart GLB contains a large grey duplicate mesh
	## (Box055) used as a baked shadow. In the real-time preview and race it
	## reads as a second transparent cart floating behind the red one.
	if not scene_path.contains("shopping_cart"):
		return
	var shadow: Node = node.find_child("Box055", true, false)
	if shadow is MeshInstance3D:
		(shadow as MeshInstance3D).visible = false


static func _force_visible_materials(node: Node) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			for surface in mesh_instance.mesh.get_surface_count():
				var material: Material = mesh_instance.get_active_material(surface)
				if material is BaseMaterial3D:
					var opaque := (material as BaseMaterial3D).duplicate() as BaseMaterial3D
					opaque.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
					opaque.albedo_color.a = 1.0
					opaque.cull_mode = BaseMaterial3D.CULL_DISABLED
					opaque.no_depth_test = false
					opaque.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
					mesh_instance.set_surface_override_material(surface, opaque)
	for child: Node in node.get_children():
		_force_visible_materials(child)


static func _add_fallback_body(holder: Node3D, entry: Dictionary) -> void:
	## A missing/unreadable model must never become an invisible kart. The
	## collider still works, so this fallback gives the player something solid
	## to see and aim at.
	var body := MeshInstance3D.new()
	body.name = "FallbackBody"
	var box := BoxMesh.new()
	box.size = Vector3(float(entry.get("width", 1.5)), float(entry.get("height", 1.2)),
		float(entry.get("length", 2.4)))
	body.mesh = box
	var material := StandardMaterial3D.new()
	material.albedo_color = Color(0.82, 0.28, 0.22)
	material.roughness = 0.72
	body.material_override = material
	body.position.y = box.size.y * 0.5
	holder.add_child(body)


static func _add_outline(node: Node) -> void:
	## Inverted-hull ink line around the cart. This is the 3D version of the
	## thick navy outline the menus and AI art already use, and it is what
	## stops the photo-textured models from looking pasted onto the flat UI.
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		if mesh_instance.mesh != null:
			for surface in mesh_instance.mesh.get_surface_count():
				var material: Material = mesh_instance.get_active_material(surface)
				if material == null:
					continue
				var copy: Material = material.duplicate()
				var outline := ShaderMaterial.new()
				outline.shader = OUTLINE_SHADER
				outline.set_shader_parameter("thickness", 0.018)
				copy.next_pass = outline
				mesh_instance.set_surface_override_material(surface, copy)
	for child: Node in node.get_children():
		_add_outline(child)


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
