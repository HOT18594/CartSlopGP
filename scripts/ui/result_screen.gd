extends RefCounted
## Shared, mode-agnostic result / end-screen layout for every minigame.
##
## The four minigame scripts used to hand-build four different end screens with
## four different panel widths, scrims, banner paddings, row styles, button
## sets and focus orders. 0.8.7 replaces that with this one builder:
##
##   header   : slanted accent banner (title) + subtitle + optional status slot
##   content  : multiplayer -> [telemetry column | standings column]
##              solo          -> [telemetry column / standings column stacked]
##   actions  : primary (host / solo only) + [back | main menu] footer
##
## Every surface colour, gap and plate comes from UiKit / UiPalette, the
## standings table scrolls instead of growing past the 720p safe box, and the
## action set is driven by the caller so host-only vs client-only buttons can
## never drift between modes again.
##
## 0.8.7 host / non-host contract (resolved HERE, not in each mode):
##   * solo / multiplayer host: the authored primary + secondary + tertiary.
##     A MAIN MENU button that ends a live multiplayer session is gated by a
##     fast dark-slanted confirm dialog (Cancel / Leave).
##   * multiplayer non-host: the host-only set is replaced by a concise animated
##     "Waiting for host..." status and a single LEAVE LOBBY action. Even if a
##     caller passes stale primary/secondary/tertiary text, no host-only button
##     is ever built and the leave action is confirm-gated.
##
## The mode scripts keep ownership of the standings *data contract* (they still
## compute their own entry dictionaries); they only hand the rows over here.
##
## Build once:
##    _result_ui = ResultScreen.new()
##    _result_card = _result_ui.build(_hud_root, {
##        "title": "RACE COMPLETE",
##        "multiplayer": _multiplayer,
##        "primary_text": "RACE AGAIN",          # "" hides it (MP client)
##        "primary_color": UiPalette.YELLOW,
##        "on_primary": _on_race_again,
##        "secondary_text": "BACK TO LOBBY",
##        "on_secondary": _on_back_to_lobby,
##        "tertiary_text": "MAIN MENU",
##        "on_tertiary": _on_main_menu,
##        "standings_columns": [
##            {"label": "POS", "width": 34.0, "align": 1},
##            {"label": "DRIVER", "expand": true, "align": 0, "swatch": true},
##            {"label": "TOTAL", "width": 76.0, "align": 2},
##        ],
##    })
##
## Then fill it:
##    _result_ui.set_title(_result_card, "VICTORY!")
##    _result_ui.set_subtitle(_result_card, "MEADOW CUP  ·  3 LAPS")
##    _result_ui.set_standings(_result_card, entries)   # one entry per cart
##    _result_ui.present(_result_card)

const UiPalette := preload("res://scripts/ui/ui_palette.gd")
const Kit := preload("res://scripts/ui/ui_kit.gd")

const PANEL_MAX_WIDTH_MP: float = 1180.0
const PANEL_MAX_WIDTH_SOLO: float = 880.0
const STANDINGS_MIN_WIDTH: float = 430.0
const ROW_HEIGHT: float = 36.0
const ROW_SEPARATION: int = 6
const TITLE_FONT_SIZE: int = 30

## Multiplayer client flow: the animated status + the single exit action.
const WAITING_BASE_TEXT: String = "Waiting for host"
const WAITING_FONT_SIZE: int = 18
const WAITING_DOT_INTERVAL: float = 0.42 ## Seconds per dot step (1 -> 2 -> 3).
const LEAVE_TEXT_DEFAULT: String = "LEAVE LOBBY"
const LEAVE_BUTTON_WIDTH: float = 340.0

## Shared exit confirmation. Exact owner-specified copy for every gate.
const CONFIRM_QUESTION_DEFAULT: String = "Leave lobby and return to Main Menu?"
const CONFIRM_LEAVE_TEXT: String = "Leave"
const CONFIRM_CANCEL_TEXT: String = "Cancel"
const CONFIRM_MIN_WIDTH: float = 560.0
const CONFIRM_FONT_SIZE: int = 18
const CONFIRM_BUTTON_HEIGHT: float = 46.0
const CONFIRM_BUTTON_WIDTH: float = 190.0

## Max table height per variant, tuned so the whole card stays inside the
## 1280x720 safe box (720 - 2*SCREEN_MARGIN = 664) even with a visible status
## banner and the host's two action rows.
const TABLE_CAP_MP_HOST: float = 272.0
const TABLE_CAP_MP_CLIENT: float = 336.0
const TABLE_CAP_SOLO: float = 292.0
const STATUS_RESERVE: float = 40.0 ## Vertical budget kept for a status banner.

var _kit: Node


func _init() -> void:
	_kit = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("UiKit")


# --------------------------------------------------------------------------
# build
# --------------------------------------------------------------------------


func build(parent: Control, opts: Dictionary) -> Dictionary:
	var card: Dictionary = {}
	card["opts"] = opts
	card["multiplayer"] = bool(opts.get("multiplayer", false))
	card["is_host"] = bool(opts.get("is_host", true))

	var root := Control.new()
	root.name = str(opts.get("name", "ResultCard"))
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_STOP
	root.visible = false
	root.add_to_group("nav_scope")
	parent.add_child(root)
	card["root"] = root

	var dim := ColorRect.new()
	dim.name = "Dim"
	dim.set_anchors_preset(Control.PRESET_FULL_RECT)
	dim.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_kit.call("apply_scrim", dim)
	root.add_child(dim)
	card["dim"] = dim

	var center := CenterContainer.new()
	center.name = "Center"
	center.set_anchors_preset(Control.PRESET_FULL_RECT)
	center.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.add_child(center)
	card["center"] = center

	var panel := PanelContainer.new()
	panel.name = "ResultPanel"
	var multiplayer: bool = bool(card["multiplayer"])
	var max_width: float = float(opts.get("panel_width",
		PANEL_MAX_WIDTH_MP if multiplayer else PANEL_MAX_WIDTH_SOLO))
	var viewport: Vector2 = parent.get_viewport_rect().size
	panel.custom_minimum_size = Vector2(
		minf(max_width, maxf(620.0, viewport.x - Kit.SCREEN_MARGIN * 2.0)), 0.0)
	panel.add_theme_stylebox_override("panel",
		_kit.call("modal_panel", Kit.MODAL_PAD_H, Kit.MODAL_PAD_V, 0.045))
	center.add_child(panel)
	card["panel"] = panel

	var body := VBoxContainer.new()
	body.name = "Body"
	body.add_theme_constant_override("separation", Kit.SPACING_MED)
	panel.add_child(body)
	card["body"] = body

	_build_header(card, body, opts)
	_build_content(card, body, opts)
	_build_actions(card, body, opts)
	_build_confirm_overlay(card, opts)
	return card


