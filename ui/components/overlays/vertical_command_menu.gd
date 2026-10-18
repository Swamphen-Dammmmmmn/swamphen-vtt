extends Control

signal action_requested(id: String)
signal closed

# 挂载到 PageShell.add_overlay()；同主画布，不创建 Window/Viewport。
const Spec = preload("res://ui/theme/tokens/library_card_spec.gd")
const MenuTheme = preload("res://ui/theme/themes/vertical_command_menu_theme.gd")
const Icons = preload("res://ui/theme/icons/library_icons.gd")
var _anchor: Control
var _panel: PanelContainer
var _scroll: ScrollContainer
var _items: VBoxContainer
var _backdrop: Control
var _buttons: Array[Button] = []
var _connections: Array[Dictionary] = []
var _generation := 0
var _opened := false
var _anchor_rect := Rect2()
var _keyboard_mode := false
var _outside_mouse := false
var _outside_finger := -1

func _ready() -> void:
	add_to_group("vertical_command_menus")
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = MenuTheme.get_theme()
	_backdrop = Control.new()
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.gui_input.connect(_outside_input)
	_panel = PanelContainer.new()
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.gui_input.connect(_panel_input)
	add_child(_panel)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.follow_focus = true
	_scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_panel.add_child(_scroll)
	_items = VBoxContainer.new()
	_items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_items.add_theme_constant_override("separation", 0)
	_scroll.add_child(_items)
	hide()
	set_process(false)
	set_process_input(false)

func is_open() -> bool:
	return _opened

func open(anchor: Control, actions: Array[Dictionary], keyboard := false) -> void:
	if not is_inside_tree() or not is_instance_valid(anchor) or not anchor.is_visible_in_tree(): return
	if _opened: close(false)
	for other in get_tree().get_nodes_in_group("vertical_command_menus"):
		if other != self: other.close(false)
	_anchor = anchor
	_generation += 1
	_opened = true
	_keyboard_mode = keyboard
	_outside_mouse = false
	_outside_finger = -1
	_clear_items()
	_build_items(actions)
	_anchor_rect = _local_anchor_rect()
	_watch(_anchor.tree_exiting, _anchor_gone)
	_watch(_anchor.visibility_changed, _anchor_visibility)
	_watch(get_viewport().size_changed, _geometry_changed)
	_watch(get_window().focus_exited, _window_focus_lost)
	if Mobile.enabled: _watch(Mobile.changed, _geometry_changed)
	var ancestor := _anchor.get_parent()
	while ancestor != null:
		if ancestor is ScrollContainer:
			_watch(ancestor.get_v_scroll_bar().value_changed, _page_scrolled)
			_watch(ancestor.get_h_scroll_bar().value_changed, _page_scrolled)
		ancestor = ancestor.get_parent()
	_panel.hide()
	show()
	set_process(true)
	set_process_input(true)
	_finish_open(_generation)

func _finish_open(generation: int) -> void:
	await get_tree().process_frame
	if not _valid_session(generation): return
	_fit()
	if not _valid_session(generation): return
	_panel.show()
	# 鼠标打开也有可用的键盘目标，但只在键盘导航时画焦点框。
	_focus_step(1, true)

func _valid_session(generation: int) -> bool:
	return is_inside_tree() and not is_queued_for_deletion() and _opened and generation == _generation and is_instance_valid(_anchor) and not _anchor.is_queued_for_deletion() and _anchor.is_visible_in_tree()

func close(restore_focus := true) -> void:
	if not _opened: return
	_opened = false
	_generation += 1
	var previous := _anchor
	_anchor = null
	_disconnect()
	hide()
	set_process(false)
	set_process_input(false)
	_outside_mouse = false
	_outside_finger = -1
	if restore_focus and is_instance_valid(previous) and previous.is_visible_in_tree() and not previous.is_queued_for_deletion():
		previous.grab_focus()
	closed.emit()

func _exit_tree() -> void:
	close(false)
	_generation += 1
	_disconnect()

func _watch(source: Signal, callback: Callable) -> void:
	source.connect(callback)
	_connections.append({"source": source, "callback": callback})

