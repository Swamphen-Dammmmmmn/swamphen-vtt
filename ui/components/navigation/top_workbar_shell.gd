extends VBoxContainer

signal category_changed(category_id: String, expanded: bool)
signal secondary_folded
signal layout_height_changed(bottom_y: float)

const TopbarTheme = preload("res://ui/theme/themes/adventure_topbar_theme.gd")
const Bar = preload("res://ui/theme/tokens/adventure_topbar_tokens.gd")
const Icons = preload("res://ui/theme/icons/library_icons.gd")
const ButtonFocus = preload("res://ui/components/button_focus.gd")
const FluentButton = preload("res://ui/components/controls/fluent_button.gd")

var _primary_panel: PanelContainer
var _primary_row: HBoxContainer
var _left_slot: HBoxContainer
var _category_scroll: ScrollContainer
var _category_row: HBoxContainer
var _right_slot: HBoxContainer

var _secondary_panel: PanelContainer
var _secondary_column: VBoxContainer
var _secondary_header: HBoxContainer
var _secondary_header_extra: HBoxContainer
var _fold_button: Button
var _secondary_body: VBoxContainer

var _tool_strip_panel: PanelContainer
var _tool_strip_body: VBoxContainer

var _categories: Array[Dictionary] = []
var _category_buttons: Dictionary = {}
var _current_category := ""
var _expanded := false
var _built := false
var _pending_categories: Array[Dictionary] = []

func _init() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 0)
	set_meta("style_owned", true)

func request_layout_sync() -> void:
	_sync_full_width()

func _sync_full_width() -> void:
	var parent_ctrl := get_parent() as Control
	if parent_ctrl == null:
		return
	position = Vector2.ZERO
	size.x = parent_ctrl.size.x
	var min_y := get_combined_minimum_size().y
	size.y = min_y