func _build_header(card: Dictionary, body: VBoxContainer, opts: Dictionary) -> void:
	var header := VBoxContainer.new()
	header.name = "Header"
	header.add_theme_constant_override("separation", Kit.SPACING_TIGHT)
	body.add_child(header)
	card["header"] = header

	var banner := PanelContainer.new()
	banner.name = "TitleBanner"
	banner.add_theme_stylebox_override("panel",
		_kit.call("banner_style", opts.get("banner_color", UiPalette.YELLOW)))
	header.add_child(banner)
	card["title_banner"] = banner

	var title := Label.new()
	title.name = "ResultTitle"
	title.theme_type_variation = &"TitleLabel"
	title.add_theme_font_size_override("font_size", TITLE_FONT_SIZE)
	title.add_theme_color_override("font_color", UiPalette.INK)
	title.add_theme_constant_override("outline_size", 0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.clip_text = true
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.text = str(opts.get("title", "FINISHED"))
	banner.add_child(title)
	card["title"] = title

	var subtitle := _kit.call("label", str(opts.get("subtitle", "")),
		Kit.CAPTION_SIZE, UiPalette.CYAN) as Label
	subtitle.name = "ResultSubtitle"
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(subtitle)
	card["subtitle"] = subtitle

	# Status slot (racing's "WAITING FOR OTHER PLAYERS", host migration notes).
	# Hidden by default and folded into the header height budget when shown.
	var status_banner := PanelContainer.new()
	status_banner.name = "StatusBanner"
	status_banner.visible = false
	status_banner.add_theme_stylebox_override("panel",
		_kit.call("banner_style", UiPalette.YELLOW))
	header.add_child(status_banner)
	card["status_banner"] = status_banner
	var status := _kit.call("label", "", Kit.CAPTION_SIZE, UiPalette.INK) as Label
	status.name = "StatusLabel"
	status.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	status_banner.add_child(status)
	card["status_label"] = status


func _build_content(card: Dictionary, body: VBoxContainer, opts: Dictionary) -> void:
	var multiplayer: bool = bool(card["multiplayer"])
	var stacked: bool = bool(opts.get("stacked", false))
	if multiplayer and not stacked:
		var content := HBoxContainer.new()
		content.name = "Content"
		content.add_theme_constant_override("separation", Kit.SPACING_WIDE)
		body.add_child(content)
		card["content"] = content
		var telemetry := VBoxContainer.new()
		telemetry.name = "Telemetry"
		telemetry.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		telemetry.add_theme_constant_override("separation", Kit.SPACING_MED)
		content.add_child(telemetry)
		card["telemetry"] = telemetry
		if not (opts.get("standings_columns", []) as Array).is_empty():
			var standings := _build_standings(card, opts, true)
			content.add_child(standings)
		elif bool(opts.get("standings_slot", false)):
			# External standings: the mode owns its row contract (racing's
			# authoritative snapshot table) and only needs the column slot.
			var slot := VBoxContainer.new()
			slot.name = "StandingsSlot"
			slot.custom_minimum_size = Vector2(STANDINGS_MIN_WIDTH, 0.0)
			slot.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			slot.add_theme_constant_override("separation", Kit.SPACING_TIGHT)
			content.add_child(slot)
			card["standings_slot"] = slot
		return
	var content_solo := VBoxContainer.new()
	content_solo.name = "Content"
	content_solo.add_theme_constant_override("separation", Kit.SPACING_MED)
	body.add_child(content_solo)
	card["content"] = content_solo
	var telemetry_solo := VBoxContainer.new()
	telemetry_solo.name = "Telemetry"
	telemetry_solo.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	telemetry_solo.add_theme_constant_override("separation", Kit.SPACING_MED)
	content_solo.add_child(telemetry_solo)
	card["telemetry"] = telemetry_solo
	if not (opts.get("standings_columns", []) as Array).is_empty():
		var standings_solo := _build_standings(card, opts, false)
		content_solo.add_child(standings_solo)


func _build_standings(card: Dictionary, opts: Dictionary, multiplayer: bool) -> VBoxContainer:
	var column := VBoxContainer.new()
	column.name = "Standings"
	column.add_theme_constant_override("separation", Kit.SPACING_TIGHT)
	if multiplayer:
		column.custom_minimum_size = Vector2(STANDINGS_MIN_WIDTH, 0.0)
	var columns: Array = opts.get("standings_columns", [])
	card["standings_columns"] = columns

	var heading_text: String = str(opts.get("standings_title", "STANDINGS"))
	if heading_text != "":
		var heading := Label.new()
		heading.name = "StandingsHeading"
		heading.theme_type_variation = &"TitleLabel"
		heading.add_theme_font_size_override("font_size", 18)
		heading.add_theme_color_override("font_color", UiPalette.YELLOW)
		heading.add_theme_constant_override("outline_size", 0)
		heading.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		column.add_child(heading)
		card["standings_heading"] = heading

	# Column header, offset right by the scrollbar gutter so it lines up with
	# the rows inside the ScrollContainer.
	var header_pad := MarginContainer.new()
	header_pad.add_theme_constant_override("margin_right", 12)
	column.add_child(header_pad)
	var header := HBoxContainer.new()
	header.name = "StandingsHeader"
	header.add_theme_constant_override("separation", Kit.SPACING_TIGHT)
	header_pad.add_child(header)
	var has_swatch: bool = _has_swatch(columns)
	for def: Dictionary in columns:
		if bool(def.get("swatch", false)):
			var spacer := Control.new()
			spacer.custom_minimum_size = Vector2(14.0, 0.0)
			header.add_child(spacer)
			continue
		header.add_child(_header_label(str(def.get("label", "")), def))
	card["standings_header"] = header
	card["standings_has_swatch"] = has_swatch

	var scroll := ScrollContainer.new()
	scroll.name = "StandingsScroll"
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	scroll.follow_focus = true
	scroll.custom_minimum_size = Vector2(0.0, _standings_cap(card))
	column.add_child(scroll)
	card["standings_scroll"] = scroll

	var rows := VBoxContainer.new()
	rows.name = "StandingsRows"
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	rows.add_theme_constant_override("separation", ROW_SEPARATION)
	scroll.add_child(rows)
	card["standings_rows"] = rows
	card["standings"] = column
	return column


func _build_actions(card: Dictionary, body: VBoxContainer, opts: Dictionary) -> void:
	var actions := VBoxContainer.new()
	actions.name = "Actions"
	actions.add_theme_constant_override("separation", Kit.SPACING_TIGHT)
	body.add_child(actions)
	card["actions"] = actions

	var multiplayer: bool = bool(card["multiplayer"])
	var is_host: bool = bool(card["is_host"])
	if multiplayer and not is_host:
		# Canonical client action set. Host-only navigation (rematch / back to
		# lobby) and MAIN MENU are never built here, even if the caller passed
		# stale text, so a client can never trigger the host's session flow.
		_build_waiting_status(card, actions)
		_build_leave_action(card, actions, opts)
		card["focus_default"] = card.get("leave")
		return

	var primary_text: String = str(opts.get("primary_text", ""))
	if primary_text != "":
		var primary_row := HBoxContainer.new()
		primary_row.alignment = BoxContainer.ALIGNMENT_CENTER
		actions.add_child(primary_row)
		var primary: Button = _kit.call("tile", primary_text,
			opts.get("primary_color", UiPalette.YELLOW),
			float(opts.get("primary_height", 54.0)), Kit.BUTTON_FONT) as Button
		_kit.call("cap_button", primary, 460.0)
		primary.set_meta("nav_default", true)
		var on_primary: Callable = opts.get("on_primary", Callable())
		if on_primary.is_valid():
			primary.pressed.connect(on_primary)
		primary_row.add_child(primary)
		card["primary"] = primary

	var secondary_text: String = str(opts.get("secondary_text", ""))
	var tertiary_text: String = str(opts.get("tertiary_text", ""))
	if secondary_text == "" and tertiary_text == "":
		card["focus_default"] = card.get("primary")
		return
	var footer := HBoxContainer.new()
	footer.name = "SecondaryActions"
	footer.alignment = BoxContainer.ALIGNMENT_CENTER
	footer.add_theme_constant_override("separation", Kit.SPACING_MED)
	actions.add_child(footer)
	if secondary_text != "":
		var back: Button = _kit.call("tile", secondary_text,
			opts.get("secondary_color", UiPalette.CYAN),
			float(opts.get("secondary_height", 50.0)), Kit.COMPACT_FONT) as Button
		_kit.call("cap_button", back, 340.0)
		var on_secondary: Callable = opts.get("on_secondary", Callable())
		if on_secondary.is_valid():
			back.pressed.connect(on_secondary)
		footer.add_child(back)
		card["secondary"] = back
	if tertiary_text != "":
		var menu: Button = _kit.call("tile", tertiary_text,
			opts.get("tertiary_color", UiPalette.RED),
			float(opts.get("tertiary_height", 50.0)), Kit.COMPACT_FONT) as Button
		_kit.call("cap_button", menu, 340.0)
		var on_tertiary: Callable = opts.get("on_tertiary", Callable())
		if on_tertiary.is_valid():
			if bool(opts.get("confirm_main_menu", false)):
				# MAIN MENU ends a live multiplayer session: it uses the same
				# fast Cancel/Leave gate as a client's LEAVE LOBBY.
				menu.pressed.connect(func() -> void:
					_open_confirm(card,
						str(opts.get("confirm_question", CONFIRM_QUESTION_DEFAULT)),
						on_tertiary, menu))
			else:
				menu.pressed.connect(on_tertiary)
		footer.add_child(menu)
		card["tertiary"] = menu
	if not card.has("primary"):
		if card.has("secondary"):
			(card["secondary"] as Button).set_meta("nav_default", true)
		elif card.has("tertiary"):
			(card["tertiary"] as Button).set_meta("nav_default", true)
	card["focus_default"] = card.get("primary",
		card.get("secondary", card.get("tertiary")))


func _build_waiting_status(card: Dictionary, actions: VBoxContainer) -> void:
	## "Waiting for host..." with smoothly cycling dots, replacing the host-only
	## navigation for a multiplayer client. Reduce Motion keeps it static.
	var row := HBoxContainer.new()
	row.name = "WaitingRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	actions.add_child(row)
	var label: Label = _kit.call("label", WAITING_BASE_TEXT, WAITING_FONT_SIZE,
		UiPalette.CYAN) as Label
	label.name = "WaitingForHost"
	label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	row.add_child(label)
	card["waiting"] = label
	card["waiting_frame"] = 0
	_tick_waiting_dots(card)
	if _reduce_motion():
		return
	var timer := Timer.new()
	timer.name = "WaitingDotsTimer"
	timer.wait_time = WAITING_DOT_INTERVAL
	timer.one_shot = false
	timer.autostart = true
	timer.timeout.connect(_tick_waiting_dots.bind(card))
	(card["root"] as Control).add_child(timer)
	card["waiting_timer"] = timer


func _tick_waiting_dots(card: Dictionary) -> void:
	var label: Variant = card.get("waiting")
	if not (label is Label) or not is_instance_valid(label):
		return
	if _reduce_motion():
		(label as Label).text = WAITING_BASE_TEXT + "..."
		return
	# 1 -> 2 -> 3 dots, restarted forever: a smooth typing-dots pulse.
	var frame: int = int(card.get("waiting_frame", 0)) + 1
	card["waiting_frame"] = frame
	(label as Label).text = WAITING_BASE_TEXT + ".".repeat(1 + frame % 3)


func _build_leave_action(card: Dictionary, actions: VBoxContainer,
		opts: Dictionary) -> void:
	var row := HBoxContainer.new()
	row.name = "LeaveRow"
	row.alignment = BoxContainer.ALIGNMENT_CENTER
	actions.add_child(row)
	var leave: Button = _kit.call("tile",
		str(opts.get("leave_text", LEAVE_TEXT_DEFAULT)), UiPalette.RED,
		float(opts.get("leave_height", 50.0)), Kit.COMPACT_FONT) as Button
	_kit.call("cap_button", leave, LEAVE_BUTTON_WIDTH)
	leave.name = "LeaveLobby"
	leave.set_meta("nav_default", true)
	leave.pressed.connect(func() -> void: request_leave(card))
	row.add_child(leave)
	card["leave"] = leave


func _build_confirm_overlay(card: Dictionary, _opts: Dictionary) -> void:
	## One reusable dark-slanted Cancel/Leave dialog per card, hidden until a
	## gated action needs it. It is only registered as a nav scope while open, so
	## it can never capture focus when hidden.
	var dialog := _ConfirmDialog.new()
	dialog.name = "LeaveConfirm"
	(card["root"] as Control).add_child(dialog)
	dialog.confirmed.connect(_on_confirm_accepted.bind(card))
	dialog.cancelled.connect(_on_confirm_cancelled.bind(card))
	card["confirm"] = dialog


func _open_confirm(card: Dictionary, question: String, on_confirm: Callable,
		return_focus: Control = null) -> void:
	var dialog: Variant = card.get("confirm")
	if not (dialog is _ConfirmDialog) or not is_instance_valid(dialog):
		return
	card["confirm_action"] = on_confirm
	(dialog as _ConfirmDialog).open(question, CONFIRM_LEAVE_TEXT,
		CONFIRM_CANCEL_TEXT, return_focus)


func _on_confirm_accepted(card: Dictionary) -> void:
	var pending: Variant = card.get("confirm_action")
	card["confirm_action"] = Callable()
	if pending is Callable and (pending as Callable).is_valid():
		(pending as Callable).call()


func _on_confirm_cancelled(card: Dictionary) -> void:
	card["confirm_action"] = Callable()


# --------------------------------------------------------------------------
# action-set / confirmation API (public: modes call this; audits assert it)
# --------------------------------------------------------------------------


func request_leave(card: Dictionary) -> void:
	## What the client's LEAVE LOBBY button does. Always confirm-gated unless the
	## caller explicitly opts out with `confirm_leave = false`.
	if not bool(card["multiplayer"]) or bool(card["is_host"]):
		return
	var opts: Dictionary = card.get("opts", {}) as Dictionary
	var on_leave: Callable = opts.get("on_leave", Callable())
	if not bool(opts.get("confirm_leave", true)):
		if on_leave.is_valid():
			on_leave.call()
		return
	_open_confirm(card, str(opts.get("confirm_question",
		CONFIRM_QUESTION_DEFAULT)), on_leave, card.get("leave") as Control)


func action_set(card: Dictionary) -> Array[String]:
	## Visible action labels in visual order. The audit harness asserts the
	## host set is unchanged and a client only ever sees LEAVE LOBBY.
	var out: Array[String] = []
	for key: String in ["primary", "secondary", "tertiary", "leave"]:
		var node: Variant = card.get(key)
		if node is Button and is_instance_valid(node) \
				and (node as Button).is_visible_in_tree():
			out.append((node as Button).text)
	return out


func waiting_text(card: Dictionary) -> String:
	var label: Variant = card.get("waiting")
	if label is Label and is_instance_valid(label):
		return (label as Label).text
	return ""


func confirm_visible(card: Dictionary) -> bool:
	var dialog: Variant = card.get("confirm")
	if dialog is _ConfirmDialog and is_instance_valid(dialog):
		return (dialog as _ConfirmDialog).visible
	return false


func confirm_state(card: Dictionary) -> Dictionary:
	## {visible, question, buttons} for headless assertions.
	var dialog: Variant = card.get("confirm")
	if not (dialog is _ConfirmDialog) or not is_instance_valid(dialog):
		return {"visible": false, "question": "", "buttons": []}
	var gate: _ConfirmDialog = dialog as _ConfirmDialog
	return {"visible": gate.visible, "question": gate.question_text(),
		"buttons": gate.button_texts(), "cancel": gate.cancel_text(),
		"leave": gate.accept_text()}


func confirm_accept(card: Dictionary) -> void:
	var dialog: Variant = card.get("confirm")
	if dialog is _ConfirmDialog and is_instance_valid(dialog):
		(dialog as _ConfirmDialog).accept()


func confirm_cancel(card: Dictionary) -> void:
	var dialog: Variant = card.get("confirm")
	if dialog is _ConfirmDialog and is_instance_valid(dialog):
		(dialog as _ConfirmDialog).cancel()


func pause_isolation(card: Dictionary) -> Dictionary:
	## WS5P3-14 audit hook: while the gate is open, reports whether the scene's
	## PauseMenu Control was resolved, whether its unhandled-input processing is
	## off, and whether its own ESC-suspension API is engaged.
	var dialog: Variant = card.get("confirm")
	if dialog is _ConfirmDialog and is_instance_valid(dialog):
		return (dialog as _ConfirmDialog).debug_pause_isolation()
	return {"resolved": false, "processing": true, "api_suspended": false}


func _reduce_motion() -> bool:
	var loop: MainLoop = Engine.get_main_loop()
	if loop is SceneTree:
		var settings: Node = (loop as SceneTree).root.get_node_or_null(
			"GameSettings")
		return settings != null and bool(settings.get("reduce_motion"))
	return false



# --------------------------------------------------------------------------
# fill / update
# --------------------------------------------------------------------------


func set_title(card: Dictionary, text: String) -> void:
	(card["title"] as Label).text = text


func set_subtitle(card: Dictionary, text: String) -> void:
	(card["subtitle"] as Label).text = text


func set_banner_color(card: Dictionary, color: Color) -> void:
	(card["title_banner"] as PanelContainer).add_theme_stylebox_override("panel",
		_kit.call("banner_style", color))
	(card["title"] as Label).add_theme_color_override("font_color", UiPalette.INK)


func set_status(card: Dictionary, text: String, color: Color = UiPalette.YELLOW) -> void:
	var banner := card["status_banner"] as PanelContainer
	var label := card["status_label"] as Label
	label.text = text
	label.add_theme_color_override("font_color", UiPalette.INK)
	banner.add_theme_stylebox_override("panel", _kit.call("banner_style", color))
	banner.visible = text != ""


func clear_status(card: Dictionary) -> void:
	(card["status_banner"] as PanelContainer).visible = false


func present(card: Dictionary) -> void:
	## Reveal the card with the shared quick fade. Focus / nav-scope handling
	## stays with the mode script (it knows whether Pause is open).
	var root: Control = card["root"]
	root.visible = true
	root.modulate.a = 0.0
	var tween: Tween = root.create_tween()
	tween.tween_property(root, "modulate:a", 1.0, 0.22) \
		.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_OUT)


