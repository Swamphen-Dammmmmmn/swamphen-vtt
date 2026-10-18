extends BoxContainer

# Fluent settings field: label + option selector
# Provides consistent horizontal layout for all settings options

const Typography = preload("res://ui/theme/typography.gd")
const FluentTokens = preload("res://ui/theme/tokens/fluent_tokens.gd")

var label: Label
var option: OptionButton

func _ready() -> void:
	add_theme_constant_override("separation", 16)
	custom_minimum_size.y = 40

	# Label on left
	label = Label.new()
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.add_theme_font_size_override("font_size", Typography.BODY)
	label.add_theme_color_override("font_color", FluentTokens.FOREGROUND)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.text_overrun_behavior = TextServer.OVERRUN_NO_TRIMMING
	add_child(label)

	# Option selector on right
	option = OptionButton.new()
	option.fit_to_longest_item = false
	option.clip_text = true
	option.custom_minimum_size.y = FluentTokens.BUTTON_HEIGHT
	option.size_flags_horizontal = Control.SIZE_SHRINK_END
	option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	add_child(option)

	resized.connect(_on_resized)

func _on_resized() -> void:
	vertical = size.x < FluentTokens.SETTINGS_FIELD_COMPACT_WIDTH
	option.size_flags_horizontal = Control.SIZE_EXPAND_FILL if vertical else Control.SIZE_SHRINK_END
	option.custom_minimum_size.x = 0 if vertical else clampf(size.x * 0.45, 160, 400)

func setup(label_text: String, items: Array) -> void:
	label.text = label_text
	for item in items:
		option.add_item(item)
