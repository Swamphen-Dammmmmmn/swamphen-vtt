extends Control

const SEGMENT_LABEL = preload("res://ui/components/segment_label.tscn")
const PATH_POINT = preload("res://ui/components/path_point.tscn")
const TOKEN_NAME = preload("res://ui/components/token_name.tscn")
const AdventureWorkbar = preload("res://ui/components/features/adventure/adventure_workbar.gd")
const VerticalCommandMenu = preload("res://ui/components/overlays/vertical_command_menu.gd")
const Bar = preload("res://ui/theme/tokens/adventure_topbar_tokens.gd")

signal tool_requested(tool: String)
signal menu_requested
signal floating_area_changed(area: Rect2)
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
signal entity_context_dismissed
signal entity_selection_requested(mouse: Vector2)
signal route_action_requested(action: String)
signal token_renamed(index: int, title: String)
signal token_stats_changed(index: int, hp: int, maximum: int, ac: int, temporary: int)
signal token_notes_changed(index: int, text: String)

const MEASUREMENT_LABEL_Z := 1 # Nodes (0) < distance labels (1) < token cards (2).
const TOKEN_CARD_Z := 2 # Below context (5), topbar (6) and tools (10).
var workbar: AdventureWorkbar
var delete_dialog: Control
var creation_palette: PanelContainer
var _measure_restore_available := false
var displayed_token := -1
var current_tool := "select"
var overlap_actions: ScrollContainer
var command_menu_layer: CanvasLayer
var command_menu: VerticalCommandMenu
var _menu_session_seq := 0
var _active_menu_context: Dictionary = {}
var _closing_menu_context: Dictionary = {}
var network_notice: Label
var network_notice_revision := 0

func _enter_tree() -> void:
	BoardUiStyle.configure()