func focus_default(card: Dictionary) -> Control:
	var preferred: Variant = card.get("focus_default")
	if preferred is Control and is_instance_valid(preferred):
		return preferred as Control
	return null


# --------------------------------------------------------------------------
# standings table
# --------------------------------------------------------------------------


func set_standings(card: Dictionary, entries: Array) -> void:
	## entries: Array of dictionaries, one per cart:
	##   "cells":  Array of String values matching the column definitions
	##   "colors": optional Array of Color overrides per cell
	##   "local":  optional bool (cyan rim)
	##   "accent": optional Color (thicker rim, e.g. winner yellow)
	##   "swatch": optional Color (player colour dot when a column says swatch)
	var rows: VBoxContainer = card["standings_rows"]
	while rows.get_child_count() < entries.size():
		rows.add_child(_make_row(card))
	while rows.get_child_count() > entries.size():
		var extra: Node = rows.get_child(rows.get_child_count() - 1)
		rows.remove_child(extra)
		extra.queue_free()
	for index in entries.size():
		_apply_row(card, rows.get_child(index) as PanelContainer,
			entries[index] as Dictionary, index)
	var scroll: ScrollContainer = card["standings_scroll"]
	scroll.custom_minimum_size.y = _table_height(card, entries.size())
	(card["standings"] as VBoxContainer).visible = not entries.is_empty()


