extends RefCounted
## High-fidelity scenery layer for MEADOW LOOP.
##
## Three tiers, from the camera outwards:
##   1. ~420 procedural PBR trees (real bark normal maps + alpha-cutout leaf
##      atlases, generated from Poly Haven CC0 scans) in the 10-40 m verge.
##   2. ~5,000 wind-animated, kart-bending grass cards.
##   3. ~1,400 instanced photogrammetry ground-cover glTF models.
## The original Kenney low-poly forest stays as the cheap far-field canopy.
##
## Every cutout shares one of a handful of ShaderMaterials; the race controller
## feeds the kart's world position into them so grass visibly bends aside.

const RealisticTree := preload("res://scripts/minigames/realistic_tree.gd")
const PbrBaker := preload("res://scripts/minigames/pbr_baker.gd")
const FoliageBaker := preload("res://scripts/minigames/foliage_baker.gd")

const TEX: String = "res://assets/textures/polyhaven/"
const CARD: String = "res://assets/textures/foliage/"
const WIND_SHADER: String = "res://assets/materials/foliage_wind.gdshader"
const PBR_SHADER: String = "res://assets/materials/ground_pbr.gdshader"

const SCANNED_MODELS: PackedStringArray = [
	"grass_medium_01", "grass_medium_02", "fern_02", "moss_01", "dead_tree_trunk_02",
]

var wind_materials: Array[ShaderMaterial] = []
var bend_materials: Array[ShaderMaterial] = []
var stats: Dictionary = {"trees": 0, "grass_cards": 0, "scanned": 0, "draw_calls": 0}

var _parent: Node3D
var _spline: RefCounted
var _host: Node
var _rng: RandomNumberGenerator


func build(parent: Node3D, spline: RefCounted, host: Node, seed_value: int) -> Dictionary:
	_parent = parent
	_spline = spline
	_host = host
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value
	_build_trees()
	_build_grass_cards()
	_build_scanned_plants()
	return {
		"wind_materials": wind_materials,
		"bend_materials": bend_materials,
		"stats": stats,
	}


# --------------------------------------------------------------------------
# materials


func _wind_material(card: String, tint: Color, sway_height: float,
		strength: float, speed: float, bend: bool) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(WIND_SHADER) as Shader
	mat.set_shader_parameter("card_tex", load(CARD + card + ".png"))
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("sway_height", sway_height)
	mat.set_shader_parameter("wind_strength", strength)
	mat.set_shader_parameter("wind_speed", speed)
	mat.set_shader_parameter("phase_offset", _rng.randf() * 10.0)
	mat.set_shader_parameter("alpha_cutoff", 0.42)
	mat.set_shader_parameter("bend_radius", 5.5 if bend else 0.0)
	mat.set_shader_parameter("bend_strength", 0.9 if bend else 0.0)
	mat.set_shader_parameter("kart_position", Vector3(0.0, -1000.0, 0.0))
	wind_materials.append(mat)
	if bend:
		bend_materials.append(mat)
	return mat


func _bark_material(diff: String, nor: String, tint: Color) -> ShaderMaterial:
	var mat := ShaderMaterial.new()
	mat.shader = load(PBR_SHADER) as Shader
	mat.set_shader_parameter("albedo_tex", load(TEX + diff + ".jpg"))
	mat.set_shader_parameter("normal_tex", load(TEX + nor + ".jpg"))
	mat.set_shader_parameter("rough_tex", load(TEX + "grass_rough.jpg"))
	mat.set_shader_parameter("tint", tint)
	mat.set_shader_parameter("uv_scale", 1.0)
	mat.set_shader_parameter("detail_strength", 0.28)
	mat.set_shader_parameter("macro_variation", 0.035)
	mat.set_shader_parameter("roughness_min", 0.82)
	return mat


# --------------------------------------------------------------------------
# tier 1 - procedural realistic trees


func _build_trees() -> void:
	var broad_leaf := _wind_material("leaf_broad", Color(0.92, 1.0, 0.88),
		10.0, 0.30, 1.05, false)
	var frond_leaf := _wind_material("leaf_frond", Color(0.66, 0.86, 0.62),
		12.0, 0.34, 0.92, false)
	var broad_bark := _bark_material("bark_diff", "bark_nor", Color(0.95, 0.93, 0.88))
	var pine_bark := _bark_material("pinebark_diff", "pinebark_nor", Color(0.90, 0.82, 0.72))

	var buckets: Dictionary = {}
	for i in RealisticTree.variant_count():
		buckets[i] = []
	for i in 860:
		var position: Vector3 = _verge_point(10.5, 70.0)
		if position == Vector3.INF or bool(_host.call("_near_track", position, 9.2)):
			continue
		var variant: int = _rng.randi_range(0, RealisticTree.variant_count() - 1)
		var scale: float = _rng.randf_range(0.78, 1.32)
		var basis: Basis = Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * scale)
		buckets[variant].append(Transform3D(basis, position + Vector3.UP * 0.02))

	var holder := Node3D.new()
	holder.name = "RealisticForest"
	_parent.add_child(holder)
	var builder := RealisticTree.new()
	for variant: int in buckets:
		var transforms: Array = buckets[variant]
		if transforms.is_empty():
			continue
		var tree: Dictionary = builder.build(variant, 4400 + variant * 131)
		var is_frond: bool = str(tree["atlas"]) == "frond"
		var bark_mesh: ArrayMesh = tree["bark"]
		var leaf_mesh: ArrayMesh = tree["leaf"]
		holder.add_child(FoliageBaker.create_instances(
			bark_mesh, pine_bark if is_frond else broad_bark, transforms, true))
		holder.add_child(FoliageBaker.create_instances(
			leaf_mesh, frond_leaf if is_frond else broad_leaf, transforms, true))
		stats["trees"] = int(stats["trees"]) + transforms.size()
		stats["draw_calls"] = int(stats["draw_calls"]) + 2


