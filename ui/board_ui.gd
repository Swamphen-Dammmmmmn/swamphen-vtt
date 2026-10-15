extends Control

const SEGMENT_LABEL = preload("res://ui/components/segment_label.tscn")
const PATH_POINT = preload("res://ui/components/path_point.tscn")
const TOKEN_NAME = preload("res://ui/components/token_name.tscn")
const TOKEN_ACTIONS = preload("res://ui/components/token_actions.tscn")

signal tool_requested(tool: String)
signal menu_requested
signal map_collection_requested
signal tray_requested
signal token_placement_requested(parameters: Dictionary)
signal token_appearance_saved(token_id: int, parameters: Dictionary)
signal token_deletion_confirmed(token_id: int)
signal token_placement_action_requested(action: String)
signal shape_parameters_changed(parameters: Dictionary)
signal shape_action_requested(action: String)
signal campaign_mode_requested(index: int)
signal token_action_requested(action: String)
signal point_action_requested(action: String)
signal path_point_selected(index: int)
signal measurement_action_requested(action: String)
signal entity_action_requested(target: Dictionary, action: String)
signal entity_hovered(target: Dictionary)
signal entity_selection_requested(mouse: Vector2)
signal route_action_requested(action: String)
signal token_renamed(index: int, title: String)
signal token_stats_changed(index: int, hp: int, maximum: int, ac: int, temporary: int)
signal token_notes_changed(index: int, text: String)

const TOKEN_MENU_ACTIONS := ["rename", "appearance", "copy", "delete", "store"]
var tray_button: Button
var tray_button_panel: PanelContainer
var delete_dialog: Control
var creation_palette: PanelContainer
var displayed_token := -1
var current_tool := "select"
var overlap_actions: ScrollContainer
var overlap_menu: PopupMenu
var menu_target: Dictionary = {}
var map_button_panel: PanelContainer
var map_navigation: Button
var network_notice: Label
var network_notice_revision := 0

func _enter_tree() -> void:
	BoardUiStyle.configure()

