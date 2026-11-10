extends Node
## One source of truth for menu sizing and focus feedback. Any normal
## Button/LineEdit that enters the tree is snapped to the same height and type
## scale, so screens cannot drift apart again. Large preview cards
## (>= 120 px tall) are left alone.
##
## It also installs a bright, uniform keyboard-focus ring. Before this, the
## default theme ring was a thin white outline on an already white-outlined
## candy button, so arrow-key navigation was effectively invisible.

const BUTTON_HEIGHT: float = 54.0
const FIELD_HEIGHT: float = 50.0
const BUTTON_FONT: int = 22
const FIELD_FONT: int = 18
const CORNER_RADIUS: int = 24
const FOCUS_RING: Color = Color("ffd22e")
const FOCUS_RING_DARK: Color = Color("1e1b3a")


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
	# Every button is mouse/touch only, including swatches that opt out of the
	# size tokens.
	if node is Button:
		(node as Button).focus_mode = Control.FOCUS_NONE
	# Small colour swatches opt out: they are buttons, but not 54 px pills.
	if node.has_meta("skip_kit"):
		return
	if node is OptionButton or node is MenuButton:
		return
	if node is CheckButton:
		var toggle := node as CheckButton
		toggle.custom_minimum_size.y = BUTTON_HEIGHT
		toggle.add_theme_font_size_override("font_size", 18)
		toggle.alignment = HORIZONTAL_ALIGNMENT_CENTER
		toggle.focus_mode = Control.FOCUS_NONE
		return
	if node is Button:
		var button := node as Button
		# Minigame preview cards are Buttons too; keep their card size.
		if button.custom_minimum_size.y >= 120.0:
			return
		# Floor, not override: a screen that authored a 78 px PLAY button or a
		# 28 px RESUME keeps its hierarchy. Only buttons with no size/type set
		# fall back to the shared token.
		if button.custom_minimum_size.y <= 0.0:
			button.custom_minimum_size.y = BUTTON_HEIGHT
		if not button.has_theme_font_size_override("font_size"):
			button.add_theme_font_size_override("font_size", BUTTON_FONT)
		# Every action label is optically centred in its pill. The styleboxes
		# use symmetric top/bottom content margins, so vertical centring comes
		# from Button itself; this pins the horizontal side.
		button.alignment = HORIZONTAL_ALIGNMENT_CENTER
	elif node is LineEdit:
		var field := node as LineEdit
		field.custom_minimum_size.y = FIELD_HEIGHT
		field.add_theme_font_size_override("font_size", FIELD_FONT)


func _install_focus_ring(_button: Button) -> void:
	## Kept as a no-op for older call sites. Focus visuals were removed.
	pass
