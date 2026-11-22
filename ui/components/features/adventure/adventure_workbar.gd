extends Control

signal tool_requested(tool: String)
signal panel_requested(panel: String)
signal menu_requested
signal map_collection_requested
signal creation_entry_chosen(entry: Dictionary)
signal layout_height_changed(bottom_y: float)

const Shell = preload("res://ui/components/navigation/top_workbar_shell.gd")
const CreationPalette = preload("res://ui/components/creation_palette.gd")
const PauseMenuEntry = preload("res://ui/components/controls/pause_menu_entry.gd")
const FluentButton = preload("res://ui/components/controls/fluent_button.gd")
const TopbarTheme = preload("res://ui/theme/themes/adventure_topbar_theme.gd")
const Bar = preload("res://ui/theme/tokens/adventure_topbar_tokens.gd")

var _shell: Shell
var _select_button: Button
var _map_button: FluentButton
var _pause_entry: PauseMenuEntry

var _tools_pane: HFlowContainer
var _tool_buttons: Dictionary = {}
var _aux_buttons: Dictionary = {}
var _tokens_pane: VBoxContainer
var _creation_palette: CreationPalette
var _tray_pane: VBoxContainer
var _tray_panel: Control
var _terrain_pane: HBoxContainer
var _more_pane: HFlowContainer

var _current_tool := "select"
var _map_title := "地图集"
var _map_active := false
var _tray_count := 0

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_meta("style_owned", true)

func _ready() -> void:
	theme = TopbarTheme.shared()

	_shell = Shell.new()
	add_child(_shell)
	_shell.category_changed.connect(_on_category_changed)
	_shell.layout_height_changed.connect(func(bottom_y: float):
		size.y = bottom_y
		layout_height_changed.emit(bottom_y)
	)

	# Left slot: Direct Select Tool
	_select_button = _shell.add_primary_action("选择", "选择并操作棋子及可交互场景对象", "res://ui/theme/icons/topbar_cursor.svg")
	_select_button.pressed.connect(func(): tool_requested.emit("select"))

	# Categories on primary bar (preserving all real adventure entries + terrain placeholder)
	_shell.set_categories([
		{"id": "tools", "title": "工具", "tooltip": "测距、形状与表达式计算器", "icon_path": "res://ui/theme/icons/topbar_ruler.svg"},
		{"id": "tokens", "title": "棋子", "tooltip": "内置基础创建与本地棋子库取用", "go_icon": GoIconSet.USERS},
		{"id": "tray", "title": _tray_tab_title(), "tooltip": "DM、公共与成员个人托盘", "icon_path": "res://ui/theme/icons/topbar_tray.svg"},
		{"id": "terrain", "title": "场地", "tooltip": "场地：功能尚未实现", "icon_path": "res://ui/theme/icons/topbar_terrain.svg"},
		{"id": "more", "title": "更多", "tooltip": "团内全局计距规则设置", "go_icon": GoIconSet.MORE},
	])

	# Right slot: Map Collection + Pause Menu
	_map_button = FluentButton.new()
	_map_button.text = _map_title
	_map_button.tooltip_text = _map_title
	_map_button.variant = "FluentChoiceSelected" if _map_active else "FluentChoice"
	_map_button.icon_name = GoIconSet.MAP
	_map_button.minimum_height = Bar.CATEGORY_BUTTON_HEIGHT
	_map_button.custom_minimum_size.x = Bar.MAP_BUTTON_MIN_WIDTH
	_map_button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	_map_button.clip_text = true
	_map_button.pressed.connect(func():
		set_map_navigation_active(true)
		map_collection_requested.emit()
	)
	_shell.right_slot().add_child(_map_button)
	_update_map_button_width()

	_pause_entry = PauseMenuEntry.new()
	_pause_entry.pressed.connect(func(): menu_requested.emit())
	_shell.right_slot().add_child(_pause_entry)

	# Secondary panes
	_build_tools_pane()
	_build_tokens_pane()
	_build_tray_pane()
	_build_terrain_pane()
	_build_more_pane()
	_sync_secondary_panes()

	if get_parent() is Control:
		(get_parent() as Control).resized.connect(_sync_host_width)
	_sync_host_width()
	set_tool(_current_tool)

