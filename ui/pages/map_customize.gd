extends Control
var mobile_touch: Node
var mobile_previous_tool := ""
var mobile_tool_state: Dictionary = {}
const Style = preload("res://ui/components/page_style.gd")
const Layout = preload("res://ui/components/editor_layout.gd")
const DisplaySettings = preload("res://ui/components/designer_display_settings.gd")
const UtilityPopup = preload("res://ui/components/designer_utility_popup.gd")
const Weather = preload("res://scripts/map_weather.gd")
const WeatherPanel = preload("res://ui/components/map_weather_panel.gd")
const Store = preload("res://scripts/map_library_store.gd")
const Data = preload("res://scripts/map_data.gd")
const Preview = preload("res://ui/components/map_preview.gd")
const Toolbar = preload("res://ui/components/map_toolbar.gd")
const BuildMenu = preload("res://ui/components/build_menu.gd")
const Palette = preload("res://ui/components/platform_palette.gd")
const Overlap = preload("res://ui/components/overlap_actions.gd")
const Modal = preload("res://ui/components/page_modal.gd")
const MoveGizmo = preload("res://ui/components/map_move_gizmo.gd")
const PlatformEditor = preload("res://ui/pages/platform_customize.gd")
signal return_requested
signal content_changed
var page: Control
var values := Data.defaults()
var edit_id := ""
var saved_signature := ""
var save_delegate: Callable
var save_state_provider: Callable
var container_save_title := "保存到地图库"
var container_return_title := "返回地图库"
var container_product_name: Callable
var external_blocked: Callable
var preview: Control
var tools: PanelContainer
var menu: Control
var palette: PanelContainer
var panel: PanelContainer
var panel_body: VBoxContainer
var panel_scroll: ScrollContainer
var heading: Label
var name_input: LineEdit
var properties: VBoxContainer
var selection: VBoxContainer
var selection_title: Label
var selection_size: Label
var position_inputs: Dictionary = {}
var list: VBoxContainer
var list_search: LineEdit
var list_rows: VBoxContainer
var status: Label
var actions: ScrollContainer
var common_bar: PanelContainer
var save_button: Button
var save_state: Label
var handle: Button
var display_panel: PanelContainer
var selected := ""
var hovered := ""
var candidates: Array[String] = []
var moving := ""
var draft := {}
var source_record := {}
var candidate := Vector3.ZERO
var candidate_valid := false
var active_tool := "map_select"
var expanded := true
var normal_speed := 20.0
var fast_speed := 80.0
var rotating := false
var mouse_origin := Vector2.ZERO
var accepted_leave := false
var saving := false
var modal: Control
var fit_pending := false
var panel_tween: Tween
var move_gizmo: Node3D
var platform_editor: Control
var editing_platform := ""
var camera_before_edit := Transform3D.IDENTITY
var target_before_edit := Vector3.ZERO
var camera_transition: Tween
var weather_panel: VBoxContainer

