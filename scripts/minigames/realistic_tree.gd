class_name RealisticTree
extends RefCounted
## Builds game-ready, textured broadleaf/conifer trees at runtime.
##
## Poly Haven's photogrammetry tree scans are 60-950 MB of geometry each, far too
## heavy to instance. Instead we use their CC0 PBR bark and leaf atlases on a
## deterministic procedural skeleton: tapered trunk, three levels of branches
## and ~150 alpha-cutout leaf cards. Each variant is ~1-1.5k vertices, so a few
## hundred trees still cost only a handful of MultiMesh draw calls while
## looking far more detailed than the flat-shaded low-poly trees.
##
## Returns {bark: ArrayMesh, leaf: ArrayMesh, atlas: String}.

const VARIANTS: Array[Dictionary] = [
	{"height": 9.2, "radius": 0.42, "crown": 3.1, "branches": 7, "cards": 8, "atlas": "broad", "lean": 0.05},
	{"height": 11.6, "radius": 0.38, "crown": 2.7, "branches": 8, "cards": 8, "atlas": "broad", "lean": 0.09},
	{"height": 7.8, "radius": 0.36, "crown": 3.6, "branches": 6, "cards": 10, "atlas": "broad", "lean": 0.13},
	{"height": 13.4, "radius": 0.40, "crown": 2.1, "branches": 10, "cards": 6, "atlas": "frond", "lean": 0.02},
	{"height": 6.4, "radius": 0.27, "crown": 2.5, "branches": 6, "cards": 8, "atlas": "broad", "lean": 0.16},
	{"height": 10.4, "radius": 0.35, "crown": 2.9, "branches": 8, "cards": 7, "atlas": "frond", "lean": 0.06},
]

# The broadleaf atlas has 5 leaves on the top row and 3 on the bottom row.
const BROAD_CELLS: Array[Rect2] = [
	Rect2(0.00, 0.00, 0.20, 0.50), Rect2(0.20, 0.00, 0.20, 0.50),
	Rect2(0.40, 0.00, 0.20, 0.50), Rect2(0.60, 0.00, 0.20, 0.50),
	Rect2(0.80, 0.00, 0.20, 0.50), Rect2(0.00, 0.50, 0.333, 0.50),
	Rect2(0.333, 0.50, 0.333, 0.50), Rect2(0.666, 0.50, 0.334, 0.50),
]
const FROND_CELLS: Array[Rect2] = [
	Rect2(0.00, 0.00, 0.50, 0.50), Rect2(0.50, 0.00, 0.50, 0.50),
	Rect2(0.00, 0.50, 0.50, 0.50), Rect2(0.50, 0.50, 0.50, 0.50),
]

# Scratch buffers, reset for every build.
var _v: PackedVector3Array
var _n: PackedVector3Array
var _uv: PackedVector2Array
var _idx: PackedInt32Array
var _rng: RandomNumberGenerator


static func variant_count() -> int:
	return VARIANTS.size()


static func atlas_for(index: int) -> String:
	return str(VARIANTS[index % VARIANTS.size()]["atlas"])


func build(index: int, seed_value: int) -> Dictionary:
	return _build(index, seed_value)


func _build(index: int, seed_value: int) -> Dictionary:
	var cfg: Dictionary = VARIANTS[index % VARIANTS.size()]
	_rng = RandomNumberGenerator.new()
	_rng.seed = seed_value + index * 7919
	var height: float = float(cfg["height"])
	var radius: float = float(cfg["radius"])
	var lean: float = float(cfg["lean"])
	var lean_angle: float = _rng.randf() * TAU
	var lean_dir := Vector3(cos(lean_angle), 0.0, sin(lean_angle)) * lean * height

	# ---------------------------------------------------------------- bark
	_reset()
	var segments: int = 7
	for s in segments:
		var t0: float = float(s) / float(segments)
		var t1: float = float(s + 1) / float(segments)
		_cylinder(_trunk(t0, height, lean_dir), _trunk(t1, height, lean_dir),
			radius * (1.0 - 0.62 * t0), radius * (1.0 - 0.62 * t1), 9,
			t0 * height * 0.45, t1 * height * 0.45)

	var tips: Array[Vector3] = []
	var branch_count: int = int(cfg["branches"])
	for level in 3:
		var level_count: int = branch_count + level * 2
		for b in level_count:
			var trunk_t: float = clampf(0.38 + 0.55 * float(level) / 3.0
				+ _rng.randf_range(-0.10, 0.14), 0.32, 0.96)
			var base: Vector3 = _trunk(trunk_t, height, lean_dir)
			var angle: float = TAU * (float(b) / float(level_count)) + _rng.randf_range(-0.45, 0.45)
			var lift: float = _rng.randf_range(0.30, 0.85) - level * 0.08
			var length: float = (float(cfg["crown"]) * (0.85 - 0.16 * float(level))) \
				* _rng.randf_range(0.72, 1.18)
			var direction := Vector3(cos(angle), lift, sin(angle)).normalized()
			var tip: Vector3 = base + direction * length
			var r0: float = radius * (0.34 - 0.06 * float(level))
			_cylinder(base, tip, maxf(r0, 0.045), maxf(r0 * 0.35, 0.02), 5, 0.0, 1.0)
			tips.append(tip)
			# A thinner sub-branch gives the crown a less synthetic silhouette.
			if level < 2 and _rng.randf() < 0.6:
				var sub_dir := Vector3(cos(angle + 0.8), lift * 0.6 + 0.3, sin(angle + 0.8)).normalized()
				var sub_tip: Vector3 = tip + sub_dir * length * 0.5
				_cylinder(tip, sub_tip, maxf(r0 * 0.4, 0.025), 0.018, 4, 0.0, 0.6)
				tips.append(sub_tip)
	var bark: ArrayMesh = _mesh()

	# ---------------------------------------------------------------- leaves
	_reset()
	var cells: Array[Rect2] = BROAD_CELLS if str(cfg["atlas"]) == "broad" else FROND_CELLS
	var cards: int = int(cfg["cards"])
	var card_size: float = 0.78 if str(cfg["atlas"]) == "broad" else 1.22
	for tip: Vector3 in tips:
		for c in cards:
			var offset := Vector3(
				_rng.randf_range(-0.85, 0.85),
				_rng.randf_range(-0.6, 0.9),
				_rng.randf_range(-0.85, 0.85)) * (float(cfg["crown"]) * 0.42)
			_card(tip + offset,
				card_size * _rng.randf_range(0.72, 1.35),
				_rng.randf() * TAU,
				_rng.randf_range(-0.55, 0.55),
				cells[_rng.randi_range(0, cells.size() - 1)])
	# A few extra cards fill the very top so the crown is not hollow.
	for c in 14:
		var top: Vector3 = _trunk(1.0, height, lean_dir)
		var offset := Vector3(_rng.randf_range(-1.0, 1.0),
			_rng.randf_range(-0.3, 0.9), _rng.randf_range(-1.0, 1.0))
		_card(top + offset, card_size, _rng.randf() * TAU,
			_rng.randf_range(-0.4, 0.4), cells[_rng.randi_range(0, cells.size() - 1)])
	var leaf: ArrayMesh = _mesh()
	return {"bark": bark, "leaf": leaf, "atlas": str(cfg["atlas"]), "height": height}


