extends "res://ui/components/features/editor/editor_property_panel.gd"

signal parameter_changed(key: String, value: Variant)
signal rotation_requested
signal undo_requested
signal reset_requested
signal frame_requested
signal mode_changed(placing: bool)

const Parameters = preload("res://scripts/scenery/wall_parameters.gd")
const NumberField = preload("res://ui/components/forms/editor_number_field.gd")
const OptionField = preload("res://ui/components/forms/editor_option_field.gd")
const FoldGroup = preload("res://ui/components/layout/editor_foldable_group.gd")
const FluentButton = preload("res://ui/components/controls/fluent_button.gd")
const ColorWell = preload("res://ui/components/color_well.gd")

var popup_host: Control
var _values := Parameters.defaults()
var _fields: Dictionary = {}
var _kind: OptionField
var _surface: OptionField
var _mode: OptionField
var _color: ColorWell
var _undo: Button
var _rotation: Button
var _reset: Button
var _generation_busy := false

func _init() -> void:
	super._init()
	setup(PanelSide.LEFT, "墙壁 · 材质预览", false)

func _ready() -> void:
	super._ready()
	_mode = OptionField.new()
	_mode.setup("操作", ["摆放墙体", "只看场景"], 0)
	fixed_header().add_child(_mode)
	_mode.option_selected.connect(func(index: int, _text: String): mode_changed.emit(index == 0))
	_rotation = _button("旋转90度 · 0°", func(): rotation_requested.emit())
	fixed_header().add_child(_rotation)
	_kind = OptionField.new()
	_kind.setup("墙体类型", Parameters.TITLES, int(_values.kind))
	content().add_child(_kind)
	_kind.option_selected.connect(func(index: int, _text: String): parameter_changed.emit("kind", index))
	_surface = OptionField.new()
	_surface.setup("墙面材质", Parameters.SURFACE_TITLES, Parameters.SURFACES.find(_values.surface))
	content().add_child(_surface)
	_surface.option_selected.connect(func(index: int, _text: String): parameter_changed.emit("surface", Parameters.SURFACES[index]))
	var wall_group := FoldGroup.new()
	wall_group.set_group_title("墙体尺寸")
	content().add_child(wall_group)
	var opening_group := FoldGroup.new()
	opening_group.set_group_title("洞口尺寸")
	content().add_child(opening_group)
	for entry in Parameters.NUMBERS:
		var key: String = entry[0]
		var field := NumberField.new()
		field.setup(entry[1], "英尺", entry[2], entry[3], true, float(_values[key]))
		(wall_group if key in ["length", "height", "thickness"] else opening_group).content().add_child(field)
		_fields[key] = field
		field.value_submitted.connect(func(value: float): parameter_changed.emit(key, value))
	_color = ColorWell.new()
	_color.popup_host = popup_host if popup_host != null else self
	_color.theme_type_variation = "FluentButton"
	_color.custom_minimum_size.y = T.BUTTON_HEIGHT
	_color.color = _values.color
	content().add_child(_color)
	_color.color_changed.connect(func(value: Color): parameter_changed.emit("color", value))
	_reset = _button("恢复初始样板", func(): reset_requested.emit())
	content().add_child(_reset)
	_undo = _button("撤销摆放", func(): undo_requested.emit())
	add_action(_undo)
	add_action(_button("查看全景", func(): frame_requested.emit()))
	set_values(_values)
	set_count(0)

func _button(title: String, action: Callable) -> Button:
	var button := FluentButton.new()
	button.text = title
	button.pressed.connect(action)
	return button

func set_values(values: Dictionary) -> void:
	_values = values.duplicate(true)
	if not is_node_ready(): return
	_kind.set_selected_index(int(values.kind))
	_surface.set_selected_index(Parameters.SURFACES.find(values.surface))
	for key in _fields:
		_fields[key].set_value(float(values[key]), true)
		_fields[key].set_disabled(_generation_busy or (key.begins_with("opening_") and int(values.kind) == 0) or (key == "sill" and int(values.kind) != 2))
	_color.color = values.color

func set_orientation(degrees: int) -> void:
	_rotation.text = "旋转90度 · %d°" % degrees

func set_count(count: int) -> void:
	set_action_enabled(_undo, count > 0)

func set_placing(placing: bool) -> void:
	_mode.set_selected_index(0 if placing else 1)

func set_generation_busy(value: bool) -> void:
	_generation_busy = value
	set_busy(value)
	close_popups()
	_kind.set_disabled(value)
	_surface.set_disabled(value)
	_mode.set_disabled(value)
	_color.disabled = value
	_rotation.disabled = value
	_reset.disabled = value
	for key in _fields:
		_fields[key].set_disabled(value or (key.begins_with("opening_") and int(_values.kind) == 0) or (key == "sill" and int(_values.kind) != 2))

func is_popup_open() -> bool:
	return _kind.is_popup_open() or _surface.is_popup_open() or _mode.is_popup_open() or _color.is_popup_open()

func close_popups() -> void:
	_kind.close_popup()
	_surface.close_popup()
	_mode.close_popup()
	_color.close_popup()