func _ready() -> void:
	Mobile.register_root(self)
	$TokenNames.z_index = TOKEN_CARD_Z
	$SavedMeasurement.z_index = MEASUREMENT_LABEL_Z
	$Title.hide()
	$BoardInfo.hide()

	workbar = AdventureWorkbar.new()
	workbar.z_index = 6
	add_child(workbar)
	creation_palette = workbar.creation_palette()

	workbar.tool_requested.connect(_on_tool)
	workbar.panel_requested.connect(_on_panel_requested)
	workbar.menu_requested.connect(func(): menu_requested.emit())
	workbar.map_collection_requested.connect(func(): map_collection_requested.emit())
	workbar.creation_entry_chosen.connect(_on_creation_entry)
	workbar.layout_height_changed.connect(func(_bottom_y: float): _on_workbar_layout_changed())

	network_notice = Label.new()
	add_child(network_notice)
	network_notice.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	network_notice.offset_left = -440
	network_notice.offset_right = -20
	network_notice.offset_top = 68
	network_notice.offset_bottom = 94
	network_notice.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	network_notice.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	network_notice.mouse_filter = Control.MOUSE_FILTER_IGNORE
	network_notice.add_theme_color_override("font_color", Color("ffffff"))
	network_notice.hide()

	delete_dialog = preload("res://ui/components/token_delete_dialog.gd").new()
	delete_dialog.z_index = 20
	add_child(delete_dialog)
	delete_dialog.deletion_confirmed.connect(func(id: int): token_deletion_confirmed.emit(id))
	$TokenCreate.appearance_saved.connect(func(id: int, parameters: Dictionary): token_appearance_saved.emit(id, parameters))
	$TokenCreate.placement_requested.connect(func(parameters: Dictionary): token_placement_requested.emit(parameters))
	$TokenPlacementPanel.action_requested.connect(func(action: String): token_placement_action_requested.emit(action))
	$TokenPlacementPanel.user_close_requested.connect(func(): token_placement_action_requested.emit("cancel"))

	resized.connect(_on_workbar_layout_changed)

	$MeasureSettings.user_close_requested.connect(func(): _close_tool_panel("measure"))
	$ShapeSettings.user_close_requested.connect(func(): _close_tool_panel("shape"))
	$MeasureSettings.action_requested.connect(_on_measurement_action)
	$MeasurementUndoTimer.timeout.connect(func():
		hide_measurement_undo()
		measurement_action_requested.emit("forget_measure")
	)

	command_menu_layer = CanvasLayer.new()
	var parent_layer := get_canvas_layer_node()
	command_menu_layer.layer = (parent_layer.layer if parent_layer != null else 1) + 2
	add_child(command_menu_layer)
	command_menu = VerticalCommandMenu.new()
	command_menu_layer.add_child(command_menu)
	command_menu.action_requested.connect(_on_command_menu_action)
	command_menu.closed.connect(_on_command_menu_closed)

	overlap_actions = preload("res://ui/components/overlap_actions.gd").new()
	overlap_actions.fluent = true
	add_child(overlap_actions)
	overlap_actions.action_requested.connect(_on_entity_action)
	overlap_actions.target_hovered.connect(func(target: Dictionary):
		if not _menu_open("overlap"):
			entity_hovered.emit(target)
	)

	$MovementRoutePanel.action_requested.connect(func(action: String):
		if current_tool != "route": return
		if action in ["move_point", "delete_point"]:
			point_action_requested.emit("move" if action == "move_point" else "delete")
		else:
			route_action_requested.emit(action)
	)
	$MovementRoutePanel.user_close_requested.connect(func(): _close_tool_panel("route"))
	$CampaignSettings.mode_requested.connect(func(index: int): campaign_mode_requested.emit(index))
	$CampaignSettings.visibility_changed.connect(func():
		if is_instance_valid(workbar):
			workbar.set_auxiliary_panel_open("campaign_settings", $CampaignSettings.visible)
	)
	$Calculator.visibility_changed.connect(func():
		if is_instance_valid(workbar):
			workbar.set_auxiliary_panel_open("calculator", $Calculator.visible)
	)
	$ShapeSettings.parameters_changed.connect(func(parameters: Dictionary):
		_sync_shape_summary()
		shape_parameters_changed.emit(parameters)
	)
	$ShapeSettings.visibility_changed.connect(_sync_shape_summary)
	$ShapeSettings.action_requested.connect(func(action: String): shape_action_requested.emit(action))
	$ShapeUndoTimer.timeout.connect(func():
		hide_shape_undo()
		shape_action_requested.emit("forget_delete")
	)
	_position_utility_panels()
	_sync_shape_summary()
	$RenameDialog.name_saved.connect(func(index: int, title: String): token_renamed.emit(index, title))
	$StatsDialog.stats_saved.connect(func(index: int, hp: int, maximum: int, ac: int, temporary: int): token_stats_changed.emit(index, hp, maximum, ac, temporary))

func _on_workbar_layout_changed() -> void:
	var top := topbar_bottom()
	if is_instance_valid(network_notice):
		network_notice.offset_top = top + 8.0
		network_notice.offset_bottom = top + 34.0
	_position_utility_panels()
	if is_instance_valid(overlap_actions):
		overlap_actions.update_available_area(size, sidebar_right(), safe_floating_top())
	floating_area_changed.emit(floating_area())

func sidebar_right() -> float:
	return Bar.BOARD_EDGE_MARGIN

func topbar_bottom() -> float:
	if is_instance_valid(workbar):
		return maxf(Bar.PRIMARY_MIN_HEIGHT, workbar.occupied_bottom())
	return Bar.PRIMARY_MIN_HEIGHT

func safe_floating_top() -> float:
	return topbar_bottom() + Bar.TOPBAR_FLOATING_GAP

func floating_area() -> Rect2:
	var top := safe_floating_top()
	return Rect2(Vector2(0, top), Vector2(size.x, maxf(0, size.y - top)))