func _disconnect() -> void:
	for connection in _connections:
		var source: Signal = connection.source
		if not source.is_null() and is_instance_valid(source.get_object()) and source.is_connected(connection.callback): source.disconnect(connection.callback)
	_connections.clear()

func _clear_items() -> void:
	_buttons.clear()
	for child in _items.get_children():
		_items.remove_child(child)
		child.queue_free()
	_panel.custom_minimum_size = Vector2.ZERO
	_scroll.custom_minimum_size = Vector2.ZERO
	_scroll.scroll_vertical = 0

func _build_items(actions: Array[Dictionary]) -> void:
	for action in actions:
		if action.get("separator_before", false):
			var separator := HSeparator.new()
			separator.mouse_filter = Control.MOUSE_FILTER_IGNORE
			_items.add_child(separator)
		var title := str(action.get("title", ""))
		if title.is_empty(): continue
		var button := Button.new()
		button.text = title
		button.tooltip_text = title
		button.clip_text = true
		button.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.focus_mode = Control.FOCUS_ALL
		button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		button.disabled = bool(action.get("disabled", false))
		button.custom_minimum_size.y = 48.0 if Mobile.enabled else float(Spec.data().menu.item_height)
		var icon_path := str(action.get("icon", ""))
		if icon_path.is_empty() and action.get("danger", false): icon_path = "res://ui/theme/icons/library/trash.svg"
		if not icon_path.is_empty():
			button.icon = Icons.texture(icon_path)
			button.expand_icon = true
		if action.get("danger", false):
			for state in ["normal", "hover", "pressed", "focus", "hover_pressed"]:
				button.add_theme_color_override("icon_" + state + "_color", Spec.color("danger"))
		button.pressed.connect(_activate.bind(str(action["id"]), _generation))
		button.gui_input.connect(_item_input)
		_buttons.append(button)
		_items.add_child(button)
	_set_keyboard_mode(_keyboard_mode)

func _set_keyboard_mode(enabled: bool) -> void:
	_keyboard_mode = enabled
	for button in _buttons:
		if enabled: button.remove_theme_stylebox_override("focus")
		else: button.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

func _local_anchor_rect() -> Rect2:
	return get_global_transform_with_canvas().affine_inverse() * (_anchor.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, _anchor.size))

func _fit() -> void:
	var viewport_bounds := get_viewport_rect()
	if Mobile.enabled: viewport_bounds = Mobile.safe_rect(viewport_bounds.size)
	var bounds: Rect2 = get_global_transform_with_canvas().affine_inverse() * viewport_bounds
	var margin := float(Spec.data().menu.safe_margin)
	var safe := bounds.grow(-minf(margin, minf(bounds.size.x, bounds.size.y) * 0.25))
	var face := _panel.get_theme_stylebox("panel")
	var padding := face.get_minimum_size()
	var natural_width := 0.0
	var natural_height := 0.0
	for child in _items.get_children():
		var minimum: Vector2 = child.get_combined_minimum_size()
		if child is Button:
			minimum.x += child.get_theme_font("font").get_string_size(child.text, HORIZONTAL_ALIGNMENT_LEFT, -1, child.get_theme_font_size("font_size")).x
			if child.icon != null:
				minimum.x += child.get_theme_constant("icon_max_width") + child.get_theme_constant("h_separation")
		natural_width = maxf(natural_width, minimum.x)
		natural_height += minimum.y
	var height := minf(natural_height, maxf(1, safe.size.y - padding.y))
	var bar_width := 0.0
	if height < natural_height: bar_width = _scroll.get_v_scroll_bar().get_combined_minimum_size().x
	var width := minf(natural_width + padding.x + bar_width, maxf(1, safe.size.x))
	_scroll.custom_minimum_size = Vector2(maxf(1, width - padding.x), height)
	_panel.custom_minimum_size = Vector2.ZERO
	_panel.size = Vector2(width, height + padding.y)
	_anchor_rect = _local_anchor_rect()
	var at := Vector2(_anchor_rect.end.x - _panel.size.x, _anchor_rect.end.y + 6)
	if at.y + _panel.size.y > safe.end.y: at.y = _anchor_rect.position.y - _panel.size.y - 6
	at.x = clampf(at.x, safe.position.x, maxf(safe.position.x, safe.end.x - _panel.size.x))
	at.y = clampf(at.y, safe.position.y, maxf(safe.position.y, safe.end.y - _panel.size.y))
	_panel.position = at