func _ready() -> void:
	_mobile_attach.call_deferred()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview = Preview.new()
	add_child(preview)
	preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for item: Dictionary in values["platforms"]: preview.add_platform(item)
	preview.frame_all()
	preview.apply_weather(values["environment"])
	move_gizmo = MoveGizmo.new()
	preview.world.add_child(move_gizmo)
	move_gizmo.camera = preview.camera
	move_gizmo.values_changed.connect(_gizmo_changed)
	tools = Toolbar.new()
	add_child(tools)
	tools.tool_selected.connect(_select_tool)
	tools.category_changed.connect(_select_tool)
	tools.layout_changed.connect(_queue_fit)
	panel = Style.card()
	panel.add_theme_stylebox_override("panel",BoardUiStyle.card_face(16))
	add_child(panel)
	var column := Style.column(12)
	panel.add_child(column)
	var header := HBoxContainer.new()
	column.add_child(header)
	var fold_space := Control.new()
	fold_space.custom_minimum_size = Vector2(40,44)
	header.add_child(fold_space)
	heading = Style.text("地图",20)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(heading)
	panel_scroll = ScrollContainer.new()
	column.add_child(panel_scroll)
	Layout.scroll(panel_scroll)
	panel_body = Style.column(12)
	panel_scroll.add_child(panel_body)
	properties = Style.column(12)
	panel_body.add_child(properties)
	name_input = LineEdit.new()
	name_input.text = values["title"]
	name_input.max_length = 60
	name_input.custom_minimum_size.y = 44
	Layout.field(properties,"名称").add_child(name_input)
	name_input.text_changed.connect(func(text: String): values["title"] = text; _mark_unsaved())
	selection = Style.column(12)
	panel_body.add_child(selection)
	selection_title = Style.text("未选择地台",18)
	selection.add_child(selection_title)
	selection_size = Style.text("",14,true)
	selection.add_child(selection_size)
	var horizontal := Layout.pair(selection)
	_position_number(horizontal,"X · 英尺","x",5)
	_position_number(horizontal,"Z · 英尺","z",5)
	_position_number(selection,"顶面高度 · 英尺","y",1)
	var selection_actions := Layout.pair(selection)
	selection_actions.add_child(_button("移动",func(): _start_move(selected)))
	selection_actions.add_child(_button("编辑",func(): _edit_platform(selected)))
	selection_actions.add_child(_button("删除",func(): _delete_selected(),false,true))
	selection_actions.set_meta("selection_actions",true)
	list = Style.column(12)
	panel_body.add_child(list)
	list_search = LineEdit.new()
	list_search.placeholder_text = "搜索地图内地台"
	list_search.custom_minimum_size.y = 44
	list.add_child(list_search)
	list_search.text_changed.connect(func(_text: String): _refresh_list())
	list_rows = Style.column(8)
	list.add_child(list_rows)
	weather_panel = WeatherPanel.new()
	weather_panel.popup_host = self
	panel_body.add_child(weather_panel)
	weather_panel.changed.connect(_weather_changed)
	status = Layout.status()
	column.add_child(status)
	handle = _button("",_toggle_panel)
	handle.custom_minimum_size = Vector2(44,44)
	handle.expand_icon = true
	handle.add_theme_constant_override("icon_max_width",20)
	add_child(handle)
	actions = Overlap.new()
	add_child(actions)
	actions.action_requested.connect(func(target: Dictionary, action: String, _anchor: Rect2):
		match action:
			"select": _select(target["id"])
			"move": _start_move(target["id"])
			"delete": _select(target["id"]); _delete_selected()
			"edit": _edit_platform(target["id"])
	)
	actions.target_hovered.connect(func(target: Dictionary):
		if not target.is_empty() and preview.selected_id!=target["id"]: preview.highlight(target["id"])
	)
	palette = Palette.new()
	add_child(palette)
	palette.entry_chosen.connect(_choose_platform)
	palette.z_index = 6
	menu = BuildMenu.new()
	menu.page = page
	menu.return_title = container_return_title
	menu.save_title = container_save_title
	menu.product_title = func(): return container_product_name.call() if container_product_name.is_valid() else name_input.text
	add_child(menu)
	save_button = menu.save_button
	save_state = menu.state_label
	menu.save_requested.connect(func(): await _save())
	menu.return_requested.connect(func(): return_requested.emit())
	menu.menu_opened.connect(func(): _cancel_operation(); palette.close(); _release_camera())
	_build_common_bar()
	resized.connect(_queue_fit)
	panel_body.minimum_size_changed.connect(_queue_fit)
	_refresh_list()
	_refresh_panel()
	if not edit_id.is_empty(): saved_signature = Store.signature(values)
	_mark_unsaved()
	_queue_fit()
	Style.Motion.fade_in(panel)

func _button(title: String, callback: Callable, primary := false, danger := false) -> Button:
	var button := Button.new()
	button.text = title
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Style.card_button(button)
	if primary or danger: Style.button(button,primary,44,danger)
	button.pressed.connect(callback)
	return button

func _position_number(parent: Control, title: String, key: String, step: float) -> void:
	var input := SpinBox.new()
	input.min_value = -1000000
	input.max_value = 1000000
	input.step = step
	input.custom_minimum_size.y = 44
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Layout.field(parent,title).add_child(input)
	position_inputs[key] = input
	input.value_changed.connect(func(value: float): _change_position(key,value))

func _item(id: String) -> Dictionary:
	for item: Dictionary in values["platforms"]:
		if item["id"]==id: return item
	return {}

func _select_tool(key: String) -> void:
	if key == "mobile_camera":
		if active_tool == key:
			_select_tool(mobile_previous_tool)
			if not mobile_tool_state.get("draft",{}).is_empty():
				draft = mobile_tool_state["draft"].duplicate(true)
				source_record = mobile_tool_state["source"].duplicate(true)
				palette.close()
				_refresh_panel()
			elif not str(mobile_tool_state.get("moving","")).is_empty(): _start_move(mobile_tool_state["moving"])
			mobile_tool_state.clear()
			if tools.buttons.has(mobile_previous_tool): tools.buttons[mobile_previous_tool].button_pressed = true
			return
		mobile_previous_tool = active_tool
		mobile_tool_state = {"draft":draft.duplicate(true),"source":source_record.duplicate(true),"moving":moving}
		_cancel_operation()
		palette.close()
		active_tool = key
		if expanded: _toggle_panel()
		return
	_cancel_operation()
	palette.close()
	active_tool = key
	if key.begins_with("weather_"): preview.highlight("")
	candidates.clear()
	if key=="add_platform": palette.open(_panel_edge()+340+12,"platform")
	_refresh_panel()

