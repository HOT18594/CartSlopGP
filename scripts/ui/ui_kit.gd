extends Node
## One source of truth for menu sizing. Any normal Button/LineEdit that enters
## the tree is snapped to the same height and type scale, so screens cannot
## drift apart again. Large preview cards (>= 120 px tall) are left alone.

const BUTTON_HEIGHT: float = 54.0
const FIELD_HEIGHT: float = 50.0
const BUTTON_FONT: int = 22
const FIELD_FONT: int = 18
const CORNER_RADIUS: int = 24


func _ready() -> void:
	get_tree().node_added.connect(_on_node_added)
	call_deferred("_normalize_tree", get_tree().root)


func _on_node_added(node: Node) -> void:
	if node is Button or node is LineEdit:
		call_deferred("_style_node", node)


func _normalize_tree(root: Node) -> void:
	_style_node(root)
	for child: Node in root.get_children():
		_normalize_tree(child)


func _style_node(node: Node) -> void:
	if not is_instance_valid(node) or not node.is_inside_tree():
		return
	if node is OptionButton or node is MenuButton:
		return
	if node is CheckButton:
		var toggle := node as CheckButton
		toggle.custom_minimum_size.y = BUTTON_HEIGHT
		toggle.add_theme_font_size_override("font_size", 18)
		return
	if node is Button:
		var button := node as Button
		# Minigame preview cards are Buttons too; keep their card size.
		if button.custom_minimum_size.y >= 120.0:
			return
		button.custom_minimum_size.y = BUTTON_HEIGHT
		button.add_theme_font_size_override("font_size", BUTTON_FONT)
		if "corner_radius" in button:
			button.set("corner_radius", CORNER_RADIUS)
	elif node is LineEdit:
		var field := node as LineEdit
		field.custom_minimum_size.y = FIELD_HEIGHT
		field.add_theme_font_size_override("font_size", FIELD_FONT)
