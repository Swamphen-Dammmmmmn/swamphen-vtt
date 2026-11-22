# Editor spin field component (immediate numeric stepping & live preview)
extends "res://ui/components/forms/editor_field_base.gd"

signal value_changed(value: float)

var _spin: SpinBox

func _init() -> void:
	super._init()
	size_flags_horizontal = Control.SIZE_EXPAND_FILL

	_label = _create_label("")
	add_child(_label)

	_spin = SpinBox.new()
	_spin.custom_minimum_size.y = T.BUTTON_HEIGHT
	_spin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_spin.get_line_edit().add_theme_font_size_override("font_size", T.BODY_SIZE)
	add_child(_spin)
	_input_control = _spin

	_error_label = _create_error_label()
	add_child(_error_label)

func _ready() -> void:
	super._ready()
	_spin.value_changed.connect(func(val: float): value_changed.emit(val))
	_update_appearance()

func setup(label_text: String, min_val := 0.0, max_val := 100.0, step_val := 1.0, initial_value := 0.0) -> void:
	_label.text = label_text
	_spin.min_value = min_val
	_spin.max_value = max_val
	_spin.step = step_val
	_spin.set_value_no_signal(initial_value)

func set_spin_variation(variation: StringName) -> void:
	_spin.theme_type_variation = variation

func get_value() -> float:
	return _spin.value

func set_value(value: float, emit_signal := false) -> void:
	if emit_signal:
		_spin.value = value
	else:
		_spin.set_value_no_signal(value)

func _update_appearance() -> void:
	super._update_appearance()
	_spin.editable = not (_readonly or _disabled)
	var line_edit := _spin.get_line_edit()
	if _has_error:
		line_edit.add_theme_color_override("font_color", T.DANGER)
	elif _disabled:
		line_edit.add_theme_color_override("font_color", T.DISABLED)
	elif _readonly:
		line_edit.add_theme_color_override("font_color", T.SECONDARY)
	else:
		line_edit.add_theme_color_override("font_color", T.FOREGROUND)
