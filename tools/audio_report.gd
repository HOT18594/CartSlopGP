extends SceneTree

const DIRS: PackedStringArray = ["res://assets/audio"]


func _init() -> void:
	_report("res://assets/audio")
	quit(0)


func _report(path: String) -> void:
	var dir := DirAccess.open(path)
	if dir == null:
		return
	dir.list_dir_begin()
	var name: String = dir.get_next()
	while name != "":
		if name.begins_with("."):
			name = dir.get_next()
			continue
		var full: String = path + "/" + name
		if dir.current_is_dir():
			_report(full)
		elif name.get_extension().to_lower() in ["wav", "ogg", "mp3"]:
			var stream: AudioStream = load(full) as AudioStream
			if stream == null:
				print("MISSING ", full)
			else:
				print("%-72s %6.2fs" % [full, stream.get_length()])
		name = dir.get_next()
	dir.list_dir_end()