func _weather_changed() -> void:
	preview.apply_weather(values["environment"])
	weather_panel.sync_angles()
	_mark_unsaved()

func _select(id: String) -> void:
	selected = id
	candidates.clear()
	preview.highlight(id)
	_refresh_panel()

func _refresh_panel() -> void:
	var is_weather := active_tool.begins_with("weather_")
	weather_panel.visible = is_weather
	if is_weather and weather_panel.tool!=active_tool: weather_panel.show_tool(active_tool,values["environment"] )
	properties.visible = active_tool=="map_properties"
	list.visible = active_tool=="platforms"
	selection.visible = not properties.visible and not list.visible and not is_weather
	var item := draft if not draft.is_empty() else _item(selected)
	var available := not item.is_empty()
	selection_title.text = str(item["data"]["title"]) if available else "未选择地台"
	selection_size.text = "%d × %d 英尺 · 厚 %d 英尺" % [item["data"]["width_feet"],item["data"]["length_feet"],item["data"]["thickness_feet"]] if available else ""
	selection_size.visible = available
	for key: String in position_inputs:
		var input: SpinBox = position_inputs[key]
		input.get_parent().visible = available
		input.editable = move_gizmo.dragged < 0
	if available:
		var box := Data.bounds(item)
		position_inputs["x"].set_value_no_signal(box.position.x)
		position_inputs["z"].set_value_no_signal(box.position.z)
		position_inputs["y"].set_value_no_signal(box.end.y)
		position_inputs["x"].get_parent().visible = draft.is_empty()
		position_inputs["z"].get_parent().visible = draft.is_empty()
	for child in selection.get_children():
		if child.has_meta("selection_actions"): child.visible = available and draft.is_empty() and moving.is_empty()
	heading.text = "地图 · 属性" if properties.visible else ("地图 · 地台列表" if list.visible else ("地图 · 添加地台" if active_tool=="add_platform" else "地图 · 选择地台"))
	if is_weather: heading.text = "天气 · "+{"weather_atmosphere":"氛围","weather_sky":"天空","weather_light":"光照","weather_wind":"风"}[active_tool]
	_queue_fit()

func _change_position(key: String, value: float) -> void:
	var item := draft if not draft.is_empty() else _item(selected)
	if item.is_empty(): return
	var at: Vector3 = item["offset_feet"]
	var data: Dictionary = item["data"]
	var origin: Vector2 = data.get("bounds_origin_feet",data["grid_origin_feet"])
	match key:
		"x": at.x = snappedf(value-origin.x,5)
		"z": at.z = snappedf(value-origin.y,5)
		"y": at.y = roundf(value-float(data["top_feet"]))
	if absf(at.x)>1000000 or absf(at.y)>1000000 or absf(at.z)>1000000:
		Layout.set_status(status,"位置超出支持范围，原位置已保留。",true)
		_refresh_panel()
		return
	if draft.is_empty() and Data.conflicts(item,at,values["platforms"]):
		Layout.set_status(status,"位置与其他地台相交，原位置已保留。",true)
		_refresh_panel()
		return
	item["offset_feet"] = at
	if draft.is_empty():
		preview.move_platform(selected,at)
		_mark_unsaved()
		_refresh_list()
	_refresh_panel()

func _refresh_list() -> void:
	for child in list_rows.get_children():
		list_rows.remove_child(child)
		child.queue_free()
	var query := list_search.text.strip_edges().to_lower()
	for item: Dictionary in values["platforms"]:
		var title: String = item["data"]["title"]
		if not query.is_empty() and not title.to_lower().contains(query): continue
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation",8)
		list_rows.add_child(row)
		var pick := _button(title,func():
			active_tool = "map_select"
			tools.buttons["map_select"].button_pressed = true
			_select(item["id"])
		)
		pick.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		pick.tooltip_text = "%s · 顶面 %s 英尺" % [title,str(Data.bounds(item).end.y)]
		row.add_child(pick)
		var locate := _button("定位",func(): preview.focus_platform(item["id"]))
		locate.size_flags_horizontal = Control.SIZE_SHRINK_END
		row.add_child(locate)
	if list_rows.get_child_count()==0: list_rows.add_child(Style.text("尚未添加地台。" if query.is_empty() else "没有符合搜索的地台。",14,true))