func clear_standings(card: Dictionary) -> void:
	set_standings(card, [])


func _make_row(card: Dictionary) -> PanelContainer:
	var panel := PanelContainer.new()
	panel.custom_minimum_size = Vector2(0.0, ROW_HEIGHT)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Kit.SPACING_TIGHT)
	panel.add_child(row)
	var columns: Array = card["standings_columns"]
	var labels: Array[Label] = []
	for def: Dictionary in columns:
		if bool(def.get("swatch", false)):
			var dot := ColorRect.new()
			dot.custom_minimum_size = Vector2(10.0, 12.0)
			dot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
			dot.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.add_child(dot)
			panel.set_meta("swatch", dot)
			continue
		var label := Label.new()
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.horizontal_alignment = int(def.get("align", HORIZONTAL_ALIGNMENT_LEFT))
		label.clip_text = true
		label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var width: float = float(def.get("width", 0.0))
		if width > 0.0:
			label.custom_minimum_size = Vector2(width, 0.0)
		if bool(def.get("expand", false)):
			label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		label.add_theme_font_size_override("font_size", int(def.get("font", 14)))
		label.add_theme_color_override("font_color",
			def.get("color", UiPalette.CREAM))
		row.add_child(label)
		labels.append(label)
	panel.set_meta("labels", labels)
	return panel


