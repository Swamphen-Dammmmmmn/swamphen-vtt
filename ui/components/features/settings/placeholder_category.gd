extends VBoxContainer

# Placeholder for unavailable settings category

const Typography = preload("res://ui/theme/typography.gd")
const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const FluentTokens = preload("res://ui/theme/tokens/fluent_tokens.gd")

func _ready() -> void:
	theme = FluentTheme.shared()

	var title := Label.new()
	title.text = get_meta("category_title", "")
	title.add_theme_font_override("font", Typography.MEDIUM)
	title.add_theme_font_size_override("font_size", Typography.SECTION)
	title.add_theme_color_override("font_color", FluentTokens.FOREGROUND)
	add_child(title)

	var message := Label.new()
	message.text = "此分类暂未开放。"
	message.add_theme_font_size_override("font_size", Typography.BODY)
	message.add_theme_color_override("font_color", FluentTokens.SECONDARY)
	add_child(message)
