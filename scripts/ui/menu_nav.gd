extends Node
## Keyboard and gamepad focus navigation for every menu.
##
## A "nav scope" is the screen the player is allowed to touch: the current
## full-screen Control, or the topmost visible overlay registered in the
## `nav_scope` group (Settings, Pause, Room Browser, Update, Changelog, the race
## result card). Only controls inside that scope can take focus, so arrow keys
## and Tab can never wander behind a dimmed overlay.
##
## `refresh()` is the single entry point every screen already calls after it
## opens, closes or rebuilds its list. It rebuilds the focus map for the current
## scope, wires explicit focus neighbours in all four directions plus a Tab
## loop, and restores focus to the control the player used last on that scope
## (or the marked default, or the first focusable control).
##
## Escape is a safety net: if nothing closer handled it, the top overlay is
## closed instead of every overlay being dismissed at once.

const SCOPE_GROUP: String = "nav_scope"
const VERIFY_INTERVAL: float = 0.25
const MIN_GAP: float = 1.0 ## Ignore candidates that are almost straight ahead.

var _scope: Control = null
var _focusables: Array[Control] = []
var _last_focus: Dictionary = {} ## scope instance id -> Control
var _dirty: bool = true
var _verify_timer: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	# A screen that is built before the UI is laid out still needs its focus
	# map; the deferred pass below catches the first frame of every scene.
	refresh()


func refresh() -> void:
	## Rebuild the focus map for the topmost menu scope. Cheap: call it on open,
	## close, page changes and after a list rebuild.
	_dirty = true


func focus(control: Control) -> bool:
	## Focus a specific control if it belongs to the current scope. Screens use
	## this for their "obvious" first action after a state change.
	if control == null or not is_instance_valid(control):
		return false
	if not _focusables.has(control):
		# A screen may call this before the deferred refresh ran (its own
		# _ready). Build the map now so the request is not silently dropped.
		_rebuild()
	if not _focusables.has(control):
		_dirty = true
		return false
	return _grab(control)


func focused_control() -> Control:
	## The control that currently owns keyboard focus, if any.
	var vp: Viewport = get_viewport()
	return vp.gui_get_focus_owner() if vp != null else null


func current_scope() -> Control:
	## The screen currently allowed to take focus (an overlay or the scene root).
	return _scope


func close_top() -> bool:
	## Dismiss only the overlay the player is looking at. Used as the
	## `ui_cancel` fallback so one Escape never tears down a whole stack.
	var top: Control = _find_top_scope()
	if top == null or top == get_tree().current_scene:
		return false
	if top.has_method("request_close"):
		top.call("request_close")
		return true
	if top.has_method("close"):
		top.call("close")
		return true
	return false


func _process(delta: float) -> void:
	if _dirty:
		_dirty = false
		_rebuild()
	_verify_timer += delta
	if _verify_timer < VERIFY_INTERVAL:
		return
	_verify_timer = 0.0
	_verify_focus()


func _unhandled_input(event: InputEvent) -> void:
	if not event.is_pressed() or event.is_echo():
		return
	var vp: Viewport = get_viewport()
	if vp == null:
		return

	# Allow WASD to navigate any active menu / overlay scope just like Arrow Keys,
	# while NEVER hijacking typing inside a LineEdit / TextEdit or driving in 3D!
	if event is InputEventKey:
		var kev := event as InputEventKey
		var focused: Control = vp.gui_get_focus_owner()
		var typing: bool = focused is LineEdit or focused is TextEdit
		if not typing and _is_menu_scope_active():
			var dir_side: int = -1
			match kev.physical_keycode:
				KEY_W: dir_side = SIDE_TOP
				KEY_S: dir_side = SIDE_BOTTOM
				KEY_A: dir_side = SIDE_LEFT
				KEY_D: dir_side = SIDE_RIGHT
			if dir_side != -1:
				if _move_focus_direction(dir_side):
					vp.set_input_as_handled()
					return

	if event.is_action("ui_accept") or event.is_action("ui_focus_next") \
			or event.is_action("ui_focus_prev"):
		# Enter on a screen whose focus was lost should select something rather
		# than do nothing forever.
		if vp.gui_get_focus_owner() == null:
			_dirty = true
		return
	if event.is_action("ui_cancel") or event.is_action("pause"):
		# If the user is typing in a text field, first ESC releases text focus.
		var focused_esc: Control = vp.gui_get_focus_owner()
		if focused_esc is LineEdit or focused_esc is TextEdit:
			vp.set_input_as_handled()
			focused_esc.release_focus()
			return
		if close_top():
			vp.set_input_as_handled()
			return
		# Universal ESC back-out fallback on every full-screen menu scene!
		if _back_out_current_scene():
			vp.set_input_as_handled()


func _is_menu_scope_active() -> bool:
	var top: Control = _find_top_scope()
	if top == null or not top.is_visible_in_tree():
		return false
	return true