func _trunk(t: float, height: float, lean_dir: Vector3) -> Vector3:
	return Vector3(lean_dir.x * t * t, t * height, lean_dir.z * t * t)


func _reset() -> void:
	_v = PackedVector3Array()
	_n = PackedVector3Array()
	_uv = PackedVector2Array()
	_idx = PackedInt32Array()


func _mesh() -> ArrayMesh:
	var arrays: Array = []
	arrays.resize(Mesh.ARRAY_MAX)
	arrays[Mesh.ARRAY_VERTEX] = _v
	arrays[Mesh.ARRAY_NORMAL] = _n
	arrays[Mesh.ARRAY_TEX_UV] = _uv
	arrays[Mesh.ARRAY_INDEX] = _idx
	var mesh := ArrayMesh.new()
	mesh.add_surface_from_arrays(Mesh.PRIMITIVE_TRIANGLES, arrays)
	return mesh


func _cylinder(from: Vector3, to: Vector3, r0: float, r1: float,
		sides: int, v0: float, v1: float) -> void:
	var axis: Vector3 = to - from
	if axis.length_squared() < 0.000001:
		return
	axis = axis.normalized()
	var u: Vector3 = axis.cross(Vector3.UP)
	if u.length_squared() < 0.01:
		u = axis.cross(Vector3.RIGHT)
	u = u.normalized()
	var v: Vector3 = axis.cross(u).normalized()
	var base: int = _v.size()
	for i in sides + 1:
		var angle: float = TAU * float(i) / float(sides)
		var radial: Vector3 = (u * cos(angle) + v * sin(angle)).normalized()
		_v.append(from + radial * r0)
		_v.append(to + radial * r1)
		_n.append(radial)
		_n.append(radial)
		var uv_u: float = float(i) / float(sides)
		_uv.append(Vector2(uv_u, v0))
		_uv.append(Vector2(uv_u, v1))
	for i in sides:
		var a: int = base + i * 2
		_idx.append(a)
		_idx.append(a + 1)
		_idx.append(a + 2)
		_idx.append(a + 1)
		_idx.append(a + 3)
		_idx.append(a + 2)


func _card(center: Vector3, size: float, yaw: float, pitch: float, cell: Rect2) -> void:
	var basis: Basis = Basis(Vector3.UP, yaw) * Basis(Vector3.RIGHT, pitch)
	var half: float = size * 0.5
	var corners: Array[Vector3] = [
		Vector3(-half, -half * 0.55, 0.0),
		Vector3(half, -half * 0.55, 0.0),
		Vector3(half, half, 0.0),
		Vector3(-half, half, 0.0),
	]
	var uvs: Array[Vector2] = [
		Vector2(cell.position.x, cell.end.y),
		Vector2(cell.end.x, cell.end.y),
		Vector2(cell.end.x, cell.position.y),
		Vector2(cell.position.x, cell.position.y),
	]
	var inset: float = 0.004
	var base: int = _v.size()
	for i in 4:
		_v.append(center + basis * corners[i])
		# Up-facing normals give the canopy soft, even light on both sides.
		_n.append(Vector3.UP)
		var uv: Vector2 = uvs[i]
		uv.x = clampf(uv.x, cell.position.x + inset, cell.end.x - inset)
		uv.y = clampf(uv.y, cell.position.y + inset, cell.end.y - inset)
		_uv.append(uv)
	_idx.append(base)
	_idx.append(base + 1)
	_idx.append(base + 2)
	_idx.append(base)
	_idx.append(base + 2)
	_idx.append(base + 3)
