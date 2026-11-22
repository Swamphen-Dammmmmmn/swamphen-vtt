# Editor option field component
extends "res://ui/components/forms/editor_field_base.gd"

const FluentOptionButton = preload("res://ui/components/controls/fluent_option_button.gd")

signal option_selected(index: int, value: String)

var _option: FluentOptionButton

func _init() -> void:
	super._init()

	# Label
	_label = _create_label("")
	add_child(_label)

	# Option: shared select control (trigger and in-canvas list are one component)
	_option = FluentOptionButton.new()
	add_child(_option)
	_input_control = _option

	# Error label
	_error_label = _create_error_label()
	add_child(_error_label)

func _ready() -> void:
	super._ready()
	_option.item_selected.connect(_on_item_selected)
	_update_appearance()

func setup(label_text: String, options: Array, initial_index := -1) -> void:
	"""Configure the field. Can be called before or after _ready()."""
	_label.text = label_text

	# Clear and rebuild options
	_option.clear()
	for option_text in options:
		_option.add_item(str(option_text))

	# Set initial selection if valid
	if initial_index >= 0 and initial_index < options.size():
		_option.selected = initial_index

func get_selected_index() -> int:
	return _option.selected

func get_selected_value() -> String:
	var idx := _option.selected
	if idx < 0 or idx >= _option.item_count:
		return ""
	return _option.get_item_text(idx)

func set_selected_index(index: int, emit_signal := false) -> void:
	"""Set selected index. Does not emit signal by default."""
	if index < 0 or index >= _option.item_count:
		push_error("EditorOptionField: Invalid index %d" % index)
		return
	var old_idx := _option.selected
	_option.selected = index
	if emit_signal and index != old_idx:
		option_selected.emit(index, get_selected_value())

func _update_appearance() -> void:
	"""Unified state refresh - applies disabled state."""
	super._update_appearance()
	_option.disabled = _readonly or _disabled

func _on_item_selected(index: int) -> void:
	_clear_error_on_input()
	option_selected.emit(index, get_selected_value())

func is_popup_open() -> bool:
	return _option.is_popup_open()

func close_popup() -> void:
	# Closes the list only; selection and signals are unchanged.
	_option.close_popup()
