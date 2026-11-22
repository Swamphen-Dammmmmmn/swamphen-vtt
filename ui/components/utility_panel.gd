extends PanelContainer

signal panel_closed
signal user_close_requested
signal panel_action_requested(action: String)

@export var panel_title := "辅助面板"
@export var preferred_width := 360.0
@export var fluent := false
var layout_key := ""
var host_controls_close := false
const PanelPreferences = preload("res://scripts/floating_panel_preferences.gd")
const ActionButton = preload("res://ui/components/controls/fluent_button.gd")
var _preferred_position: Variant = null
var _action_grid: GridContainer
var _panel_actions: Dictionary = {}
var _position_notice: Label
const EditorLayout = preload("res://ui/components/editor_layout.gd")
const EditorStyle = preload("res://ui/components/page_style.gd")
const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
const Icons = preload("res://ui/theme/icons/library_icons.gd")
const Typography = preload("res://ui/theme/typography.gd")
const ButtonFocus = preload("res://ui/components/button_focus.gd")
var editor_mode := false
var editor_footer: VBoxContainer
var editor_status: Label
var editor_message := ""
var editor_error := false
var editor_modal: Control
var dragging := false
var drag_offset := Vector2.ZERO
var user_positioned := false
var _content_inset: MarginContainer
var _scroll_column: VBoxContainer
var _body_content: VBoxContainer
var _available_rect := Rect2()
var _has_available_rect := false
var _fit_pending := false

func _ready() -> void:
	if not layout_key.is_empty():
		_preferred_position = PanelPreferences.position_for(layout_key)
		user_positioned = _preferred_position != null
	if fluent:
		set_meta("style_owned", true)
		theme = FluentTheme.shared()
		var face := FluentTheme.face(T.SURFACE, T.STROKE, T.RADIUS, 1)
		face.set_content_margin_all(EditorLayout.PADDING)
		add_theme_stylebox_override("panel", face)
		$Shell.add_theme_constant_override("separation", EditorLayout.GAP)
		$Shell/Header.custom_minimum_size.y = 40
		EditorLayout.scroll($Shell/Body)
		_mount_fluent_inset()
		content().add_theme_constant_override("separation", EditorLayout.GAP)
		var title_lbl := $Shell/Header/Row/Title as Label
		title_lbl.add_theme_font_override("font", Typography.MEDIUM)
		title_lbl.add_theme_font_size_override("font_size", Typography.SECTION)
		title_lbl.add_theme_color_override("font_color", T.FOREGROUND)
		title_lbl.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		var close_btn := $Shell/Header/Row/Close as Button
		close_btn.theme_type_variation = &"FluentInputAction"
		close_btn.icon = Icons.texture("res://ui/theme/icons/close_tintable.svg")
		close_btn.expand_icon = true
		close_btn.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		close_btn.add_theme_constant_override("icon_max_width", 20)
		close_btn.custom_minimum_size = Vector2(40, 40)
		close_btn.focus_mode = Control.FOCUS_ALL
		close_btn.add_child(ButtonFocus.new())
	else:
		theme = GoUi.theme()
		add_theme_stylebox_override("panel", BoardUiStyle.card_face(BoardUiStyle.PANEL_PADDING))
		$Shell.add_theme_constant_override("separation", BoardUiStyle.CONTENT_GAP)
		$Shell/Header.custom_minimum_size.y = BoardUiStyle.CONTROL_HEIGHT
		content().add_theme_constant_override("separation", BoardUiStyle.CONTENT_GAP)
		_style_content.call_deferred()
		GoStyle.apply_icon($Shell/Header/Row/Close, GoIconSet.CLOSE, 16)
	$Shell/Header/Row/Title.text = panel_title
	$Shell/Header/Row/Close.pressed.connect(request_close)
	$Shell/Header.gui_input.connect(_header_input)
	$Shell/Header.mouse_default_cursor_shape = Control.CURSOR_MOVE
	gui_input.connect(_surface_input)
	get_parent().resized.connect(_queue_fit)
	if Mobile.enabled: Mobile.changed.connect(_queue_fit)
	content().minimum_size_changed.connect(_queue_fit)
	$Shell.minimum_size_changed.connect(_queue_fit)
	_queue_fit()