func _move_focus_direction(side: int) -> bool:
	if _focusables.is_empty():
		_rebuild()
	if _focusables.is_empty():
		return false
	var vp: Viewport = get_viewport()
	var current: Control = vp.gui_get_focus_owner() if vp != null else null
	if current == null or not _focusables.has(current):
		return _grab(_default_focus())
	# Sliders & PillCyclers handle Left/Right natively via ui_left/ui_right!
	if (side == SIDE_LEFT or side == SIDE_RIGHT) and current.has_method("step"):
		current.call("step", -1 if side == SIDE_LEFT else 1)
		return true
	if (side == SIDE_LEFT or side == SIDE_RIGHT) and current is Range:
		var rng := current as Range
		var step_v: float = maxf(rng.step, (rng.max_value - rng.min_value) * 0.05)
		rng.value = clampf(rng.value + (-step_v if side == SIDE_LEFT else step_v), rng.min_value, rng.max_value)
		return true
	var next_path: NodePath
	match side:
		SIDE_LEFT: next_path = current.focus_neighbor_left
		SIDE_RIGHT: next_path = current.focus_neighbor_right
		SIDE_TOP: next_path = current.focus_neighbor_top
		SIDE_BOTTOM: next_path = current.focus_neighbor_bottom
	if not next_path.is_empty():
		var target: Control = current.get_node_or_null(next_path) as Control
		if target != null and _is_focusable(target):
			return _grab(target)
	return false


func _back_out_current_scene() -> bool:
	var scene: Node = get_tree().current_scene
	if scene == null or not (scene is Control):
		return false
	if SceneLoader != null and SceneLoader.has_method("is_busy") and SceneLoader.is_busy():
		return false
	for method_name: String in ["request_back", "_on_back_pressed", "_on_back", "_go_back"]:
		if scene.has_method(method_name):
			if UiKit != null and UiKit.has_method("play_back"):
				UiKit.play_back()
			scene.call(method_name)
			return true
	return false


func _rebuild() -> void:
	var old_scope: Control = _scope
	var vp: Viewport = get_viewport()
	var focused: Control = vp.gui_get_focus_owner() if vp != null else null
	if is_instance_valid(old_scope) and is_instance_valid(focused) \
			and old_scope.is_ancestor_of(focused):
		_last_focus[old_scope.get_instance_id()] = focused
	_scope = _find_top_scope()
	_focusables.clear()
	if is_instance_valid(_scope):
		_collect_focusables(_scope)
	_clean_last_focus()
	if _focusables.is_empty():
		return
	_wire_neighbours()
	var current: Control = vp.gui_get_focus_owner() if vp != null else null
	if current != null and _is_focusable(current) and _focusables.has(current):
		return
	_grab(_default_focus())


func _find_top_scope() -> Control:
	## Last visible nav scope in tree order is the topmost one; full-screen menu
	## scenes are their own scope even when they are not registered. Restrict
	## the walk to the current scene so an overlay from a scene that is being
	## torn down can never capture focus on the incoming screen.
	var scene: Node = get_tree().current_scene
	if scene != null:
		var best: Control = _walk_scopes(scene, null)
		if best != null:
			return best
		if scene is Control and (scene as Control).is_visible_in_tree():
			return scene as Control
	var fallback: Control = _walk_scopes(get_tree().root, null)
	if fallback != null:
		return fallback
	if scene is Control and (scene as Control).is_visible_in_tree():
		return scene as Control
	return null


func _walk_scopes(node: Node, best: Control) -> Control:
	for child: Node in node.get_children():
		if child is Control:
			var control := child as Control
			if control.is_in_group(SCOPE_GROUP) and control.is_visible_in_tree():
				best = control
		if child.get_child_count() > 0:
			best = _walk_scopes(child, best)
	return best


func _collect_focusables(node: Node) -> void:
	for child: Node in node.get_children():
		if child is Control:
			var control := child as Control
			if _is_focusable(control):
				_focusables.append(control)
		if child.get_child_count() > 0:
			_collect_focusables(child)


func _is_focusable(control: Control) -> bool:
	if not is_instance_valid(control) or not control.is_inside_tree():
		return false
	if control.focus_mode == Control.FOCUS_NONE:
		return false
	if not control.is_visible_in_tree():
		return false
	if control.has_meta("nav_skip"):
		return false
	if control is BaseButton and (control as BaseButton).disabled:
		return false
	return true


