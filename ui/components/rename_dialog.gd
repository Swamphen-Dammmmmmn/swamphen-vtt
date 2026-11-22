extends Control

signal name_saved(index: int, title: String)

const Typography = preload("res://ui/theme/typography.gd")
const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
const Icons = preload("res://ui/theme/icons/library_icons.gd")
const ButtonFocus = preload("res://ui/components/button_focus.gd")

var token_index := -1
var anchor_rect := Rect2()
var left_margin := 16.0
var top_margin := 64.0

func _ready() -> void:
	set_meta("style_owned", true)
	theme = FluentTheme.shared()
	$Panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	$Panel.custom_minimum_size.x = BoardUiStyle.EDIT_WIDTH
	var face := FluentTheme.face(T.SURFACE, T.STROKE, T.RADIUS, 1)
	face.set_content_margin_all(16)
	$Panel.add_theme_stylebox_override("panel", face)
	$Panel/Content.add_theme_constant_override("separation", 12)

	var heading := $Panel/Content/Header/Heading as Label
	heading.add_theme_font_override("font", Typography.MEDIUM)
	heading.add_theme_font_size_override("font_size", Typography.SECTION)
	heading.add_theme_color_override("font_color", T.FOREGROUND)

	var close := $Panel/Content/Header/Close as Button
	close.theme_type_variation = &"FluentInputAction"
	close.icon = Icons.texture("res://ui/theme/icons/close_tintable.svg")
	close.expand_icon = true
	close.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close.add_theme_constant_override("icon_max_width", 20)
	close.custom_minimum_size = Vector2(36, 36)
	close.focus_mode = Control.FOCUS_ALL
	close.add_child(ButtonFocus.new())
	close.pressed.connect(hide)

	var name_edit := $Panel/Content/Name as LineEdit
	name_edit.custom_minimum_size = Vector2(0, T.BUTTON_HEIGHT)

	var cancel_btn := $Panel/Content/Buttons/Cancel as Button
	cancel_btn.theme_type_variation = &"FluentButton"
	cancel_btn.custom_minimum_size.y = 38
	cancel_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	cancel_btn.add_child(ButtonFocus.new())
	cancel_btn.pressed.connect(hide)

	var save_btn := $Panel/Content/Buttons/Save as Button
	save_btn.theme_type_variation = &"FluentPrimary"
	save_btn.custom_minimum_size.y = 38
	save_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	save_btn.add_child(ButtonFocus.new())
	save_btn.pressed.connect(_save)

	resized.connect(_position_panel)
	gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			hide()
	)
	name_edit.text_submitted.connect(func(_text: String): _save())
	name_edit.text_changed.connect(func(text: String): save_btn.disabled = text.strip_edges().is_empty())

func open(index: int, title: String, at: Rect2, margin: float, top := 64.0) -> void:
	token_index = index
	anchor_rect = at
	left_margin = margin
	top_margin = top
	$Panel/Content/Name.text = title
	$Panel/Content/Buttons/Save.disabled = title.strip_edges().is_empty()
	show()
	$Panel.modulate.a = 0.0
	create_tween().tween_property($Panel, "modulate:a", 1.0, preload("res://ui/components/page_motion.gd").duration(BoardUiStyle.FADE_TIME))
	_position_panel.call_deferred()
	$Panel/Content/Name.grab_focus()
	$Panel/Content/Name.select_all()

func _position_panel() -> void:
	BoardUiStyle.place_floating($Panel, anchor_rect, size, left_margin, BoardUiStyle.FloatingRole.EDIT, false, top_margin)

func _save() -> void:
	var title: String = $Panel/Content/Name.text.strip_edges()
	if title.is_empty():
		return
	name_saved.emit(token_index, title)
	hide()

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide()
		get_viewport().set_input_as_handled()
