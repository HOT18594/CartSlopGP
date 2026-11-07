extends Node
## Centralised keyboard / gamepad navigation for EVERY menu.
##
## The old behaviour relied on Godot's automatic spatial focus search. That
## broke on the candy buttons (they scale and rotate every frame), on the
## two-column grids, on hidden cards and on any screen with a LineEdit: focus
## jumped to a random button, got stuck behind an overlay, or leaked into a
## hidden panel. This autoload owns the whole problem instead.
##
##  - It discovers the active scope: the topmost visible modal overlay, else
##    the current screen. Hidden panels can never take focus.
##  - It builds a deterministic, geometry-aware focus map for every focusable
##    control and installs it as explicit focus_neighbor_* paths (so Tab and
##    the engine's own handling agree with the arrow keys).
##  - Arrow keys, WASD and d-pad move focus in the pressed direction with
##    wrapping. Left/right also drive screen-level actions when the screen
##    exposes `nav_horizontal(direction) -> bool` (page turn, vehicle swap).
##  - Typing is never stolen from a LineEdit, and sliders keep left/right for
##    their own value.

const REBUILD_INTERVAL: float = 0.30
const ROW_TOLERANCE: float = 18.0
const ROW_SNAP: float = 26.0
const CROSS_AXIS_PENALTY: float = 2.4

var _items: Array[Control] = []
var _scope: Control
var _timer: float = 0.0
var _dirty: bool = true
var _enabled_override: bool = true


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().node_added.connect(_mark_dirty)
	get_tree().node_removed.connect(_mark_dirty)


func set_enabled(value: bool) -> void:
	_enabled_override = value


func refresh() -> void:
	_mark_dirty()
	_rebuild()


func _mark_dirty(_node: Node = null) -> void:
	_dirty = true


func _nav_enabled() -> bool:
	if not _enabled_override:
		return false
	var cursor: Node = get_node_or_null("/root/CursorController")
	if cursor != null and cursor.has_method("is_menu_mode") \
			and not bool(cursor.call("is_menu_mode")):
		return false
	var loader: Node = get_node_or_null("/root/SceneLoader")
	if loader != null and loader.has_method("is_busy") and bool(loader.call("is_busy")):
		return false
	return true


func _process(delta: float) -> void:
	if not _nav_enabled():
		return
	_timer += delta
	if _dirty or _timer >= REBUILD_INTERVAL:
		_timer = 0.0
		_rebuild()


# --------------------------------------------------------------------------
# scope and focus map


func _find_scope() -> Control:
	## Overlays register themselves in the "nav_scope" group. The last visible
	## one wins, which handles nested overlays (settings opened from pause).
	var chosen: Control = null
	var best_depth: int = -1
	for node: Node in get_tree().get_nodes_in_group("nav_scope"):
		var control := node as Control
		if control == null or not control.is_visible_in_tree():
			continue
		# Nested overlays (settings inside the pause menu) are more specific
		# than the panel that owns them, regardless of _ready order.
		var depth: int = str(control.get_path()).split("/").size()
		if depth > best_depth:
			best_depth = depth
			chosen = control
	if chosen != null:
		return chosen
	return get_tree().current_scene as Control


func _collect_items(root: Node, output: Array[Control]) -> void:
	for child: Node in root.get_children():
		if child is CanvasItem and not (child as CanvasItem).is_visible_in_tree():
			continue
		var control := child as Control
		if control != null:
			if _usable(control):
				output.append(control)
			_collect_items(control, output)
		elif child.get_child_count() > 0:
			_collect_items(child, output)


func _usable(control: Control) -> bool:
	if not is_instance_valid(control):
		return false
	if control.focus_mode == Control.FOCUS_NONE or not control.is_visible_in_tree():
		return false
	if control is ScrollBar or control is Separator:
		return false
	if control is BaseButton and (control as BaseButton).disabled:
		return false
	if not (control is Button or control is LineEdit or control is Range
			or control is OptionButton or control is TextEdit):
		return false
	return true


func _center(control: Control) -> Vector2:
	return control.get_global_rect().get_center()


func _reading_order(a: Control, b: Control) -> bool:
	var a_row: float = snappedf(_center(a).y, ROW_SNAP)
	var b_row: float = snappedf(_center(b).y, ROW_SNAP)
	if not is_equal_approx(a_row, b_row):
		return a_row < b_row
	return _center(a).x < _center(b).x