func _choose_platform(entry: Dictionary) -> void:
	_cancel_operation()
	selected = ""
	source_record = entry
	draft = Data.import_platform(entry)
	active_tool = "add_platform"
	preview.highlight("")
	Layout.set_status(status,"")
	_refresh_panel()

func _start_move(id: String) -> void:
	_cancel_operation()
	_select(id)
	if _item(id).is_empty(): return
	moving = id
	palette.close()
	actions.hide()
	move_gizmo.configure_platform(Data.bounds(_item(id)).get_center(),_item(id)["offset_feet"])
	move_gizmo.set_mode("position")
	Layout.set_status(status,"")
	_refresh_panel()

func _cancel_operation() -> void:
	if is_instance_valid(weather_panel): weather_panel.cancel_interaction()
	if is_instance_valid(weather_panel): weather_panel.hide_popups()
	if is_instance_valid(move_gizmo): move_gizmo.set_mode("")
	moving = ""
	draft.clear()
	source_record.clear()
	candidate_valid = false
	if is_instance_valid(preview): preview.hide_ghost()
	if is_instance_valid(selection): _refresh_panel()

func _gizmo_changed(_mode: String, coordinates: Array) -> void:
	var item := _item(moving)
	if item.is_empty(): return
	candidate = Vector3(coordinates[0],coordinates[1],coordinates[2])
	candidate_valid = absf(candidate.x)<=1000000 and absf(candidate.y)<=1000000 and absf(candidate.z)<=1000000 and not Data.conflicts(item,candidate,values["platforms"])
	preview.show_ghost(item,candidate,not candidate_valid)
	move_gizmo.configure_platform(Data.bounds(item,candidate).get_center(),candidate)

func _finish_gizmo_drag() -> void:
	if move_gizmo.dragged < 0: return
	move_gizmo.end_drag()
	if candidate_valid:
		var item := _item(moving)
		item["offset_feet"] = candidate
		preview.move_platform(moving,candidate)
		_mark_unsaved()
		_refresh_list()
		Layout.set_status(status,"已移动地台")
	else:
		Layout.set_status(status,"位置相交或超出范围，原位置已保留。",true)
	preview.hide_ghost()
	move_gizmo.configure_platform(Data.bounds(_item(moving)).get_center(),_item(moving)["offset_feet"])
	_refresh_panel()

func _update_pointer(point: Vector2) -> void:
	var item := draft
	if item.is_empty(): return
	var at: Vector3 = item["offset_feet"]
	var hit: Variant = preview.plane_point(point,float(item["data"]["top_feet"])+at.y)
	if hit==null:
		candidate_valid = false
		preview.hide_ghost()
		return
	var local_center := Data.bounds(item,Vector3.ZERO).get_center()
	candidate = Vector3(snappedf(hit.x-local_center.x,5),at.y,snappedf(hit.z-local_center.z,5))
	candidate_valid = absf(candidate.x)<=1000000 and absf(candidate.z)<=1000000 and not Data.conflicts(item,candidate,values["platforms"])
	preview.show_ghost(item,candidate,not candidate_valid)

func _commit_pointer() -> void:
	if draft.is_empty(): return
	if not candidate_valid:
		Layout.set_status(status,"此位置与其他地台相交，无法放置。",true)
		return
	if not draft.is_empty():
		if values["platforms"].size()>=256:
			Layout.set_status(status,"地图最多包含256块地台。",true)
			return
		draft["offset_feet"] = candidate
		values["platforms"].append(draft)
		preview.add_platform(draft)
		var y := candidate.y
		draft = Data.import_platform(source_record)
		draft["offset_feet"].y = y
		Layout.set_status(status,"已添加地台")
	_mark_unsaved()
	_refresh_list()
	_refresh_panel()

func _delete_selected() -> void:
	var item := _item(selected)
	if item.is_empty(): return
	_cancel_operation()
	modal = Modal.new()
	page.add_overlay(modal)
	modal.configure("删除地图内地台？","移除“%s”及其中的物件，地台库原件不受影响。" % item["data"]["title"])
	modal.add_action("取消",modal.dismiss)
	modal.add_action("删除",func():
		values["platforms"].erase(item)
		preview.remove_platform(item["id"])
		selected = ""
		candidates.clear()
		modal.dismiss()
		_mark_unsaved()
		_refresh_list()
		_refresh_panel()
	,false,true,true)

