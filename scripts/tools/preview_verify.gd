extends SceneTree
## Throwaway check: confirms every generated preview has a Godot import and
## loads as a 1280x720 texture through the same ResourceLoader the menu uses.

const NAMES: PackedStringArray = ["circuit", "dockyard", "alpine", "cargo_rush"]


func _init() -> void:
	var failures: int = 0
	for name: String in NAMES:
		var path: String = "res://assets/ui/art/preview_%s.png" % name
		var exists: bool = ResourceLoader.exists(path)
		var texture: Texture2D = load(path) as Texture2D if exists else null
		var size: Vector2i = texture.get_size() if texture != null else Vector2i.ZERO
		print("%s exists=%s size=%s" % [path, exists, size])
		if texture == null or size != Vector2i(1280, 720):
			failures += 1
	quit(failures)
