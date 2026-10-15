extends Control
var mobile_touch: Node
var mobile_previous_tool := ""
var mobile_tool_state: Dictionary = {}
const Style = preload("res://ui/components/page_style.gd")
const Layout = preload("res://ui/components/editor_layout.gd")
const DisplaySettings = preload("res://ui/components/designer_display_settings.gd")
const UtilityPopup = preload("res://ui/components/designer_utility_popup.gd")
const Store = preload("res://scripts/platform_library_store.gd")
const Parameters = preload("res://scripts/platform_parameters.gd")
const PaintTool = preload("res://ui/components/platform_paint_tool.gd")
const LandingTool = preload("res://ui/components/platform_landing_tool.gd")
const Preview = preload("res://ui/components/platform_preview.gd")
const BuildMenu = preload("res://ui/components/build_menu.gd")
const Toolbar = preload("res://ui/components/build_toolbar.gd")
const TokenTool = preload("res://ui/components/platform_token_tool.gd")
var token_tool: VBoxContainer
const Modal = preload("res://ui/components/page_modal.gd")
signal return_requested
signal content_changed
var embedded := false
var supplied_preview: SubViewportContainer
var geometry_check: Callable
var save_delegate: Callable
var container_save_title := "保存到地图库"
var container_return_title := "返回地图库"
var container_return_action: Callable
var container_product_title: Callable
var external_blocked: Callable
var page: Control
var preview: SubViewportContainer
var panel: PanelContainer
var content: VBoxContainer
var scroll: ScrollContainer
var form: VBoxContainer
var heading: Label
var heading_spacer: Control
var shade: ColorRect
var name_input: LineEdit
var numbers: Dictionary = {}
var material_input: OptionButton
var create_button: Button
var create_actions: BoxContainer
var status: Label
var handle: Button
var menu: Control
var tools: PanelContainer
var category_notice: VBoxContainer
var category_text: Label
var property_form: VBoxContainer
var landing_tool: VBoxContainer
var paint_tool: VBoxContainer
var expansion_form: VBoxContainer
var expansion_actions: BoxContainer
var expansion_inputs: Dictionary = {}
var expansion_values: Dictionary = {}
var apply_button: Button
var expansion_result: Label
var expansion_dragging := false
var expansion_drag_key := ""
var expansion_drag_start := 0.0
var active_tool := "select"
var values := Parameters.defaults()
var created := false
var expanded := true
var rotating := false
var mouse_origin := Vector2.ZERO
var normal_speed := 20.0
var fast_speed := 80.0
var display_panel: PanelContainer
var common_bar: PanelContainer
var common_buttons: Array[Button] = []
var tween: Tween
var fit_pending := false
var leave_modal: Control
var accepted_leave := false
var edit_id := ""
var saved_signature := ""
var save_button: Button
var save_state: Label
var saving := false
var save_error: Control