func _present_actions() -> void:
	if active_tool.begins_with("weather_"):
		actions.hide()
		return
	if not draft.is_empty() or not moving.is_empty() or palette.visible or _blocked():
		actions.hide()
		return
	var entries: Array[Dictionary] = []
	var ids: Array[String] = candidates.duplicate()
	if ids.is_empty() and not selected.is_empty(): ids.append(selected)
	for id in ids:
		var item := _item(id)
		if item.is_empty(): continue
		entries.append({"id":id,"kind":"platform","label":"地台 · "+str(item["data"]["title"]),"actions":[["select","选择"]] if not candidates.is_empty() else [["move","移动"],["delete","删除"],["edit","编辑"]]})
	if entries.is_empty():
		actions.hide()
		return
	var box := Data.bounds(_item(entries[0]["id"]))
	var center := box.get_center()/5.0
	center.y = box.end.y/5.0
	if preview.camera.is_position_behind(center):
		actions.hide()
		return
	actions.present(entries,preview.camera.unproject_position(center),size,_panel_edge()+panel.size.x+12)

func _build_common_bar() -> void:
	common_bar = PanelContainer.new()
	common_bar.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	add_child(common_bar)
	var body := HBoxContainer.new()
	body.add_theme_constant_override("separation",8)
	common_bar.add_child(body)
	body.add_child(_button("显示设置",_toggle_display_panel))

func _toggle_display_panel() -> void:
	_cancel_operation()
	_release_camera()
	if is_instance_valid(display_panel):
		display_panel.visible = not display_panel.visible
		if display_panel.visible: Style.Motion.fade_in(display_panel)
		return
	display_panel = UtilityPopup.new()
	add_child(display_panel)
	var body: VBoxContainer = display_panel.body
	DisplaySettings.populate(body,preview,true,normal_speed,fast_speed,func(accelerated: bool,value: float):
		if accelerated: fast_speed = value
		else: normal_speed = value
	,_queue_fit)
	_queue_fit()
	display_panel.reveal_at(size,common_bar.position)

func _mark_unsaved() -> void:
	content_changed.emit()
	_refresh_save_state()

func _refresh_save_state() -> void:
	if not is_instance_valid(save_state): return
	save_state.text = str(save_state_provider.call()) if save_state_provider.is_valid() else ("已保存" if not saved_signature.is_empty() and Store.signature(values)==saved_signature else "未保存")
	if is_instance_valid(platform_editor): platform_editor.save_state.text = save_state.text

func _save() -> bool:
	if saving: return false
	if is_instance_valid(platform_editor) and is_instance_valid(platform_editor.token_tool.full_editor): return false
	var focused := get_viewport().gui_get_focus_owner()
	if focused!=null: focused.release_focus()
	if is_instance_valid(platform_editor):
		platform_editor._pause_tools()
		platform_editor._reset_expansion()
		platform_editor._release_camera()
		_sync_local_platform()
	_cancel_operation()
	palette.close()
	_release_camera()
	values["title"] = name_input.text
	if values["title"].strip_edges().is_empty():
		save_state.text = "保存失败"
		_message("保存失败","地图名称不能为空。")
		return false
	saving = true
	save_button.disabled = true
	actions.hide()
	preview.highlight("")
	var marker_states: Array = []
	if is_instance_valid(platform_editor):
		marker_states = preview.hide_edit_markers()
		# Marker visibility must remain fixed until the thumbnail is captured.
		preview.set_process(false)
	var blocker := Control.new()
	page.add_overlay(blocker)
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var image: Image = preview.viewport.get_texture().get_image()
	if is_instance_valid(platform_editor):
		preview.restore_edit_markers(marker_states)
		preview.set_process(true)
	var result: Dictionary
	if save_delegate.is_valid():
		var succeeded: bool = save_delegate.call(values,image)
		result = {"ok":succeeded,"id":edit_id,"message":"冒险保存失败，修改已保留。"}
	else:
		result = Store.save(values,edit_id,image)
	blocker.queue_free()
	saving = false
	save_button.disabled = false
	if not result["ok"]:
		save_state.text = "保存失败"
		if is_instance_valid(platform_editor): platform_editor.save_state.text = "保存失败"
		if not save_delegate.is_valid(): _message("保存失败",result["message"])
		if not is_instance_valid(platform_editor): preview.highlight(selected)
		return false
	edit_id = result["id"]
	saved_signature = Store.signature(values)
	_mark_unsaved()
	if not is_instance_valid(platform_editor): preview.highlight(selected)
	Layout.set_status(status,"已保存到冒险库。" if save_delegate.is_valid() else "已保存到地图库。")
	return true