func _build_tools_pane() -> void:
	_tools_pane = HFlowContainer.new()
	_tools_pane.add_theme_constant_override("h_separation", Bar.SECONDARY_GROUP_GAP)
	_tools_pane.add_theme_constant_override("v_separation", 8)
	_tools_pane.visible = false
	_shell.secondary_body().add_child(_tools_pane)

	var board_tools := HBoxContainer.new()
	board_tools.add_theme_constant_override("separation", Bar.SECONDARY_BUTTON_GAP)
	_tools_pane.add_child(board_tools)


	var measure_btn := _make_choice_button("测距", "res://ui/theme/icons/topbar_ruler.svg")
	measure_btn.tooltip_text = "多节点测距与棋子端点绑定"
	measure_btn.pressed.connect(func(): tool_requested.emit("measure"))
	board_tools.add_child(measure_btn)
	_tool_buttons["measure"] = measure_btn

	var shape_btn := _make_choice_button("形状", "res://ui/theme/icons/topbar_shapes.svg")
	shape_btn.tooltip_text = "打开形状工具面板：圆形、扇形、矩形、线形范围"
	shape_btn.pressed.connect(func(): tool_requested.emit("shape"))
	board_tools.add_child(shape_btn)
	_tool_buttons["shape"] = shape_btn

	var vsep := VSeparator.new()
	vsep.theme_type_variation = &"TopbarVDivider"
	vsep.custom_minimum_size.y = 24
	vsep.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tools_pane.add_child(vsep)

	var aux_row := HBoxContainer.new()
	aux_row.add_theme_constant_override("separation", Bar.SECONDARY_BUTTON_GAP)
	_tools_pane.add_child(aux_row)


	var calc_btn := _make_choice_button("计算器", "res://ui/theme/icons/topbar_calculator.svg")
	calc_btn.tooltip_text = "四则运算表达式与最近 50 条记录，不切换当前棋盘工具"
	calc_btn.pressed.connect(func(): panel_requested.emit("calculator"))
	aux_row.add_child(calc_btn)
	_aux_buttons["calculator"] = calc_btn

func _build_tokens_pane() -> void:
	_tokens_pane = VBoxContainer.new()
	_tokens_pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tokens_pane.visible = false
	_shell.secondary_body().add_child(_tokens_pane)

	_creation_palette = CreationPalette.new()
	_creation_palette.embedded_in_topbar = true
	_creation_palette.fluent = true
	_creation_palette.maximum_height_ratio = 0.36
	_tokens_pane.add_child(_creation_palette)
	_creation_palette.entry_chosen.connect(func(entry: Dictionary): creation_entry_chosen.emit(entry))

func _build_tray_pane() -> void:
	_tray_pane = VBoxContainer.new()
	_tray_pane.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tray_pane.visible = false
	_shell.secondary_body().add_child(_tray_pane)
	if is_instance_valid(_tray_panel) and _tray_panel.get_parent() == null:
		_mount_tray_panel_internal(_tray_panel)

func _build_terrain_pane() -> void:
	_terrain_pane = HBoxContainer.new()
	_terrain_pane.add_theme_constant_override("separation", 10)
	_terrain_pane.visible = false
	_shell.secondary_body().add_child(_terrain_pane)

	var badge := PanelContainer.new()
	badge.theme_type_variation = &"TopbarSummaryChip"
	badge.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_terrain_pane.add_child(badge)

	var badge_text := Label.new()
	badge_text.text = "待实现"
	badge_text.theme_type_variation = &"TopbarSectionTitle"
	badge.add_child(badge_text)

	var desc := Label.new()
	desc.text = "场地工具暂未开放；浏览此分类不会改变当前棋盘工具或草稿。"
	desc.theme_type_variation = &"TopbarMuted"
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_terrain_pane.add_child(desc)

func _build_more_pane() -> void:
	_more_pane = HFlowContainer.new()
	_more_pane.add_theme_constant_override("h_separation", 12)
	_more_pane.add_theme_constant_override("v_separation", 8)
	_more_pane.visible = false
	_shell.secondary_body().add_child(_more_pane)

	var settings_btn := _make_choice_button("团内设置", "")
	settings_btn.icon_name = GoIconSet.SETTINGS
	settings_btn.minimum_height = Bar.CATEGORY_BUTTON_HEIGHT
	settings_btn.tooltip_text = "全团距离计算方式（尺子与移动共用），打开浮窗不退出当前工具"
	settings_btn.pressed.connect(func(): panel_requested.emit("campaign_settings"))
	_more_pane.add_child(settings_btn)
	_aux_buttons["campaign_settings"] = settings_btn

	var hint := Label.new()
	hint.text = "设置全团距离计算规则（每格 5 英尺、斜向交替 5/10 英尺、实际直线距离）。"
	hint.theme_type_variation = &"TopbarMuted"
	hint.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_more_pane.add_child(hint)

func _make_choice_button(title: String, svg_path: String) -> FluentButton:
	var btn := FluentButton.new()
	btn.text = title
	btn.variant = "FluentToolbar"
	btn.icon_path = svg_path
	btn.minimum_height = Bar.CATEGORY_BUTTON_HEIGHT
	return btn

func _sync_host_width() -> void:
	var parent_ctrl := get_parent() as Control
	if parent_ctrl == null:
		return
	position = Vector2.ZERO
	size.x = parent_ctrl.size.x
	size.y = occupied_bottom()
	if is_instance_valid(_shell):
		_shell.request_layout_sync()
	_update_map_button_width()