func _ready() -> void:
	_mobile_attach.call_deferred()
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview = supplied_preview if embedded else Preview.new()
	if not embedded:
		add_child(preview)
		preview.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade = ColorRect.new()
	shade.color = Color(0,0,0,0.28)
	shade.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	panel = Style.card()
	panel.add_theme_stylebox_override("panel",BoardUiStyle.card_face(16))
	add_child(panel)
	content = Style.column(12)
	panel.add_child(content)
	var header := HBoxContainer.new()
	content.add_child(header)
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(44,44)
	header.add_child(spacer)
	heading_spacer = spacer
	spacer.hide()
	heading = Style.text("创建地台",20)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(heading)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.add_child(scroll)
	Layout.scroll(scroll)
	form = Style.column(12)
	scroll.add_child(form)
	property_form = Style.column(12)
	form.add_child(property_form)
	name_input = LineEdit.new()
	name_input.text = values["title"]
	name_input.max_length = 60
	name_input.custom_minimum_size.y = 44
	Layout.field(property_form,"名称").add_child(name_input)
	name_input.text_changed.connect(func(text: String):
		values["title"] = text
		_mark_unsaved()
	)
	var dimensions := Layout.pair(property_form)
	_number(dimensions,"长 · 英尺","length_feet",5,1000,5)
	_number(dimensions,"宽 · 英尺","width_feet",5,1000,5)
	_number(property_form,"基础厚度 · 英尺","thickness_feet",1,50,1)
	material_input = OptionButton.new()
	material_input.custom_minimum_size.y = 44
	for title in Parameters.TITLES: material_input.add_item(title)
	material_input.select(Parameters.MATERIALS.find(values["material"]))
	Layout.field(property_form,"默认地面").add_child(material_input)
	material_input.item_selected.connect(func(index: int):
		values["material"] = Parameters.MATERIALS[index]
		_mark_unsaved()
		_update_preview(false)
	)
	category_notice = Style.column(12)
	form.add_child(category_notice)
	category_text = Style.text("",16,true)
	category_notice.add_child(category_text)
	category_notice.hide()
	_build_expansion_form()
	landing_tool = LandingTool.new()
	landing_tool.editor = self
	landing_tool.page = page
	landing_tool.preview = preview
	form.add_child(landing_tool)
	landing_tool.hide()
	landing_tool.state_changed.connect(_queue_fit)
	landing_tool.cells_changed.connect(_mark_unsaved)
	paint_tool = PaintTool.new()
	paint_tool.editor = self
	paint_tool.preview = preview
	form.add_child(paint_tool)
	paint_tool.hide()
	paint_tool.state_changed.connect(_queue_fit)
	preview.paint.changed.connect(_sync_paint_data)
	status = Layout.status()
	content.add_child(status)
	expansion_actions = Layout.pair(content)
	expansion_actions.hide()
	var cancel := _button("取消扩展",false)
	cancel.pressed.connect(_reset_expansion)
	expansion_actions.add_child(cancel)
	apply_button = _button("应用扩展",true)
	apply_button.pressed.connect(_apply_expansion)
	expansion_actions.add_child(apply_button)
	paint_tool.status = status
	landing_tool.status = status
	landing_tool.attach(values)
	var footer := Layout.pair(content)
	create_actions = footer
	create_button = _button("创建地台",true)
	create_button.pressed.connect(_create)
	footer.add_child(create_button)
	token_tool = TokenTool.new()
	token_tool.editor = self
	form.add_child(token_tool)
	token_tool.hide()
	_build_common_bar()
	tools = Toolbar.new()
	add_child(tools)
	tools.tool_selected.connect(_select_tool)
	tools.category_changed.connect(func(key: String): _select_tool(key,false))
	tools.layout_changed.connect(_toolbar_layout_changed)
	handle = _button("",false)
	handle.custom_minimum_size = Vector2(44,44)
	handle.expand_icon = true
	handle.add_theme_constant_override("icon_max_width",20)
	handle.pressed.connect(_toggle)
	add_child(handle)
	menu = BuildMenu.new()
	menu.page = page
	menu.return_title = "返回地台库"
	menu.save_title = container_save_title if embedded else "保存到地台库"
	menu.product_title = func(): return container_product_title.call() if container_product_title.is_valid() else (str(get_meta("map_title","地图")) if embedded else name_input.text)
	add_child(menu)
	save_button = menu.save_button
	save_button.disabled = true
	save_state = menu.state_label
	common_buttons.append(save_button)
	menu.save_requested.connect(func(): await _save())
	if embedded:
		menu.return_title = container_return_title
		menu.return_requested.connect(func():
			if container_return_action.is_valid(): container_return_action.call()
			else: page.navigation_requested.emit("map_library","")
		)
	else: menu.return_requested.connect(func(): return_requested.emit())
	menu.menu_opened.connect(func():
		_pause_tools()
		_release_camera()
	)
	tools.hide()
	handle.hide()
	Style.Motion.fade_in(panel)
	form.minimum_size_changed.connect(_queue_fit)
	resized.connect(_window_resized)
	_update_preview(true)
	_queue_fit()
	if embedded:
		_create()
		var back := _button("返回地图组合",false)
		content.get_child(0).add_child(back)
		back.pressed.connect(func(): return_requested.emit())
		var target_label := Style.text("正在编辑："+str(values["title"]),14,true)
		target_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		target_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		content.add_child(target_label)
		content.move_child(target_label,1)
		name_input.text_changed.connect(func(text: String): target_label.text = "正在编辑："+text)
		save_state.text = "未保存"
	elif not edit_id.is_empty():
		set_meta("persisted_product_id",edit_id)
		_create()
		saved_signature = Store.signature(values)
		save_state.text = "已保存"