# --------------------------------------------------------------------------
# tier 2 - wind-animated grass cards


func _build_grass_cards() -> void:
	var mat := _wind_material("grass_card", Color(0.86, 1.0, 0.78),
		0.9, 0.16, 2.1, true)
	var fern_mat := _wind_material("fern_card", Color(0.78, 0.95, 0.72),
		1.3, 0.14, 1.7, true)

	var grass_mesh := _crossed_cards(0.85, 3)
	var fern_mesh := _crossed_cards(1.3, 2)
	var grass_xf: Array = []
	var fern_xf: Array = []
	for i in 3800:
		var position: Vector3 = _verge_point(6.9, 46.0)
		if position == Vector3.INF or bool(_host.call("_near_track", position, 6.6)):
			continue
		var scale: float = _rng.randf_range(0.55, 1.5)
		var basis: Basis = Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * scale)
		var xf := Transform3D(basis, position + Vector3.UP * 0.015)
		if _rng.randf() < 0.14:
			fern_xf.append(xf)
		else:
			grass_xf.append(xf)

	var holder := Node3D.new()
	holder.name = "WindGrass"
	_parent.add_child(holder)
	if not grass_xf.is_empty():
		holder.add_child(FoliageBaker.create_instances(grass_mesh, mat, grass_xf, false))
		stats["draw_calls"] = int(stats["draw_calls"]) + 1
	if not fern_xf.is_empty():
		holder.add_child(FoliageBaker.create_instances(fern_mesh, fern_mat, fern_xf, false))
		stats["draw_calls"] = int(stats["draw_calls"]) + 1
	stats["grass_cards"] = grass_xf.size() + fern_xf.size()


func _crossed_cards(size: float, count: int) -> ArrayMesh:
	# Several intersecting quads make a clump that reads from every angle.
	var verts := PackedVector3Array()
	var norms := PackedVector3Array()
	var uvs := PackedVector2Array()
	for c in count:
		var yaw: float = PI * float(c) / float(count)
		var basis := Basis(Vector3.UP, yaw)
		var half: float = size * 0.5
		for corner: Vector2 in [Vector2(-half, 0.0), Vector2(half, 0.0),
				Vector2(half, size), Vector2(-half, size)]:
			verts.append(basis * Vector3(corner.x, corner.y, 0.0))
			norms.append(Vector3.UP)
		uvs.append(Vector2(0, 1))
		uvs.append(Vector2(1, 1))
		uvs.append(Vector2(1, 0))
		uvs.append(Vector2(0, 0))
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = verts
	arrays[Mesh.ARRAY_NORMAL] = norms
	arrays[Mesh.ARRAY_TEX_UV] = uvs
	arrays[Mesh.ARRAY_INDEX] = _quad_indices(verts.size() / 4)
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _quad_indices(quad_count: int) -> PackedInt32Array:
	var indices := PackedInt32Array()
	for q in quad_count:
		var a: int = q * 4
		indices.append(a)
		indices.append(a + 1)
		indices.append(a + 2)
		indices.append(a)
		indices.append(a + 2)
		indices.append(a + 3)
	return indices


# --------------------------------------------------------------------------
# tier 3 - instanced photogrammetry ground cover


func _build_scanned_plants() -> void:
	var holder := Node3D.new()
	holder.name = "ScannedGroundCover"
	_parent.add_child(holder)
	var attempts: Array[int] = [220, 200, 150, 170, 44]
	var target_heights: Array[float] = [0.75, 0.65, 1.1, 0.35, 2.2]
	for m in SCANNED_MODELS.size():
		var data: Dictionary = PbrBaker.bake(SCANNED_MODELS[m], 2)
		var groups: Array = data["groups"]
		if groups.is_empty():
			continue
		var bounds: AABB = data["bounds"]
		var height: float = maxf(bounds.size.y, 0.01)
		var scale: float = target_heights[m] / height
		var transforms: Array = []
		for i in attempts[m]:
			var position: Vector3 = _verge_point(7.5, 48.0)
			if position == Vector3.INF or bool(_host.call("_near_track", position, 7.2)):
				continue
			var s: float = scale * _rng.randf_range(0.7, 1.45)
			var basis: Basis = Basis(Vector3.UP, _rng.randf() * TAU).scaled(Vector3.ONE * s)
			transforms.append(Transform3D(basis,
				position - Vector3.UP * bounds.position.y * s))
		if transforms.is_empty():
			continue
		for group: Dictionary in groups:
			holder.add_child(PbrBaker.create_instances(
				group, null, transforms, m == 4))
			stats["draw_calls"] = int(stats["draw_calls"]) + 1
		stats["scanned"] = int(stats["scanned"]) + transforms.size()


# --------------------------------------------------------------------------
# placement


func _verge_point(min_distance: float, max_distance: float) -> Vector3:
	# Band sampling around the loop keeps the expensive detail where the chase
	# camera can actually see it; occasional wide samples soften the edge.
	var frame: Dictionary
	if _rng.randf() < 0.86:
		frame = _spline.sample(_rng.randf() * _spline.total_length)
		var angle: float = _rng.randf() * TAU
		var distance: float = _rng.randf_range(min_distance, max_distance)
		return frame["position"] + Vector3(cos(angle), 0.0, sin(angle)) * distance
	return Vector3(_rng.randf_range(-180.0, 180.0), 0.0,
		_rng.randf_range(-150.0, 150.0))
