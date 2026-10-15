class_name BoardUiStyle
extends RefCounted

static var configured := false
const BORDER_COLOR := Color("596a80")
const CARD_RADIUS := 12
const CONTROL_RADIUS := 8
const COMPACT_RADIUS := 6
const ACTION_PADDING := 6.0
const PANEL_PADDING := 12.0
const CONTENT_GAP := 8
const ACTION_HEIGHT := 32.0
const CONTROL_HEIGHT := 36.0
const EDIT_WIDTH := 320.0
const WIDE_WIDTH := 360.0
const FADE_TIME := 0.12
const HOVER_DELAY := 0.3
const CREATION_PALETTE_WIDTH := 960.0
const CREATION_SLOT_WIDTH := 104.0
const CREATION_SLOT_HEIGHT := 120.0
enum FloatingRole { ACTION, CONFIRM, EDIT, MENU, INFO }

static func floating_gap(role: int) -> float:
	match role:
		FloatingRole.CONFIRM: return 30.0
		FloatingRole.EDIT: return 16.0
		FloatingRole.MENU: return 8.0
		FloatingRole.INFO: return 10.0
	return 22.0

static func floating_position(dimensions: Vector2, anchor: Rect2, bounds: Vector2, left_margin: float, role: int = FloatingRole.ACTION, below := false) -> Vector2:
	var gap := floating_gap(role)
	var upper := anchor.position.y - dimensions.y - gap
	var lower := anchor.end.y + gap
	var y := lower if below else upper
	if below and lower + dimensions.y > bounds.y - 54.0 and upper >= 64.0:
		y = upper
	elif not below and upper < 64.0 and lower + dimensions.y <= bounds.y - 54.0:
		y = lower
	return Vector2(clampf(anchor.get_center().x - dimensions.x / 2.0, left_margin, maxf(left_margin, bounds.x - dimensions.x - 16)), clampf(y, 64, maxf(64, bounds.y - dimensions.y - 54))).round()

static func place_floating(control: Control, anchor: Rect2, bounds: Vector2, left_margin: float, role: int = FloatingRole.ACTION, below := false) -> void:
	control.reset_size()
	control.size = control.get_combined_minimum_size()
	control.position = floating_position(control.size, anchor, bounds, left_margin, role, below)
	if Mobile.enabled and control.get_parent() is Control:
		var safe := Mobile.local_safe_rect(control.get_parent())
		control.position = control.position.clamp(safe.position,(safe.end-control.size).max(safe.position))

static func popup_at(menu: PopupMenu, anchor: Rect2, bounds: Vector2, left_margin: float) -> void:
	menu.theme = GoUi.theme()
	menu.add_theme_font_size_override("font_size", roundi(14 * preload("res://scripts/ui_preferences.gd").shared().floating_text))
	menu.add_theme_constant_override("v_separation", 12)
	menu.add_theme_stylebox_override("panel", card_face(ACTION_PADDING))
	menu.reset_size()
	var dimensions := Vector2(menu.size)
	dimensions.x = maxf(dimensions.x, 160)
	dimensions.y = maxf(dimensions.y, 32)
	var at := floating_position(dimensions, anchor, bounds, left_margin, FloatingRole.MENU, true)
	menu.popup(Rect2i(Vector2i(at), Vector2i(dimensions)))

static func action_button(button: Button, height: float = ACTION_HEIGHT, primary := false, danger := false) -> void:
	button.custom_minimum_size.y = maxf(48,height) if OS.has_feature("android") or OS.get_cmdline_user_args().has("--mobile-preview") else height
	button.add_theme_font_size_override("font_size", 14)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var face := StyleBoxFlat.new()
		face.set_corner_radius_all(CONTROL_RADIUS)
		face.content_margin_left = 8
		face.content_margin_right = 8
		face.content_margin_top = 4 if height == ACTION_HEIGHT else 6
		face.content_margin_bottom = face.content_margin_top
		face.bg_color = Color("e1edfc") if state in ["pressed", "hover_pressed"] else (Color("f0f4f9") if state == "hover" else Color.TRANSPARENT)
		if primary:
			face.bg_color = Color("2563a6") if state in ["pressed", "hover_pressed"] else (Color("438ce5") if state == "hover" else Color("2e7ae0"))
		if state == "disabled":
			face.bg_color = Color("f8fafc")
		button.add_theme_stylebox_override(state, face)
		var ink := Color.WHITE if primary else (Color("b33c3c") if danger else Color("334155"))
		if state == "disabled":
			ink = Color("94a3b8")
		button.add_theme_color_override("font_" + ("color" if state == "normal" else state + "_color"), ink)
		button.add_theme_color_override("icon_" + state + "_color", ink)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.set_corner_radius_all(CONTROL_RADIUS)
	focus.set_border_width_all(2)
	focus.border_color = Color("60a5fa")
	button.add_theme_stylebox_override("focus", focus)