func _button(title: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = title
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Style.card_button(button)
	if primary: Style.button(button,true)
	return button

func _number(parent: Control,title: String,key: String,low: float,high: float,step: float) -> void:
	var group := Layout.field(parent,title)
	var input := SpinBox.new()
	input.min_value = low
	input.max_value = high
	input.step = step
	input.value = values[key]
	input.custom_minimum_size.y = 44
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	group.add_child(input)
	numbers[key] = input
	input.value_changed.connect(func(value: float):
		values[key] = value
		_update_preview(true)
	)

func _update_preview(fit_camera: bool) -> void:
	if created:
		preview.configure(values,fit_camera and not embedded)
		_sync_paint_data()
		landing_tool.attach(values)
		if is_instance_valid(token_tool): token_tool.refresh()
	Layout.set_status(status,"%d × %d 英尺 · %d × %d 格 · 厚 %d 英尺" % [values["length_feet"],values["width_feet"],int(values["length_feet"])/5,int(values["width_feet"])/5,values["thickness_feet"]])

func _create() -> void:
	# Commit pending SpinBox text before validating the draft.
	for input: SpinBox in numbers.values(): input.apply()
	var checked := Parameters.validate(values)
	if not checked["ok"]:
		Layout.set_status(status,checked["message"],true)
		return
	values = checked["data"]
	created = true
	_mark_unsaved()
	heading.text = "地台 · 属性"
	for input: SpinBox in numbers.values(): input.editable = false
	material_input.disabled = false
	create_actions.hide()
	for button in common_buttons: button.disabled = false
	heading_spacer.show()
	handle.show()
	tools.show()
	_update_preview(true)
	Layout.set_status(status,"地台已创建")
	var old_position := panel.position
	_fit()
	var destination := panel.position
	panel.position = old_position
	tween = create_tween().set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel,"position",destination,Style.Motion.duration(0.16))
	tween.finished.connect(_queue_fit)
	var shade_tween := Style.Motion.fade_to(shade,0.0)
	shade_tween.finished.connect(func(): shade.hide())

func has_unsaved_changes() -> bool:
	if is_instance_valid(token_tool) and is_instance_valid(token_tool.full_editor) and token_tool.full_editor.editor.has_unsaved_changes(): return true
	if not created and values == Parameters.defaults(): return false
	return not created or saved_signature.is_empty() or Store.signature(values) != saved_signature

func guard_leave(action: Callable) -> bool:
	if saving: return true
	if is_instance_valid(token_tool) and is_instance_valid(token_tool.full_editor): return true
	if accepted_leave: return false
	_pause_tools()
	if not created and values == Parameters.defaults(): return false
	if created and not saved_signature.is_empty() and Store.signature(values)==saved_signature: return false
	if is_instance_valid(leave_modal): return true
	_release_camera()
	var modal := Modal.new()
	leave_modal = modal
	page.add_overlay(modal)
	modal.configure("有未保存的修改","返回前是否保存？放弃只丢弃尚未保存的修改，已保存的地台会保留。")
	modal.add_action("继续编辑",modal.dismiss)
	if created:
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
	, false, true, true)
	return true

func _mark_unsaved() -> void:
	if is_instance_valid(save_state) and created: save_state.text = "未保存"
	if embedded and created: content_changed.emit()