func _rebuild() -> void:
	_dirty = false
	_scope = _find_scope()
	_items.clear()
	if _scope == null or not _scope.is_visible_in_tree():
		return
	_collect_items(_scope, _items)
	if _items.is_empty():
		return
	_items.sort_custom(Callable(self, "_reading_order"))
	_install_paths()


func _install_paths() -> void:
	## Explicit neighbours make Godot's own ui_* handling deterministic too,
	## including after a control is disabled or a card is shown/hidden.
	for item: Control in _items:
		item.focus_neighbor_top = _neighbor_path(item, Vector2.UP)
		item.focus_neighbor_bottom = _neighbor_path(item, Vector2.DOWN)
		item.focus_neighbor_left = _neighbor_path(item, Vector2.LEFT)
		item.focus_neighbor_right = _neighbor_path(item, Vector2.RIGHT)
	for index in _items.size():
		var item: Control = _items[index]
		var next_item: Control = _items[(index + 1) % _items.size()]
		var prev_item: Control = _items[(index - 1 + _items.size()) % _items.size()]
		item.focus_next = item.get_path_to(next_item)
		item.focus_previous = item.get_path_to(prev_item)


func _neighbor_path(from: Control, direction: Vector2) -> NodePath:
	var target: Control = _pick(from, direction)
	return from.get_path_to(target) if target != null and target != from else NodePath()


func _pick(from: Control, direction: Vector2) -> Control:
	var origin: Vector2 = _center(from)
	var vertical: bool = direction.y != 0.0
	# Two passes: first find the NEAREST ROW in the pressed direction, then
	# pick the closest control inside that row. A single weighted score lets a
	# centred button two rows down beat the button right next to you, which is
	# exactly the "arrow keys jump randomly" bug this controller exists to fix.
	var candidates: Array[Control] = []
	var nearest: float = INF
	for item: Control in _items:
		if item == from or not _usable(item):
			continue
		var point: Vector2 = _center(item)
		var main: float = (point.y - origin.y) if vertical else (point.x - origin.x)
		if direction.y < 0.0 and main > -ROW_TOLERANCE:
			continue
		if direction.y > 0.0 and main < ROW_TOLERANCE:
			continue
		if direction.x < 0.0 and main > -ROW_TOLERANCE:
			continue
		if direction.x > 0.0 and main < ROW_TOLERANCE:
			continue
		candidates.append(item)
		nearest = minf(nearest, absf(main))
	if candidates.is_empty():
		return _wrap_pick(from, direction, origin, vertical)
	var best: Control = null
	var best_cross: float = INF
	for item: Control in candidates:
		var point: Vector2 = _center(item)
		var main: float = (point.y - origin.y) if vertical else (point.x - origin.x)
		if absf(main) > nearest + ROW_SNAP:
			continue
		var cross: float = absf(point.x - origin.x) if vertical \
			else absf(point.y - origin.y)
		if cross < best_cross:
			best_cross = cross
			best = item
	return best if best != null else candidates[0]


func _wrap_pick(from: Control, direction: Vector2, origin: Vector2,
		vertical: bool) -> Control:
	## No control in that direction: wrap to the opposite edge, then take the
	## control in that edge row closest on the other axis.
	var edge: float = INF if (direction.y < 0.0 or direction.x < 0.0) else -INF
	for item: Control in _items:
		if item == from or not _usable(item):
			continue
		var coordinate: float = _center(item).y if vertical else _center(item).x
		edge = minf(edge, coordinate) if (direction.y < 0.0 or direction.x < 0.0) \
			else maxf(edge, coordinate)
	var best: Control = null
	var best_cross: float = INF
	for item: Control in _items:
		if item == from or not _usable(item):
			continue
		var point: Vector2 = _center(item)
		var coordinate: float = point.y if vertical else point.x
		if absf(coordinate - edge) > ROW_SNAP:
			continue
		var cross: float = absf(point.x - origin.x) if vertical \
			else absf(point.y - origin.y)
		if cross < best_cross:
			best_cross = cross
			best = item
	return best


# --------------------------------------------------------------------------
# input