func utility_panel_layout_snapshot() -> Dictionary:
	var snapshots := {}
	for panel in [$CampaignSettings, $Calculator, $ShapeSettings, $MeasureSettings, $TokenCreate, $TokenPlacementPanel, $MovementRoutePanel]:
		if panel.visible:
			var snapshot: Dictionary = panel.layout_snapshot()
			snapshot["below_workbar"] = panel.position.y >= safe_floating_top() - 0.5
			snapshot["above_bottom_margin"] = panel.position.y + panel.size.y <= size.y - 54.0 + 0.5
			snapshots[str(panel.name)] = snapshot
	return snapshots

func mount_tray_panel(panel: Control) -> void:
	if is_instance_valid(workbar):
		workbar.mount_tray_panel(panel)

func set_tray_count(count: int) -> void:
	if is_instance_valid(workbar):
		workbar.set_tray_count(count)

func open_tray_drawer(key: String) -> void:
	if is_instance_valid(workbar):
		workbar.open_tray_category(key)

func is_tray_drawer_open() -> bool:
	return is_instance_valid(workbar) and workbar.is_secondary_expanded() and workbar.active_category() == "tray"

func collapse_workbar_drawer() -> void:
	if is_instance_valid(workbar):
		workbar.collapse_secondary()

func set_tray_navigation_active(_opened: bool) -> void:
	pass

func _exit_tree() -> void:
	_active_menu_context = {}
	_closing_menu_context = {}

func _sync_shape_summary() -> void:
	if is_instance_valid(workbar):
		workbar.set_shape_summary($ShapeSettings.summary_text(), $ShapeSettings.visible)

func _menu_open(kind := "") -> bool:
	if not is_instance_valid(command_menu) or not command_menu.is_open():
		return false
	return kind.is_empty() or str(_active_menu_context.get("kind", "")) == kind

func _close_command_menu(kind := "") -> bool:
	if not _menu_open(kind):
		return false
	command_menu.close(false)
	return true

func _open_command_menu(kind: String, anchor: Control, actions: Array[Dictionary], target: Dictionary = {}) -> void:
	if not is_instance_valid(command_menu) or not is_instance_valid(anchor):
		return
	var parent_layer := get_canvas_layer_node()
	if is_instance_valid(command_menu_layer) and parent_layer != null:
		command_menu_layer.layer = parent_layer.layer + 2
	if command_menu.is_open():
		command_menu.close(false)
	_closing_menu_context = {}
	_menu_session_seq += 1
	_active_menu_context = {
		"id": _menu_session_seq,
		"kind": kind,
		"target": target.duplicate(true),
	}
	command_menu.open(anchor, actions)
	if not command_menu.is_open():
		if kind == "overlap":
			entity_hovered.emit({})
		_active_menu_context = {}

func _token_menu_entries() -> Array[Dictionary]:
	return [
		{"title": "重命名", "id": "rename", "icon": "res://ui/theme/icons/library/edit.svg"},
		{"title": "编辑棋子", "id": "appearance", "icon": "res://ui/theme/icons/library/edit.svg"},
		{"title": "复制", "id": "copy", "icon": "res://ui/theme/icons/library/copy.svg"},
		{"title": "收纳到托盘…", "id": "store", "icon": "res://ui/theme/icons/topbar_tray.svg"},
		{"title": "删除", "id": "delete", "danger": true, "separator_before": true},
	]

func _shape_menu_entries() -> Array[Dictionary]:
	return [
		{"title": "编辑参数", "id": "edit", "icon": "res://ui/theme/icons/library/edit.svg"},
	]

