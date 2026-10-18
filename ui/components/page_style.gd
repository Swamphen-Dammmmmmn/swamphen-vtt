extends RefCounted

const Typography = preload("res://ui/theme/typography.gd")

const Motion = preload("res://ui/components/page_motion.gd")
const ButtonFocus = preload("res://ui/components/button_focus.gd")

const BACKGROUND := Color("e5e7eb")
const MAX_WIDTH := 1120.0
const PAGE_MARGIN := 32
const SECTION_GAP := 24
const ITEM_GAP := 12
const TITLE_SIZE := Typography.PAGE_TITLE
const BODY_SIZE := Typography.BODY
const BUTTON_HEIGHT := 44.0
const FIELD_LABEL_WIDTH := 112.0
const CUSTOMIZE_PANEL_WIDTH := 440.0
const LIBRARY_CARD_WIDTH := 220.0
const LIBRARY_PREVIEW_HEIGHT := 150.0

static func button(control: Button, primary := false, height := BUTTON_HEIGHT, danger := false) -> void:
	BoardUiStyle.action_button(control, height, primary and not danger, danger)
	if not primary or danger:
		for state in ["normal","hover","pressed","hover_pressed","disabled"]:
			var face := control.get_theme_stylebox(state).duplicate() as StyleBoxFlat
			face.set_border_width_all(2)
			face.border_color = Color("b8c3d1") if state=="disabled" else BoardUiStyle.BORDER_COLOR
			if danger and state!="disabled":
				face.bg_color = Color("fbe5e5") if state in ["pressed","hover_pressed"] else (Color("fff0f0") if state=="hover" else Color.TRANSPARENT)
			control.add_theme_stylebox_override(state,face)
	control.add_theme_font_size_override("font_size", BODY_SIZE)
	control.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	Motion.prepare_button(control)

static func card_button(control: Button, height := BUTTON_HEIGHT) -> void:
	button(control, false, height)
	for state in ["normal", "hover", "pressed", "hover_pressed", "disabled"]:
		var face := control.get_theme_stylebox(state).duplicate() as StyleBoxFlat
		face.set_border_width_all(2)
		face.border_color = Color("b8c3d1") if state == "disabled" else BoardUiStyle.BORDER_COLOR
		face.bg_color = Color("f0f4f9")
		if state == "hover": face.bg_color = Color("e6edf6")
		if state in ["pressed", "hover_pressed"]: face.bg_color = Color("d8e5f5")
		if state == "disabled": face.bg_color = Color("f8fafc")
		control.add_theme_stylebox_override(state, face)
	if not control.has_meta("card_focus_prepared"):
		control.set_meta("card_focus_prepared", true)
		control.add_child(ButtonFocus.new())

static func text(value: String, font_size := BODY_SIZE, secondary := false) -> Label:
	var label := Label.new()
	label.text = value
	if font_size >= Typography.SECTION:
		label.add_theme_font_override("font", Typography.MEDIUM)
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", Color("64748b") if secondary else Color("334155"))
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

static func field_label(value: String) -> Label:
	var label := text(value)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.custom_minimum_size.x = FIELD_LABEL_WIDTH
	label.size_flags_horizontal = Control.SIZE_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	return label

static func column(gap := ITEM_GAP) -> VBoxContainer:
	var box := VBoxContainer.new()
	box.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	box.add_theme_constant_override("separation", gap)
	return box

static func card() -> PanelContainer:
	var panel := PanelContainer.new()
	panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	panel.add_theme_stylebox_override("panel", BoardUiStyle.card_face(20))
	return panel