func _apply_row(card: Dictionary, panel: PanelContainer, entry: Dictionary,
		index: int) -> void:
	var labels: Array = panel.get_meta("labels")
	var cells: Array = entry.get("cells", [])
	var colors: Array = entry.get("colors", [])
	for cell_index in labels.size():
		var label: Label = labels[cell_index] as Label
		label.text = str(cells[cell_index]) if cell_index < cells.size() else ""
		var color: Color = UiPalette.CREAM
		if cell_index < colors.size():
			color = colors[cell_index] as Color
		else:
			var def: Dictionary = (card["standings_columns"] as Array)[cell_index] as Dictionary
			color = def.get("color", UiPalette.CREAM) as Color
		label.add_theme_color_override("font_color", color)
	if panel.has_meta("swatch"):
		var dot: ColorRect = panel.get_meta("swatch") as ColorRect
		dot.color = entry.get("swatch", UiPalette.SURFACE_CHIP) as Color
	var local: bool = bool(entry.get("local", false))
	var style: StyleBoxFlat = _kit.call("row_style", local) as StyleBoxFlat
	var accent: Variant = entry.get("accent")
	if accent is Color:
		style.border_color = accent as Color
		style.set_border_width_all(2)
	panel.add_theme_stylebox_override("panel", style)
	panel.set_meta("row_index", index)


func table_cap(card: Dictionary) -> float:
	## Vertical budget available to a standings table in this card. Modes that
	## build their own table (racing's canonical snapshot) size their
	## ScrollContainer from this so the action buttons stay on-screen.
	return _fit_table_cap(card)


func _table_height(card: Dictionary, row_count: int) -> float:
	if row_count <= 0:
		return 0.0
	var content: float = float(row_count) * (ROW_HEIGHT + float(ROW_SEPARATION)) + 4.0
	return clampf(content, ROW_HEIGHT + 4.0, _fit_table_cap(card))


func _fit_table_cap(card: Dictionary) -> float:
	## Per-card table cap: the card is measured against the 1280x720 safe box so
	## a solo telemetry column stacked above the table (racing) can never push
	## the action buttons off-screen.
	var hard_cap: float = _standings_cap(card)
	var header: Control = card.get("header") as Control
	var actions: Control = card.get("actions") as Control
	var telemetry: Control = card.get("telemetry") as Control
	var paddings: float = Kit.MODAL_PAD_V * 2.0 + Kit.SPACING_MED * 2.0
	var used: float = paddings + STATUS_RESERVE
	if header != null:
		used += header.get_combined_minimum_size().y
	if actions != null:
		used += actions.get_combined_minimum_size().y
	var multiplayer: bool = bool(card["multiplayer"])
	if not multiplayer and telemetry != null:
		used += telemetry.get_combined_minimum_size().y + Kit.SPACING_MED
	# Standings heading + column header + their two 10 px gaps.
	used += 18.0 + 18.0 + Kit.SPACING_TIGHT * 2.0
	var available: float = Kit.SCREEN_HEIGHT - Kit.SCREEN_MARGIN * 2.0 - used
	return clampf(available, ROW_HEIGHT + 4.0, hard_cap)


func _standings_cap(card: Dictionary) -> float:
	if not bool(card["multiplayer"]):
		return TABLE_CAP_SOLO
	if bool(card["is_host"]) or card.get("primary") != null:
		return TABLE_CAP_MP_HOST
	return TABLE_CAP_MP_CLIENT


func _has_swatch(columns: Array) -> bool:
	for def: Dictionary in columns:
		if bool(def.get("swatch", false)):
			return true
	return false


func _header_label(text: String, def: Dictionary) -> Label:
	var label := Label.new()
	label.text = text
	label.horizontal_alignment = int(def.get("align", HORIZONTAL_ALIGNMENT_LEFT))
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.clip_text = true
	var width: float = float(def.get("width", 0.0))
	if width > 0.0:
		label.custom_minimum_size = Vector2(width, 0.0)
	if bool(def.get("expand", false)):
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.add_theme_font_size_override("font_size", 12)
	label.add_theme_color_override("font_color", UiPalette.CYAN)
	return label


# --------------------------------------------------------------------------
# telemetry primitives (mode-specific content still lives in the mode script)
# --------------------------------------------------------------------------


func make_stat_tiles(captions: Array) -> Dictionary:
	## Caption row over value row: the shared "RACE TIME / BEST LAP / ..." grid.
	var grid := GridContainer.new()
	grid.columns = captions.size()
	grid.add_theme_constant_override("h_separation", Kit.SPACING)
	grid.add_theme_constant_override("v_separation", Kit.SPACING_TIGHT)
	var values: Array[Label] = []
	for caption_text: Variant in captions:
		grid.add_child(_header_label(str(caption_text), {"align": 1, "expand": true}))
	for _caption: Variant in captions:
		var value: Label = _kit.call("label", "—", Kit.BUTTON_FONT,
			UiPalette.CREAM) as Label
		value.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		value.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		grid.add_child(value)
		values.append(value)
	return {"grid": grid, "values": values}


func make_table(columns: Array) -> Dictionary:
	## Lightweight caption header + rows container for mode-specific tables
	## (racing lap table, cargo team breakdown). The mode fills the rows itself
	## with make_table_row() so its data contract stays untouched.
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", ROW_SEPARATION)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", Kit.SPACING_TIGHT)
	box.add_child(header)
	for def: Dictionary in columns:
		header.add_child(_header_label(str(def.get("label", "")), def))
	var rows := VBoxContainer.new()
	rows.add_theme_constant_override("separation", ROW_SEPARATION)
	rows.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_child(rows)
	return {"box": box, "header": header, "rows": rows}


