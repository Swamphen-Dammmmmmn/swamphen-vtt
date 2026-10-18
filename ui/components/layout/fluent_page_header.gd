extends HBoxContainer

const Typography = preload("res://ui/theme/typography.gd")

signal back_requested
const FluentButton = preload("res://ui/components/controls/fluent_button.gd")
const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
var title := ""

func _ready() -> void:
	theme = FluentTheme.shared()
	add_theme_constant_override("separation", 20)
	var back := FluentButton.new()
	back.text = "返回"
	back.icon_name = GoIconSet.BACK
	back.minimum_height = 48
	add_child(back)
	back.pressed.connect(func(): back_requested.emit())
	var label := Label.new()
	label.text = title
	label.theme_type_variation = "FluentStrong"
	label.add_theme_font_size_override("font_size", Typography.LIBRARY_TITLE)
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(label)