func _ready() -> void:
	Mobile.register_root(self)
	network_notice = Label.new()
	add_child(network_notice)
	network_notice.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	network_notice.offset_left = -440
	network_notice.offset_right = -20
	network_notice.offset_top = 78
	network_notice.offset_bottom = 104
	network_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	network_notice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	network_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	network_notice.add_theme_color_override("font_color",Color("ffffff"))
	network_notice.hide()
	tray_button_panel = PanelContainer.new()
	add_child(tray_button_panel)
	tray_button_panel.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	tray_button_panel.offset_left = 20
	tray_button_panel.offset_right = 205
	tray_button_panel.offset_top = -70
	tray_button_panel.offset_bottom = -18
	tray_button = Button.new()
	tray_button.text = "棋子托盘 · 0"
	tray_button_panel.add_child(tray_button)
	BoardUiStyle.small_sidebar_entry(tray_button_panel,tray_button)
	tray_button.pressed.connect(func(): tray_requested.emit())
	var maps := PanelContainer.new()
	map_button_panel = maps
	maps.z_index = 1
	add_child(maps)
	maps.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_LEFT)
	maps.offset_left = 20
	maps.offset_right = 205
	maps.offset_top = -130
	maps.offset_bottom = -78
	map_navigation = Button.new()
	map_navigation.text = "地图集"
	map_navigation.toggle_mode = true
	map_navigation.focus_mode = Control.FOCUS_NONE
	map_navigation.alignment = HORIZONTAL_ALIGNMENT_LEFT
	map_navigation.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	GoStyle.apply_icon(map_navigation,GoIconSet.MAP,18)
	map_navigation.icon_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	maps.add_child(map_navigation)
	BoardUiStyle.small_sidebar_entry(maps,map_navigation)
	map_navigation.pressed.connect(func():
		set_map_navigation_active(true)
		map_collection_requested.emit()
	)
	$Title.hide()
	creation_palette = preload("res://ui/components/creation_palette.gd").new()
	creation_palette.z_index = 6
	add_child(creation_palette)
	creation_palette.entry_chosen.connect(_on_creation_entry)
	creation_palette.state_changed.connect($Toolbar.set_creation_state)
	delete_dialog = preload("res://ui/components/token_delete_dialog.gd").new()
	delete_dialog.z_index = 20
	add_child(delete_dialog)
	delete_dialog.deletion_confirmed.connect(func(id: int): token_deletion_confirmed.emit(id))
	$TokenCreate.appearance_saved.connect(func(id: int, parameters: Dictionary): token_appearance_saved.emit(id, parameters))
	$TokenCreate.placement_requested.connect(func(parameters: Dictionary): token_placement_requested.emit(parameters))
	$TokenPlacementActions.action_requested.connect(func(action: String): token_placement_action_requested.emit(action))
	$HomeCard.add_theme_stylebox_override("panel", BoardUiStyle.card_face(BoardUiStyle.ACTION_PADDING))
	BoardUiStyle.action_button($HomeCard/Home, 36)
	GoStyle.apply_icon($HomeCard/Home, GoIconSet.MENU, 18)
	$HomeCard/Home.pressed.connect(func(): menu_requested.emit())
	BoardUiStyle.small_sidebar_entry($SelectCard,$SelectCard/Select)
	GoStyle.apply_icon($SelectCard/Select, GoIconSet.USER, 16)
	$SelectCard/Select.tooltip_text = "操作棋子及可交互场景对象"
	$SelectCard/Select.set_pressed_no_signal(true)
	BoardUiStyle.refresh_sidebar_button($SelectCard/Select, true)
	$SelectCard/Select.pressed.connect(func(): tool_requested.emit("select"))
	$Toolbar.resized.connect(func():
		$SelectCard.size.x = $Toolbar.size.x
		map_button_panel.size.x = $Toolbar.size.x
		tray_button_panel.size.x = $Toolbar.size.x
	)
	map_button_panel.size.x = $Toolbar.size.x
	tray_button_panel.size.x = $Toolbar.size.x
	$Toolbar.tool_requested.connect(_on_tool)
	$Toolbar.panel_requested.connect(_on_panel_requested)
	$Toolbar.resized.connect(_position_campaign_settings)
	resized.connect(_position_shape_undo)
	resized.connect(_position_measurement_undo)
	$MeasurementActions.action_requested.connect(_on_measurement_action)
	$MeasureSettings.action_requested.connect(_on_measurement_action)
	$MeasurementUndo.set_mode("measure_undo")
	$MeasurementUndo.action_requested.connect(func(action: String): measurement_action_requested.emit(action))
	$MeasurementUndoTimer.timeout.connect(func():
		$MeasurementUndo.hide()
		measurement_action_requested.emit("forget_measure")
	)
	overlap_actions = preload("res://ui/components/overlap_actions.gd").new()
	add_child(overlap_actions)
	overlap_actions.action_requested.connect(_on_entity_action)
	overlap_actions.target_hovered.connect(func(target: Dictionary):
		if not overlap_menu.visible:
			entity_hovered.emit(target)
	)
	overlap_menu = PopupMenu.new()
	add_child(overlap_menu)
	overlap_menu.id_pressed.connect(func(id: int):
		entity_action_requested.emit(menu_target, TOKEN_MENU_ACTIONS[id] if menu_target.get("kind") == "token" else "edit")
	)
	overlap_menu.popup_hide.connect(func(): entity_hovered.emit({}))
	$PointActions.set_actions([
		{"id": "move", "label": "移动", "tooltip": "调整此路径点的位置"},
		{"id": "delete", "label": "删除", "tooltip": "删除此点并连接前后路径"}
	])
	$PointActions.action_requested.connect(func(action: String): point_action_requested.emit(action))
	$RouteCard.action_requested.connect(func(action: String): route_action_requested.emit(action))
	$CampaignSettings.mode_requested.connect(func(index: int): campaign_mode_requested.emit(index))
	$ShapeSettings.parameters_changed.connect(func(parameters: Dictionary): shape_parameters_changed.emit(parameters))
	$ShapeSettings.action_requested.connect(func(action: String): shape_action_requested.emit(action))
	$ShapeActions.action_requested.connect(_on_shape_action)
	$ShapeUndo.set_mode("undo")
	$ShapeUndo.action_requested.connect(func(action: String): shape_action_requested.emit(action))
	$ShapeMenu.add_item("编辑参数", 0)
	$ShapeMenu.id_pressed.connect(func(_id: int): shape_action_requested.emit("edit"))
	$ShapeUndoTimer.timeout.connect(func():
		$ShapeUndo.hide()
		shape_action_requested.emit("forget_delete")
	)
	_position_campaign_settings()
	_populate_token_menu($TokenMenu)
	$TokenMenu.id_pressed.connect(func(id: int): token_action_requested.emit(TOKEN_MENU_ACTIONS[id]))
	$RenameDialog.name_saved.connect(func(index: int, title: String): token_renamed.emit(index, title))
	$StatsDialog.stats_saved.connect(func(index: int, hp: int, maximum: int, ac: int, temporary: int): token_stats_changed.emit(index, hp, maximum, ac, temporary))