func _mount_fluent_inset() -> void:
	if _content_inset != null:
		return
	var body_scroll: ScrollContainer = $Shell/Body
	_body_content = $Shell/Body/Content
	_content_inset = MarginContainer.new()
	_content_inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for edge in ["left", "right", "top", "bottom"]:
		_content_inset.add_theme_constant_override("margin_" + edge, T.MODAL_BODY_DRAW_INSET)
	_scroll_column = EditorStyle.column(EditorLayout.GAP)
	_scroll_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.follow_focus = true
	body_scroll.remove_child(_body_content)
	body_scroll.add_child(_content_inset)
	_content_inset.add_child(_scroll_column)
	_scroll_column.add_child(_body_content)
	_scroll_column.minimum_size_changed.connect(_queue_fit)

func _style_content() -> void:
	if fluent:
		_queue_fit()
		return
	BoardUiStyle.style_controls(self, 44.0 if editor_mode else BoardUiStyle.CONTROL_HEIGHT)
	if editor_mode: _editor_buttons(self)
	_queue_fit()

func content() -> VBoxContainer:
	return _body_content if _body_content != null else $Shell/Body/Content

func set_panel_title(value: String) -> void:
	panel_title = value
	if is_node_ready():
		$Shell/Header/Row/Title.text = value

func ensure_control_visible(target: Control) -> void:
	if is_instance_valid(target):
		$Shell/Body.ensure_control_visible(target)

func open() -> void:
	show()
	bring_to_front()
	grab_focus()
	_queue_fit()

func close() -> void:
	_finish_position_drag()
	close_popups()
	dragging = false
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and (focused == self or is_ancestor_of(focused)):
		focused.release_focus()
	hide()
	panel_closed.emit()

func request_close() -> void:
	if host_controls_close:
		user_close_requested.emit()
	else:
		close()

func suspend_pointer_input() -> void:
	_finish_position_drag()
	close_popups()

# The shared footer owns its controls. Callers only supply action state.
func set_panel_actions(entries: Array[Dictionary]) -> void:
	if _action_grid == null:
		_action_grid = GridContainer.new()
		_action_grid.columns = 2
		_action_grid.add_theme_constant_override("h_separation", EditorLayout.GAP)
		_action_grid.add_theme_constant_override("v_separation", EditorLayout.GAP)
		editor_footer.add_child(_action_grid)
	var shown_ids: Array[String] = []
	for item in entries:
		var id := str(item["id"])
		shown_ids.append(id)
		if not _panel_actions.has(id):
			var created := ActionButton.new()
			created.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			created.pressed.connect(func(): panel_action_requested.emit(id))
			_action_grid.add_child(created)
			_panel_actions[id] = created
		var button: ActionButton = _panel_actions[id]
		button.text = str(item["title"])
		button.set_variant("FluentPrimary" if item.get("primary", false) else "FluentButton")
		button.disabled = not item.get("enabled", true)
		button.tooltip_text = str(item.get("hint", ""))
		button.visible = item.get("visible", true)
	for id in _panel_actions:
		if not shown_ids.has(id): _panel_actions[id].hide()

func close_popups() -> bool:
	return false

func owns_keyboard() -> bool:
	var focused := get_viewport().gui_get_focus_owner()
	return visible and focused != null and (focused == self or is_ancestor_of(focused))

func popup_visible() -> bool:
	return false

func bring_to_front() -> void:
	get_parent().move_child(self, get_parent().get_child_count() - 1)

func place_initial(at: Vector2) -> void:
	if not user_positioned:
		position = at
	_queue_fit()

# Host restriction in parent-local coordinates; screen/safe-area margins still apply.
# An unset restriction preserves the existing full-window layout for other hosts.
func set_available_rect(area: Rect2) -> void:
	if _has_available_rect and _available_rect.is_equal_approx(area):
		return
	_available_rect = area
	_has_available_rect = true
	_queue_fit()