func _input(event: InputEvent) -> void:
	if not _nav_enabled():
		return
	var viewport: Viewport = get_viewport()
	if viewport != null and viewport.has_method("is_input_handled") \
			and bool(viewport.call("is_input_handled")):
		return
	var direction: Vector2 = Vector2.ZERO
	var tab: int = 0
	var letter_nav: bool = false
	if event.is_action_pressed("ui_focus_next", true):
		tab = 1
	elif event.is_action_pressed("ui_focus_prev", true):
		tab = -1
	elif event.is_action_pressed("ui_up", true):
		direction = Vector2.UP
	elif event.is_action_pressed("ui_down", true):
		direction = Vector2.DOWN
	elif event.is_action_pressed("ui_left", true):
		direction = Vector2.LEFT
	elif event.is_action_pressed("ui_right", true):
		direction = Vector2.RIGHT
	else:
		var key := event as InputEventKey
		if key != null and key.pressed and not key.echo:
			letter_nav = true
			match key.keycode:
				KEY_W: direction = Vector2.UP
				KEY_S: direction = Vector2.DOWN
				KEY_A: direction = Vector2.LEFT
				KEY_D: direction = Vector2.RIGHT
				_: direction = Vector2.ZERO
		if direction == Vector2.ZERO and tab == 0:
			var joypad: Vector2 = _joypad_direction(event)
			if joypad != Vector2.ZERO:
				direction = joypad
				letter_nav = false
	if direction == Vector2.ZERO and tab == 0:
		return

	var focus: Control = viewport.gui_get_focus_owner() if viewport != null else null
	var typing: bool = focus is LineEdit or focus is TextEdit
	# LineEdits own their letters and horizontal arrows (caret movement).
	if typing and (letter_nav or direction.x != 0.0):
		return
	# Sliders / option buttons use left/right to change their own value.
	if direction.x != 0.0 and (focus is Range or focus is OptionButton):
		return

	viewport.set_input_as_handled()
	if _dirty or _items.is_empty():
		_rebuild()
	if _items.is_empty():
		return
	if tab != 0:
		_step(tab)
		return
	# A focused pill (BOTS / MODE) cycles its own value with left/right.
	if direction.x != 0.0 and focus != null and focus.has_method("step"):
		focus.call("step", int(signf(direction.x)))
		return
	if direction.x != 0.0 and _screen_action(int(signf(direction.x))):
		return
	_move(direction)


func _joypad_direction(event: InputEvent) -> Vector2:
	var pad := event as InputEventJoypadButton
	if pad == null or not pad.pressed:
		return Vector2.ZERO
	match pad.button_index:
		JOY_BUTTON_DPAD_UP: return Vector2.UP
		JOY_BUTTON_DPAD_DOWN: return Vector2.DOWN
		JOY_BUTTON_DPAD_LEFT: return Vector2.LEFT
		JOY_BUTTON_DPAD_RIGHT: return Vector2.RIGHT
	return Vector2.ZERO


func _screen_action(direction: int) -> bool:
	## Screens may claim left/right for a meaningful action. Returning true
	## means "handled", so focus does not move as well.
	var candidates: Array[Node] = []
	if _scope != null:
		candidates.append(_scope)
	var scene: Node = get_tree().current_scene
	if scene != null and scene != _scope:
		candidates.append(scene)
	for node: Node in candidates:
		if node != null and node.has_method("nav_horizontal"):
			return bool(node.call("nav_horizontal", direction))
	return false


func _step(direction: int) -> void:
	var focus: Control = get_viewport().gui_get_focus_owner()
	var index: int = _items.find(focus)
	var next_index: int = 0 if index < 0 else wrapi(index + direction, 0, _items.size())
	_focus(_items[next_index])


func _move(direction: Vector2) -> void:
	var focus: Control = get_viewport().gui_get_focus_owner()
	if focus == null or _items.find(focus) < 0:
		_focus(_items[0])
		return
	var target: Control = _pick(focus, direction)
	if target != null:
		_focus(target)


func _focus(control: Control) -> void:
	if not _usable(control):
		return
	control.grab_focus()
	_ensure_visible(control)


func _ensure_visible(control: Control) -> void:
	## Dynamic room lists live in a ScrollContainer; focus must scroll to them.
	var node: Node = control.get_parent()
	while node != null:
		var scroll := node as ScrollContainer
		if scroll != null:
			scroll.ensure_control_visible(control)
			return
		node = node.get_parent()
