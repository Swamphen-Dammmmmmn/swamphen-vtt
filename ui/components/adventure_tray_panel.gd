extends "res://ui/components/creation_palette.gd"

const FluentOptionButton = preload("res://ui/components/controls/fluent_option_button.gd")
const VerticalCommandMenu = preload("res://ui/components/overlays/vertical_command_menu.gd")

signal tray_action(action: String, id: String)

var values: Dictionary = {"dm": [], "public": []}
var member_names: Dictionary = {}
var permitted_ids: Dictionary = {}
var personal_key := "dm"
var allowed_keys: Array = []
var chooser_keys: Array = []
var selected_id := ""
var chooser: FluentOptionButton
var selected_label: Label
var place_button: Button
var transfer_button: Button
var more_button: Button
var options_layer: CanvasLayer
var options_menu: VerticalCommandMenu
var _menu_target_id := ""
var search_row: HBoxContainer
var compact_header := false
var selection_row: HBoxContainer

func _init() -> void:
	fluent = true
	category = "dm"
	entries = {"dm": [], "public": []}
	memory = {"dm": {"query": "", "first": 0}, "public": {"query": "", "first": 0}}
	additional_overhead = 0.0
	maximum_height_ratio = 0.45

func _ready() -> void:
	super._ready()
	title.hide()

	chooser = FluentOptionButton.new()
	chooser.custom_minimum_size = Vector2(148, 36)
	chooser.add_item("DM 托盘")
	chooser.add_item("公共托盘")
	header.add_child(chooser)
	header.move_child(chooser, 0)
	chooser.item_selected.connect(func(index: int): open(left_margin, chooser_keys[index]))

	var add := FluentButton.new()
	add.text = "从库添加"
	add.variant = "FluentCompact"
	add.icon_path = "res://ui/theme/icons/library/plus_tintable.svg"
	add.minimum_height = 36.0
	header.add_child(add)
	header.move_child(add, header.get_child_count() - 2)
	add.pressed.connect(func(): tray_action.emit("add", ""))

	search_row = HBoxContainer.new()
	search_row.add_theme_constant_override("separation", 8)
	main_column.add_child(search_row)
	main_column.move_child(search_row, 1)
	search_row.hide()

	var row := HBoxContainer.new()
	selection_row = row
	row.add_theme_constant_override("separation", 8)
	row.visible = false
	main_column.add_child(row)
	main_column.move_child(row, main_column.get_child_count() - 2)

	selected_label = Label.new()
	selected_label.theme_type_variation = &"FluentSecondary"
	selected_label.add_theme_font_size_override("font_size", Typography.CAPTION)
	selected_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	selected_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	selected_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selected_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(selected_label)

	place_button = _action_button(row, "放置", "place", true)
	transfer_button = _action_button(row, "转移", "transfer")
	more_button = FluentButton.new()
	more_button.icon_path = "res://ui/theme/icons/library/more_tintable.svg"
	more_button.tooltip_text = "更多操作"
	more_button.custom_minimum_size.x = 40
	row.add_child(more_button)

	options_layer = CanvasLayer.new()
	var parent_layer := get_canvas_layer_node()
	options_layer.layer = (parent_layer.layer if parent_layer != null else 1) + 2
	add_child(options_layer)
	options_menu = VerticalCommandMenu.new()
	options_layer.add_child(options_menu)
	options_menu.action_requested.connect(func(action_id: String):
		if not _menu_target_id.is_empty():
			tray_action.emit(action_id, _menu_target_id)
	)

	more_button.pressed.connect(_open_more_menu)
	_sync_selection()

func _open_more_menu() -> void:
	if not is_instance_valid(options_menu):
		return
	if options_menu.is_open():
		options_menu.close()
		return
	if selected_id.is_empty():
		return
	var parent_layer := get_canvas_layer_node()
	if is_instance_valid(options_layer) and parent_layer != null:
		options_layer.layer = parent_layer.layer + 2
	_menu_target_id = selected_id
	var menu_actions: Array[Dictionary] = [
		{"title": "编辑棋子", "id": "edit", "icon": "res://ui/theme/icons/library/edit.svg"},
		{"title": "复制", "id": "copy", "icon": "res://ui/theme/icons/library/copy.svg"},
		{"title": "删除…", "id": "delete", "danger": true, "separator_before": true},
	]
	options_menu.open(more_button, menu_actions)

func _reflow(anchor: int = -1) -> void:
	if is_instance_valid(search_row):
		var parent_ctrl := get_parent() as Control
		var available: float = size.x if embedded_in_topbar and size.x > 64.0 else (parent_ctrl.size.x if embedded_in_topbar and parent_ctrl != null and parent_ctrl.size.x > 64.0 else parent_ctrl.size.x - minf(left_margin, maxf(16, parent_ctrl.size.x - 420)) - 16)
		var compact := available < 620
		if compact != compact_header:
			compact_header = compact
			search.reparent(search_row if compact else header)
			clear_button.reparent(search_row if compact else header)
			if not compact:
				header.move_child(search, 1)
				header.move_child(clear_button, 2)
		search_row.visible = compact
		additional_overhead = (46.0 if compact else 0.0) + (46.0 if is_instance_valid(selection_row) and selection_row.visible else 0.0)
	super._reflow(anchor)