func _ready() -> void:
	theme = TopbarTheme.shared()

	# 1. Primary sticky bar
	_primary_panel = PanelContainer.new()
	_primary_panel.theme_type_variation = &"TopbarPrimarySurface"
	_primary_panel.custom_minimum_size.y = Bar.PRIMARY_MIN_HEIGHT
	_primary_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_primary_panel)

	_primary_row = HBoxContainer.new()
	_primary_row.add_theme_constant_override("separation", Bar.PRIMARY_GAP)
	_primary_row.alignment = BoxContainer.ALIGNMENT_BEGIN
	_primary_panel.add_child(_primary_row)

	_left_slot = HBoxContainer.new()
	_left_slot.add_theme_constant_override("separation", Bar.GLOBAL_ACTION_GAP)
	_left_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_primary_row.add_child(_left_slot)

	var left_divider := VSeparator.new()
	left_divider.theme_type_variation = &"TopbarVDivider"
	left_divider.custom_minimum_size.y = 24
	left_divider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_primary_row.add_child(left_divider)

	_category_scroll = ScrollContainer.new()
	_category_scroll.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_category_scroll.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_category_scroll.custom_minimum_size.y = Bar.CATEGORY_BUTTON_HEIGHT + Bar.DRAW_INSET * 2
	_category_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_category_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_category_scroll.follow_focus = true
	_category_scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_primary_row.add_child(_category_scroll)

	var category_inset := MarginContainer.new()
	category_inset.add_theme_constant_override("margin_left", Bar.DRAW_INSET)
	category_inset.add_theme_constant_override("margin_right", Bar.DRAW_INSET)
	category_inset.add_theme_constant_override("margin_top", Bar.DRAW_INSET)
	category_inset.add_theme_constant_override("margin_bottom", Bar.DRAW_INSET)
	_category_scroll.add_child(category_inset)

	_category_row = HBoxContainer.new()
	_category_row.add_theme_constant_override("separation", Bar.CATEGORY_GAP)
	category_inset.add_child(_category_row)

	_right_slot = HBoxContainer.new()
	_right_slot.add_theme_constant_override("separation", Bar.GLOBAL_ACTION_GAP)
	_right_slot.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_primary_row.add_child(_right_slot)

	# 2. Full-width secondary drawer (initially collapsed)
	_secondary_panel = PanelContainer.new()
	_secondary_panel.theme_type_variation = &"TopbarSecondarySurface"
	_secondary_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_secondary_panel.visible = false
	add_child(_secondary_panel)

	var content_row := HBoxContainer.new()
	content_row.add_theme_constant_override("separation", Bar.SECONDARY_GROUP_GAP)
	_secondary_panel.add_child(content_row)
	_secondary_column = VBoxContainer.new()
	_secondary_column.add_theme_constant_override("separation", Bar.SECONDARY_BODY_GAP)
	_secondary_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content_row.add_child(_secondary_column)

	_secondary_header = HBoxContainer.new()
	_secondary_header.add_theme_constant_override("separation", Bar.SECONDARY_HEADER_GAP)
	_secondary_header.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	content_row.add_child(_secondary_header)

	_secondary_header_extra = HBoxContainer.new()
	_secondary_header_extra.add_theme_constant_override("separation", 8)
	_secondary_header_extra.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_secondary_header_extra.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_secondary_header.add_child(_secondary_header_extra)

	var fold_btn := FluentButton.new()
	fold_btn.text = "收起"
	fold_btn.variant = "FluentToolbar"
	fold_btn.icon_path = "res://ui/theme/icons/topbar_fold_up.svg"
	fold_btn.minimum_height = Bar.CATEGORY_BUTTON_HEIGHT
	fold_btn.tooltip_text = "手动收起当前分类展开区"
	fold_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	fold_btn.pressed.connect(collapse_secondary)
	_secondary_header.add_child(fold_btn)
	_fold_button = fold_btn

	_secondary_body = VBoxContainer.new()
	_secondary_body.add_theme_constant_override("separation", Bar.SECONDARY_BODY_GAP)
	_secondary_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_secondary_column.add_child(_secondary_body)

	# 3. Active tool settings strip (independent of secondary drawer)
	_tool_strip_panel = PanelContainer.new()
	_tool_strip_panel.theme_type_variation = &"TopbarToolStripSurface"
	_tool_strip_panel.custom_minimum_size.y = Bar.TOOL_STRIP_MIN_HEIGHT
	_tool_strip_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_tool_strip_panel.visible = false
	add_child(_tool_strip_panel)

	_tool_strip_body = VBoxContainer.new()
	_tool_strip_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_tool_strip_body.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_tool_strip_panel.add_child(_tool_strip_body)

	_built = true
	if not _pending_categories.is_empty():
		set_categories(_pending_categories)
		_pending_categories.clear()

	if get_parent() is Control:
		(get_parent() as Control).resized.connect(_sync_full_width)
	resized.connect(_emit_height_deferred)
	minimum_size_changed.connect(_emit_height_deferred)
	_secondary_panel.resized.connect(_emit_height_deferred)
	_tool_strip_panel.resized.connect(_emit_height_deferred)
	_sync_full_width()
	_emit_height_deferred()

func left_slot() -> HBoxContainer:
	return _left_slot

func add_primary_action(title: String, tooltip: String, icon_path: String) -> Button:
	var button := _make_primary_button(title, tooltip, icon_path)
	_left_slot.add_child(button)
	return button

func _make_primary_button(title: String, tooltip: String, icon_path := "", go_icon: StringName = &"") -> Button:
	var button := Button.new()
	button.text = title
	button.tooltip_text = tooltip
	button.theme_type_variation = &"TopbarTab"
	button.custom_minimum_size.y = Bar.CATEGORY_BUTTON_HEIGHT
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if not icon_path.is_empty():
		button.icon = Icons.texture(icon_path)
		button.expand_icon = button.icon != null and Bar.ICON_SIZE > button.icon.get_width()
	elif not go_icon.is_empty():
		GoStyle.apply_icon(button, go_icon, Bar.ICON_SIZE)
	button.add_child(ButtonFocus.new())
	return button

func right_slot() -> HBoxContainer:
	return _right_slot

func secondary_header_extra() -> HBoxContainer:
	return _secondary_header_extra

func secondary_body() -> VBoxContainer:
	return _secondary_body

