extends Node

var button: Button
var keyboard_face: StyleBox
var mouse_face := StyleBoxEmpty.new()

func _ready() -> void:
	button = get_parent() as Button
	keyboard_face = button.get_theme_stylebox("focus")
	button.add_theme_stylebox_override("focus", mouse_face)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		button.add_theme_stylebox_override("focus", mouse_face)
	elif event is InputEventKey and event.pressed:
		button.add_theme_stylebox_override("focus", keyboard_face)