func _process(_delta: float) -> void:
	if not _valid_session(_generation):
		close(false)
		return
	if not _local_anchor_rect().is_equal_approx(_anchor_rect):
		close()
		return
	var focused := get_viewport().gui_get_focus_owner()
	# 后续模态框或其他控件接管焦点，不再截获它们的键盘事件。
	if focused != null and focused != _anchor and not _panel.is_ancestor_of(focused): close(false)

func _outside_input(event: InputEvent) -> void:
	# 遮罩消费完整按下/抬手；只在此处开始的点击关闭，打开菜单的抬手不算。
	_backdrop.accept_event()
	if event is InputEventMouseButton:
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			close()
		elif event.button_index in [MOUSE_BUTTON_LEFT, MOUSE_BUTTON_RIGHT]:
			if event.pressed: _outside_mouse = true
			elif _outside_mouse: close()
	elif event is InputEventScreenTouch:
		if event.pressed: _outside_finger = event.index
		elif event.index == _outside_finger:
			if not event.canceled: close()
			_outside_finger = -1

func _panel_input(event: InputEvent) -> void:
	# 面板空隙也消费输入；内部ScrollContainer由项目手机仲裁处理拖动。
	if event is InputEventMouseButton or event is InputEventScreenTouch: _panel.accept_event()

func _item_input(event: InputEvent) -> void:
	if event is InputEventMouseButton: _set_keyboard_mode(false)

func _input(event: InputEvent) -> void:
	if not _panel.visible or not event is InputEventKey or not event.pressed or event.echo: return
	if event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		close()
		return
	var direction := 0
	var edge := false
	match event.keycode:
		KEY_DOWN: direction = 1
		KEY_UP: direction = -1
		KEY_HOME: direction = 1; edge = true
		KEY_END: direction = -1; edge = true
		KEY_TAB: direction = -1 if event.shift_pressed else 1
	if direction != 0:
		_set_keyboard_mode(true)
		_focus_step(direction, edge)
		get_viewport().set_input_as_handled()
	elif event.is_action("ui_accept"):
		var focused := get_viewport().gui_get_focus_owner()
		if not _buttons.has(focused):
			_set_keyboard_mode(true)
			_focus_step(1, true)
			get_viewport().set_input_as_handled()

func _focus_step(direction: int, edge := false) -> void:
	if _buttons.is_empty(): return
	var index := _buttons.find(get_viewport().gui_get_focus_owner())
	if edge or index < 0: index = -1 if direction > 0 else _buttons.size()
	for offset in range(1, _buttons.size() + 1):
		var next := posmod(index + direction * offset, _buttons.size())
		if not _buttons[next].disabled:
			_buttons[next].grab_focus()
			_scroll.ensure_control_visible(_buttons[next])
			return

func _activate(id: String, generation: int) -> void:
	# 按钮只属于创建它的会话，旧按钮的迟到回调不能执行新菜单命令。
	if not _valid_session(generation) or not _panel.is_visible_in_tree(): return
	close()
	action_requested.emit(id)

func _anchor_gone() -> void:
	close(false)

func _anchor_visibility() -> void:
	if not is_instance_valid(_anchor) or not _anchor.is_visible_in_tree(): close(false)

func _geometry_changed() -> void:
	close()

func _window_focus_lost() -> void:
	close(false)

func _page_scrolled(_value: float) -> void:
	close()

# 只读诊断接口，供初始静态样板核对布局，不暴露内部节点。
func layout_snapshot() -> Dictionary:
	return {"open": _opened, "visible": _panel.is_visible_in_tree(), "panel": _panel.get_global_rect(), "items": _buttons.size(), "layer": get_canvas_layer_node().layer if get_canvas_layer_node() != null else 0}
