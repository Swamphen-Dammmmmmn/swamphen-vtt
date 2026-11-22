# Editor slider field component
extends "res://ui/components/forms/editor_field_base.gd"

signal value_changed(value: float)

const ET = preload("res://ui/theme/tokens/editor_tokens.gd")

var _header: HBoxContainer
var _value_label: Label
var _slider: HSlider
var _format_string := "%.0f"
var _suffix := ""

func _init() -> void:
	super._init()

	# Header with label and value
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", ET.SLIDER_HEADER_GAP)
	add_child(_header)

	# Label
	_label = _create_label("")
	_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_header.add_child(_label)

	# Value label
	_value_label = Label.new()
	_value_label.add_theme_font_size_override("font_size", T.CAPTION_SIZE)
	_value_label.add_theme_color_override("font_color", T.SECONDARY)
	_header.add_child(_value_label)

	# Slider
	_slider = HSlider.new()
	_slider.custom_minimum_size.y = T.BUTTON_HEIGHT
	_slider.step = 0.01
	add_child(_slider)
	_input_control = _slider

	# Error label
	_error_label = _create_error_label()
	add_child(_error_label)

func _ready() -> void:
	super._ready()
	_slider.value_changed.connect(_on_value_changed)
	_update_appearance()

func setup(label_text: String, min_val := 0.0, max_val := 100.0, initial_value := 50.0, suffix := "", format_str := "%.0f") -> void:
	"""Configure the field. Can be called before or after _ready()."""
	_label.text = label_text
	_suffix = suffix
	_format_string = format_str

	# Configure slider range
	_slider.min_value = min_val
	_slider.max_value = max_val

	# Determine step based on format
	if format_str.contains("f") and not format_str.ends_with("0f"):
		_slider.step = 0.01
	else:
		_slider.step = 1.0

	_slider.set_value_no_signal(initial_value)
	_update_value_label(initial_value)

func get_value() -> float:
	return _slider.value

func set_value(value: float, emit_signal := false) -> void:
	"""Set the slider value. Does not emit signal by default. Updates label immediately."""
	var old_value := _slider.value
	_slider.set_value_no_signal(value)
	_update_value_label(_slider.value)
	if emit_signal and not is_equal_approx(_slider.value, old_value):
		value_changed.emit(_slider.value)

func _update_appearance() -> void:
	"""Unified state refresh based on readonly and disabled flags."""
	super._update_appearance()
	_slider.editable = not (_readonly or _disabled)
	if _readonly or _disabled:
		_label.add_theme_color_override("font_color", T.DISABLED)
		_value_label.add_theme_color_override("font_color", T.DISABLED)
	else:
		_label.add_theme_color_override("font_color", T.SECONDARY)
		_value_label.add_theme_color_override("font_color", T.SECONDARY)

func set_slider_variation(variation: StringName) -> void:
	_slider.theme_type_variation = variation

func set_value_label_visible(shown: bool) -> void:
	# Display option for hosts that pair the slider with an exact text input.
	_value_label.visible = shown

func _update_value_label(value: float) -> void:
	var formatted := _format_string % value
	if not _suffix.is_empty():
		formatted += _suffix
	_value_label.text = formatted

func _on_value_changed(value: float) -> void:
	_update_value_label(value)
	_clear_error_on_input()
	value_changed.emit(value)