func _wire_neighbours() -> void:
	## Explicit neighbours in every direction. The engine's focus navigation
	## follows these paths before falling back to raw geometry, so a control at
	## the edge of a panel can never hand focus to something behind the dim.
	var rects: Array[Rect2] = []
	rects.resize(_focusables.size())
	for index in _focusables.size():
		rects[index] = _focusables[index].get_global_rect()
	for index in _focusables.size():
		var control: Control = _focusables[index]
		control.focus_neighbor_left = _neighbour_path(control, index, rects, SIDE_LEFT)
		control.focus_neighbor_right = _neighbour_path(control, index, rects, SIDE_RIGHT)
		control.focus_neighbor_top = _neighbour_path(control, index, rects, SIDE_TOP)
		control.focus_neighbor_bottom = _neighbour_path(control, index, rects, SIDE_BOTTOM)
		var count: int = _focusables.size()
		if count > 1:
			control.focus_next = _focusables[index].get_path_to(
				_focusables[(index + 1) % count])
			control.focus_previous = _focusables[index].get_path_to(
				_focusables[wrapi(index - 1, 0, count)])
		else:
			control.focus_next = NodePath()
			control.focus_previous = NodePath()


func _neighbour_path(control: Control, index: int, rects: Array[Rect2],
		side: int) -> NodePath:
	var target: int = _pick_neighbour(index, rects, side)
	if target < 0:
		return NodePath()
	return control.get_path_to(_focusables[target])


func _pick_neighbour(index: int, rects: Array[Rect2], side: int) -> int:
	var origin: Rect2 = rects[index]
	var best: int = -1
	var best_score: float = INF
	for other in rects.size():
		if other == index:
			continue
		var rect: Rect2 = rects[other]
		var primary: float = _primary_gap(origin, rect, side)
		if primary < MIN_GAP:
			continue
		var secondary: float = _secondary_gap(origin, rect, side)
		var overlap: bool = _overlaps(origin, rect, side)
		var score: float = primary + secondary * (0.35 if overlap else 1.6)
		if score < best_score:
			best_score = score
			best = other
	if best >= 0:
		return best
	# Wrap along the same axis so the ring is never broken (no focus traps).
	for other in rects.size():
		if other == index:
			continue
		var rect: Rect2 = rects[other]
		var primary: float = _primary_gap(rect, origin, side)
		var score: float = primary + _secondary_gap(origin, rect, side) * 0.35
		if score < best_score:
			best_score = score
			best = other
	return best


func _primary_gap(origin: Rect2, other: Rect2, side: int) -> float:
	var origin_center: Vector2 = origin.get_center()
	var other_center: Vector2 = other.get_center()
	match side:
		SIDE_LEFT:
			return origin_center.x - other_center.x
		SIDE_RIGHT:
			return other_center.x - origin_center.x
		SIDE_TOP:
			return origin_center.y - other_center.y
		SIDE_BOTTOM:
			return other_center.y - origin_center.y
	return 0.0


func _secondary_gap(origin: Rect2, other: Rect2, side: int) -> float:
	var origin_center: Vector2 = origin.get_center()
	var other_center: Vector2 = other.get_center()
	if side == SIDE_LEFT or side == SIDE_RIGHT:
		return absf(other_center.y - origin_center.y)
	return absf(other_center.x - origin_center.x)


func _overlaps(origin: Rect2, other: Rect2, side: int) -> bool:
	if side == SIDE_LEFT or side == SIDE_RIGHT:
		return origin.position.y < other.end.y and other.position.y < origin.end.y
	return origin.position.x < other.end.x and other.position.x < origin.end.x


func _default_focus() -> Control:
	var id: int = _scope.get_instance_id()
	var remembered: Variant = _last_focus.get(id)
	if remembered is Control and is_instance_valid(remembered) \
			and _focusables.has(remembered) and remembered.is_visible_in_tree():
		return remembered as Control
	for control: Control in _focusables:
		if control.has_meta("nav_default"):
			return control
	return _focusables[0]


func _grab(control: Control) -> bool:
	if not _is_focusable(control):
		return false
	control.grab_focus()
	return true


func _verify_focus() -> void:
	if not is_instance_valid(_scope) or _focusables.is_empty():
		return
	var vp: Viewport = get_viewport()
	if vp == null:
		return
	var focused: Control = vp.gui_get_focus_owner()
	if focused == null:
		_grab(_default_focus())
		return
	if _focusables.has(focused):
		return
	if not is_instance_valid(_scope) or not _scope.is_ancestor_of(focused):
		_grab(_default_focus())
		return
	# Still owned by this screen but no longer focusable (disabled mid-action,
	# hidden page). Move the ring somewhere usable instead of stranding it.
	if not _is_focusable(focused):
		_grab(_default_focus())


func _clean_last_focus() -> void:
	var stale: Array[int] = []
	for id: int in _last_focus:
		var control: Variant = _last_focus[id]
		# Validate before the type test: `is` on an already freed instance
		# raises "Left operand of 'is' is a previously freed instance", which
		# used to abort _rebuild() and leave the incoming menu with no focus.
		if not is_instance_valid(control) or not (control is Control):
			stale.append(id)
	for id: int in stale:
		_last_focus.erase(id)
