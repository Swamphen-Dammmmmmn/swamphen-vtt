extends VBoxContainer

const Typography = preload("res://ui/theme/typography.gd")

const Style = preload("res://ui/components/page_style.gd")
const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const FluentTokens = preload("res://ui/theme/tokens/fluent_tokens.gd")
const EyeOpen = preload("res://ui/icons/eye_open.svg")
const EyeClosed = preload("res://ui/icons/eye_closed.svg")
const InputAction = preload("res://ui/components/input_action_button.gd")
var input: LineEdit
var error: Label

func setup(title: String, placeholder: String, password := false) -> void:
	var compact: bool = get_meta("compact_error", false)
	var fluent_variant: bool = get_meta("fluent_variant", false)
	add_theme_constant_override("separation", 6 if (compact or fluent_variant) else 8)

	# Label styling
	if fluent_variant:
		var label := Label.new()
		label.text = title
		label.add_theme_font_size_override("font_size", FluentTokens.CAPTION_SIZE)
		label.add_theme_color_override("font_color", FluentTokens.SECONDARY)
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		add_child(label)
	else:
		add_child(Style.text(title, Typography.CAPTION if compact else Typography.BODY, compact))

	input = LineEdit.new()
	input.placeholder_text = placeholder
	input.secret = password
	input.max_length = 128 if password else 64
	input.custom_minimum_size.y = FluentTokens.BUTTON_HEIGHT if fluent_variant else Style.BUTTON_HEIGHT
	input.add_theme_font_size_override("font_size", FluentTokens.BODY_SIZE if fluent_variant else Style.BODY_SIZE)

	# Apply Fluent theme if requested
	if fluent_variant:
		input.theme = FluentTheme.shared()

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

	# Error label styling
	if fluent_variant:
		error = Label.new()
		error.text = ""
		error.add_theme_font_size_override("font_size", FluentTokens.CAPTION_SIZE)
		error.add_theme_color_override("font_color", FluentTokens.DANGER)
		error.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		error.mouse_filter = Control.MOUSE_FILTER_IGNORE
		error.hide()
	else:
		error = Style.text("", Typography.CAPTION)
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