func _save() -> bool:
	if not created or saving: return false
	values["title"] = name_input.text
	if embedded:
		_pause_tools()
		_reset_expansion()
		_release_camera()
		content_changed.emit()
		saving = true
		save_button.disabled = true
		var succeeded: bool = await save_delegate.call()
		saving = false
		save_button.disabled = false
		save_state.text = "已保存" if succeeded else "保存失败"
		return succeeded
	saving = true
	save_button.disabled = true
	_pause_tools()
	_release_camera()
	var focused := get_viewport().gui_get_focus_owner()
	if focused!=null: focused.release_focus()
	var blocker := ColorRect.new()
	blocker.color = Color(0,0,0,0)
	blocker.z_index = 100
	add_child(blocker)
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var snapshot := values.duplicate(true)
	# Capture after the viewport renders without draft markers or placement ghosts.
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var screenshot: Image = preview.viewport.get_texture().get_image()
	var target_id: String = get_meta("persisted_product_id",edit_id)
	var result := Store.save(snapshot,target_id,screenshot)
	blocker.queue_free()
	saving = false
	save_button.disabled = false
	if not result["ok"]:
		push_warning("地台保存失败："+str(result["message"]))
		save_state.text = "保存失败"
		var modal := Modal.new()
		save_error = modal
		page.add_overlay(modal)
		modal.configure("保存失败",result["message"])
		modal.add_action("继续编辑",modal.dismiss)
		return false
	edit_id = result["id"]
	set_meta("persisted_product_id",edit_id)
	print("地台保存：%s，编号 %s" % ["更新原件" if not target_id.is_empty() else "首次保存",edit_id])
	saved_signature = Store.signature(snapshot)
	save_state.text = "已保存" if Store.signature(values)==saved_signature else "未保存"
	return true

func _queue_fit() -> void:
	if fit_pending: return
	fit_pending = true
	_fit.call_deferred()

func _fit() -> void:
	fit_pending = false
	if tween != null and tween.is_running(): return
	_fit_common_bar()
	var width := minf(320.0 if Mobile.enabled else Style.CUSTOMIZE_PANEL_WIDTH,maxf(1,size.x-(_panel_edge()+24 if created else 112)))
	var limit := maxf(1,Mobile.safe_rect(size).size.y-48)
	var chrome := panel.get_theme_stylebox("panel").get_minimum_size().y
	var count := 0
	for child in content.get_children():
		if child is Control and child.visible:
			count += 1
			if child != scroll: chrome += child.get_combined_minimum_size().y
	chrome += maxi(0,count-1)*12
	var body := form.get_combined_minimum_size().y
	scroll.custom_minimum_size.y = minf(body,maxf(1,limit-chrome))
	panel.size = Vector2(width,minf(limit,chrome+body))
	if not created:
		panel.position = Mobile.safe_rect(size).position+(Mobile.safe_rect(size).size-panel.size)/2.0
		return
	tools.fit(maxf(1,common_bar.position.y-24-16))
	tools.position = Mobile.safe_rect(size).position+Vector2(24,24)
	var edge := _panel_edge()
	panel.position = Vector2(edge if expanded else -width,Mobile.safe_rect(size).position.y+24)
	handle.position = Vector2(edge+16 if expanded else edge-12,Mobile.safe_rect(size).position.y+40)
	handle.icon = preload("res://ui/icons/chevron_left.svg") if expanded else preload("res://ui/icons/chevron_right.svg")
	_fit_display_panel()