func _on_command_menu_action(action_id: String) -> void:
	if not is_inside_tree() or is_queued_for_deletion():
		_closing_menu_context = {}
		return
	# VerticalCommandMenu._activate() emits `closed` synchronously inside close() before emitting `action_requested`.
	# Consume the exact session captured by `_on_command_menu_closed()` so activation never loses context
	# and never acts on a newly opened replacement menu.
	var ctx: Dictionary = _closing_menu_context if not _closing_menu_context.is_empty() else _active_menu_context
	_closing_menu_context = {}
	if not _active_menu_context.is_empty() and int(_active_menu_context.get("id", -1)) == int(ctx.get("id", -2)):
		_active_menu_context = {}
	var kind := str(ctx.get("kind", ""))
	match kind:
		"shape":
			shape_action_requested.emit(action_id)
		"overlap":
			var target: Dictionary = ctx.get("target", {})
			if not target.is_empty():
				entity_action_requested.emit(target, action_id if target.get("kind") == "token" else "edit")

func _on_command_menu_closed() -> void:
	var ctx := _active_menu_context
	_active_menu_context = {}
	if ctx.is_empty():
		return
	if str(ctx.get("kind", "")) == "overlap":
		entity_hovered.emit({})
	_closing_menu_context = ctx
	var closed_id := int(ctx.get("id", 0))
	_expire_closing_menu_context.call_deferred(closed_id)

func _expire_closing_menu_context(closed_id: int) -> void:
	if int(_closing_menu_context.get("id", -1)) == closed_id:
		_closing_menu_context = {}

func rename_open() -> bool:
	return $RenameDialog.visible or $StatsDialog.visible or delete_dialog.visible or $TokenCreate.is_editing_instance()

func session_shortcuts_blocked() -> bool:
	var workbar_popup := is_instance_valid(workbar) and workbar.popup_visible()
	return rename_open() or _menu_open() or $CampaignSettings.popup_visible() or $ShapeSettings.popup_visible() or $TokenCreate.visible or workbar_popup

func close_local_ui_for_escape() -> bool:
	# 1. Active dropdowns / context popups via public component APIs (never collapsing the topbar secondary drawer)
	if is_instance_valid(workbar) and workbar.close_popups():
		return true
	if _close_command_menu():
		return true
	for panel in [$CampaignSettings, $ShapeSettings, $TokenCreate]:
		if panel.close_popups():
			return true
	# 2. Local modal / in-place editing panels and floating auxiliary windows
	if delete_dialog.visible:
		delete_dialog.hide()
		return true
	if $RenameDialog.visible:
		$RenameDialog.hide()
		return true
	if $StatsDialog.visible:
		$StatsDialog.hide()
		return true
	if overlap_actions.has_context_entries():
		hide_entity_actions()
		entity_context_dismissed.emit()
		return true
	var panels: Array[Control] = []
	for panel in [$TokenCreate, $TokenPlacementPanel, $MovementRoutePanel, $ShapeSettings, $MeasureSettings, $Calculator, $CampaignSettings]:
		if panel.visible: panels.append(panel)
	panels.sort_custom(func(a: Control, b: Control): return a.get_index() > b.get_index())
	if not panels.is_empty():
		panels[0].request_close()
		return true
	# 3. Release focus from inputs or buttons inside the board UI before affecting tools
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and is_ancestor_of(focused):
		var release_only := focused is LineEdit or focused is TextEdit
		focused.release_focus()
		if release_only:
			return true
	return false

func token_name_rect(index: int) -> Rect2:
	if index >= 0 and index < $TokenNames.get_child_count():
		return ($TokenNames.get_child(index) as Control).get_global_rect()
	return Rect2()

func open_rename(index: int, title: String) -> void:
	var card := $TokenNames.get_child(index) as Control
	$RenameDialog.open(index, title, card.get_global_rect(), sidebar_right(), safe_floating_top())

func open_stats(index: int, data: Dictionary, mode: String) -> void:
	var card := $TokenNames.get_child(index) as Control
	$StatsDialog.left_margin = sidebar_right()
	$StatsDialog.top_margin = safe_floating_top()
	$StatsDialog.open(index, data, mode, card.get_global_rect())

func open_token_appearance(data: Dictionary) -> void:
	$RenameDialog.hide()
	$StatsDialog.hide()
	$TokenCreate.open_edit(data)

