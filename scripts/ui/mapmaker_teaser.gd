extends Control
## Clean dark-slanted "COMING SOON" popup for the main-menu MAPMAKER teaser.
##
## The MAPMAKER tile is a greyed-out lock teaser that is still clickable (see
## `main_menu.gd` `_SimHeroTile.teaser`), so clicking it has to feel like a real
## menu action instead of a dead button. This overlay owns:
##   - one centred dark-glass slanted plate (UiKit.modal_panel + the shared
##     scrim), the exact `COMING SOON :D` copy and a single OK button;
##   - exactly one one-shot confetti burst per open. The burst is spawned on the
##     same frame the plate appears, is a CPUParticles2D (no viewport, no
##     process material, no texture asset — Godot draws CPUParticles2D as small
##     squares when no texture is set), and the node is retired when the
##     one-shot finishes (plus a safety timer) so it can never stack or emit
##     continuously;
##   - reduced-motion: no particles at all, the popup still opens.
##
## It joins the `nav_scope` group while visible (MenuNav picks the topmost
## visible scope), so keyboard/gamepad focus cannot escape behind it. Escape and
## a scrim click both route through `request_close()`.

signal closed

const UiAnim := preload("res://scripts/ui/ui_anim.gd")
const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const TITLE_FONT: Font = preload("res://assets/ui/fonts/LuckiestGuy-Regular.ttf")

const MESSAGE: String = "COMING SOON :D"
const TITLE: String = "MAPMAKER"
const HINT: String = "Build and share your own tracks in a future update."
const PANEL_MIN_SIZE: Vector2 = Vector2(560.0, 320.0)

## One-shot particle tuning. Short, punchy, UI-space only.
const CONFETTI_AMOUNT: int = 96
const CONFETTI_LIFETIME: float = 1.4 ## s; the whole burst is over in well under 2 s.
const CONFETTI_SAFETY_SECONDS: float = 2.6 ## Free even if `finished` never lands.
const CONFETTI_GRAVITY: Vector2 = Vector2(0.0, 620.0)
const CONFETTI_SPEED_MIN: float = 180.0
const CONFETTI_SPEED_MAX: float = 520.0

var _dim: ColorRect
var _panel: PanelContainer
var _message: Label
var _ok: Button

var _burst_count: int = 0
var _skipped_bursts: int = 0
var _live_burst: CPUParticles2D = null


class _TeaserLockBadge extends Control:
	## Oversized crisp procedural lock for the popup plate (same vector language
	## as the small lock drawn on the MAPMAKER rail tile, no binary assets).
	func _ready() -> void:
		custom_minimum_size = Vector2(74.0, 74.0)
		mouse_filter = Control.MOUSE_FILTER_IGNORE
		resized.connect(queue_redraw)

	func _draw() -> void:
		var center: Vector2 = size * 0.5
		var radius: float = 30.0
		draw_circle(center, radius, Color(UiPalette.YELLOW, 0.10))
		draw_arc(center, radius, 0.0, TAU, 44, Color(UiPalette.YELLOW, 0.45),
			2.0, true)
		var metal := Color(0.85, 0.88, 0.98, 0.95)
		var ink := UiPalette.INK
		# Shackle.
		var shackle_center: Vector2 = center + Vector2(0.0, -10.0)
		draw_arc(shackle_center, 12.0, PI, TAU, 22, metal, 6.0, true)
		# Body plate + keyhole.
		var body := Rect2(center + Vector2(-17.0, -3.0), Vector2(34.0, 26.0))
		draw_rect(body, metal, true)
		draw_rect(body, ink, false, 2.5)
		draw_circle(center + Vector2(0.0, 7.0), 3.4, ink)
		draw_rect(Rect2(center + Vector2(-1.7, 8.0), Vector2(3.4, 8.0)), ink, true)


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	add_to_group("nav_scope")
	mouse_filter = Control.MOUSE_FILTER_STOP
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_build_ui()
	hide()


func _build_ui() -> void:
	_dim = ColorRect.new()
	_dim.name = "Dim"
	_dim.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	UiKit.apply_scrim(_dim)
	_dim.gui_input.connect(_on_dim_input)
	add_child(_dim)

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(center)

	_panel = PanelContainer.new()
	_panel.name = "Panel"
	_panel.custom_minimum_size = PANEL_MIN_SIZE
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.add_theme_stylebox_override("panel", UiKit.modal_panel(44.0, 30.0))
	center.add_child(_panel)

	var body := VBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", UiKit.SPACING_MED)
	body.alignment = BoxContainer.ALIGNMENT_CENTER
	_panel.add_child(body)

	body.add_child(_TeaserLockBadge.new())

	var title := Label.new()
	title.name = "Title"
	title.text = TITLE
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.add_theme_font_override("font", TITLE_FONT)
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(title)

	_message = Label.new()
	_message.name = "Message"
	_message.text = MESSAGE
	_message.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_message.add_theme_font_override("font", TITLE_FONT)
	_message.add_theme_font_size_override("font_size", 40)
	_message.add_theme_color_override("font_color", UiPalette.YELLOW)
	_message.add_theme_color_override("font_outline_color", UiPalette.INK)
	_message.add_theme_constant_override("outline_size", 8)
	_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(_message)

	var hint := Label.new()
	hint.name = "Hint"
	hint.text = HINT
	hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hint.add_theme_font_size_override("font_size", int(UiKit.CAPTION_SIZE))
	hint.add_theme_color_override("font_color", UiPalette.TEXT_DIM)
	hint.mouse_filter = Control.MOUSE_FILTER_IGNORE
	body.add_child(hint)

	_ok = UiKit.tile("OK", UiPalette.YELLOW, 54.0, 24)
	_ok.name = "OkButton"
	_ok.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	UiKit.cap_button(_ok, 190.0)
	_ok.pressed.connect(close)
	body.add_child(_ok)


