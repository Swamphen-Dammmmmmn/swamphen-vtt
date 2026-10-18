extends PanelContainer

const Typography = preload("res://ui/theme/typography.gd")

signal tool_requested(tool: String)
signal category_changed(category: String)
signal panel_requested(panel: String)

const COLUMN_WIDTH := 78.0
const PADDING := 8.0
var current_category := "tools"
var current_tool := "select"
var category_buttons: Dictionary = {}
var tool_buttons: Dictionary = {}
var category_list: VBoxContainer
var action_list: VBoxContainer
var tool_list: VBoxContainer
var placeholder: Label
var settings_button: Button
var create_buttons: Dictionary = {}

func _ready() -> void:
	theme = GoUi.theme()
	add_theme_stylebox_override("panel", BoardUiStyle.card_face(PADDING))
	category_list = _make_column($Columns)
	var divider := VSeparator.new()
	var line := StyleBoxLine.new()
	line.color = Color("dce3ec")
	line.thickness = 1
	line.vertical = true
	divider.add_theme_stylebox_override("separator", line)
	divider.add_theme_constant_override("separation", 1)
	$Columns.add_child(divider)
	action_list = _make_column($Columns)
	for entry in [["tools", "工具", GoIconSet.SLIDERS], ["tokens", "棋子", GoIconSet.USERS], ["terrain", "场地", GoIconSet.GLOBE], ["more", "更多", GoIconSet.MORE]]:
		var category: String = entry[0]
		var button := _make_button(entry[1], entry[2])
		button.tooltip_text = "工具分类" if category == "tools" else ("团内设置" if category == "more" else ("创建团内棋子" if category == "tokens" else "%s：功能尚未实现" % entry[1]))
		button.pressed.connect(func(): set_category(category))
		category_list.add_child(button)
		category_buttons[category] = button
	tool_list = VBoxContainer.new()
	tool_list.add_theme_constant_override("separation", 6)
	action_list.add_child(tool_list)
	for entry in [["measure", "测距", GoIconSet.SLIDERS], ["shape", "形状", GoIconSet.GLOBE]]:
		var tool: String = entry[0]
		var button := _make_button(entry[1], entry[2])
		button.tooltip_text = {"measure": "测距", "shape": "形状"}[tool]
		button.pressed.connect(func(): tool_requested.emit(tool))
		tool_list.add_child(button)
		tool_buttons[tool] = button
	var calculator_button := _make_button("计算", GoIconSet.SLIDERS)
	calculator_button.toggle_mode = false
	calculator_button.tooltip_text = "计算器，不切换棋盘工具"
	calculator_button.pressed.connect(func(): panel_requested.emit("calculator"))
	tool_list.add_child(calculator_button)
	placeholder = Label.new()
	placeholder.text = "待实现"
	placeholder.custom_minimum_size.y = 40
	placeholder.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	placeholder.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	placeholder.modulate = Color("64748b")
	placeholder.tooltip_text = "此分类目前仅占位，棋盘工具保持不变"
	action_list.add_child(placeholder)
	settings_button = _make_button("设置", GoIconSet.SETTINGS)
	settings_button.toggle_mode = false
	settings_button.tooltip_text = "团内全局设置，不切换棋盘工具"
	settings_button.pressed.connect(func(): panel_requested.emit("campaign_settings"))
	action_list.add_child(settings_button)
	for entry in [["basic", "基础棋子"], ["advanced", "高级棋子"]]:
		var key: String = entry[0]
		var button := _make_button(entry[1], GoIconSet.USER)
		button.icon = null
		button.tooltip_text = "打开%s创建栏" % entry[1]
		button.pressed.connect(func(): panel_requested.emit("token_" + key))
		action_list.add_child(button)
		create_buttons[key] = button
	get_parent().resized.connect(_fit_height)
	category_list.minimum_size_changed.connect(func(): _fit_height.call_deferred())
	action_list.minimum_size_changed.connect(func(): _fit_height.call_deferred())
	set_category(current_category)
	set_tool(current_tool)
	_fit_height.call_deferred()

func _make_column(parent: Control) -> VBoxContainer:
	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size.x = COLUMN_WIDTH
	scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	parent.add_child(scroll)
	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 6)
	scroll.add_child(list)
	return list

func _make_button(title: String, icon_name: StringName) -> Button:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size = Vector2(0, 40)
	button.focus_mode = Control.FOCUS_NONE
	button.toggle_mode = true
	button.add_theme_font_size_override("font_size", Typography.CAPTION)
	BoardUiStyle.sidebar_button(button)
	GoStyle.apply_icon(button, icon_name, 14)
	return button

func set_category(category: String) -> void:
	current_category = category
	for key in category_buttons:
		var button: Button = category_buttons[key]
		button.set_pressed_no_signal(key == category)
		BoardUiStyle.refresh_sidebar_button(button, true)
	tool_list.visible = category == "tools"
	placeholder.visible = category not in ["tools", "more", "tokens"]
	settings_button.visible = category == "more"
	for button in create_buttons.values():
		button.visible = category == "tokens"
	_fit_height.call_deferred()
	category_changed.emit(category)

func set_creation_state(category: String, opened: bool) -> void:
	for key in create_buttons:
		var button: Button = create_buttons[key]
		button.set_pressed_no_signal(opened and key == category)
		BoardUiStyle.refresh_sidebar_button(button, true)

func set_tool(tool: String) -> void:
	current_tool = tool
	for key in tool_buttons:
		var button: Button = tool_buttons[key]
		button.set_pressed_no_signal(key == tool)
		BoardUiStyle.refresh_sidebar_button(button, true)

func _fit_height() -> void:
	var content_height := maxf(category_list.get_combined_minimum_size().y, action_list.get_combined_minimum_size().y)
	var available := maxf(0.0, get_parent().size.y - position.y - 148.0)
	size.y = minf(content_height + PADDING * 2.0, available)