func rename_open() -> bool:
	return $RenameDialog.visible or $StatsDialog.visible or delete_dialog.visible or ($TokenCreate.visible and $TokenCreate.editing_id >= 0)

func session_shortcuts_blocked() -> bool:
	return rename_open() or $TokenMenu.visible or $ShapeMenu.visible or overlap_menu.visible or $CampaignSettings.popup_visible() or $ShapeSettings.popup_visible() or $TokenCreate.visible

func open_rename(index: int, title: String) -> void:
	creation_palette.close()
	var card := $TokenNames.get_child(index) as Control
	$RenameDialog.open(index, title, card.get_global_rect(), sidebar_right())

func open_stats(index: int, data: Dictionary, mode: String) -> void:
	creation_palette.close()
	var card := $TokenNames.get_child(index) as Control
	$StatsDialog.left_margin = sidebar_right()
	$StatsDialog.open(index, data, mode, card.get_global_rect())

func _populate_token_menu(menu: PopupMenu) -> void:
	menu.clear()
	for label in ["重命名", "编辑棋子", "复制", "删除", "收纳到托盘…"]:
		menu.add_item(label)

func open_token_appearance(data: Dictionary) -> void:
	creation_palette.close()
	$RenameDialog.hide()
	$StatsDialog.hide()
	$TokenCreate.open_edit(data)

func open_token_delete(data: Dictionary, measurement_count: int) -> void:
	creation_palette.close()
	$RenameDialog.hide()
	$StatsDialog.hide()
	$TokenCreate.close()
	delete_dialog.open(data, measurement_count)

func reset_after_token_removal(token_id: int) -> void:
	$RenameDialog.hide()
	$StatsDialog.hide()
	$StatsDialog.history.erase(token_id)
	$TokenCreate.close()
	delete_dialog.hide()
	hide_token_actions()
	hide_entity_actions()
	# Rebuild index-based callbacks after the list changes.
	for container in [$TokenNames, $TokenOperations]:
		for child in container.get_children():
			container.remove_child(child)
			child.queue_free()

func sidebar_right() -> float:
	return $Toolbar.position.x + $Toolbar.size.x + 12.0