func _message(title: String, message: String) -> void:
	modal = Modal.new()
	page.add_overlay(modal)
	modal.configure(title,message)
	modal.add_action("继续编辑",modal.dismiss)

func has_unsaved_changes() -> bool:
	if is_instance_valid(platform_editor):
		if is_instance_valid(platform_editor.token_tool.full_editor) and platform_editor.token_tool.full_editor.editor.has_unsaved_changes(): return true
		_sync_local_platform()
	if edit_id.is_empty() and values["platforms"].is_empty() and values["title"] == "地图": return false
	return saved_signature.is_empty() or Store.signature(values) != saved_signature

func guard_leave(action: Callable) -> bool:
	if saving: return true
	if is_instance_valid(platform_editor):
		if is_instance_valid(platform_editor.token_tool.full_editor): return true
		platform_editor._pause_tools()
		platform_editor._release_camera()
		_sync_local_platform()
	if accepted_leave: return false
	_cancel_operation()
	palette.close()
	_release_camera()
	if not saved_signature.is_empty() and Store.signature(values)==saved_signature: return false
	if edit_id.is_empty() and values["platforms"].is_empty() and values["title"]=="地图": return false
	if is_instance_valid(modal) and modal.visible: return true
	modal = Modal.new()
	page.add_overlay(modal)
	modal.configure("有未保存的修改","返回前是否保存地图？已保存的内容会保留。")
	modal.add_action("继续编辑",modal.dismiss)
	modal.add_action("保存并返回",func():
		modal.dismiss()
		if await _save():
			accepted_leave = true
			action.call()
	,true)
	modal.add_action("放弃修改并返回",func():
		accepted_leave = true
		modal.dismiss()
		action.call()
	,false,true,true)
	return true

func _panel_edge() -> float:
	return Mobile.safe_rect(size).position.x+24+maxf(152,tools.toolbar_width())+12

func _queue_fit() -> void:
	if fit_pending: return
	fit_pending = true
	_fit.call_deferred()

func _fit() -> void:
	fit_pending = false
	if not is_instance_valid(common_bar): return
	common_bar.size = common_bar.get_combined_minimum_size()
	common_bar.position = Vector2(Mobile.safe_rect(size).position.x+24,maxf(24,Mobile.safe_rect(size).end.y-common_bar.size.y-24))
	tools.position = Mobile.safe_rect(size).position+Vector2(24,24)
	tools.fit(common_bar.position.y-36)
	panel.custom_minimum_size.x = minf(340,maxf(180,size.x-_panel_edge()-24))
	panel_scroll.custom_minimum_size.y = minf(panel_body.get_combined_minimum_size().y,maxf(44,Mobile.safe_rect(size).size.y-150))
	panel.size = Vector2(panel.custom_minimum_size.x,0)
	if panel_tween==null or not panel_tween.is_valid(): panel.position = Vector2(_panel_edge() if expanded else -panel.size.x-16,Mobile.safe_rect(size).position.y+24)
	handle.position = Vector2(_panel_edge()+16,Mobile.safe_rect(size).position.y+40)
	handle.icon = preload("res://ui/icons/chevron_left.svg") if expanded else preload("res://ui/icons/chevron_right.svg")
	if is_instance_valid(display_panel): display_panel.fit_at(size,common_bar.position)

func _toggle_panel() -> void:
	if panel_tween!=null and panel_tween.is_valid(): panel_tween.kill()
	expanded = not expanded
	if expanded: panel.show()
	Layout.enabled(panel,expanded)
	panel_tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	panel_tween.tween_property(panel,"position:x",_panel_edge() if expanded else -panel.size.x-16,Style.Motion.duration(0.16))
	panel_tween.finished.connect(func(): panel.visible = expanded; _queue_fit())
	_queue_fit()

func _blocked() -> bool:
	return saving or (external_blocked.is_valid() and external_blocked.call()) or not DisplayServer.window_is_focused() or weather_panel.blocked() or menu.is_open() or (is_instance_valid(modal) and modal.visible)

func _over_ui(point: Vector2) -> bool:
	for node in [tools,panel,handle,common_bar,menu,palette,actions,display_panel]:
		if is_instance_valid(node) and node.visible and node.get_global_rect().has_point(point): return true
	return false