func _toggle() -> void:
	if not created: return
	_pause_tools()
	expanded = not expanded
	_release_camera()
	material_input.get_popup().hide()
	if tween != null and tween.is_valid(): tween.kill()
	panel.show()
	Layout.enabled(panel,expanded)
	handle.icon = preload("res://ui/icons/chevron_left.svg") if expanded else preload("res://ui/icons/chevron_right.svg")
	tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	var duration := Style.Motion.duration(0.16)
	tween.tween_property(panel,"position:x",_panel_edge() if expanded else -panel.size.x,duration)
	tween.tween_property(panel,"modulate:a",1.0 if expanded else 0.0,duration)
	tween.tween_property(handle,"position:x",_panel_edge()+16 if expanded else _panel_edge()-12,duration)
	tween.finished.connect(func():
		if not expanded: panel.hide()
		_queue_fit()
	)

func _over_ui(point: Vector2) -> bool:
	return menu.get_global_rect().has_point(point) or (expanded and panel.get_global_rect().has_point(point)) or handle.get_global_rect().has_point(point) or tools.get_global_rect().has_point(point) or (is_instance_valid(token_tool) and token_tool.over_ui(point)) or common_bar.get_global_rect().has_point(point) or (is_instance_valid(display_panel) and display_panel.visible and display_panel.get_global_rect().has_point(point))

func _camera_blocked() -> bool:
	if embedded and external_blocked.is_valid() and external_blocked.call(): return true
	return saving or (is_instance_valid(token_tool) and token_tool.blocked()) or not created or shade.visible or menu.is_open() or tools.is_popup_open() or material_input.get_popup().visible or (is_instance_valid(leave_modal) and leave_modal.visible) or (is_instance_valid(save_error) and save_error.visible) or landing_tool.blocked() or not DisplayServer.window_is_focused()

func _save_shortcut(event: InputEvent) -> bool:
	if not (event is InputEventKey and event.pressed and not event.echo and event.ctrl_pressed and event.keycode==KEY_S): return false
	if is_instance_valid(token_tool) and is_instance_valid(token_tool.full_editor): return false
	get_viewport().set_input_as_handled()
	if not created or saving or not DisplayServer.window_is_focused() or is_instance_valid(menu.auxiliary): return true
	if (is_instance_valid(leave_modal) and leave_modal.visible) or (is_instance_valid(save_error) and save_error.visible): return true
	if external_blocked.is_valid() and external_blocked.call(): return true
	_save()
	return true

func _input(event: InputEvent) -> void:
	if is_instance_valid(mobile_touch) and mobile_touch.handle(event): return
	if _save_shortcut(event): return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed and rotating:
		_release_camera()
		get_viewport().set_input_as_handled()
		return
	if _camera_blocked():
		_pause_tools()
		_release_camera()
		return
	if not rotating and token_tool.handle_pointer(event,_over_ui(get_global_mouse_position())):
		get_viewport().set_input_as_handled()
		return
	if not rotating and _handle_expansion(event,_over_ui(get_global_mouse_position())):
		get_viewport().set_input_as_handled()
		return
	if not rotating and paint_tool.handle_pointer(event,_over_ui(get_global_mouse_position())):
		get_viewport().set_input_as_handled()
		return
	if not rotating and landing_tool.handle_pointer(event,_over_ui(get_global_mouse_position())):
		get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		if landing_tool.dragging or expansion_dragging or paint_tool.dragging or token_tool.dragging:
			get_viewport().set_input_as_handled()
			return
		if not _over_ui(event.position) and get_global_rect().has_point(event.position):
			var focused := get_viewport().gui_get_focus_owner()
			if focused != null: focused.release_focus()
			mouse_origin = event.position
			rotating = true
			Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
			get_viewport().set_input_as_handled()
	elif rotating and event is InputEventMouseMotion:
		preview.turn(event.relative)
		get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if not is_instance_valid(menu) or _camera_blocked():
		_pause_tools()
		_release_camera()
		return
	if landing_tool.dragging or expansion_dragging or paint_tool.dragging or token_tool.dragging: return
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit or focused is SpinBox: return
	if not rotating:
		var point := get_global_mouse_position()
		if not get_global_rect().has_point(point) or _over_ui(point): return
	var camera: Camera3D = preview.camera
	if Input.is_physical_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_ALT) or Input.is_physical_key_pressed(KEY_META): return
	var direction := Vector3.ZERO
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
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_release_camera()
		_pause_tools()

