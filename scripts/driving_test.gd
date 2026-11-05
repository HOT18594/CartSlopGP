extends Node3D
## Scene-level wiring for the driving sandbox: hide the menu cursor and let the
## mouse be captured while driving. No gameplay logic lives here.

func _ready() -> void:
	CursorController.set_menu_mode(false)