func _save_shortcut(event: InputEvent) -> bool:
	if not (event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed and event.keycode==KEY_S): return false
	get_viewport().set_input_as_handled()
	if saving or (external_blocked.is_valid() and external_blocked.call()) or weather_panel.blocked() or not DisplayServer.window_is_focused() or is_instance_valid(menu.auxiliary) or (is_instance_valid(modal) and modal.visible): return true
	_save()
	return true

func _input(event: InputEvent) -> void:
	if is_instance_valid(mobile_touch) and mobile_touch.handle(event): return
	if is_instance_valid(platform_editor): return
	if _save_shortcut(event): return
	if is_instance_valid(menu) and _blocked():
		if not moving.is_empty() or not draft.is_empty(): _cancel_operation()
		return

	if is_instance_valid(move_gizmo) and move_gizmo.dragged >= 0:
		if event is InputEventMouseMotion:
			move_gizmo.drag(event.position-preview.get_global_rect().position)
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed:
			_finish_gizmo_drag()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT and not event.pressed and rotating:
		_release_camera()
		get_viewport().set_input_as_handled()
		return
	if _blocked(): return
	if event is InputEventMouseButton and event.pressed:
		if event.button_index==MOUSE_BUTTON_RIGHT and (not moving.is_empty() or not draft.is_empty()):
			_cancel_operation()
			Layout.set_status(status,"已取消当前操作。")
			get_viewport().set_input_as_handled()
			return
		if _over_ui(event.position): return
		if event.button_index==MOUSE_BUTTON_LEFT:
			if active_tool.begins_with("weather_"): return
			if not moving.is_empty():
				candidate = _item(moving)["offset_feet"]
				candidate_valid = true
				if move_gizmo.begin_drag(event.position-preview.get_global_rect().position): _refresh_panel()
			elif not draft.is_empty():
				_update_pointer(event.position)
				_commit_pointer()
			else:
				var ids: Array[String] = preview.picks(event.position)
				if ids.size()>1:
					selected = ""
					candidates = ids
					_refresh_panel()
				else: _select(ids[0] if ids.size()==1 else "")
			get_viewport().set_input_as_handled()
		elif event.button_index==MOUSE_BUTTON_RIGHT:
			var focused := get_viewport().gui_get_focus_owner()
			if focused!=null: focused.release_focus()
			rotating = true
			mouse_origin = event.position
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
	elif rotating and event is InputEventMouseMotion:
		preview.turn(event.relative)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(platform_editor): return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:
		if weather_panel.color_open():
			weather_panel.hide_popups()
			get_viewport().set_input_as_handled()
			return
		_release_camera()
		menu.handle_escape()
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if is_instance_valid(platform_editor): return
	if not is_instance_valid(menu): return
	if _blocked():
		_release_camera()
		if not moving.is_empty() or not draft.is_empty(): _cancel_operation()
		actions.hide()
		return
	_present_actions()
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit or focused is SpinBox: return
	if move_gizmo.dragged >= 0: return
	if not moving.is_empty():
		move_gizmo.configure_platform(Data.bounds(_item(moving)).get_center(),_item(moving)["offset_feet"])
	var point := get_global_mouse_position()
	if not rotating and (not get_global_rect().has_point(point) or _over_ui(point)):
		preview.hide_ghost()
		return
	if not rotating:
		if not moving.is_empty(): move_gizmo.hover(point-preview.get_global_rect().position)
		elif not draft.is_empty(): _update_pointer(point)
		elif not active_tool.begins_with("weather_"):
			var hits: Array[String] = preview.picks(point)
			hovered = hits[0] if not hits.is_empty() else selected
			if preview.selected_id!=hovered: preview.highlight(hovered)
	var direction := Vector3.ZERO
	var camera: Camera3D = preview.camera
	if Input.is_physical_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_ALT) or Input.is_physical_key_pressed(KEY_META): return
	if Input.is_physical_key_pressed(KEY_W): direction -= camera.basis.z
	if Input.is_physical_key_pressed(KEY_S): direction += camera.basis.z
	if Input.is_physical_key_pressed(KEY_A): direction -= camera.basis.x
	if Input.is_physical_key_pressed(KEY_D): direction += camera.basis.x
	if Input.is_physical_key_pressed(KEY_E): direction += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q): direction -= Vector3.UP
	preview.move_free(direction,fast_speed if Input.is_physical_key_pressed(KEY_SHIFT) else normal_speed,delta)

func _release_camera() -> void:
	if not rotating: return
	rotating = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if is_inside_tree() and DisplayServer.window_is_focused(): get_viewport().warp_mouse(mouse_origin)

func _notification(what: int) -> void:
	if what==NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_camera()
		if is_instance_valid(preview): _cancel_operation()