func _exit_tree() -> void:
	_release_camera()

func _panel_edge() -> float:
	return Mobile.safe_rect(size).position.x+24.0+maxf(tools.toolbar_width(),152)+12.0

func _build_expansion_form() -> void:
	expansion_form = Style.column(12)
	form.add_child(expansion_form)
	expansion_form.hide()
	expansion_form.add_child(Style.text("水平追加 · 英尺",16))
	var x_pair := Layout.pair(expansion_form)
	_expansion_number(x_pair,"X− 方向","x_negative",5,995)
	_expansion_number(x_pair,"X+ 方向","x_positive",5,995)
	var z_pair := Layout.pair(expansion_form)
	_expansion_number(z_pair,"Z− 方向","z_negative",5,995)
	_expansion_number(z_pair,"Z+ 方向","z_positive",5,995)
	_expansion_number(expansion_form,"底部追加 · 英尺","bottom",1,49)
	expansion_result = Style.text("",14,true)
	expansion_form.add_child(expansion_result)

func _expansion_number(parent: Control,title: String,key: String,interval: float,maximum: float) -> void:
	var input := SpinBox.new()
	input.min_value = 0
	input.max_value = maximum
	input.step = interval
	input.custom_minimum_size.y = 44
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Layout.field(parent,title).add_child(input)
	expansion_inputs[key] = input
	expansion_values[key] = 0.0
	input.value_changed.connect(func(amount: float):
		expansion_values[key] = amount
		_refresh_expansion()
	)

func _select_tool(key: String, open_panel := true) -> void:
	if key == "mobile_camera":
		if active_tool == key:
			_select_tool(mobile_previous_tool)
			for field in mobile_tool_state.get("expansion",{}):
				expansion_values[field] = mobile_tool_state["expansion"][field]
				expansion_inputs[field].set_value_no_signal(expansion_values[field])
			if mobile_previous_tool=="expand": _refresh_expansion()
			if not mobile_tool_state.get("draft",{}).is_empty(): token_tool.begin(mobile_tool_state["draft"])
			elif not str(mobile_tool_state.get("moving","")).is_empty():
				token_tool.selected = mobile_tool_state["moving"]
				token_tool._move()
			else: token_tool.selected = str(mobile_tool_state.get("selected",""))
			mobile_tool_state.clear()
			if tools.buttons.has(mobile_previous_tool): tools.buttons[mobile_previous_tool].button_pressed = true
			return
		mobile_previous_tool = active_tool
		mobile_tool_state = {"draft":token_tool.draft.duplicate(true),"moving":token_tool.moving,"selected":token_tool.selected,"expansion":expansion_values.duplicate()}
		_pause_tools()
		paint_tool.set_active(false)
		landing_tool.set_active(false)
		token_tool.active = false
		token_tool.hide()
		preview.show_expansion({},false)
		active_tool = key
		if expanded: _toggle()
		return
	_pause_tools()
	if active_tool == key:
		if key in ["token_basic","token_advanced"]: token_tool.set_active(key)
		if open_panel and not expanded: _toggle()
		return
	_release_camera()
	material_input.get_popup().hide()
	_reset_expansion()
	active_tool = key
	property_form.visible = key == "select"
	expansion_form.visible = key == "expand"
	expansion_actions.visible = key == "expand"
	landing_tool.set_active(key=="landing")
	paint_tool.set_active(key=="paint")
	category_notice.visible = false
	token_tool.set_active(key)
	category_text.text = "物件用于管理棋子、景观、地板和墙壁。棋子摆放将在下一轮接入。"
	heading.text = {"landing":"地台 · 棋子摆放区域","expand":"地台 · 扩展","paint":"地台 · 地面绘制","select":"地台 · 属性","object_select":"物件 · 选择","token_basic":"物件 · 基础棋子","token_advanced":"物件 · 高级棋子"}[key]
	if key == "expand": _refresh_expansion()
	else:
		preview.show_expansion({},false)
		if key not in ["landing","paint"]: _update_size_status()
	if open_panel and not expanded: _toggle()
	Style.Motion.fade_in(form)
	_queue_fit()

