# Editor text field component
extends "res://ui/components/forms/editor_field_base.gd"

signal text_changed(value: String)

var _input: LineEdit

func _init() -> void:
	super._init()

	# Label
	_label = _create_label("")
	add_child(_label)

	# Input
	_input = LineEdit.new()
	_input.custom_minimum_size.y = T.BUTTON_HEIGHT
	_input.add_theme_font_size_override("font_size", T.BODY_SIZE)
	add_child(_input)
	_input_control = _input

	# Error label
	_error_label = _create_error_label()
	add_child(_error_label)

func _ready() -> void:
	super._ready()
	_input.text_changed.connect(_on_text_changed)
	_update_appearance()

func setup(label_text: String, placeholder := "", initial_value := "") -> void:
	"""Configure the field. Can be called before or after _ready()."""
	_label.text = label_text
	_input.placeholder_text = placeholder
	_input.text = initial_value

func get_value() -> String:
	return _input.text

func set_value(value: String, emit_signal := false) -> void:
	"""Set the text value. Does not reset cursor if already editing."""
	var old_text := _input.text
	if old_text == value:
		return

	var caret_pos := _input.caret_column
	_input.text = value
	if _input.has_focus() and value.length() == old_text.length():
		_input.caret_column = caret_pos

	if emit_signal:
		text_changed.emit(value)

func _update_appearance() -> void:
	"""Unified state refresh - applies colors based on all state flags."""
	super._update_appearance()
	_input.editable = not _readonly and not _disabled

	# Determine text color by priority: error > disabled > readonly > normal
	if _has_error:
		_input.add_theme_color_override("font_color", T.DANGER)
	elif _disabled:
		_input.add_theme_color_override("font_color", T.DISABLED)
	elif _readonly:
		_input.add_theme_color_override("font_color", T.SECONDARY)
	else:
		_input.add_theme_color_override("font_color", T.FOREGROUND)

func _on_text_changed(new_text: String) -> void:
	_clear_error_on_input()
	text_changed.emit(new_text)

func configure_input(max_length: int, keyboard_type: LineEdit.VirtualKeyboardType = LineEdit.KEYBOARD_TYPE_DEFAULT) -> void:
	_input.max_length = max_length
	_input.virtual_keyboard_type = keyboard_type

func focus_input() -> void:
	_input.grab_focus()

func is_editing() -> bool:
	# Hosts that echo external state skip overwriting text the user is typing.
	return _input.has_focus()