func tool_strip_body() -> VBoxContainer:
	return _tool_strip_body

func set_categories(definitions: Array[Dictionary]) -> void:
	if not _built:
		_pending_categories = definitions.duplicate(true)
		return
	_categories = definitions.duplicate(true)
	_category_buttons.clear()
	for child in _category_row.get_children():
		_category_row.remove_child(child)
		child.queue_free()
	for item in _categories:
		var cat_id := str(item.get("id", ""))
		if cat_id.is_empty():
			continue
		var title := str(item.get("title", cat_id))
		var btn := _make_primary_button(title, str(item.get("tooltip", title)), str(item.get("icon_path", "")), item.get("go_icon", &""))
		btn.pressed.connect(func(): toggle_category(cat_id))
		_category_row.add_child(btn)
		_category_buttons[cat_id] = btn
	_refresh_category_visuals()

func set_category_title(category_id: String, new_title: String, new_tooltip := "") -> void:
	for item in _categories:
		if str(item.get("id", "")) == category_id:
			item["title"] = new_title
			if not new_tooltip.is_empty():
				item["tooltip"] = new_tooltip
	if _category_buttons.has(category_id):
		var btn: Button = _category_buttons[category_id]
		btn.text = new_title
		if not new_tooltip.is_empty():
			btn.tooltip_text = new_tooltip

func toggle_category(category_id: String) -> void:
	if not _category_buttons.has(category_id):
		return
	if _current_category == category_id and _expanded:
		_expanded = false
	else:
		_current_category = category_id
		_expanded = true
	_apply_secondary_state(true)

func expand_category(category_id: String, emit_signal := true) -> void:
	if not _category_buttons.has(category_id):
		return
	var changed := (_current_category != category_id) or (not _expanded)
	_current_category = category_id
	_expanded = true
	_apply_secondary_state(emit_signal and changed)

func collapse_secondary() -> void:
	if not _expanded:
		return
	_expanded = false
	_apply_secondary_state(true)
	secondary_folded.emit()

func is_secondary_expanded() -> bool:
	return _expanded

func active_category() -> String:
	return _current_category

func set_tool_strip_visible(shown: bool) -> void:
	if not is_instance_valid(_tool_strip_panel):
		return
	if _tool_strip_panel.visible == shown:
		return
	_tool_strip_panel.visible = shown
	_sync_full_width()
	_emit_height_deferred()

func is_tool_strip_visible() -> bool:
	return is_instance_valid(_tool_strip_panel) and _tool_strip_panel.visible

func occupied_bottom() -> float:
	if not is_inside_tree():
		return Bar.PRIMARY_MIN_HEIGHT
	var bottom := position.y
	for panel in [_primary_panel, _secondary_panel, _tool_strip_panel]:
		if is_instance_valid(panel) and panel.visible:
			bottom = maxf(bottom, position.y + panel.position.y + maxf(panel.size.y, panel.get_combined_minimum_size().y))
	return bottom

func hit_test(global_point: Vector2) -> bool:
	if not is_visible_in_tree():
		return false
	for panel in [_primary_panel, _secondary_panel, _tool_strip_panel]:
		if is_instance_valid(panel) and panel.visible and panel.get_global_rect().has_point(global_point):
			return true
	return false

func _apply_secondary_state(emit_signal: bool) -> void:
	if is_instance_valid(_secondary_panel):
		_secondary_panel.visible = _expanded and not _current_category.is_empty()
	_refresh_category_visuals()
	_sync_full_width()
	if emit_signal:
		category_changed.emit(_current_category, _expanded)
	_emit_height_deferred()

func _refresh_category_visuals() -> void:
	for cat_id in _category_buttons:
		var btn: Button = _category_buttons[cat_id]
		var active: bool = _expanded and cat_id == _current_category
		btn.theme_type_variation = &"TopbarTabActive" if active else &"TopbarTab"

func _emit_height_deferred() -> void:
	if not is_inside_tree():
		return
	(func():
		if is_inside_tree():
			_sync_full_width()
			layout_height_changed.emit(occupied_bottom())
	).call_deferred()