func open_token_delete(data: Dictionary, measurement_count: int) -> void:
	$RenameDialog.hide()
	$StatsDialog.hide()
	$TokenCreate.close()
	delete_dialog.open(data, measurement_count)

func clear_token_stats_history(token_id: int) -> void:
	$StatsDialog.clear_token_history(token_id)

func clear_all_stats_history() -> void:
	$StatsDialog.clear_all_history()

func close_stats_if_editing_token(index: int) -> void:
	$StatsDialog.close_if_editing_token(index)

func reset_after_token_removal(token_id: int) -> void:
	$RenameDialog.hide()
	$StatsDialog.hide()
	$StatsDialog.clear_token_history(token_id)
	$TokenCreate.close()
	delete_dialog.hide()
	hide_token_actions()
	hide_entity_actions()
	# Rebuild index-based callbacks after the list changes.
	for child in $TokenNames.get_children():
		$TokenNames.remove_child(child)
		child.queue_free()

func show_token_name(index: int, data: Dictionary, at: Vector2, in_front: bool, selected: bool, interactive: bool, info_zoom: float, editable: bool = true) -> void:
	while $TokenNames.get_child_count() <= index:
		var new_card := TOKEN_NAME.instantiate()
		var card_index: int = $TokenNames.get_child_count()
		new_card.action_requested.connect(func(action: String):
			displayed_token = card_index
			_on_token_action(action)
		)
		new_card.notes_changed.connect(func(text: String): token_notes_changed.emit(card_index, text))
		new_card.gui_input.connect(func(event: InputEvent):
			if current_tool == "select" and event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
				entity_selection_requested.emit(get_global_mouse_position())
				new_card.accept_event()
		)
		$TokenNames.add_child(new_card)
	var chip := $TokenNames.get_child(index) as Control
	var stable: bool = Mobile.enabled and (selected or chip.expanded)
	chip.scale = Vector2.ONE * (Interface.preferences.info_scale if stable else (8.0 / 9.0) * info_zoom * Interface.preferences.info_scale)
	var details_interactive: bool = interactive and (not Mobile.enabled or selected or chip.expanded)
	chip.update_data(data["title"], data["color"], data["hp"], data["max_hp"], data["ac"], int(data.get("temp_hp", 0)), str(data.get("notes", "")))
	chip.set_editable(editable and details_interactive)
	chip.set_selected(selected)
	chip.set_details_interactive(details_interactive)
	chip.mouse_filter = Control.MOUSE_FILTER_STOP if interactive else Control.MOUSE_FILTER_IGNORE
	var top_limit := safe_floating_top()
	chip.visible = in_front and get_global_rect().has_point(at)
	chip.reset_size()
	var dimensions := chip.get_combined_minimum_size() * chip.scale
	chip.position = at - Vector2(dimensions.x / 2.0, dimensions.y + 52.0 * info_zoom)
	chip.position.x = clampf(chip.position.x, sidebar_right(), maxf(sidebar_right(), size.x - dimensions.x - 16.0))
	chip.position.y = clampf(chip.position.y, top_limit, maxf(top_limit, size.y - dimensions.y - 100.0))

func pointer_on_creation_palette() -> bool:
	return is_instance_valid(workbar) and workbar.pointer_on_asset_drawer(get_global_mouse_position())

func token_index_under_pointer() -> int:
	if is_instance_valid(workbar) and workbar.hit_test(get_global_mouse_position()):
		return -1
	for index in range($TokenNames.get_child_count() - 1, -1, -1):
		var card := $TokenNames.get_child(index) as Control
		if card.visible and card.get_global_rect().has_point(get_global_mouse_position()):
			return index
	return -1

func _on_tool(tool: String) -> void:
	tool_requested.emit(tool)

func configure_campaign_settings(settings) -> void:
	$CampaignSettings.set_mode(settings.distance_mode)
	$CampaignSettings.set_storage_status(settings.storage_message, settings.storage_failed)
	settings.distance_mode_changed.connect($CampaignSettings.set_mode)
	settings.storage_status_changed.connect($CampaignSettings.set_storage_status)

