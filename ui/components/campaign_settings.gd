extends "res://ui/components/utility_panel.gd"

signal mode_requested(mode: int)

const OptionField = preload("res://ui/components/forms/editor_option_field.gd")

const MODES := [
	"每格 5 英尺（含斜向）",
	"斜向交替 5 / 10 英尺",
	"实际直线距离",
]

var _algorithm_field: OptionField
var _scope_label: Label
var _storage_label: Label
var _pending_mode := 0
var _pending_message := "更改后自动保存在本机。"
var _pending_failed := false

func _init() -> void:
	fluent = true
	panel_title = "团内设置"
	preferred_width = 360.0

func _ready() -> void:
	super._ready()
	_algorithm_field = OptionField.new()
	_algorithm_field.setup("全团距离计算方式", MODES, _pending_mode)
	content().add_child(_algorithm_field)
	_algorithm_field.option_selected.connect(func(index: int, _value: String): mode_requested.emit(index))

	_scope_label = Label.new()
	_scope_label.text = "尺子与棋子移动共用此规则。"
	_scope_label.theme_type_variation = &"FluentSecondary"
	_scope_label.add_theme_font_size_override("font_size", Typography.CAPTION)
	_scope_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content().add_child(_scope_label)

	_storage_label = Label.new()
	_storage_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_storage_label.add_theme_font_size_override("font_size", Typography.STATUS)
	content().add_child(_storage_label)
	set_storage_status(_pending_message, _pending_failed)

func open() -> void:
	super.open()

func close() -> void:
	close_popups()
	super.close()

func set_mode(mode: int) -> void:
	_pending_mode = clampi(mode, 0, MODES.size() - 1)
	if is_instance_valid(_algorithm_field):
		_algorithm_field.set_selected_index(_pending_mode, false)

func set_storage_status(message: String, failed: bool) -> void:
	_pending_message = message
	_pending_failed = failed
	if is_instance_valid(_storage_label):
		_storage_label.text = message
		_storage_label.visible = not message.is_empty()
		_storage_label.add_theme_color_override("font_color", T.DANGER if failed else T.SECONDARY)
		fit_to_window.call_deferred()

func popup_visible() -> bool:
	return is_instance_valid(_algorithm_field) and _algorithm_field.is_popup_open()

func close_popups() -> bool:
	if popup_visible():
		_algorithm_field.close_popup()
		return true
	return false