func _exit_tree() -> void:
	_release_camera()

func _edit_platform(id: String) -> void:
	if is_instance_valid(platform_editor) or _item(id).is_empty(): return
	_cancel_operation()
	_release_camera()
	palette.close()
	editing_platform = id
	camera_before_edit = preview.camera.transform
	target_before_edit = preview.target
	for node in [tools,panel,handle,common_bar,menu,actions,display_panel]:
		if is_instance_valid(node): node.hide()
	preview.begin_platform_edit(id)
	platform_editor = PlatformEditor.new()
	platform_editor.page = page
	platform_editor.embedded = true
	platform_editor.supplied_preview = preview
	platform_editor.values = _item(id)["data"].duplicate(true)
	platform_editor.geometry_check = _check_local_geometry
	platform_editor.save_delegate = _save
	platform_editor.container_save_title = container_save_title
	platform_editor.container_return_title = "返回地图组合"
	platform_editor.container_return_action = _return_to_combination
	if save_delegate.is_valid():
		platform_editor.container_product_title = func(): return container_product_name.call() if container_product_name.is_valid() else name_input.text
	platform_editor.external_blocked = _blocked
	platform_editor.normal_speed = normal_speed
	platform_editor.fast_speed = fast_speed
	platform_editor.content_changed.connect(_sync_local_platform)
	platform_editor.return_requested.connect(_return_to_combination)
	add_child(platform_editor)
	_sync_local_platform()
	var start: Transform3D = preview.camera.transform
	preview.target = Data.bounds(_item(id),Vector3.ZERO).get_center()/5.0
	preview.distance = maxf(8,Data.bounds(_item(id)).size.length()/5.0*1.4)
	preview._position_camera()
	var destination: Transform3D = preview.camera.transform
	preview.camera.transform = start
	platform_editor.process_mode = Node.PROCESS_MODE_DISABLED
	camera_transition = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	camera_transition.tween_method(func(weight: float): preview.camera.transform = start.interpolate_with(destination,weight),0.0,1.0,Style.Motion.duration(0.3))
	camera_transition.finished.connect(func():
		if is_instance_valid(platform_editor): platform_editor.process_mode = Node.PROCESS_MODE_INHERIT
	)

func _check_local_geometry(data: Dictionary) -> Dictionary:
	var item := _item(editing_platform).duplicate()
	item["data"] = data
	if Data.conflicts(item,item["offset_feet"],values["platforms"]):
		return {"ok":false,"message":"扩展范围与其他地台相交，无法应用。"}
	return {"ok":true,"data":data}

func _sync_local_platform() -> void:
	if not is_instance_valid(platform_editor): return
	_item(editing_platform)["data"] = platform_editor.values
	_mark_unsaved()
	platform_editor.save_state.text = save_state.text
	platform_editor.set_meta("map_title",name_input.text)

func _return_to_combination() -> void:
	if saving: return
	if not is_instance_valid(platform_editor): return
	if is_instance_valid(platform_editor.token_tool.full_editor): return
	if camera_transition!=null and camera_transition.is_valid(): camera_transition.kill()
	platform_editor._pause_tools()
	platform_editor._release_camera()
	normal_speed = platform_editor.normal_speed
	fast_speed = platform_editor.fast_speed
	_sync_local_platform()
	if is_instance_valid(platform_editor.token_tool.layer):
		preview.world.remove_child(platform_editor.token_tool.layer)
		platform_editor.token_tool.layer.queue_free()
	platform_editor.process_mode = Node.PROCESS_MODE_DISABLED
	platform_editor.hide()
	platform_editor.queue_free()
	platform_editor = null
	preview.finish_platform_edit()
	preview.set_permissions(preview.landing_highlight)
	var item := _item(editing_platform)
	preview.remove_platform(editing_platform)
	preview.add_platform(item)
	editing_platform = ""
	preview.camera.transform = camera_before_edit
	preview.target = target_before_edit
	preview.free_yaw = preview.camera.rotation.y
	preview.free_pitch = preview.camera.rotation.x
	for window in [display_panel]:
		if is_instance_valid(window):
			remove_child(window)
			window.queue_free()
	display_panel = null
	for node in [tools,handle,common_bar,menu]: node.show()
	panel.visible = expanded
	preview.highlight(selected)
	_refresh_list()
	_refresh_panel()
	_mark_unsaved()

func _mobile_attach() -> void:
	if Mobile.enabled: Mobile.changed.connect(_queue_fit)
	if Mobile.enabled: mobile_touch = preload("res://ui/components/mobile_scene_input.gd").attach(self)