func keyboard_owned_by_ui() -> bool:
	if is_instance_valid(overlap_actions) and overlap_actions.owns_keyboard():
		return true
	var workbar_popup := is_instance_valid(workbar) and workbar.popup_visible()
	if rename_open() or _menu_open() or $CampaignSettings.popup_visible() or $ShapeSettings.popup_visible() or $TokenCreate.popup_visible() or workbar_popup:
		return true
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and (focused is LineEdit or focused is TextEdit):
		return true
	if focused != null and $TokenNames.is_ancestor_of(focused):
		return true
	for panel in [$CampaignSettings, $Calculator, $ShapeSettings, $MeasureSettings, $TokenCreate, $TokenPlacementPanel, $MovementRoutePanel]:
		if panel.visible and focused != null and (focused == panel or panel.is_ancestor_of(focused)):
			return true
	return false

func release_keyboard_focus() -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and is_ancestor_of(focused):
		focused.release_focus()

func suspend_pointer_input() -> void:
	if is_instance_valid(workbar):
		workbar.close_popups()
	_close_command_menu()
	for panel in [$CampaignSettings, $Calculator, $ShapeSettings, $MeasureSettings, $TokenCreate, $TokenPlacementPanel, $MovementRoutePanel]:
		panel.suspend_pointer_input()

func set_navigation_suspended(suspended: bool) -> void:
	if suspended:
		if is_instance_valid(workbar):
			workbar.close_popups()
		_close_command_menu()
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

func request_panel(panel: String) -> void:
	_on_panel_requested(panel)

func _on_panel_requested(panel: String) -> void:
	if panel == "campaign_settings":
		_close_command_menu("token")
		if $CampaignSettings.visible:
			$CampaignSettings.close()
		else:
			$CampaignSettings.open()
	elif panel == "calculator":
		$Calculator.open()
	elif panel in ["token_basic", "token_advanced"]:
		if current_tool == "token_create":
			return
		$TokenCreate.close()
		var category := "basic" if panel == "token_basic" else "advanced"
		if is_instance_valid(creation_palette):
			creation_palette.switch_embedded_category(category)
		if is_instance_valid(workbar):
			workbar.expand_category("tokens")

func open_builtin_token_creation() -> void:
	if is_instance_valid(creation_palette):
		_on_creation_entry(creation_palette.BUILTIN_BASIC)
	else:
		$TokenCreate.open_creation()

func _on_creation_entry(entry: Dictionary) -> void:
	if entry.get("builtin", false):
		if current_tool == "token_create":
			tool_requested.emit("select")
		$TokenCreate.open_creation()
	else:
		token_placement_requested.emit(entry["parameters"].duplicate(true))

func _position_utility_panels() -> void:
	var y_top := safe_floating_top()
	var x_left := sidebar_right()
	var area := floating_area()
	for panel in [$CampaignSettings, $Calculator, $ShapeSettings, $MeasureSettings, $TokenCreate, $TokenPlacementPanel, $MovementRoutePanel]:
		panel.set_available_rect(area)
	$CampaignSettings.place_initial(Vector2(x_left, y_top))
	$Calculator.place_initial(Vector2(x_left + $ShapeSettings.preferred_width + Bar.TOPBAR_FLOATING_GAP, y_top))
	$ShapeSettings.place_initial(Vector2(x_left, y_top))
	$MeasureSettings.place_initial(Vector2(x_left, y_top))
	$TokenCreate.place_initial(Vector2(x_left, y_top))
	$TokenPlacementPanel.place_initial(Vector2(x_left, y_top))
	$MovementRoutePanel.place_initial(Vector2(x_left, y_top))

func set_token_placement_workflow(state: Dictionary) -> void:
	$TokenPlacementPanel.set_workflow_state(state)
	if state.get("active", false):
		if not $TokenPlacementPanel.visible:
			$TokenPlacementPanel.open()
	elif $TokenPlacementPanel.visible:
		$TokenPlacementPanel.close()