static func creation_slot(button: Button, empty: bool) -> void:
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var face := StyleBoxFlat.new()
		face.set_corner_radius_all(CONTROL_RADIUS)
		face.set_border_width_all(2)
		face.border_color = Color("dce3ec") if empty else BORDER_COLOR
		face.bg_color = Color("f3f6fa") if empty else (Color("e1edfc") if state in ["pressed", "hover_pressed"] else (Color("f0f4f9") if state == "hover" else Color.WHITE))
		button.add_theme_stylebox_override(state, face)

static func style_controls(root: Node, height: float = CONTROL_HEIGHT) -> void:
	if root is Button and not root is OptionButton and not root.get_meta("embedded_input_action",false):
		var face := root.get_theme_stylebox("normal") as StyleBoxFlat
		var primary: bool = root.theme_type_variation == &"PrimaryButton" or (face != null and face.bg_color.a > 0.5 and face.bg_color.r < 0.45 and face.bg_color.b > 0.4)
		action_button(root, height, primary)
	elif root is LineEdit:
		root.custom_minimum_size.y = maxf(48,height) if OS.has_feature("android") or OS.get_cmdline_user_args().has("--mobile-preview") else height
		root.add_theme_font_size_override("font_size", 14)
	elif root is OptionButton:
		root.custom_minimum_size.y = maxf(48,height) if OS.has_feature("android") or OS.get_cmdline_user_args().has("--mobile-preview") else height
		root.add_theme_font_size_override("font_size", 14)
	for child in root.get_children():
		style_controls(child, height)

static func configure() -> void:
	if configured:
		return
	configured = true
	var look := preload("res://addons/gohud/themes/gohud_light.tres").duplicate(true) as Theme
	var original := preload("res://ui/theme/modern.tres")
	look.default_font = original.default_font
	look.default_font_size = 14
	for type in look.get_type_list():
		for key in look.get_stylebox_list(type):
			var face := look.get_stylebox(key, type) as StyleBoxFlat
			if face == null:
				continue
			face.shadow_size = 0
			if type in ["PanelContainer", "GoCard", "PopupMenu"]:
				face.bg_color = Color.WHITE
				face.set_border_width_all(3)
				face.border_color = BORDER_COLOR
				face.set_corner_radius_all(CARD_RADIUS)
			elif type in ["LineEdit", "OptionButton"]:
				face.set_border_width_all(2)
				face.border_color = Color("60a5fa") if key == "focus" else Color("7b8a9e")
				face.set_corner_radius_all(CONTROL_RADIUS)
			elif "Button" in type:
				face.set_corner_radius_all(CONTROL_RADIUS)
	for target in [original, look]:
		for type in ["LineEdit", "OptionButton"]:
			for state in ["normal", "hover", "pressed", "hover_pressed", "disabled", "focus"]:
				var input_face := StyleBoxFlat.new()
				input_face.bg_color = Color.TRANSPARENT if state == "focus" else Color("f8fafc")
				input_face.set_corner_radius_all(CONTROL_RADIUS)
				input_face.set_border_width_all(2)
				input_face.border_color = Color("60a5fa") if state == "focus" else Color("7b8a9e")
				input_face.content_margin_left = 12
				input_face.content_margin_right = 12
				input_face.content_margin_top = 8
				input_face.content_margin_bottom = 8
				target.set_stylebox(state, type, input_face)
		var tip := StyleBoxFlat.new()
		tip.bg_color = Color.WHITE
		tip.set_corner_radius_all(COMPACT_RADIUS)
		tip.set_border_width_all(1)
		tip.border_color = BORDER_COLOR
		tip.set_content_margin_all(8)
		target.set_stylebox("panel", "TooltipPanel", tip)
	var config := GoConfig.new()
	config.preset = &"default_light"
	config.theme = look
	config.base_font_size = 14
	GoUi.config = config