func make_table_row(cells: Array, colors: Array = []) -> Dictionary:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", Kit.SPACING_TIGHT)
	var labels: Array[Label] = []
	for index in cells.size():
		var label := Label.new()
		label.text = str(cells[index])
		label.add_theme_font_size_override("font_size", 13)
		label.add_theme_color_override("font_color",
			colors[index] if index < colors.size() else UiPalette.CREAM)
		label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		label.clip_text = true
		label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(label)
		labels.append(label)
	return {"row": row, "labels": labels}


# --------------------------------------------------------------------------
# audit support (headless layout proof)
# --------------------------------------------------------------------------


func build_audit_card(host: Control, case: Dictionary) -> Dictionary:
	## Deterministic sample card for scripts/ui/ui_layout_audit.gd: exercises the
	## full header/content/standings/actions structure at both 720p and 1080p
	## without needing a live race or network session.
	var mode: String = str(case.get("mode", "racing"))
	var multiplayer: bool = bool(case.get("multiplayer", false))
	var is_host: bool = bool(case.get("is_host", true))
	var opts: Dictionary = {
		"name": "AuditResultCard",
		"title": _audit_title(mode, multiplayer),
		"subtitle": "%s  ·  3 LAPS  ·  MEADOW CUP" % mode.to_upper(),
		"multiplayer": multiplayer,
		"is_host": is_host,
		"primary_text": _audit_primary(mode, multiplayer, is_host),
		"on_primary": Callable(),
		"secondary_text": "BACK TO LOBBY" if multiplayer else "BACK TO MODES",
		"on_secondary": Callable(),
		"tertiary_text": "MAIN MENU",
		"on_tertiary": Callable(),
		# 0.8.7 host/non-host flow: a client card resolves to the animated
		# waiting status + LEAVE LOBBY; a host's MAIN MENU is confirm-gated.
		"on_leave": Callable(),
		"confirm_main_menu": multiplayer,
		"standings_columns": _audit_columns(mode),
	}
	var card: Dictionary = build(host, opts)
	var telemetry: VBoxContainer = card["telemetry"]
	_audit_telemetry(card, telemetry, mode, multiplayer)
	if multiplayer and mode == "racing":
		set_status(card, "WAITING FOR OTHER PLAYERS", UiPalette.YELLOW)
	var entries: Array = []
	for index in 7:
		entries.append(_audit_entry(mode, index))
	set_standings(card, entries)
	set_title(card, _audit_result_title(mode, true))
	present(card)
	return card


func _audit_title(mode: String, multiplayer: bool) -> String:
	match mode:
		"knockout":
			return "KNOCKOUT CHAMPION!"
		"cargo_rush":
			return "VICTORY!"
		"bomb_tag":
			return "WINNER!"
		_:
			return "RACE COMPLETE"


func _audit_result_title(mode: String, local_won: bool) -> String:
	match mode:
		"knockout":
			return "VICTORY!  ·  YOU" if local_won else "WINNER: RIVAL"
		"cargo_rush":
			return "VICTORY!" if local_won else "DEFEAT"
		"bomb_tag":
			return "VICTORY!  ·  #1 YOU" if local_won else "WINNER: RIVAL!"
		_:
			return "RACE COMPLETE"


func _audit_primary(mode: String, multiplayer: bool, is_host: bool) -> String:
	if multiplayer and not is_host:
		return ""
	if mode == "cargo_rush":
		return "PLAY AGAIN"
	if mode == "knockout":
		return "PLAY AGAIN"
	if mode == "bomb_tag":
		return "PLAY AGAIN"
	return "RACE AGAIN"


func _audit_columns(mode: String) -> Array:
	match mode:
		"knockout":
			return [
				{"label": "#", "width": 30.0, "align": 1, "color": UiPalette.CYAN},
				{"label": "DRIVER", "expand": true, "align": 0, "swatch": true},
				{"label": "KO", "width": 54.0, "align": 2},
				{"label": "PTS", "width": 62.0, "align": 2, "color": UiPalette.YELLOW},
			]
		"cargo_rush":
			return [
				{"label": "TEAM", "width": 64.0, "align": 0},
				{"label": "DRIVER", "expand": true, "align": 0, "swatch": true},
				{"label": "DELIVERIES", "width": 86.0, "align": 2, "color": UiPalette.YELLOW},
			]
		"bomb_tag":
			return [
				{"label": "#", "width": 30.0, "align": 1, "color": UiPalette.CYAN},
				{"label": "CONTESTANT", "expand": true, "align": 0},
				{"label": "PTS", "width": 50.0, "align": 2, "color": UiPalette.YELLOW},
				{"label": "PASSES", "width": 66.0, "align": 2},
				{"label": "SURVIVALS", "width": 82.0, "align": 2},
			]
		_:
			return [
				{"label": "POS", "width": 34.0, "align": 1, "color": UiPalette.CYAN},
				{"label": "DRIVER", "expand": true, "align": 0, "swatch": true},
				{"label": "TOTAL", "width": 76.0, "align": 2},
				{"label": "BEST", "width": 76.0, "align": 2, "color": UiPalette.CYAN},
				{"label": "GAP", "width": 64.0, "align": 2, "color": UiPalette.YELLOW},
			]


func _audit_entry(mode: String, index: int) -> Dictionary:
	var name_label: String = "YOU" if index == 1 else "DRIVER %d" % (index + 1)
	var local: bool = index == 1
	var accent: Variant = UiPalette.YELLOW if index == 0 else null
	match mode:
		"knockout":
			return {"cells": [str(index + 1), name_label, str(4 - mini(index, 3)),
				str(120 - index * 12)], "local": local, "accent": accent,
				"swatch": UiPalette.YELLOW.lerp(UiPalette.CYAN, float(index) / 7.0)}
		"cargo_rush":
			return {"cells": ["BLUE" if index % 2 == 0 else "RED", name_label,
				str(5 - mini(index, 4))], "local": local, "accent": accent,
				"swatch": UiPalette.BLUE if index % 2 == 0 else UiPalette.RED}
		"bomb_tag":
			return {"cells": [str(index + 1), name_label,
				str(60 - index * 5), str(8 + index), str(4 - mini(index, 3))],
				"local": local, "accent": accent}
		_:
			var total: float = 92.0 + float(index) * 3.5
			return {"cells": [str(index + 1), name_label,
				"1:%05.2f" % total, "0:3%02d.18" % index,
				"WINNER" if index == 0 else "+%d m" % (index * 18)],
				"local": local, "accent": accent,
				"swatch": UiPalette.YELLOW.lerp(UiPalette.CYAN, float(index) / 7.0)}


