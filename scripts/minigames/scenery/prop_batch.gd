extends RefCounted
## Accumulates coloured primitives into one merged, flat-shaded ArrayMesh.
##
## A real circuit needs hundreds of little boxes: posts, rails, steps, awnings,
## sign panels. Merging them into a single mesh with baked vertex colours keeps
## the whole group at one draw call with one shared material.

const SceneryKit := preload("res://scripts/minigames/scenery/scenery_kit.gd")

const _CORNERS: Array[Vector3] = [
	Vector3(-0.5, -0.5, -0.5), Vector3(0.5, -0.5, -0.5),
	Vector3(0.5, 0.5, -0.5), Vector3(-0.5, 0.5, -0.5),
	Vector3(-0.5, -0.5, 0.5), Vector3(0.5, -0.5, 0.5),
	Vector3(0.5, 0.5, 0.5), Vector3(-0.5, 0.5, 0.5),
]
const _FACES: Array = [
	[4, 5, 6, 7], [1, 0, 3, 2], [5, 1, 2, 6],
	[0, 4, 7, 3], [3, 7, 6, 2], [4, 0, 1, 5],
]

var _verts: PackedVector3Array = PackedVector3Array()
var _colors: PackedColorArray = PackedColorArray()
var _indices: PackedInt32Array = PackedInt32Array()


## Adds a box of `size` placed by `xform`, baked with `color`.
func add_box(xform: Transform3D, size: Vector3, color: Color) -> void:
	var corners: Array[Vector3] = []
	corners.resize(_CORNERS.size())
	for i in _CORNERS.size():
		var corner: Vector3 = _CORNERS[i]
		corners[i] = xform * Vector3(corner.x * size.x, corner.y * size.y,
			corner.z * size.z)
	for face: Array in _FACES:
		var base: int = _verts.size()
		for index: int in face:
			_verts.append(corners[index])
			_colors.append(color)
		_indices.append(base)
		_indices.append(base + 1)
		_indices.append(base + 2)
		_indices.append(base)
		_indices.append(base + 2)
		_indices.append(base + 3)


## Adds a quad from four corners, wound counter-clockwise when seen from the
## side the normal should face.
func add_quad(a: Vector3, b: Vector3, c: Vector3, d: Vector3,
		color: Color) -> void:
	var base: int = _verts.size()
	for corner: Vector3 in [a, b, c, d]:
		_verts.append(corner)
		_colors.append(color)
	_indices.append(base)
	_indices.append(base + 1)
	_indices.append(base + 2)
	_indices.append(base)
	_indices.append(base + 2)
	_indices.append(base + 3)


## Adds a single triangle, wound counter-clockwise when seen from its front.
func add_triangle(a: Vector3, b: Vector3, c: Vector3, color: Color) -> void:
	var base: int = _verts.size()
	for corner: Vector3 in [a, b, c]:
		_verts.append(corner)
		_colors.append(color)
	_indices.append(base)
	_indices.append(base + 1)
	_indices.append(base + 2)


## Adds a capped cylinder of `height` along local Y, transformed by `xform`.
func add_cylinder(xform: Transform3D, radius: float, height: float,
		segments: int, color: Color) -> void:
	var count: int = maxi(segments, 3)
	var half: float = height * 0.5
	var center_top: Vector3 = xform * Vector3(0.0, half, 0.0)
	var center_bottom: Vector3 = xform * Vector3(0.0, -half, 0.0)
	for i in count:
		var a0: float = TAU * float(i) / float(count)
		var a1: float = TAU * float(i + 1) / float(count)
		var bottom0 := Vector3(cos(a0) * radius, -half, sin(a0) * radius)
		var bottom1 := Vector3(cos(a1) * radius, -half, sin(a1) * radius)
		var top0 := Vector3(cos(a0) * radius, half, sin(a0) * radius)
		var top1 := Vector3(cos(a1) * radius, half, sin(a1) * radius)
		add_quad(xform * bottom0, xform * top0, xform * top1, xform * bottom1, color)
		add_triangle(center_top, xform * top1, xform * top0, color)
		add_triangle(center_bottom, xform * bottom0, xform * bottom1, color)


## Merges everything added so far. Returns null when the batch is empty.
func build() -> ArrayMesh:
	return SceneryKit.mesh_from(_verts, _colors, _indices, true)