static func card_face(padding: float = 10.0) -> StyleBoxFlat:
	var face := GoStyle.box(GoTheme.BOX_CARD, Color.TRANSPARENT, 1.0)
	face.bg_color = Color.WHITE
	face.set_border_width_all(3)
	face.border_color = BORDER_COLOR
	face.set_corner_radius_all(CARD_RADIUS)
	face.set_content_margin_all(padding)
	face.shadow_size = 0
	return face

static func sidebar_button(button: Button) -> void:
	var face := StyleBoxFlat.new()
	face.set_corner_radius_all(CONTROL_RADIUS)
	face.content_margin_left = 4
	face.content_margin_right = 4
	face.content_margin_top = 4
	face.content_margin_bottom = 4
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		button.add_theme_stylebox_override(state, face)
		var ink := Color("2563a6") if state in ["pressed", "hover_pressed"] else Color("334155")
		if state == "disabled":
			ink = Color("94a3b8")
		button.add_theme_color_override("font_" + ("color" if state == "normal" else state + "_color"), ink)
		button.add_theme_color_override("icon_" + state + "_color", ink)
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.set_corner_radius_all(CONTROL_RADIUS)
	focus.set_border_width_all(2)
	focus.border_color = Color("60a5fa")
	button.add_theme_stylebox_override("focus", focus)
	button.add_theme_constant_override("h_separation", 4)
	button.mouse_entered.connect(func():
		button.set_meta("sidebar_hover", true)
		refresh_sidebar_button(button, true)
	)
	button.mouse_exited.connect(func():
		button.set_meta("sidebar_hover", false)
		refresh_sidebar_button(button, true)
	)
	button.button_down.connect(func():
		button.set_meta("sidebar_down", true)
		refresh_sidebar_button(button, true)
	)
	button.button_up.connect(func():
		button.set_meta("sidebar_down", false)
		refresh_sidebar_button(button, true)
	)
	refresh_sidebar_button(button)

static func refresh_sidebar_button(button: Button, animate := false) -> void:
	var color := Color.TRANSPARENT
	if button.disabled:
		color = Color("f8fafc")
	elif button.get_meta("sidebar_down", false):
		color = Color("c9def7")
	elif button.button_pressed:
		color = Color("e1edfc")
	elif button.get_meta("sidebar_hover", false):
		color = Color("f0f4f9")
	var previous: Tween = button.get_meta("sidebar_tween") if button.has_meta("sidebar_tween") else null
	if previous and previous.is_valid():
		previous.kill()
	var face := button.get_theme_stylebox("normal") as StyleBoxFlat
	if animate:
		var motion := button.create_tween()
		motion.tween_property(face, "bg_color", color, preload("res://ui/components/page_motion.gd").duration(0.1))
		button.set_meta("sidebar_tween", motion)
	else:
		face.bg_color = color

static func configure_color_picker(button: ColorPickerButton) -> void:
	var popup := button.get_popup()
	var picker := button.get_picker()
	popup.theme = GoUi.theme()
	popup.add_theme_stylebox_override("panel", BoardUiStyle.card_face(BoardUiStyle.PANEL_PADDING))
	picker.theme = GoUi.theme()
	picker.modulate = Color.WHITE
	# Keep the picker surface fully opaque; its color swatches still show colors.
	var surface := StyleBoxFlat.new()
	surface.bg_color = Color.WHITE
	surface.set_corner_radius_all(BoardUiStyle.CONTROL_RADIUS)
	surface.set_content_margin_all(8)
	picker.add_theme_stylebox_override("panel", surface)
	popup.about_to_popup.connect(func():
		BoardUiStyle.style_controls(picker)
		popup.reset_size()
	)
	BoardUiStyle.style_controls(picker)

static func small_sidebar_entry(panel: PanelContainer, button: Button) -> void:
	panel.add_theme_stylebox_override("panel", card_face(ACTION_PADDING))
	button.custom_minimum_size.y = 40
	button.focus_mode = Control.FOCUS_NONE
	button.toggle_mode = true
	sidebar_button(button)
