extends VBoxContainer

const Style = preload("res://ui/components/page_style.gd")
const EyeOpen = preload("res://ui/icons/eye_open.svg")
const EyeClosed = preload("res://ui/icons/eye_closed.svg")
const InputAction = preload("res://ui/components/input_action_button.gd")
var input: LineEdit
var error: Label

func setup(title: String, placeholder: String, password := false) -> void:
	var compact: bool = get_meta("compact_error", false)
	add_theme_constant_override("separation", 6 if compact else 8)
	add_child(Style.text(title, 14 if compact else 16, compact))
	input = LineEdit.new()
	input.placeholder_text = placeholder
	input.secret = password
	input.max_length = 128 if password else 64
	input.custom_minimum_size.y = Style.BUTTON_HEIGHT
	input.add_theme_font_size_override("font_size", Style.BODY_SIZE)
	add_child(input)
	if password:
		var reveal := InputAction.new()
		reveal.toggle_mode = true
		reveal.icon = EyeClosed
		reveal.tooltip_text = "显示密码"
		reveal.accessibility_name = "显示密码"
		input.add_child(reveal)
		reveal.fit_input(input)
		reveal.toggled.connect(func(visible_text: bool):
			input.secret = not visible_text
			reveal.icon = EyeOpen if visible_text else EyeClosed
			reveal.tooltip_text = "隐藏密码" if visible_text else "显示密码"
			reveal.accessibility_name = reveal.tooltip_text
		)
	error = Style.text("", 14)
	error.add_theme_color_override("font_color", Color("b33c3c"))
	error.hide()
	add_child(error)
	input.text_changed.connect(func(_value: String): set_error(""))

func set_error(message: String) -> void:
	if get_meta("compact_error", false):
		preload("res://ui/components/editor_layout.gd").field_error(input, message)
		error.hide()
		return
	var was_visible := error.visible
	error.text = message
	error.visible = not message.is_empty()
	if error.visible and not was_visible:
		Style.Motion.fade_in(error, Style.Motion.NOTICE_FADE)
