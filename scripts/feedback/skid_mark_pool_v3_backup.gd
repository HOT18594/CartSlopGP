# class_name removed: would clash with the live script's global class
extends Node3D
## Fixed-size pool of skid mark quads that fade out and recycle.

@export var pool_size: int = 80 ## Maximum simultaneous skid marks (hard cap).
@export var mark_lifetime: float = 4.0 ## Seconds until a mark fades out.
@export var mark_scene: PackedScene = preload("res://scenes/feedback/skid_mark.tscn")

var _free: Array[MeshInstance3D] = []
var _active: Array[MeshInstance3D] = []


func _ready() -> void:
	for i in pool_size:
		var mark: MeshInstance3D = mark_scene.instantiate() as MeshInstance3D
		mark.visible = false
		mark.transparency = 1.0
		add_child(mark)
		_free.append(mark)


func spawn_mark(pos: Vector3, yaw: float) -> void:
	## Places one quad on the ground; recycles the oldest mark when full.
	if _free.is_empty() and not _active.is_empty():
		var oldest: MeshInstance3D = _active.pop_front()
		_free.append(oldest)
	if _free.is_empty():
		return
	var mark: MeshInstance3D = _free.pop_back()
	mark.global_transform = Transform3D(Basis(Vector3.UP, yaw), pos)
	mark.transparency = 0.0
	mark.visible = true
	_active.append(mark)


func _process(delta: float) -> void:
	var i: int = _active.size() - 1
	while i >= 0:
		var mark: MeshInstance3D = _active[i]
		mark.transparency = mark.transparency + delta / mark_lifetime
		if mark.transparency >= 1.0:
			mark.visible = false
			_free.append(mark)
			_active.remove_at(i)
		i -= 1


func active_count() -> int:
	return _active.size()


func clear_marks() -> void:
	while not _active.is_empty():
		var mark: MeshInstance3D = _active.pop_back()
		mark.visible = false
		_free.append(mark)
