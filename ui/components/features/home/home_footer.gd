extends VBoxContainer

signal exit_requested
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const FluentButton = preload("res://ui/components/controls/fluent_button.gd")
var version := ""
var _exit: Button

func _ready() -> void:
	theme = FluentTheme.shared()
	add_theme_constant_override("separation", 16)
	var separator := HSeparator.new()
	var line := StyleBoxLine.new()
	line.color = Color("e0e4eb")
	line.thickness = 1
	separator.add_theme_stylebox_override("separator", line)
	separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(separator)
	var row := HBoxContainer.new()
	row.alignment = BoxContainer.ALIGNMENT_END
	row.add_theme_constant_override("separation", 16)
	add_child(row)
	var label := Label.new()
	label.text = "v"+version
	label.add_theme_font_size_override("font_size", T.CAPTION_SIZE)
	label.add_theme_color_override("font_color", T.SECONDARY)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(label)
	var exit := FluentButton.new()
	exit.text = "退出"
	exit.icon_name = GoIconSet.LOGOUT
	exit.minimum_height = 48
	exit.custom_minimum_size.x = 128
	_exit = exit
	row.add_child(exit)
	exit.pressed.connect(func(): exit_requested.emit())

# Public focus targets are for keyboard traversal only, not style/structure access.
func focus_targets() -> Array[Control]:
	return [_exit]