func open() -> void:
	## Show the plate, hand it the focus scope and fire the one-shot burst.
	show()
	visible = true
	UiAnim.modal_open(_panel, _dim)
	_fire_burst()
	MenuNav.refresh()
	MenuNav.focus(_ok)


func close() -> void:
	if not visible:
		return
	hide()
	_retire_all_bursts()
	_panel.scale = Vector2.ONE
	_panel.modulate = Color.WHITE
	MenuNav.refresh()
	closed.emit()


func request_close() -> void:
	close()


func _on_dim_input(event: InputEvent) -> void:
	## WS5P3-16: the scrim closes on a LEFT click only, matching the rest of the
	## slanted UI. A right/middle click at the popup must not dismiss it.
	if event is InputEventMouseButton and (event as InputEventMouseButton).pressed \
			and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT:
		close()


# --------------------------------------------------------------------------
# Confetti: one tagged one-shot CPUParticles2D per open, freed afterwards.
# --------------------------------------------------------------------------


func _reduced_motion() -> bool:
	var settings: Node = get_node_or_null("/root/GameSettings")
	return settings != null and bool(settings.get("reduce_motion"))


func _confetti_gradient() -> Gradient:
	var gradient := Gradient.new()
	gradient.set_color(0, UiPalette.YELLOW)
	gradient.set_color(1, UiPalette.PINK)
	gradient.add_point(0.33, UiPalette.CYAN)
	gradient.add_point(0.66, UiPalette.GRASS)
	return gradient


func _fire_burst() -> void:
	_retire_all_bursts()
	if _reduced_motion():
		_skipped_bursts += 1
		return
	var burst := CPUParticles2D.new()
	burst.name = "ConfettiBurst"
	burst.set_meta("ws2_confetti", true)
	burst.one_shot = true
	burst.amount = CONFETTI_AMOUNT
	burst.lifetime = CONFETTI_LIFETIME
	burst.explosiveness = 1.0
	burst.randomness = 0.55
	burst.local_coords = false
	burst.direction = Vector2(0.0, -1.0)
	burst.spread = 180.0
	burst.gravity = CONFETTI_GRAVITY
	burst.initial_velocity_min = CONFETTI_SPEED_MIN
	burst.initial_velocity_max = CONFETTI_SPEED_MAX
	burst.angular_velocity_min = -540.0
	burst.angular_velocity_max = 540.0
	burst.angle_min = 0.0
	burst.angle_max = 360.0
	burst.scale_amount_min = 2.5
	burst.scale_amount_max = 6.0
	burst.color_ramp = _confetti_gradient()
	burst.z_index = 20
	burst.position = get_viewport_rect().size * 0.5
	add_child(burst)
	_live_burst = burst
	_burst_count += 1
	burst.finished.connect(_retire_burst.bind(burst))
	get_tree().create_timer(CONFETTI_SAFETY_SECONDS).timeout.connect(
		_retire_burst.bind(burst))
	burst.restart()
	burst.emitting = true


func _retire_burst(burst: CPUParticles2D) -> void:
	if burst == null or not is_instance_valid(burst):
		return
	if _live_burst == burst:
		_live_burst = null
	burst.emitting = false
	if not burst.is_queued_for_deletion():
		burst.queue_free()


func _retire_all_bursts() -> void:
	if is_instance_valid(_live_burst):
		_retire_burst(_live_burst)
	_live_burst = null


func live_burst_count() -> int:
	## Test hook: live (not queued-for-deletion) tagged confetti emitters.
	var count: int = 0
	for child: Node in get_children():
		if child.has_meta("ws2_confetti") and is_instance_valid(child) \
				and not child.is_queued_for_deletion():
			count += 1
	return count


func burst_count() -> int:
	## Test hook: how many one-shot bursts this popup has fired.
	return _burst_count


func skipped_burst_count() -> int:
	## Test hook: bursts suppressed by the player's reduced-motion setting.
	return _skipped_bursts


func message_text() -> String:
	return _message.text if _message != null else ""


func ok_button() -> Button:
	return _ok