func show_token_name(index: int, data: Dictionary, at: Vector2, in_front: bool, selected: bool, interactive: bool, info_zoom: float, editable: bool = true) -> void:
	while $TokenNames.get_child_count() <= index:
		var new_card := TOKEN_NAME.instantiate()
		var card_index: int = $TokenNames.get_child_count()
		new_card.action_requested.connect(func(action: String):
			displayed_token = card_index
			_on_token_action(action)
		)
		new_card.notes_changed.connect(func(text: String): token_notes_changed.emit(card_index,text))
		new_card.gui_input.connect(func(event: InputEvent):
			if current_tool=="select" and event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
				entity_selection_requested.emit(get_global_mouse_position())
				new_card.accept_event()
		)
		$TokenNames.add_child(new_card)
		var actions := TOKEN_ACTIONS.instantiate()
		actions.action_requested.connect(func(action: String):
			displayed_token = card_index
			_on_token_action(action)
		)
		$TokenOperations.add_child(actions)
	var chip := $TokenNames.get_child(index) as Control
	var stable: bool = Mobile.enabled and (selected or chip.expanded)
	chip.scale = Vector2.ONE * (Interface.preferences.info_scale if stable else (8.0 / 9.0)*info_zoom*Interface.preferences.info_scale)
	var details_interactive: bool = interactive and (not Mobile.enabled or selected or chip.expanded)
	chip.update_data(data["title"], data["color"], data["hp"], data["max_hp"], data["ac"], int(data.get("temp_hp",0)), str(data.get("notes","")))
	chip.set_editable(editable and details_interactive)
	chip.set_selected(selected)
	chip.expand_button.disabled = not details_interactive
	chip.expand_button.mouse_filter = Control.MOUSE_FILTER_STOP if details_interactive else Control.MOUSE_FILTER_IGNORE
	chip.mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	chip.get_node("Content/Header/HP").mouse_filter = Control.MOUSE_FILTER_STOP if details_interactive else Control.MOUSE_FILTER_IGNORE
	chip.get_node("Content/Header/AC").mouse_filter = Control.MOUSE_FILTER_STOP if details_interactive else Control.MOUSE_FILTER_IGNORE
	chip.visible = in_front and get_global_rect().has_point(at)
	chip.reset_size()
	var dimensions := chip.get_combined_minimum_size() * chip.scale
	chip.position = at - Vector2(dimensions.x / 2.0, dimensions.y + 52.0 * info_zoom)
	chip.position.x = clampf(chip.position.x, sidebar_right(), maxf(sidebar_right(), size.x - dimensions.x - 16.0))
	chip.position.y = clampf(chip.position.y, 64.0, maxf(64.0, size.y - dimensions.y - 100.0))
	var operations := $TokenOperations.get_child(index) as Control
	operations.set_meta("appearance_available", data.get("components", {}).is_empty())
	operations.set_expanded(false)
	operations.place_below(chip, size, sidebar_right())
	if not chip.visible:
		operations.hide()

func pointer_on_creation_palette() -> bool:
	return creation_palette.visible and creation_palette.get_global_rect().has_point(get_global_mouse_position())

func token_index_under_pointer() -> int:
	if pointer_on_creation_palette():
		return -1
	for index in range($TokenNames.get_child_count() - 1, -1, -1):
		var card := $TokenNames.get_child(index) as Control
		if card.visible and card.get_global_rect().has_point(get_global_mouse_position()):
			return index
		var operations := $TokenOperations.get_child(index) as Control
		if card.visible and operations.visible and operations.expanded:
			var surface := card.get_global_rect().merge(operations.get_global_rect())
			if surface.has_point(get_global_mouse_position()):
				return index
	return -1

func set_measure_card(measuring: bool, finished: bool, editing: bool = false) -> void:
	$RouteCard/Content/Buttons/Confirm.text = "完成" if measuring else "确认"
	$RouteCard/Content/Buttons/Confirm.visible = not (measuring and finished)
	$RouteCard/Content/Buttons/Undo.visible = not (measuring and finished)
	$RouteCard/Content/Buttons/Cancel.text = "取消本点修改" if editing and not measuring else "取消"
	$RouteCard/Content/Buttons/Confirm.tooltip_text = "完成当前测距 · Enter" if measuring else "移动到最后一个固定点 · Enter"
	$RouteCard/Content/Buttons/Cancel.tooltip_text = "取消当前测距" if measuring else ("恢复正在修改的路径点" if editing else "取消整条路线")
	if measuring and finished:
		$RouteCard/Content/Hint.hide()
		$PointActions.hide()
		for child in $PathPoints.get_children():
			child.mouse_filter = Control.MOUSE_FILTER_IGNORE
	elif measuring:
		$RouteCard/Content/Hint.hide()

