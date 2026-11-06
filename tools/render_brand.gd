extends Control
## Dev-only: renders the boot splash and window icon from the live vector art.
## Run with:
##   godot --path . --resolution 1920x1080 res://tools/render_brand.tscn

const OUT_DIR := "C:/Users/ethan/Downloads/CartSlopGP/godot_project/assets/ui"
const THEME := "res://assets/ui/theme.tres"
const BACKGROUND := "res://scenes/ui/menu_background.tscn"
const CART_ART := "res://tools/brand_cart.gd"


func _ready() -> void:
	if has_node("/root/CursorController"):
		get_node("/root/CursorController").call("set_menu_mode", false)
	_build_splash()
	for i in 30:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var splash: Image = get_viewport().get_texture().get_image()
	splash.save_png(OUT_DIR + "/boot_splash.png")
	print("BRAND_SPLASH=", splash.get_width(), "x", splash.get_height())

	var icon: Image = await _render_icon()
	icon.save_png(OUT_DIR + "/cart_icon.png")
	print("BRAND_ICON=", icon.get_width(), "x", icon.get_height())
	get_tree().quit(0)


func _build_splash() -> void:
	theme = load(THEME)
	var background: Control = (load(BACKGROUND) as PackedScene).instantiate()
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	background.set("show_store", true)
	background.set("show_carts", false)
	add_child(background)

	var title_row := HBoxContainer.new()
	title_row.set_anchors_and_offsets_preset(Control.PRESET_TOP_WIDE)
	title_row.offset_top = 82.0
	title_row.offset_bottom = 430.0
	title_row.alignment = BoxContainer.ALIGNMENT_CENTER
	title_row.add_theme_constant_override("separation", 18)
	add_child(title_row)

	_add_title(title_row, "CART", Color("ffffff"), 188, -0.045)
	_add_title(title_row, "SLOP", Color("f26ca7"), 188, 0.030, true)
	_add_title(title_row, "GP", Color("ffd22e"), 210, -0.048)

	var cart := Control.new()
	cart.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	cart.set_script(load(CART_ART))
	cart.set("cart_scale", 1.95)
	cart.set("bottom_fraction", 0.93)
	add_child(cart)


func _add_title(parent: HBoxContainer, text: String, colour: Color,
		font_size: int, rotation: float, drips: bool = false) -> void:
	var label := Label.new()
	label.text = text
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.rotation = rotation
	label.pivot_offset = Vector2(130.0, 110.0)
	label.theme_type_variation = &"TitleLabel"
	label.add_theme_color_override("font_color", colour)
	label.add_theme_color_override("font_outline_color", Color("1e1b3a"))
	label.add_theme_color_override("font_shadow_color", Color(0.12, 0.10, 0.23, 0.42))
	label.add_theme_constant_override("outline_size", 24)
	label.add_theme_constant_override("shadow_offset_x", 0)
	label.add_theme_constant_override("shadow_offset_y", 14)
	label.add_theme_font_size_override("font_size", font_size)
	if drips:
		label.set_script(load("res://scripts/ui/drip_label.gd"))
	parent.add_child(label)


func _render_icon() -> Image:
	var viewport := SubViewport.new()
	viewport.size = Vector2i(256, 256)
	viewport.transparent_bg = true
	viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
	add_child(viewport)
	var art := Control.new()
	art.size = Vector2(256, 256)
	art.set_script(load(CART_ART))
	art.set("cart_scale", 1.0)
	art.set("bottom_fraction", 0.76)
	viewport.add_child(art)
	for i in 8:
		await get_tree().process_frame
	await RenderingServer.frame_post_draw
	return viewport.get_texture().get_image()