func _update_map_button_width() -> void:
	if not is_instance_valid(_map_button):
		return
	var font := _map_button.get_theme_font("font")
	var font_size := _map_button.get_theme_font_size("font_size")
	var content_width := font.get_string_size(_map_title, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
	content_width += _map_button.get_theme_stylebox("normal").get_minimum_size().x
	if _map_button.icon != null:
		content_width += minf(_map_button.icon.get_width(), _map_button.get_theme_constant("icon_max_width"))
		content_width += _map_button.get_theme_constant("h_separation")
	_map_button.custom_minimum_size.x = clampf(ceilf(content_width), Bar.MAP_BUTTON_MIN_WIDTH, Bar.MAP_BUTTON_MAX_WIDTH)

func _on_category_changed(_category_id: String, _expanded: bool) -> void:
	if is_instance_valid(_tray_panel) and _tray_panel.has_method("close_menus"):
		_tray_panel.close_menus()
	_sync_secondary_panes()

func _sync_secondary_panes() -> void:
	if not is_instance_valid(_shell):
		return
	var expanded := _shell.is_secondary_expanded()
	var cat := _shell.active_category()
	_tools_pane.visible = expanded and cat == "tools"
	_tokens_pane.visible = expanded and cat == "tokens"
	_tray_pane.visible = expanded and cat == "tray"
	_terrain_pane.visible = expanded and cat == "terrain"
	_more_pane.visible = expanded and cat == "more"
	if _tokens_pane.visible and is_instance_valid(_creation_palette):
		_creation_palette.open(Bar.BOARD_EDGE_MARGIN, _creation_palette.category)
	if _tray_pane.visible and is_instance_valid(_tray_panel):
		_tray_panel.open(Bar.BOARD_EDGE_MARGIN, _tray_panel.category)

func _tray_tab_title() -> String:
	return "托盘 · %d" % _tray_count

# Public Host API
func creation_palette() -> CreationPalette:
	return _creation_palette

func mount_tray_panel(panel: Control) -> void:
	_tray_panel = panel
	if is_instance_valid(_tray_pane):
		_mount_tray_panel_internal(panel)

func _mount_tray_panel_internal(panel: Control) -> void:
	panel.embedded_in_topbar = true
	panel.maximum_height_ratio = 0.38
	if panel.get_parent() != null:
		panel.get_parent().remove_child(panel)
	_tray_pane.add_child(panel)
	panel.show()

func set_tray_count(count: int) -> void:
	_tray_count = maxi(0, count)
	if is_instance_valid(_shell):
		_shell.set_category_title("tray", _tray_tab_title(), "DM、公共与成员个人托盘（共 %d 枚）" % _tray_count)

func expand_category(category_id: String) -> void:
	if is_instance_valid(_shell):
		_shell.expand_category(category_id)

func collapse_secondary() -> void:
	if is_instance_valid(_shell):
		_shell.collapse_secondary()

func toggle_category(category_id: String) -> void:
	if is_instance_valid(_shell):
		_shell.toggle_category(category_id)

func is_secondary_expanded() -> bool:
	return is_instance_valid(_shell) and _shell.is_secondary_expanded()

func active_category() -> String:
	return _shell.active_category() if is_instance_valid(_shell) else ""

func open_tray_category(tray_key: String) -> void:
	if is_instance_valid(_tray_panel):
		_tray_panel.category = tray_key
	expand_category("tray")

func set_tool(tool_name: String) -> void:
	_current_tool = tool_name
	if is_instance_valid(_select_button):
		_select_button.theme_type_variation = &"TopbarTabActive" if tool_name == "select" else &"TopbarTab"
	for key in _tool_buttons:
		var btn: FluentButton = _tool_buttons[key]
		btn.set_variant("FluentToolbarSelected" if tool_name == key else "FluentToolbar")

func set_auxiliary_panel_open(panel_key: String, opened: bool) -> void:
	if _aux_buttons.has(panel_key):
		var btn: FluentButton = _aux_buttons[panel_key]
		btn.set_variant("FluentToolbarSelected" if opened else "FluentToolbar")

func set_map_title(title: String) -> void:
	_map_title = title
	if is_instance_valid(_map_button):
		_map_button.text = title
		_map_button.tooltip_text = title
		_update_map_button_width()

func set_map_navigation_active(opened: bool) -> void:
	_map_active = opened
	if is_instance_valid(_map_button):
		_map_button.set_variant("FluentChoiceSelected" if opened else "FluentChoice")

func set_shape_summary(summary: String, _panel_open: bool) -> void:
	if _tool_buttons.has("shape"):
		_tool_buttons["shape"].tooltip_text = summary

func occupied_bottom() -> float:
	return _shell.occupied_bottom() if is_instance_valid(_shell) else Bar.PRIMARY_MIN_HEIGHT

func hit_test(global_point: Vector2) -> bool:
	if popup_visible():
		return true
	return is_instance_valid(_shell) and _shell.hit_test(global_point)

func pointer_on_asset_drawer(global_point: Vector2) -> bool:
	if not is_secondary_expanded():
		return false
	if active_category() not in ["tokens", "tray"]:
		return false
	return is_instance_valid(_shell) and _shell.hit_test(global_point)

func popup_visible() -> bool:
	if is_instance_valid(_tray_panel) and _tray_panel.has_method("popup_visible") and _tray_panel.popup_visible():
		return true
	return false

func close_popups() -> bool:
	if is_instance_valid(_tray_panel) and _tray_panel.has_method("popup_visible") and _tray_panel.popup_visible():
		return bool(_tray_panel.close_menus())
	return false