func _on_tool(tool: String) -> void:
	tool_requested.emit(tool)

func configure_campaign_settings(settings) -> void:
	$CampaignSettings.set_mode(settings.distance_mode)
	$CampaignSettings.set_storage_status(settings.storage_message, settings.storage_failed)
	settings.distance_mode_changed.connect($CampaignSettings.set_mode)
	settings.storage_status_changed.connect($CampaignSettings.set_storage_status)

func keyboard_owned_by_ui() -> bool:
	if rename_open() or $ShapeMenu.visible or overlap_menu.visible or $CampaignSettings.popup_visible() or $ShapeSettings.popup_visible() or $TokenCreate.popup_visible():
		return true
	var focused := get_viewport().gui_get_focus_owner()
	return focused != null and (focused == self or is_ancestor_of(focused))

func release_keyboard_focus() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and is_ancestor_of(focused):
		focused.release_focus()

func suspend_pointer_input() -> void:
	for panel in [$CampaignSettings, $Calculator, $ShapeSettings, $MeasureSettings, $TokenCreate]:
		panel.dragging = false

func set_navigation_suspended(suspended: bool) -> void:
	_set_navigation_focus(self, suspended)

func _set_navigation_focus(node: Node, suspended: bool) -> void:
	if node is Control:
		if suspended and not node.has_meta("navigation_focus_mode"):
			node.set_meta("navigation_focus_mode", node.focus_mode)
			node.focus_mode = Control.FOCUS_NONE
		elif not suspended and node.has_meta("navigation_focus_mode"):
			node.focus_mode = node.get_meta("navigation_focus_mode")
			node.remove_meta("navigation_focus_mode")
	for child in node.get_children():
		_set_navigation_focus(child, suspended)

func _on_panel_requested(panel: String) -> void:
	if panel == "campaign_settings":
		$TokenMenu.hide()
		$CampaignSettings.open()
	elif panel == "calculator":
		$Calculator.open()
	elif panel in ["token_basic", "token_advanced"]:
		if current_tool == "token_create":
			return
		$TokenCreate.close()
		var category := "basic" if panel == "token_basic" else "advanced"
		if creation_palette.visible and creation_palette.category == category:
			creation_palette.close()
		else:
			creation_palette.open(sidebar_right(), category)

func _on_creation_entry(entry: Dictionary) -> void:
	if entry.get("builtin", false):
		$TokenCreate.open_creation()
	else:
		token_placement_requested.emit(entry["parameters"].duplicate(true))

func _position_campaign_settings() -> void:
	$CampaignSettings.place_initial(Vector2(sidebar_right(), $Toolbar.position.y))
	$Calculator.place_initial(Vector2(sidebar_right() + 32, $Toolbar.position.y + 32))
	$ShapeSettings.place_initial(Vector2(sidebar_right(), $Toolbar.position.y))
	$MeasureSettings.place_initial(Vector2(sidebar_right(), $Toolbar.position.y))
	$TokenCreate.place_initial(Vector2(sidebar_right(), $Toolbar.position.y))

func show_token_placement_actions(at: Vector2, fixed: bool) -> void:
	$TokenPlacementActions.set_mode("confirm" if fixed else "cancel_preview")
	$TokenPlacementActions.reveal()
	$TokenPlacementActions.place_above(at, sidebar_right())

func hide_token_placement_actions() -> void:
	$TokenPlacementActions.hide()