func _update_size_status() -> void:
	Layout.set_status(status,"%d × %d 英尺 · 厚 %d 英尺" % [values["length_feet"],values["width_feet"],values["thickness_feet"]])

func _refresh_expansion() -> void:
	if not created or active_tool != "expand": return
	var checked := Parameters.expanded(values,expansion_values)
	if checked["ok"] and geometry_check.is_valid(): checked = geometry_check.call(checked["data"])
	var has_change := false
	for amount: float in expansion_values.values():
		if amount > 0: has_change = true
	apply_button.disabled = not checked["ok"] or not has_change
	if not checked["ok"]:
		preview.show_expansion(Parameters.expansion_preview(values,expansion_values),true,true)
		expansion_result.text = ""
		Layout.set_status(status,checked["message"],true)
	else:
		var result: Dictionary = checked["data"]
		expansion_result.text = "扩展后：长 %d · 宽 %d · 厚 %d 英尺" % [result["length_feet"],result["width_feet"],result["thickness_feet"]]
		preview.show_expansion(result,true)
		Layout.set_status(status,"蓝色范围为扩展预览，应用后生效" if has_change else "")
	_queue_fit()

func _reset_expansion() -> void:
	_pause_expansion()
	for key: String in expansion_inputs:
		expansion_inputs[key].set_value_no_signal(0)
		expansion_values[key] = 0.0
	_refresh_expansion()

func _apply_expansion() -> void:
	for input: SpinBox in expansion_inputs.values(): input.apply()
	var checked := Parameters.expanded(values,expansion_values)
	if checked["ok"] and geometry_check.is_valid(): checked = geometry_check.call(checked["data"])
	if not checked["ok"]:
		Layout.set_status(status,checked["message"],true)
		return
	if apply_button.disabled: return
	var horizontal_changed: bool = checked["data"]["width_feet"]!=values["width_feet"] or checked["data"]["length_feet"]!=values["length_feet"]
	values = checked["data"]
	for key: String in numbers: numbers[key].set_value_no_signal(values[key])
	preview.configure(values,false)
	landing_tool.attach(values)
	_reset_expansion()
	_sync_paint_data()
	_mark_unsaved()
	Layout.set_status(status,"扩展已应用 · 地面绘制记录已清空" if horizontal_changed else "扩展已应用")

func _pause_expansion() -> void:
	if not expansion_dragging: return
	expansion_dragging = false
	expansion_drag_key = ""
	preview.handles.end_drag()

func _pause_tools() -> void:
	if is_instance_valid(token_tool): token_tool.pause()
	_pause_expansion()
	if is_instance_valid(paint_tool): paint_tool.pause_gesture()
	if is_instance_valid(landing_tool): landing_tool.pause_gesture()

func _handle_expansion(event: InputEvent, over_ui: bool) -> bool:
	if active_tool!="expand": return false
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed and expansion_dragging:
		_pause_expansion()
		return true
	if event is InputEventMouseMotion and expansion_dragging:
		var interval := 1.0 if expansion_drag_key=="bottom" else 5.0
		var change: float = snappedf(preview.handles.axis_feet(preview.screen_point(event.position)),interval)
		var maximum: float
		if expansion_drag_key=="bottom": maximum = 50.0-float(values["thickness_feet"])
		else:
			var horizontal := expansion_drag_key.begins_with("x_")
			var opposite := ("x_" if horizontal else "z_")+("positive" if expansion_drag_key.ends_with("negative") else "negative")
			maximum = maxf(0,1000.0-float(values["width_feet" if horizontal else "length_feet"])-float(expansion_values[opposite]))
		var amount := clampf(expansion_drag_start+change,0,maximum)
		if not is_equal_approx(amount,float(expansion_values[expansion_drag_key])):
			expansion_values[expansion_drag_key] = amount
			expansion_inputs[expansion_drag_key].set_value_no_signal(amount)
			_refresh_expansion()
		return true
	if over_ui:
		preview.handles.hover_key = ""
		return false
	if event is InputEventMouseMotion: preview.hit_handles(event.position)
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		var key: String = preview.hit_handles(event.position)
		if key.is_empty(): return false
		expansion_drag_key = key
		expansion_drag_start = float(expansion_values[key])
		expansion_dragging = true
		preview.handles.begin_axis(key,preview.screen_point(event.position))
		return true
	return false

