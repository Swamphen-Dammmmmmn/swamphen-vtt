# Editor checkbox field component
extends "res://ui/components/forms/editor_field_base.gd"

signal value_changed(checked: bool)

var _checkbox: CheckBox

func _init() -> void:
	super._init()

	# Label
	_label = _create_label("")
	add_child(_label)

	# Checkbox
	_checkbox = CheckBox.new()
	_checkbox.custom_minimum_size.y = T.BUTTON_HEIGHT
	add_child(_checkbox)
	_input_control = _checkbox

	# Error label
	_error_label = _create_error_label()
	add_child(_error_label)

func _ready() -> void:
	super._ready()
	_checkbox.toggled.connect(_on_toggled)
	_update_appearance()

func setup(label_text: String, initial_value := false) -> void:
	"""Configure the field. Can be called before or after _ready()."""
	_label.text = label_text
	_checkbox.set_pressed_no_signal(initial_value)

func get_value() -> bool:
	return _checkbox.button_pressed

func set_value(value: bool, emit_signal := false) -> void:
	"""Set the checkbox state. Does not emit signal by default."""
	var old_value := _checkbox.button_pressed
	_checkbox.set_pressed_no_signal(value)
	if emit_signal and value != old_value:
		value_changed.emit(value)

func _update_appearance() -> void:
	"""Unified state refresh based on readonly and disabled flags."""
	super._update_appearance()
	_checkbox.disabled = _readonly or _disabled
	if _readonly or _disabled:
		_label.add_theme_color_override("font_color", T.DISABLED)
	else:
		_label.add_theme_color_override("font_color", T.SECONDARY)

func _on_toggled(pressed: bool) -> void:
	_clear_error_on_input()
	value_changed.emit(pressed)