func _layout_rect() -> Rect2:
	var parent_control := get_parent() as Control
	var safe := Mobile.local_safe_rect(parent_control) if Mobile.enabled else Rect2(Vector2.ZERO, parent_control.size)
	var start := safe.position + Vector2(16, 16)
	var end := safe.end - Vector2(16, 54)
	if _has_available_rect:
		start = start.max(_available_rect.position)
		end = end.min(_available_rect.end)
	return Rect2(start, (end - start).max(Vector2.ZERO))

func _queue_fit() -> void:
	if _fit_pending or not is_inside_tree():
		return
	_fit_pending = true
	fit_to_window.call_deferred()

func layout_snapshot() -> Dictionary:
	var area := _layout_rect()
	var panel_rect := Rect2(position, size)
	var scrollbar: VScrollBar = $Shell/Body.get_v_scroll_bar()
	return {
		"rect": [position.x, position.y, size.x, size.y],
		"available_rect": [area.position.x, area.position.y, area.size.x, area.size.y],
		"within_available": area.grow(0.5).encloses(panel_rect),
		"body_height": $Shell/Body.size.y,
		"content_height": content().get_combined_minimum_size().y,
		"footer_scrolls": editor_footer != null and editor_footer.get_parent() == _scroll_column,
		"scroll_range": maxf(0.0, scrollbar.max_value - scrollbar.page),
	}

func _layout_footer(available_height: float) -> void:
	if not fluent or _scroll_column == null:
		return
	var shell: VBoxContainer = $Shell
	var gap := shell.get_theme_constant("separation")
	var fixed_height := get_theme_stylebox("panel").get_minimum_size().y
	fixed_height += $Shell/Header.get_combined_minimum_size().y + gap
	for detail in [editor_footer, _position_notice]:
		if is_instance_valid(detail) and detail.visible:
			fixed_height += detail.get_combined_minimum_size().y + gap
	var natural_body := content().get_combined_minimum_size().y + 2 * T.MODAL_BODY_DRAW_INSET
	var compact := available_height - fixed_height < minf(natural_body, T.UTILITY_PANEL_MIN_BODY_HEIGHT)
	var destination: VBoxContainer = _scroll_column if compact else shell
	var focused := get_viewport().gui_get_focus_owner()
	var restore_focus := false
	for detail in [editor_footer, _position_notice]:
		if is_instance_valid(detail) and detail.get_parent() != destination:
			if focused != null and (focused == detail or detail.is_ancestor_of(focused)):
				restore_focus = true
			detail.reparent(destination, false)
	if restore_focus and focused.is_visible_in_tree():
		focused.grab_focus()

func fit_to_window() -> void:
	_fit_pending = false
	var available := _layout_rect().size.max(Vector2.ONE)
	_layout_footer(available.y)
	var shell: VBoxContainer = $Shell
	var padding := get_theme_stylebox("panel").get_minimum_size().y
	var chrome := padding
	var count := 0
	for child in shell.get_children():
		if child is Control and child.visible:
			count += 1
			if child != $Shell/Body: chrome += child.get_combined_minimum_size().y
	chrome += maxf(0, count - 1) * shell.get_theme_constant("separation")
	var body_height := (_content_inset.get_combined_minimum_size().y if _content_inset != null else content().get_combined_minimum_size().y)
	$Shell/Body.custom_minimum_size.y = minf(body_height, maxf(1, available.y - chrome))
	size = Vector2(minf(preferred_width, available.x), minf(chrome + body_height, available.y))
	if _preferred_position != null and not dragging:
		position = _layout_rect().position + (_layout_rect().size - size).max(Vector2.ZERO) * _preferred_position
	_clamp_position()

func _finish_position_drag() -> void:
	if not dragging: return
	dragging = false
	if layout_key.is_empty(): return
	var room := (_layout_rect().size - size).max(Vector2.ZERO)
	var ratio: Vector2 = _preferred_position if _preferred_position != null else Vector2.ZERO
	for axis in range(2):
		if room[axis] > 0: ratio[axis] = clampf((position[axis] - _layout_rect().position[axis]) / room[axis], 0, 1)
	_preferred_position = ratio
	var error := PanelPreferences.save_position(layout_key, ratio)
	if error != OK and _position_notice == null:
		_position_notice = Label.new()
		_position_notice.text = "位置本次已保留，未能保存到本机。"
		_position_notice.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_position_notice.add_theme_color_override("font_color", T.DANGER)
		_position_notice.add_theme_font_size_override("font_size", Typography.CAPTION)
		$Shell.add_child(_position_notice)
	if _position_notice != null: _position_notice.visible = error != OK

