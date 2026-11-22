extends PanelContainer
# Shared presentation for token, shape and measurement object entry points.
# Commands and distances are supplied by the host; this component does not edit plans.
signal action_requested(action: String, anchor: Control)
const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const Face = preload("res://ui/theme/themes/entity_context_theme.gd")
const Spec = preload("res://ui/theme/tokens/entity_context_tokens.gd")
const FluentButton = preload("res://ui/components/controls/fluent_button.gd")
const Typography = preload("res://ui/theme/typography.gd")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
var _entry: Dictionary = {}
var _title: Label
var _details: Label
var _warning: Label
var _buttons: HBoxContainer
var _column: VBoxContainer
var _header: HBoxContainer
var _compact := false
var _available_width := INF

func configure(entry: Dictionary) -> void:
	_entry = entry.duplicate()
	if is_node_ready(): _apply_entry()

func _ready() -> void:
	set_meta("style_owned", true)
	theme = FluentTheme.shared()
	_column = VBoxContainer.new()
	_column.add_theme_constant_override("separation", Spec.GAP)
	add_child(_column)
	_header = HBoxContainer.new()
	_header.add_theme_constant_override("separation", Spec.GAP)
	_column.add_child(_header)
	_title = Label.new()
	_title.theme_type_variation = &"FluentStrong"
	_title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_header.add_child(_title)
	_details = _secondary_label()
	_column.add_child(_details)
	_warning = _secondary_label()
	_column.add_child(_warning)
	_buttons = HBoxContainer.new()
	_buttons.add_theme_constant_override("separation", Spec.GAP)
	_column.add_child(_buttons)
	_buttons.minimum_size_changed.connect(_update_width)
	_apply_entry()

func _secondary_label() -> Label:
	var label := Label.new()
	label.theme_type_variation = &"FluentSecondary"
	label.add_theme_font_size_override("font_size", Typography.CAPTION)
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	return label

func _apply_entry() -> void:
	_compact = _entry.get("kind", "") in ["token", "shape"]
	add_theme_stylebox_override("panel", Face.face(_compact))
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if _compact else Control.SIZE_FILL
	var button_host: Node = _header if _compact else _column
	if _buttons.get_parent() != button_host: _buttons.reparent(button_host)
	_title.add_theme_font_size_override("font_size", Typography.CAPTION if _compact else Typography.BODY)
	_title.size_flags_horizontal = Control.SIZE_FILL if _compact else Control.SIZE_EXPAND_FILL
	_title.text = str(_entry.get("label", "对象"))
	_title.tooltip_text = _title.text
	tooltip_text = _title.text
	_details.text = str(_entry.get("details", ""))
	_details.visible = not _compact and not _details.text.is_empty()
	_warning.text = str(_entry.get("warning", ""))
	_warning.visible = not _compact and not _warning.text.is_empty()
	for child in _buttons.get_children():
		_buttons.remove_child(child)
		child.queue_free()
	for item in _entry.get("actions", []):
		var action := str(item[0])
		var button := FluentButton.new()
		button.text = str(item[1])
		button.variant = "FluentToolbarDanger" if action.begins_with("delete") else "FluentToolbar"
		button.size_flags_horizontal = Control.SIZE_FILL if _compact else Control.SIZE_EXPAND_FILL
		button.disabled = not _entry.get("actions_enabled", true) and action != "select_entity"
		button.tooltip_text = str(_entry.get("disabled_reason", "")) if button.disabled else button.text
		if action == "more":
			button.text = ""
			button.tooltip_text = "更多操作"
			button.icon_path = "res://ui/theme/icons/library/more_tintable.svg"
			button.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
			button.custom_minimum_size.x = T.TOUCH_BUTTON_HEIGHT if Mobile.enabled else T.TOOLBAR_BUTTON_HEIGHT
		if action.begins_with("delete"): button.icon_path = "res://ui/theme/icons/library/trash.svg"
		button.pressed.connect(func(): action_requested.emit(action, button))
		_buttons.add_child(button)
	_buttons.visible = not _entry.get("actions", []).is_empty()
	_update_width()

func set_available_width(width: float) -> void:
	_available_width = maxf(1.0, width)
	if is_node_ready(): _update_width()

func _update_width() -> void:
	custom_minimum_size.x = 0 if _compact else minf(Spec.WIDTH, _available_width)
	if _compact:
		var text_width := _title.get_theme_font("font").get_string_size(_title.text, HORIZONTAL_ALIGNMENT_LEFT, -1, _title.get_theme_font_size("font_size")).x
		var room := _available_width - Spec.COMPACT_PADDING * 2 - Spec.GAP - _buttons.get_combined_minimum_size().x
		_title.custom_minimum_size.x = minf(text_width, minf(Spec.TITLE_MAX_WIDTH, maxf(1, room)))
	else:
		_title.custom_minimum_size.x = 0