func shape_parameters() -> Dictionary:
	return $ShapeSettings.parameters()

func update_shape_state(plan) -> void:
	if not plan.draft.is_empty():
		$ShapeSettings.set_parameters(plan.draft)
	$ShapeSettings.set_state(plan.selected >= 0, not plan.draft.is_empty(), plan.moving, plan.position_ready, plan.shapes.size(), plan.dirty())

func show_shape_actions(at: Vector2, confirming: bool = false, moving: bool = false) -> void:
	$ShapeActions.set_mode("cancel_preview" if moving else ("confirm" if confirming else "hover"))
	$ShapeActions.reveal()
	$ShapeActions.place_above(at, sidebar_right())

func hide_shape_actions() -> void:
	$ShapeActions.hide()
	$ShapeMenu.hide()

func shape_surface_under_pointer() -> bool:
	return $ShapeMenu.visible or $ShapeActions.pointer_near()

func shape_menu_visible() -> bool:
	return $ShapeMenu.visible

func open_shape_editor() -> void:
	$ShapeSettings.open()

func close_shape_editor() -> void:
	$ShapeSettings.close()

func show_shape_undo() -> void:
	$ShapeUndo.reveal()
	$ShapeUndoTimer.start()
	_position_shape_undo()

func hide_shape_undo() -> void:
	$ShapeUndo.hide()
	$ShapeUndoTimer.stop()

func _position_shape_undo() -> void:
	$ShapeUndo.place_above(Vector2(size.x / 2.0, size.y - 54), sidebar_right())

func show_measurement_actions(at: Vector2, mode: String) -> void:
	$MeasurementActions.set_mode(mode)
	$MeasurementActions.reveal()
	$MeasurementActions.place_above(at, sidebar_right())

func hide_measurement_actions() -> void:
	$MeasurementActions.hide()

func measurement_surface_under_pointer() -> bool:
	return overlap_menu.visible or $MeasurementActions.pointer_near()

func measurement_menu_visible() -> bool:
	return overlap_menu.visible

func _on_measurement_action(action: String) -> void:
	measurement_action_requested.emit(action)

func show_entity_actions(entries: Array[Dictionary], at: Vector2, below: bool = false) -> void:
	overlap_actions.present(entries, at, size, sidebar_right(), below)

func hide_entity_actions() -> void:
	overlap_actions.hide()
	overlap_menu.hide()

func entity_surface_under_pointer() -> bool:
	return overlap_actions.pointer_near() or overlap_menu.visible

func _on_entity_action(target: Dictionary, action: String, anchor: Rect2) -> void:
	if action == "more":
		menu_target = target.duplicate()
		overlap_menu.clear()
		if target["kind"] == "token":
			_populate_token_menu(overlap_menu)

		else:
			overlap_menu.add_item("编辑参数", 0)
		entity_hovered.emit(target)
		_open_object_menu(overlap_menu, anchor)
	else:
		entity_action_requested.emit(target, action)

func show_measurement_undo() -> void:
	$MeasurementUndo.reveal()
	$MeasurementUndoTimer.start()
	_position_measurement_undo()

func hide_measurement_undo() -> void:
	$MeasurementUndo.hide()
	$MeasurementUndoTimer.stop()

func _position_measurement_undo() -> void:
	$MeasurementUndo.place_above(Vector2(size.x / 2.0, size.y - 100), sidebar_right())

func _on_shape_action(action: String) -> void:
	if action == "more":
		var card: Control = $ShapeActions
		_open_object_menu($ShapeMenu, card.get_global_rect())
	else:
		shape_action_requested.emit(action)

func _on_token_action(action: String) -> void:
	if action == "more":
		var card := $TokenOperations.get_child(displayed_token) as Control
		$TokenMenu.set_item_disabled(1, false)
		$TokenMenu.set_item_text(1, "编辑棋子")
		_open_object_menu($TokenMenu, card.get_global_rect())
	else:
		token_action_requested.emit(action)