func _window_resized() -> void:
	_fit_display_panel.call_deferred()
	if created and size.x < 960 and tools.expanded: tools.set_expanded(false)
	_queue_fit()

func _toolbar_layout_changed() -> void:
	_pause_tools()
	_release_camera()
	if tween != null and tween.is_valid(): tween.kill()
	var old_position := panel.position
	var old_handle := handle.position
	_fit()
	var destination := panel.position
	var handle_destination := handle.position
	panel.position = old_position
	handle.position = old_handle
	panel.modulate.a = 1.0 if expanded else 0.0
	if not expanded: panel.hide()
	tween = create_tween().set_parallel(true).set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	tween.tween_property(panel,"position",destination,Style.Motion.duration(0.16))
	tween.tween_property(handle,"position",handle_destination,Style.Motion.duration(0.16))
	tween.finished.connect(_queue_fit)

func _unhandled_input(event: InputEvent) -> void:
	if saving: return
	if is_instance_valid(token_tool) and token_tool.blocked(): return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		menu.handle_escape()
		get_viewport().set_input_as_handled()

func _build_common_bar() -> void:
	common_bar = PanelContainer.new()
	common_bar.add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	add_child(common_bar)
	var column := HBoxContainer.new()
	column.add_theme_constant_override("separation",8)
	common_bar.add_child(column)
	for item in [["显示设置",_toggle_display_panel]]:
		var button := _button(item[0],false)
		button.disabled = true
		column.add_child(button)
		button.pressed.connect(item[1])
		common_buttons.append(button)
	common_bar.minimum_size_changed.connect(_queue_fit)

func _fit_common_bar() -> void:
	common_bar.size = common_bar.get_combined_minimum_size()
	common_bar.position = Vector2(Mobile.safe_rect(size).position.x+24,maxf(24,Mobile.safe_rect(size).end.y-common_bar.size.y-24))

func _toggle_display_panel() -> void:
	_pause_tools()
	_release_camera()
	if is_instance_valid(display_panel):
		display_panel.visible = not display_panel.visible
		if display_panel.visible: Style.Motion.fade_in(display_panel)
		return
	display_panel = UtilityPopup.new()
	add_child(display_panel)
	var column: VBoxContainer = display_panel.body
	DisplaySettings.populate(column,preview,embedded,normal_speed,fast_speed,func(accelerated: bool,value: float):
		if accelerated: fast_speed = value
		else: normal_speed = value
	,_fit_display_panel)
	_fit_display_panel.call_deferred()
	display_panel.reveal_at(size,common_bar.position)

func _fit_display_panel() -> void:
	if is_instance_valid(display_panel): display_panel.fit_at(size,common_bar.position)

func _sync_paint_data() -> void:
	_mark_unsaved()
	if not preview.paint.configured: return
	values["paint_overlay"] = preview.paint.coverage
	values["paint_origin_feet"] = preview.paint.origin_feet
	preview.values["paint_overlay"] = preview.paint.coverage
	preview.values["paint_origin_feet"] = preview.paint.origin_feet

func _mobile_attach() -> void:
	if Mobile.enabled: Mobile.changed.connect(_queue_fit)
	if Mobile.enabled: mobile_touch = preload("res://ui/components/mobile_scene_input.gd").attach(self)
