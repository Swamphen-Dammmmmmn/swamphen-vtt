extends PanelContainer

signal panel_closed

@export var panel_title := "辅助面板"
@export var preferred_width := 360.0
const EditorLayout = preload("res://ui/components/editor_layout.gd")
const EditorStyle = preload("res://ui/components/page_style.gd")
var editor_mode := false
var editor_footer: VBoxContainer
var editor_status: Label
var editor_message := ""
var editor_error := false
var editor_modal: Control
var dragging := false
var drag_offset := Vector2.ZERO
var user_positioned := false

func _ready() -> void:
	theme = GoUi.theme()
	add_theme_stylebox_override("panel", BoardUiStyle.card_face(BoardUiStyle.PANEL_PADDING))
	$Shell.add_theme_constant_override("separation", BoardUiStyle.CONTENT_GAP)
	$Shell/Header.custom_minimum_size.y = BoardUiStyle.CONTROL_HEIGHT
	content().add_theme_constant_override("separation", BoardUiStyle.CONTENT_GAP)
	_style_content.call_deferred()
	$Shell/Header/Row/Title.text = panel_title
	$Shell/Header/Row/Close.pressed.connect(close)
	GoStyle.apply_icon($Shell/Header/Row/Close, GoIconSet.CLOSE, 16)
	$Shell/Header.gui_input.connect(_header_input)
	$Shell/Header.mouse_default_cursor_shape = Control.CURSOR_MOVE
	gui_input.connect(_surface_input)
	get_parent().resized.connect(func(): fit_to_window.call_deferred())
	content().minimum_size_changed.connect(func(): fit_to_window.call_deferred())
	$Shell.minimum_size_changed.connect(func(): fit_to_window.call_deferred())
	fit_to_window.call_deferred()

func _style_content() -> void:
	BoardUiStyle.style_controls(self, 44.0 if editor_mode else BoardUiStyle.CONTROL_HEIGHT)
	if editor_mode: _editor_buttons(self)
	fit_to_window.call_deferred()

func content() -> VBoxContainer:
	return $Shell/Body/Content

func open() -> void:
	show()
	bring_to_front()
	grab_focus()
	fit_to_window.call_deferred()

func close() -> void:
	dragging = false
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and (focused == self or is_ancestor_of(focused)):
		focused.release_focus()
	hide()
	panel_closed.emit()

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
		fit_to_window.call_deferred()

func fit_to_window() -> void:
	var bounds: Vector2 = get_parent().size
	var available := Vector2(maxf(0.0, bounds.x - 32.0), maxf(0.0, bounds.y - 70.0))
	var shell: VBoxContainer = $Shell
	var padding := get_theme_stylebox("panel").get_minimum_size().y
	var chrome := padding
	var count := 0
	for child in shell.get_children():
		if child is Control and child.visible:
			count += 1
			if child != $Shell/Body: chrome += child.get_combined_minimum_size().y
	chrome += maxf(0, count - 1) * shell.get_theme_constant("separation")
	var body_height := content().get_combined_minimum_size().y
	$Shell/Body.custom_minimum_size.y = minf(body_height, maxf(1, available.y - chrome))
	size = Vector2(minf(preferred_width, available.x), minf(chrome + body_height, available.y))
	_clamp_position()

func _clamp_position() -> void:
	var bounds: Vector2 = get_parent().size
	position.x = clampf(position.x, 16.0, maxf(16.0, bounds.x - size.x - 16.0))
	position.y = clampf(position.y, 16.0, maxf(16.0, bounds.y - size.y - 54.0))

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
			dragging = false
			get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and owns_keyboard() and not popup_visible() and not is_instance_valid(editor_modal):
		close()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		dragging = false

func configure_editor() -> void:
	editor_mode = true
	add_theme_stylebox_override("panel", BoardUiStyle.card_face(EditorLayout.PADDING))
	$Shell.add_theme_constant_override("separation", EditorLayout.GAP)
	$Shell/Header.custom_minimum_size.y = 44
	$Shell/Header/Row/Close.custom_minimum_size = Vector2(44, 44)
	content().add_theme_constant_override("separation", EditorLayout.GAP)
	EditorLayout.scroll($Shell/Body)
	editor_footer = EditorStyle.column(EditorLayout.ROW_GAP)
	$Shell.add_child(editor_footer)
	editor_status = EditorLayout.status()
	editor_footer.add_child(editor_status)
	editor_status.gui_input.connect(func(event: InputEvent):
		if editor_error and event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			_show_editor_error()
	)
	editor_footer.minimum_size_changed.connect(func(): fit_to_window.call_deferred())

func set_editor_status(message: String, error := false) -> void:
	editor_message = message
	editor_error = error
	EditorLayout.set_status(editor_status, message, error)

func _show_editor_error() -> void:
	if is_instance_valid(editor_modal): return
	editor_modal = preload("res://ui/components/page_modal.gd").new()
	get_parent().add_child(editor_modal)
	editor_modal.configure("检查输入", editor_message)
	editor_modal.add_action("继续编辑", editor_modal.dismiss)
	editor_modal.dismissed.connect(func(): editor_modal = null)

func _editor_buttons(root: Node) -> void:
	if root is Button and not root is OptionButton and not root is CheckButton and not root is CheckBox:
		var face := root.get_theme_stylebox("normal") as StyleBoxFlat
		var primary := face != null and face.bg_color.a > 0.5 and face.bg_color.r < 0.45 and face.bg_color.b > 0.4
		if not primary: EditorStyle.card_button(root)
	for child in root.get_children(): _editor_buttons(child)

func _exit_tree() -> void:
	if is_instance_valid(editor_modal): editor_modal.queue_free()