func _open_object_menu(menu: PopupMenu, anchor: Rect2) -> void:
	for other in [$TokenMenu, $ShapeMenu, overlap_menu]:
		if other != menu:
			other.hide()
	BoardUiStyle.popup_at(menu, anchor, size, sidebar_right())

func set_tool(tool: String) -> void:
	creation_palette.close()
	$TokenCreate.close()
	hide_entity_actions()
	current_tool = tool
	$Toolbar.set_tool(tool)
	$SelectCard/Select.set_pressed_no_signal(tool == "select")
	BoardUiStyle.refresh_sidebar_button($SelectCard/Select, true)
	if tool == "measure":
		$MeasureSettings.open()
	else:
		$MeasureSettings.close()
	if tool == "shape":
		$ShapeSettings.open()
	else:
		$ShapeSettings.close()
		hide_shape_actions()

func set_status(message: String) -> void:
	$Status.text = message
	$Status.visible = not message.is_empty()

func show_token_actions(index: int, at: Vector2) -> void:
	displayed_token = index
	if index < $TokenNames.get_child_count():
		$TokenOperations.get_child(index).set_expanded(true)

func hide_token_actions() -> void:
	$TokenMenu.hide()
	displayed_token = -1

func token_surface_under_pointer() -> bool:
	return $TokenMenu.visible or token_index_under_pointer() >= 0

func token_menu_visible() -> bool:
	return $TokenMenu.visible

func pointer_on_ui() -> bool:
	if is_instance_valid(map_button_panel) and map_button_panel.is_visible_in_tree() and map_button_panel.get_global_rect().has_point(get_global_mouse_position()): return true
	if rename_open():
		return true
	if $TokenMenu.visible or $ShapeMenu.visible or overlap_menu.visible or $CampaignSettings.popup_visible() or $ShapeSettings.popup_visible() or $TokenCreate.popup_visible():
		return true
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered != null and hovered != self and is_ancestor_of(hovered)

func show_point_actions(at: Vector2) -> void:
	$PointActions.show()
	_place($PointActions, at, true)

func hide_point_actions() -> void:
	$PointActions.hide()

func show_route(amount: String, has_points: bool, editing: bool, at: Vector2) -> void:
	$RouteCard.update_state(amount, has_points, editing)
	$RouteCard.show()
	_place($RouteCard, at, true)

func show_distance(amount: String, at: Vector2) -> void:
	$DistanceChip/Amount.text = amount
	$DistanceChip.reset_size()
	$DistanceChip.show()
	_place($DistanceChip, at, false)

func hide_distance() -> void:
	$DistanceChip.hide()

func set_measure_summary(summary: String) -> void:
	$RouteCard/Content/Summary.text = summary

func hide_saved_measurement() -> void:
	$SavedMeasurement.hide()

func show_saved_measurements(entries: Array[Dictionary]) -> void:
	$SavedMeasurement.show()
	while $SavedMeasurement.get_child_count() < entries.size():
		var label := SEGMENT_LABEL.instantiate() as Control
		label.get_node("Amount").add_theme_color_override("font_color", Color("80602b"))
		$SavedMeasurement.add_child(label)
	for index in range($SavedMeasurement.get_child_count()):
		var label := $SavedMeasurement.get_child(index) as Control
		if index >= entries.size():
			label.hide()
			continue
		var entry: Dictionary = entries[index]
		label.get_node("Amount").text = entry["text"]
		label.set_meta("measurement_index", entry["index"])
		label.mouse_filter = Control.MOUSE_FILTER_IGNORE
		label.tooltip_text = ""
		label.visible = entry["visible"] and get_global_rect().has_point(entry["at"])
		_place(label, entry["at"], true)

