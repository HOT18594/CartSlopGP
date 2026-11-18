extends RefCounted
## Builds a normalised, ground-aligned copy of a vehicle model.
## Scale is chosen so the longest horizontal side matches the catalog length,
## which keeps every model inside the same kart-sized collision box.

const OUTLINE_SHADER := preload("res://assets/materials/toon_outline.gdshader")

## Racing paint overrides are shared per scene/surface/tint. Eight karts in the
## same colour reuse one material instead of duplicating it for every cart.
static var _paint_cache: Dictionary = {}


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
	_apply_paint_tint(instance, entry)
	return holder


# NOTE: this used to hide "Box055" from the shopping-cart GLB, on the theory
# that it was a baked shadow duplicate. It is not: Box055 is the cart's metal
# push handle (a grip bar plus two angled supports). Hiding it left the cart
# with no handle at all. Every part stays visible now; the material pass above
# is what keeps them opaque.


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


static func _apply_paint_tint(root: Node, entry: Dictionary) -> void:
	## Racing cars keep their wheels and glass; only the paint surface named by
	## the catalog entry is recoloured. Every peer renders the same tint because
	## the caller passes the per-peer tag colour into the entry. The Shopping Cart
	## has no single body surface index, so its handle/accents and anodized frame
	## are tinted selectively while keeping its dark caster wheels untouched.
	var raw_tint: Variant = entry.get("tint_color", null)
	if not (raw_tint is Color):
		return
	var tint: Color = raw_tint as Color
	if tint.a <= 0.0:
		return
	var surface: int = int(entry.get("paint_surface", -1))
	if surface < 0:
		_apply_cart_tint(root, entry, tint)
		return
	var paint_node: String = str(entry.get("paint_node", ""))
	var target: Node = _find_named(root, paint_node) if paint_node != "" else root
	if target is MeshInstance3D:
		_tint_surface(target as MeshInstance3D, entry, surface, tint)
	else:
		# A model without the named part still gets a usable colour rather than
		# silently keeping the Kenney livery.
		_tint_surface_recursive(root, entry, surface, tint)


static func _apply_cart_tint(node: Node, entry: Dictionary, tint: Color) -> void:
	if node is MeshInstance3D:
		var mesh_instance := node as MeshInstance3D
		var lower_name: String = str(mesh_instance.name).to_lower()
		var is_wheel: bool = lower_name.contains("wheel") \
			or lower_name.contains("tire") \
			or lower_name.contains("tyre") \
			or lower_name.contains("caster")
		if not is_wheel and mesh_instance.mesh != null:
			var is_accent: bool = str(mesh_instance.name) == "Box055" \
				or lower_name.contains("handle") \
				or lower_name.contains("grip") \
				or lower_name.contains("seat") \
				or lower_name.contains("plastic") \
				or lower_name.contains("bumper")
			for surface in mesh_instance.mesh.get_surface_count():
				var source: Material = mesh_instance.get_active_material(surface)
				if source is BaseMaterial3D:
					var base_mat := source as BaseMaterial3D
					var base_col: Color = base_mat.albedo_color
					if not is_accent and base_col.v < 0.26 and base_col.s < 0.22:
						continue
					var applied: Color = tint
					if not is_accent and (base_col.s <= 0.22 or base_col.v < 0.20):
						applied = base_col.lerp(tint, 0.72)
					applied.a = 1.0
					var cache_tag: String = "%s:%d" % [str(mesh_instance.name), surface]
					mesh_instance.set_surface_override_material(surface,
						_shared_named_paint(base_mat, entry, cache_tag, applied))
	for child: Node in node.get_children():
		_apply_cart_tint(child, entry, tint)


static func _shared_named_paint(source: BaseMaterial3D, entry: Dictionary,
		tag: String, tint: Color) -> BaseMaterial3D:
	var key: String = "%s|%s|%s" % [str(entry.get("scene", "")), tag,
		tint.to_html(false)]
	if _paint_cache.has(key):
		return _paint_cache[key] as BaseMaterial3D
	var paint: BaseMaterial3D = source.duplicate() as BaseMaterial3D
	paint.albedo_color = tint
	paint.albedo_color.a = 1.0
	paint.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	paint.cull_mode = BaseMaterial3D.CULL_DISABLED
	paint.no_depth_test = false
	paint.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	_paint_cache[key] = paint
	return paint


static func _tint_surface_recursive(node: Node, entry: Dictionary, surface: int,
		tint: Color) -> void:
	if node is MeshInstance3D:
		_tint_surface(node as MeshInstance3D, entry, surface, tint)
	for child: Node in node.get_children():
		_tint_surface_recursive(child, entry, surface, tint)


static func _tint_surface(mesh_instance: MeshInstance3D, entry: Dictionary,
		surface: int, tint: Color) -> void:
	if mesh_instance.mesh == null or surface >= mesh_instance.mesh.get_surface_count():
		return
	var source: Material = mesh_instance.get_active_material(surface)
	if source is BaseMaterial3D:
		mesh_instance.set_surface_override_material(surface,
			_shared_paint(source as BaseMaterial3D, entry, surface, tint))
		return
	var paint := StandardMaterial3D.new()
	paint.albedo_color = tint
	paint.roughness = 0.58
	paint.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	paint.cull_mode = BaseMaterial3D.CULL_DISABLED
	mesh_instance.set_surface_override_material(surface, paint)


static func _shared_paint(source: BaseMaterial3D, entry: Dictionary, surface: int,
		tint: Color) -> BaseMaterial3D:
	## The scene path plus surface plus tint identifies the paint material, so
	## the same chassis at the same colour shares one resource across carts.
	var key: String = "%s|%d|%s" % [str(entry.get("scene", "")), surface,
		tint.to_html(false)]
	if _paint_cache.has(key):
		return _paint_cache[key] as BaseMaterial3D
	var paint: BaseMaterial3D = source.duplicate() as BaseMaterial3D
	paint.albedo_color = tint
	paint.albedo_color.a = 1.0
	paint.transparency = BaseMaterial3D.TRANSPARENCY_DISABLED
	paint.cull_mode = BaseMaterial3D.CULL_DISABLED
	paint.no_depth_test = false
	paint.depth_draw_mode = BaseMaterial3D.DEPTH_DRAW_OPAQUE_ONLY
	_paint_cache[key] = paint
	return paint


static func _find_named(node: Node, wanted: String) -> Node:
	if str(node.name) == wanted:
		return node
	for child: Node in node.get_children():
		var found: Node = _find_named(child, wanted)
		if found != null:
			return found
	return null


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
	var raw_tint: Variant = entry.get("tint_color", null)
	if raw_tint is Color:
		material.albedo_color = raw_tint as Color
	else:
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