func _audit_telemetry(card: Dictionary, telemetry: VBoxContainer, mode: String,
		multiplayer: bool) -> void:
	if mode == "racing":
		var stats: Dictionary = make_stat_tiles(
			["RACE TIME", "BEST LAP", "POSITION", "LAPS"])
		telemetry.add_child(stats["grid"])
		var values: Array = stats["values"]
		(values[0] as Label).text = "1:32.41"
		(values[1] as Label).text = "0:29.18"
		(values[2] as Label).text = "1"
		(values[3] as Label).text = "3"
		var table: Dictionary = make_table([
			{"label": "LAP", "expand": true, "align": 0},
			{"label": "TIME", "width": 96.0, "align": 2},
			{"label": "DELTA", "width": 76.0, "align": 2},
		])
		telemetry.add_child(table["box"])
		var rows: VBoxContainer = table["rows"]
		for index in 3:
			rows.add_child(make_table_row(["LAP %d" % (index + 1),
				"0:3%02d.18" % (index + 2), "—" if index == 0 else "+0.42"])["row"])
	elif mode == "cargo_rush":
		var stats_cargo: Dictionary = make_stat_tiles(["BLUE", "RED"])
		telemetry.add_child(stats_cargo["grid"])
		var cargo_values: Array = stats_cargo["values"]
		(cargo_values[0] as Label).text = "4"
		(cargo_values[1] as Label).text = "2"
		var note: Label = _kit.call("label", "FIRST TO 5 DELIVERIES WINS",
			Kit.CAPTION_SIZE, UiPalette.TEXT_DIM) as Label
		note.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		telemetry.add_child(note)
	elif mode == "bomb_tag":
		var stats_bomb: Dictionary = make_stat_tiles(["ROUNDS", "SURVIVORS"])
		telemetry.add_child(stats_bomb["grid"])
		var bomb_values: Array = stats_bomb["values"]
		(bomb_values[0] as Label).text = "5"
		(bomb_values[1] as Label).text = "2"
	else:
		var stats_ko: Dictionary = make_stat_tiles(["ROUNDS", "FIGHTERS"])
		telemetry.add_child(stats_ko["grid"])
		var ko_values: Array = stats_ko["values"]
		(ko_values[0] as Label).text = "5"
		(ko_values[1] as Label).text = "6"


func audit_outside(card: Dictionary, design: Vector2) -> Array[String]:
	## Visible controls of the built card that escape the 1280x720 design box.
	var out: Array[String] = []
	_walk_outside(card["root"] as Node, design, out)
	return out


func _walk_outside(node: Node, design: Vector2, out: Array[String]) -> void:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	if node is Control:
		var control := node as Control
		var rect: Rect2 = control.get_global_rect()
		if rect.size.x >= 0.5 and rect.size.y >= 0.5:
			if rect.position.x < -2.0 or rect.position.y < -2.0 \
					or rect.end.x > design.x + 2.0 or rect.end.y > design.y + 2.0:
				if out.size() < 12:
					out.append("%s(%.0f,%.0f %.0fx%.0f)" % [control.name,
						rect.position.x, rect.position.y, rect.size.x, rect.size.y])
	# Scrolled content is clipped by its ScrollContainer; only the container
	# itself has to stay inside the design box.
	if node is ScrollContainer:
		return
	for child: Node in node.get_children():
		_walk_outside(child, design, out)


func audit_focus_ring(card: Dictionary) -> bool:
	## Every focusable control inside the card must be reachable from the
	## MenuNav ring built for this scope, and the ring must close.
	var nav: Node = (Engine.get_main_loop() as SceneTree).root.get_node_or_null("MenuNav")
	if nav == null:
		return false
	nav.call("refresh")
	var expected: Array[Control] = []
	_collect_focusables(card["root"] as Node, expected)
	if expected.is_empty():
		return false
	var focusables: Array = nav.get("_focusables")
	if focusables.is_empty():
		return false
	var expected_ids: Dictionary = {}
	for control: Control in expected:
		expected_ids[control.get_instance_id()] = true
	var ring_ids: Dictionary = {}
	var current: Control = focusables[0] as Control
	for _step in focusables.size() + 1:
		if not is_instance_valid(current):
			return false
		var id: int = current.get_instance_id()
		if ring_ids.has(id):
			break
		ring_ids[id] = true
		if current.focus_next.is_empty():
			# A card with a single action (the multiplayer client's LEAVE LOBBY)
			# is a valid closed ring: MenuNav leaves focus_next empty on purpose.
			if focusables.size() == 1:
				break
			return false
		current = current.get_node_or_null(current.focus_next) as Control
		if current == null:
			return false
	if ring_ids.size() != focusables.size():
		return false
	for id: int in expected_ids:
		if not ring_ids.has(id):
			return false
	return focusables.size() == expected.size()


func _collect_focusables(node: Node, out: Array[Control]) -> void:
	if node is CanvasItem and not (node as CanvasItem).is_visible_in_tree():
		return
	if node is Control:
		var control := node as Control
		if control.focus_mode != Control.FOCUS_NONE \
				and not control.has_meta("nav_skip") \
				and not (control is BaseButton and (control as BaseButton).disabled):
			out.append(control)
	for child: Node in node.get_children():
		_collect_focusables(child, out)


# --------------------------------------------------------------------------
# Leave confirmation gate (inner class: no extra script file, one owner)
# --------------------------------------------------------------------------


