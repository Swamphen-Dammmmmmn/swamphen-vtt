extends HFlowContainer
signal filters_changed(kind: String, tag: String)
const ButtonComponent = preload("res://ui/components/controls/library_reference_button.gd")
const LibTokens = preload("res://ui/theme/tokens/library_tokens.gd")
var selected_kind := "all"
var selected_tag := ""
var _buttons: Dictionary = {}
var _tags: OptionButton
var _available: Array[String] = []
var _type_group: HBoxContainer
var _tag_group: HBoxContainer

func _ready() -> void:
	add_theme_constant_override("h_separation", LibTokens.GRID_GAP)
	add_theme_constant_override("v_separation", 8)
	var control_height := LibTokens.FILTER_HEIGHT_MOBILE if Mobile.enabled else LibTokens.FILTER_HEIGHT_DESKTOP
	_type_group = HBoxContainer.new()
	_type_group.add_theme_constant_override("separation", LibTokens.FILTER_GAP)
	add_child(_type_group)
	_add_caption("类型", control_height, _type_group)
	for item in [["all","全部"],["basic","基础"],["advanced","高级"]]:
		var key: String = item[0]
		var button = ButtonComponent.new()
		button.text = item[1]
		button.toggle_mode = true
		button.presentation = "LibraryFilter"
		button.custom_minimum_size = Vector2(64 if key=="all" else 70, control_height)
		button.button_pressed = key==selected_kind
		_type_group.add_child(button)
		_buttons[key] = button
		button.pressed.connect(func(): selected_kind = key; _emit())
	_tag_group = HBoxContainer.new()
	_tag_group.add_theme_constant_override("separation", LibTokens.FILTER_GAP)
	add_child(_tag_group)
	_add_caption("分类", control_height, _tag_group)
	_tags = OptionButton.new()
	_tags.fit_to_longest_item = false
	_tags.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_tags.custom_minimum_size = Vector2(168, control_height)
	_tag_group.add_child(_tags)
	_tags.item_selected.connect(func(index: int): selected_tag = "" if index==0 else _available[index-1]; _emit())
	set_tags([])

func set_tags(values: Array) -> void:
	_available.clear()
	for value in values:
		if not str(value).is_empty() and not _available.has(str(value)): _available.append(str(value))
	_available.sort()
	if not _available.has(selected_tag): selected_tag = ""
	_tags.clear()
	_tags.add_item("全部标签")
	for tag in _available: _tags.add_item(tag)
	_tags.select(0 if selected_tag.is_empty() else _available.find(selected_tag)+1)
	_tags.disabled = _available.is_empty()

func reset() -> void:
	selected_kind = "all"
	selected_tag = ""
	_tags.select(0)
	_emit()

func _emit() -> void:
	for key in _buttons:
		var button: Button = _buttons[key]
		button.set_pressed_no_signal(key==selected_kind)
	filters_changed.emit(selected_kind,selected_tag)

func _add_caption(value: String, height: float, parent: Control, inset := 0) -> void:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", LibTokens.CAPTION_SIZE)
	label.add_theme_color_override("font_color", LibTokens.SECONDARY_TEXT)
	label.custom_minimum_size = Vector2(39+inset, height)
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(label)