func show_saved_measurement_nodes(anchors: Array[Dictionary]) -> void:
	while $SavedMeasureNodes.get_child_count() < anchors.size():
		var node := PATH_POINT.instantiate() as Button
		node.mouse_filter = Control.MOUSE_FILTER_IGNORE
		node.tooltip_text = ""
		$SavedMeasureNodes.add_child(node)
	for index in range($SavedMeasureNodes.get_child_count()):
		var node := $SavedMeasureNodes.get_child(index) as Button
		node.visible = index < anchors.size()
		if node.visible:
			node.position = anchors[index]["at"] - Vector2(12, 12)
			node.set_pressed_no_signal(anchors[index]["highlighted"])

func show_path_points(anchors: Array[Vector2], selected_index: int, editing: bool) -> void:
	while $PathPoints.get_child_count() < anchors.size():
		var button := PATH_POINT.instantiate() as Button
		var index := $PathPoints.get_child_count() + 1
		button.pressed.connect(func(): path_point_selected.emit(index))
		$PathPoints.add_child(button)
	for index in range($PathPoints.get_child_count()):
		var button := $PathPoints.get_child(index) as Button
		if index >= anchors.size():
			button.hide()
			continue
		var at := anchors[index]
		button.visible = get_global_rect().has_point(at)
		button.position = at - Vector2(12, 12)
		button.set_pressed_no_signal(selected_index == index + 1)
		button.mouse_filter = Control.MOUSE_FILTER_IGNORE if editing or current_tool == "measure" else Control.MOUSE_FILTER_STOP
		button.tooltip_text = "" if current_tool == "measure" else "路径点"

func show_segments(amounts: Array[String], anchors: Array[Vector2]) -> void:
	while $SegmentLabels.get_child_count() < amounts.size():
		$SegmentLabels.add_child(SEGMENT_LABEL.instantiate())
	for index in range($SegmentLabels.get_child_count()):
		var chip := $SegmentLabels.get_child(index) as Control
		if index < amounts.size():
			chip.get_node("Amount").text = amounts[index]
			chip.reset_size()
			chip.show()
			_place(chip, anchors[index], true)
		else:
			chip.hide()

func clear_overlays() -> void:
	hide_token_actions()
	hide_point_actions()
	hide_distance()
	$RouteCard.hide()
	for child in $SegmentLabels.get_children():
		child.hide()
	for child in $PathPoints.get_children():
		child.hide()

func _place(control: Control, at: Vector2, above: bool) -> void:
	var role := BoardUiStyle.FloatingRole.INFO
	if control == $PointActions:
		role = BoardUiStyle.FloatingRole.ACTION
	elif control == $RouteCard:
		role = BoardUiStyle.FloatingRole.CONFIRM
	BoardUiStyle.place_floating(control, Rect2(at, Vector2.ZERO), size, sidebar_right(), role, not above)

func update_measure_state(drawing: bool, has_start: bool, editing: bool) -> void:
	$MeasureSettings.set_state(drawing, has_start, editing)

func set_measure_undo_available(allowed: bool) -> void:
	$RouteCard/Content/Buttons/Undo.disabled = not allowed

func set_map_title(title: String) -> void:
	map_navigation.text = title
	map_navigation.tooltip_text = title

func set_map_navigation_active(opened: bool) -> void:
	map_navigation.set_pressed_no_signal(opened)
	BoardUiStyle.refresh_sidebar_button(map_navigation,true)

func set_tray_navigation_active(opened: bool) -> void:
	tray_button.set_pressed_no_signal(opened)
	BoardUiStyle.refresh_sidebar_button(tray_button,true)

func show_network_notice(message: String) -> void:
	network_notice_revision += 1
	var revision := network_notice_revision
	network_notice.text = message
	network_notice.tooltip_text = message
	network_notice.visible = not message.is_empty()
	get_tree().create_timer(5.0).timeout.connect(func():
		if is_instance_valid(network_notice) and revision==network_notice_revision: network_notice.hide()
	)

func notes_editing() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	return focused is TextEdit and $TokenNames.is_ancestor_of(focused)
