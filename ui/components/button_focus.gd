extends Node

var button: Button
var keyboard_face: StyleBox
var mouse_face := StyleBoxEmpty.new()
var _keyboard_mode := false

func _ready() -> void:
	button = get_parent() as Button
	refresh_theme_face()

func refresh_theme_face() -> void:
	if button == null: return
	button.remove_theme_stylebox_override("focus")
	keyboard_face = button.get_theme_stylebox("focus")
	button.add_theme_stylebox_override("focus", keyboard_face if _keyboard_mode else mouse_face)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		_keyboard_mode = false
		button.add_theme_stylebox_override("focus", mouse_face)
	elif event is InputEventKey and event.pressed:
		_keyboard_mode = true
		button.add_theme_stylebox_override("focus", keyboard_face)