func _action_button(parent: Control, text: String, action: String, primary := false) -> FluentButton:
	var button := FluentButton.new()
	button.text = text
	button.variant = "FluentPrimary" if primary else "FluentCompact"
	button.minimum_height = 36.0
	parent.add_child(button)
	if not action.is_empty():
		button.pressed.connect(func(): tray_action.emit(action, selected_id))
	return button

func refresh(data: Dictionary) -> void:
	values = data
	chooser_keys = []
	for key in values:
		if not allowed_keys.is_empty() and key not in allowed_keys:
			continue
		chooser_keys.append(key)
		if not memory.has(key):
			memory[key] = {"query": "", "first": 0}
	if chooser_keys.is_empty():
		chooser_keys.append("dm")
	if category not in chooser_keys:
		category = chooser_keys[0]
	if is_instance_valid(chooser):
		chooser.clear()
		for key in chooser_keys:
			chooser.add_item(tray_title(key))
		var idx := chooser_keys.find(category)
		if idx >= 0:
			chooser.select(idx)
	_load_local_entries()
	_filter_entries()
	if not _selected_exists():
		selected_id = ""
	_reflow()
	_sync_selection()

func _load_local_entries() -> void:
	for key in values:
		entries[key] = []
		for data: Dictionary in values[key]:
			entries[key].append({"id": data["id"], "title": data["title"], "parameters": data, "tooltip": data["title"]})

func _filter_entries() -> void:
	filtered.clear()
	if search == null or not entries.has(category):
		return
	var query := search.text.strip_edges().to_lower()
	for entry: Dictionary in entries[category]:
		if query.is_empty() or str(entry["title"]).to_lower().contains(query):
			filtered.append(entry)
	clear_button.disabled = search.text.is_empty()

func _render_slots() -> void:
	super._render_slots()
	var current_list: Array = values.get(category, [])
	if not search.text.strip_edges().is_empty() and filtered.is_empty():
		status.text = "没有匹配的托盘棋子"
	elif current_list.is_empty():
		status.text = "当前托盘暂无棋子 · 可从棋子库添加或从棋盘收纳"
	else:
		status.text = "%d 枚棋子" % current_list.size()
	status.visible = not status.text.is_empty()
	status.tooltip_text = "实际显示 %d 行，设置 %d 行。" % [actual_rows, preferences.creation_rows]
	for slot in slots.get_children():
		if not slot.entry.is_empty():
			slot.toggle_mode = true
			slot.set_selected_state(slot.entry["id"] == selected_id)

func select_item(id: String) -> void:
	selected_id = id
	for slot in slots.get_children():
		slot.set_selected_state(slot.entry.get("id", "") == selected_id)
	_sync_selection()

func _choose_entry(data: Dictionary) -> void:
	select_item(str(data["id"]))

func _selected_exists() -> bool:
	for data: Dictionary in values.get(category, []):
		if data["id"] == selected_id:
			return true
	return false

func _sync_selection() -> void:
	if selected_label == null:
		return
	transfer_button.text = "移至公共托盘" if category != "public" else "移至" + tray_title(personal_key)
	var found := false
	for data: Dictionary in values.get(category, []):
		if data["id"] != selected_id:
			continue
		found = true
		selected_label.text = "%s · HP %s · AC %s" % [
			data["title"],
			("%d/%d" % [data["hp"], data["max_hp"]]) if data["hp"] >= 0 else "—",
			str(data["ac"]) if data["ac"] >= 0 else "—",
		]
		selected_label.tooltip_text = selected_label.text
	if not found:
		selected_label.text = ""
		selected_label.tooltip_text = ""
	if selection_row.visible != found:
		selection_row.visible = found
		_reflow()
	for button in [place_button, transfer_button, more_button]:
		button.disabled = not found or not permitted_ids.has(selected_id)

func open(margin: float, key: String) -> void:
	if key != category:
		selected_id = ""
	super.open(margin, key)
	var idx := chooser_keys.find(category)
	if is_instance_valid(chooser) and idx >= 0:
		chooser.select(idx)
	_sync_selection()

func is_menu_open() -> bool:
	return is_instance_valid(options_menu) and options_menu.is_open()

func close_menus() -> bool:
	var closed := false
	if is_instance_valid(options_menu) and options_menu.is_open():
		options_menu.close(false)
		closed = true
	if is_instance_valid(chooser) and chooser.is_popup_open():
		chooser.close_popup()
		closed = true
	return closed

func popup_visible() -> bool:
	return is_menu_open() or (is_instance_valid(chooser) and chooser.is_popup_open())

func close() -> void:
	close_menus()
	super.close()

func tray_title(key: String) -> String:
	if key == "dm":
		return "DM 托盘"
	if key == "public":
		return "公共托盘"
	return str(member_names.get(key.trim_prefix("member:"), "成员")) + "的托盘"
