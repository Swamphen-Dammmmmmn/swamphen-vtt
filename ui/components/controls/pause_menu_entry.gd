extends PanelContainer

const FluentButton = preload("res://ui/components/controls/fluent_button.gd")
const Tokens = preload("res://ui/theme/tokens/fluent_tokens.gd")

signal pressed
var context_title := "冒险菜单"

func _ready() -> void:
	add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	var button := FluentButton.new()
	button.text = "菜单"
	button.icon_name = GoIconSet.MENU
	button.tooltip_text = context_title + " · Esc"
	button.minimum_height = Tokens.PAUSE_TRIGGER_SIZE.y
	button.custom_minimum_size.x = Tokens.PAUSE_TRIGGER_SIZE.x
	add_child(button)
	button.pressed.connect(func(): pressed.emit())