func _clamp_position() -> void:
	var area := _layout_rect()
	position = position.clamp(area.position, (area.end - size).max(area.position))

func _surface_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		bring_to_front()
		if not owns_keyboard():
			grab_focus()

func _header_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			bring_to_front()
			grab_focus()
			dragging = true
			drag_offset = get_global_mouse_position() - global_position
			user_positioned = true
		$Shell/Header.accept_event()

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
		var hovered := get_viewport().gui_get_hovered_control()
		if hovered != null and (hovered == self or is_ancestor_of(hovered)):
			bring_to_front()
			if not owns_keyboard():
				grab_focus()
	if dragging:
		if event is InputEventMouseMotion:
			global_position = get_global_mouse_position() - drag_offset
			_clamp_position()
			get_viewport().set_input_as_handled()
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
			_finish_position_drag()
			get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE and owns_keyboard() and not is_instance_valid(editor_modal):
		if popup_visible():
			close_popups()
			get_viewport().set_input_as_handled()
		else:
			request_close()
			get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_finish_position_drag()

func configure_editor() -> void:
	editor_mode = true
	if fluent:
		var face := FluentTheme.face(T.SURFACE, T.STROKE, T.RADIUS, 1)
		face.set_content_margin_all(EditorLayout.PADDING)
		add_theme_stylebox_override("panel", face)
		$Shell/Header.custom_minimum_size.y = 44
		$Shell/Header/Row/Close.custom_minimum_size = Vector2(44, 44)
	else:
		add_theme_stylebox_override("panel", BoardUiStyle.card_face(EditorLayout.PADDING))
		$Shell.add_theme_constant_override("separation", EditorLayout.GAP)
		$Shell/Header.custom_minimum_size.y = 44
		$Shell/Header/Row/Close.custom_minimum_size = Vector2(44, 44)
		content().add_theme_constant_override("separation", EditorLayout.GAP)
		EditorLayout.scroll($Shell/Body)
	editor_footer = EditorStyle.column(EditorLayout.ROW_GAP)
	$Shell.add_child(editor_footer)
	editor_status = EditorLayout.status()
	if fluent:
		editor_status.add_theme_color_override("font_color", T.SECONDARY)
	editor_footer.add_child(editor_status)
	editor_status.gui_input.connect(func(event: InputEvent):
		if editor_error and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_show_editor_error()
	)
	editor_footer.minimum_size_changed.connect(_queue_fit)

func set_editor_status(message: String, error := false) -> void:
	editor_message = message
	editor_error = error
	EditorLayout.set_status(editor_status, message, error)
	if fluent and editor_status != null:
		editor_status.add_theme_color_override("font_color", T.DANGER if error else T.SECONDARY)

func _show_editor_error() -> void:
	if is_instance_valid(editor_modal): return
	editor_modal = preload("res://ui/components/page_modal.gd").new()
	get_parent().add_child(editor_modal)
	editor_modal.configure("检查输入", editor_message)
	editor_modal.add_action("继续编辑", editor_modal.dismiss)
	editor_modal.dismissed.connect(func(): editor_modal = null)

func _editor_buttons(root: Node) -> void:
	if root.get_meta("style_owned", false): return
	if root is Button and not root is OptionButton and not root is CheckButton and not root is CheckBox:
		var face := root.get_theme_stylebox("normal") as StyleBoxFlat
		var primary := face != null and face.bg_color.a > 0.5 and face.bg_color.r < 0.45 and face.bg_color.b > 0.4
		if not primary: EditorStyle.card_button(root)
	for child in root.get_children(): _editor_buttons(child)

func _exit_tree() -> void:
	if is_instance_valid(editor_modal): editor_modal.queue_free()