func shape_parameters() -> Dictionary:
	return $ShapeSettings.parameters()

func update_shape_state(plan) -> void:
	if not plan.draft.is_empty():
		$ShapeSettings.set_parameters(plan.draft)
	$ShapeSettings.set_state(plan.selected >= 0, not plan.draft.is_empty(), plan.moving, plan.position_ready, plan.shapes.size(), plan.dirty())
	_sync_shape_summary()


func hide_shape_actions() -> void:
	_close_command_menu("shape")

func shape_menu_visible() -> bool:
	return _menu_open("shape")

func open_shape_editor() -> void:
	if is_instance_valid(workbar):
		workbar.set_tool("shape")
	$ShapeSettings.open()
	_sync_shape_summary()

func show_shape_undo() -> void:
	$ShapeSettings.set_delete_undo_available(true)
	$ShapeUndoTimer.start()

func hide_shape_undo() -> void:
	$ShapeSettings.set_delete_undo_available(false)
	$ShapeUndoTimer.stop()

func measurement_menu_visible() -> bool:
	return _menu_open("overlap")

func _on_measurement_action(action: String) -> void:
	measurement_action_requested.emit(action)

func show_entity_actions(entries: Array[Dictionary], at: Vector2, below: bool = false) -> void:
	overlap_actions.present(entries, at, size, sidebar_right(), below, safe_floating_top())

func hide_entity_actions() -> void:
	overlap_actions.hide()
	_close_command_menu("overlap")

func entity_surface_under_pointer() -> bool:
	return overlap_actions.pointer_near() or _menu_open("overlap")

func _on_entity_action(target: Dictionary, action: String, anchor_control: Control) -> void:
	if action == "more":
		entity_hovered.emit(target)
		var entries := _token_menu_entries() if target["kind"] == "token" else _shape_menu_entries()
		_open_command_menu("overlap", anchor_control, entries, target)
	else:
		entity_action_requested.emit(target, action)

func show_measurement_undo() -> void:
	_measure_restore_available = true
	$MeasurementUndoTimer.start()

func hide_measurement_undo() -> void:
	_measure_restore_available = false
	$MeasurementUndoTimer.stop()

func _on_token_action(action: String) -> void:
	token_action_requested.emit(action)

func set_tool(tool: String) -> void:
	# Do NOT auto-collapse topbar secondary drawer on tool changes!
	$TokenCreate.close()
	hide_entity_actions()
	current_tool = tool
	if tool == "route":
		$MovementRoutePanel.open()
	else:
		$MovementRoutePanel.close()
	if tool == "token_create":
		$TokenPlacementPanel.open()
	else:
		$TokenPlacementPanel.close()
	if is_instance_valid(workbar):
		workbar.set_tool(tool)
	if tool != "measure":
		$MeasureSettings.close()
	if tool == "measure":
		$MeasureSettings.open()
	if tool == "shape":
		$ShapeSettings.open()
	else:
		$ShapeSettings.close()
		hide_shape_actions()
	_sync_shape_summary()

func set_status(message: String) -> void:
	$Status.text = message
	$Status.visible = not message.is_empty()

func hide_token_actions() -> void:
	_close_command_menu("token")
	displayed_token = -1

func token_surface_under_pointer() -> bool:
	return _menu_open("token") or token_index_under_pointer() >= 0

func token_menu_visible() -> bool:
	return _menu_open("token")

func pointer_on_ui() -> bool:
	var mouse := get_global_mouse_position()
	if is_instance_valid(workbar) and workbar.hit_test(mouse):
		return true
	if rename_open():
		return true
	if _menu_open() or $CampaignSettings.popup_visible() or $ShapeSettings.popup_visible() or $TokenCreate.popup_visible():
		return true
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered != null and hovered != self and is_ancestor_of(hovered)