class _ConfirmDialog extends Control:
	## Fast dark-slanted Cancel/Leave gate over the result card (0.8.7).
	##
	## One instance per card, hidden until a gated action (client LEAVE LOBBY or
	## a host's MAIN MENU while a live session is active) asks for it. Built from
	## UiKit / UiPalette tokens so it matches pause/settings exactly; registered
	## as the topmost nav scope only while open, so it can never steal focus when
	## hidden. ESC/START cancel. While open it suspends the scene's PauseMenu ESC
	## handler through that menu's own `set_input_suspended()` API (WS5P3-14), so
	## diving out of the gate can never open the pause overlay behind it — the
	## isolation no longer relies on unhandled-input dispatch order.

	const Kit := preload("res://scripts/ui/ui_kit.gd")
	const UiPalette := preload("res://scripts/ui/ui_palette.gd")
	const UiAnim := preload("res://scripts/ui/ui_anim.gd")
	const DIALOG_MIN_WIDTH: float = 560.0
	const DIALOG_FONT_SIZE: int = 18
	const DIALOG_BUTTON_HEIGHT: float = 46.0
	const DIALOG_BUTTON_WIDTH: float = 190.0

	signal confirmed
	signal cancelled

	var _question_label: Label
	var _cancel_button: Button
	var _accept_button: Button
	var _panel: PanelContainer
	var _dim: ColorRect
	var _return_focus: Control = null
	var _pause_node: Node = null
	var _pause_was_processing: bool = true
	var _is_open: bool = false

	func _ready() -> void:
		set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		mouse_filter = Control.MOUSE_FILTER_STOP
		visible = false
		z_index = 60
		_dim = ColorRect.new()
		_dim.name = "Dim"
		_dim.set_anchors_preset(Control.PRESET_FULL_RECT)
		_dim.mouse_filter = Control.MOUSE_FILTER_STOP
		UiKit.apply_scrim(_dim)
		add_child(_dim)
		var center := CenterContainer.new()
		center.name = "Center"
		center.set_anchors_preset(Control.PRESET_FULL_RECT)
		center.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(center)
		_panel = PanelContainer.new()
		_panel.name = "ConfirmPanel"
		_panel.custom_minimum_size = Vector2(DIALOG_MIN_WIDTH, 0.0)
		_panel.add_theme_stylebox_override("panel",
			UiKit.modal_panel(32.0, 24.0, 0.05))
		center.add_child(_panel)
		var body := VBoxContainer.new()
		body.name = "Body"
		body.add_theme_constant_override("separation", Kit.SPACING_MED)
		_panel.add_child(body)
		_question_label = Label.new()
		_question_label.name = "Question"
		_question_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		_question_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_question_label.add_theme_font_size_override("font_size", DIALOG_FONT_SIZE)
		_question_label.add_theme_color_override("font_color", UiPalette.TEXT)
		body.add_child(_question_label)
		var row := HBoxContainer.new()
		row.name = "ChoiceRow"
		row.alignment = BoxContainer.ALIGNMENT_CENTER
		row.add_theme_constant_override("separation", Kit.SPACING_MED)
		body.add_child(row)
		_cancel_button = UiKit.tile("Cancel", UiPalette.CYAN,
			DIALOG_BUTTON_HEIGHT, Kit.COMPACT_FONT)
		_cancel_button.name = "CancelButton"
		UiKit.cap_button(_cancel_button, DIALOG_BUTTON_WIDTH)
		_cancel_button.pressed.connect(cancel)
		row.add_child(_cancel_button)
		_accept_button = UiKit.tile("Leave", UiPalette.RED,
			DIALOG_BUTTON_HEIGHT, Kit.COMPACT_FONT)
		_accept_button.name = "LeaveButton"
		UiKit.cap_button(_accept_button, DIALOG_BUTTON_WIDTH)
		_accept_button.pressed.connect(accept)
		row.add_child(_accept_button)
		set_process_unhandled_input(false)

	func open(question: String, accept_label: String, cancel_label: String,
			return_focus: Control) -> void:
		_question_label.text = question
		_accept_button.text = accept_label
		_cancel_button.text = cancel_label
		_return_focus = return_focus
		if not _is_open:
			_is_open = true
			visible = true
			_suspend_scene_pause()
			add_to_group("nav_scope")
			set_process_unhandled_input(true)
			UiAnim.modal_open(_panel, _dim)
		MenuNav.refresh()
		MenuNav.focus(_cancel_button)

	func cancel() -> void:
		if not _is_open:
			return
		_close()
		cancelled.emit()

	func accept() -> void:
		if not _is_open:
			return
		_close()
		confirmed.emit()

	func request_close() -> void:
		## MenuNav.close_top() fallback: ESC dismisses the gate, never the screen.
		cancel()

	func question_text() -> String:
		return _question_label.text if _question_label != null else ""

	func cancel_text() -> String:
		return _cancel_button.text if _cancel_button != null else ""

	func accept_text() -> String:
		return _accept_button.text if _accept_button != null else ""

	func button_texts() -> Array[String]:
		return [cancel_text(), accept_text()]

	func _close() -> void:
		_is_open = false
		visible = false
		remove_from_group("nav_scope")
		set_process_unhandled_input(false)
		_resume_scene_pause()
		MenuNav.refresh()
		if _return_focus != null and is_instance_valid(_return_focus) \
				and _return_focus.is_visible_in_tree():
			MenuNav.focus(_return_focus)
		_return_focus = null

	func _unhandled_input(event: InputEvent) -> void:
		if not _is_open:
			return
		if event.is_action_pressed("ui_cancel") or event.is_action_pressed("pause"):
			UiKit.consume_input(self)
			cancel()

	func _suspend_scene_pause() -> void:
		## WS5P3-14: make the isolation REAL. The pause screen is a CanvasLayer
		## root whose Control child (PauseMenu/Root) owns `pause_menu.gd`, so it
		## is resolved explicitly and asked to suspend its ESC handler through its
		## own API. The process-unhandled-input toggle is kept as belt-and-braces
		## (and preserves the existing live-scene assertion), but the API guard is
		## what guarantees ESC can never OPEN PAUSE behind the confirm gate even
		## if dispatch order or another node re-enables processing.
		var pause: Node = _find_scene_pause()
		if pause == null:
			return
		_pause_node = pause
		_pause_was_processing = _pause_node.is_processing_unhandled_input()
		if _pause_node.has_method("set_input_suspended"):
			_pause_node.call("set_input_suspended", true)
		_pause_node.set_process_unhandled_input(false)

	func _find_scene_pause() -> Node:
		## Resolve the scene's pause-menu Control regardless of which hop of the
		## CanvasLayer wrapper owns the script (the 0.8.6 scene puts it on the
		## Root child). Returns null when the scene has no pause menu.
		var tree: SceneTree = get_tree()
		if tree == null or tree.current_scene == null:
			return null
		var pause: Node = tree.current_scene.get_node_or_null("PauseMenu/Root")
		if pause == null:
			pause = tree.current_scene.get_node_or_null("PauseMenu")
		if pause == null:
			return null
		if pause.has_method("set_input_suspended") \
				or pause.has_method("_unhandled_input"):
			return pause
		return null

	func _resume_scene_pause() -> void:
		if _pause_node == null:
			return
		if is_instance_valid(_pause_node):
			# Clear the API guard first, then restore the original processing
			# state (a scene that had it disabled before must stay disabled).
			if _pause_node.has_method("set_input_suspended"):
				_pause_node.call("set_input_suspended", false)
			if _pause_was_processing:
				_pause_node.set_process_unhandled_input(true)
		_pause_node = null
		_pause_was_processing = true

	func debug_pause_isolation() -> Dictionary:
		## Audit hook (ws3_ui_checks / ui_layout_audit): proves ESC ownership.
		var paused: bool = _pause_node != null and is_instance_valid(_pause_node)
		var processing: bool = true
		var suspended: bool = false
		if paused:
			processing = (_pause_node as Node).is_processing_unhandled_input()
			if (_pause_node as Node).has_method("is_input_suspended"):
				suspended = bool((_pause_node as Node).call("is_input_suspended"))
		return {
			"resolved": paused,
			"processing": processing,
			"api_suspended": suspended,
		}
