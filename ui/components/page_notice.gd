extends PanelContainer

const Typography = preload("res://ui/theme/typography.gd")
const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const FluentTokens = preload("res://ui/theme/tokens/fluent_tokens.gd")

const Style = preload("res://ui/components/page_style.gd")
var message_label: Label

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_stylebox_override("panel", BoardUiStyle.card_face(20))
	message_label = Style.text("", Typography.BODY, true)
	add_child(message_label)
	hide()

func _ready() -> void:
	var fluent_variant: bool = get_meta("fluent_variant", false)

	if fluent_variant:
		# Fluent notice panel
		var panel_style := StyleBoxFlat.new()
		panel_style.bg_color = FluentTokens.NOTICE_BACKGROUND
		panel_style.border_color = FluentTokens.NOTICE_STROKE
		panel_style.set_border_width_all(1)
		panel_style.set_corner_radius_all(FluentTokens.RADIUS)
		panel_style.content_margin_left = 16
		panel_style.content_margin_right = 16
		panel_style.content_margin_top = 12
		panel_style.content_margin_bottom = 12
		add_theme_stylebox_override("panel", panel_style)

		message_label.add_theme_font_size_override("font_size", FluentTokens.CAPTION_SIZE)
		message_label.add_theme_color_override("font_color", FluentTokens.SECONDARY)
		message_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		message_label.mouse_filter = Control.MOUSE_FILTER_IGNORE

func show_message(message: String, is_error := false) -> void:
	var was_visible := visible
	message_label.text = message

	var fluent_variant: bool = get_meta("fluent_variant", false)
	if fluent_variant:
		# For Fluent variant, error uses danger color
		message_label.add_theme_color_override("font_color", FluentTokens.DANGER if is_error else FluentTokens.SECONDARY)
	else:
		message_label.add_theme_color_override("font_color", Color("b33c3c") if is_error else Color("64748b"))

	show()
	if not was_visible:
		Style.Motion.fade_in(self, Style.Motion.NOTICE_FADE)