func set_movement_workflow(state: Dictionary) -> void:
	$MovementRoutePanel.set_workflow_state(state)

func show_distance(amount: String, at: Vector2) -> void:
	$DistanceChip.z_index = MEASUREMENT_LABEL_Z if current_tool == "measure" else 0
	$DistanceChip.set_amount_text(amount)
	$DistanceChip.reset_size()
	$DistanceChip.show()
	_place($DistanceChip, at, false)

func hide_distance() -> void:
	$DistanceChip.hide()

func hide_saved_measurement() -> void:
	$SavedMeasurement.hide()

func show_saved_measurements(entries: Array[Dictionary]) -> void:
	$SavedMeasurement.show()
	while $SavedMeasurement.get_child_count() < entries.size():
		var label := SEGMENT_LABEL.instantiate() as Control
		label.set_tone(&"saved_measurement")
		$SavedMeasurement.add_child(label)
	for index in range($SavedMeasurement.get_child_count()):
		var label := $SavedMeasurement.get_child(index) as Control
		if index >= entries.size():
			label.hide()
			continue
		var entry: Dictionary = entries[index]
		label.set_amount_text(str(entry["text"]))
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

func saved_measurements_at(screen_point: Vector2) -> Array[int]:
	# Labels remain mouse-ignore: the board owns click/drag arbitration.
	var indices: Array[int] = []
	if not $SavedMeasurement.is_visible_in_tree():
		return indices
	for label: Control in $SavedMeasurement.get_children():
		var index := int(label.get_meta("measurement_index", -1))
		if index >= 0 and label.is_visible_in_tree() and label.get_global_rect().has_point(screen_point) and not indices.has(index):
			indices.append(index)
	return indices

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
	$SegmentLabels.z_index = MEASUREMENT_LABEL_Z if current_tool == "measure" else 0
	while $SegmentLabels.get_child_count() < amounts.size():
		$SegmentLabels.add_child(SEGMENT_LABEL.instantiate())
	for index in range($SegmentLabels.get_child_count()):
		var chip := $SegmentLabels.get_child(index) as Control
		if index < amounts.size():
			chip.set_amount_text(amounts[index])
			chip.reset_size()
			chip.show()
			_place(chip, anchors[index], true)
		else:
			chip.hide()

func clear_overlays() -> void:
	hide_token_actions()
	hide_distance()
	for child in $SegmentLabels.get_children():
		child.hide()
	for child in $PathPoints.get_children():
		child.hide()

func _place(control: Control, at: Vector2, above: bool) -> void:
	var role := BoardUiStyle.FloatingRole.INFO
	BoardUiStyle.place_floating(control, Rect2(at, Vector2.ZERO), size, sidebar_right(), role, not above, safe_floating_top())

func update_measure_state(drawing: bool, has_start: bool, editing: bool) -> void:
	$MeasureSettings.set_state(drawing, has_start, editing)

func set_measure_workflow(state: Dictionary) -> void:
	var snapshot := state.duplicate()
	snapshot["can_restore"] = _measure_restore_available
	$MeasureSettings.set_workflow_state(snapshot)

func _close_tool_panel(tool_id: String) -> void:
	if current_tool == tool_id:
		tool_requested.emit("select")

func set_map_title(title: String) -> void:
	if is_instance_valid(workbar):
		workbar.set_map_title(title)

func set_map_navigation_active(opened: bool) -> void:
	if is_instance_valid(workbar):
		workbar.set_map_navigation_active(opened)

func show_network_notice(message: String) -> void:
	network_notice_revision += 1
	var revision := network_notice_revision
	network_notice.text = message
	network_notice.tooltip_text = message
	network_notice.visible = not message.is_empty()
	get_tree().create_timer(5.0).timeout.connect(func():
		if is_instance_valid(network_notice) and revision == network_notice_revision:
			network_notice.hide()
	)

func notes_editing() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	return focused is TextEdit and $TokenNames.is_ancestor_of(focused)
