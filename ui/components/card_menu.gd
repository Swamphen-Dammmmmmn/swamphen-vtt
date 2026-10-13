extends CanvasLayer

const Style = preload("res://ui/components/page_style.gd")
signal action_requested(id: int)
var content: VBoxContainer
var panel: PanelContainer
var anchor: Control
var is_open := false

func _ready() -> void:
	var owner_layer: CanvasLayer = (get_parent() as CanvasItem).get_canvas_layer_node()
	layer = owner_layer.layer + 1 if owner_layer != null else 1
	add_to_group("token_card_menus")
	panel = Style.card()
	panel.theme = GoUi.theme()
	panel.add_theme_stylebox_override("panel", BoardUiStyle.card_face(12))
	add_child(panel)
	content = Style.column(4)
	panel.add_child(content)
	get_viewport().size_changed.connect(close)
	hide()

func add_action(title: String, id: int, disabled := false, danger := false) -> void:
	var button := Button.new()
	button.text = title
	Style.button(button)
	BoardUiStyle.action_button(button, Style.BUTTON_HEIGHT, false, danger)
	button.disabled = disabled
	button.alignment = HORIZONTAL_ALIGNMENT_LEFT
	if disabled and title.contains("升级"): button.tooltip_text = "高级棋子定制尚未接入，当前不能升级。"
	button.pressed.connect(func():
		close()
		action_requested.emit(id)
	)
	content.add_child(button)

func toggle_for(button: Control) -> void:
	if is_open:
		close()
		return
	for menu in get_tree().get_nodes_in_group("token_card_menus"):
		if menu != self: menu.close()
	anchor = button
	var bounds := get_viewport().get_visible_rect()
	panel.custom_minimum_size.x = 200
	panel.reset_size()
	var dimensions := panel.get_combined_minimum_size()
	panel.size = dimensions
	var rect := button.get_global_rect()
	var at := Vector2(rect.end.x - dimensions.x, rect.end.y + 8)
	if at.y + dimensions.y > bounds.end.y - 8:
		at.y = rect.position.y - dimensions.y - 8
	at.x = clampf(at.x, bounds.position.x + 8, maxf(bounds.position.x + 8, bounds.end.x - dimensions.x - 8))
	at.y = clampf(at.y, bounds.position.y + 8, maxf(bounds.position.y + 8, bounds.end.y - dimensions.y - 8))
	panel.position = at.round()
	if not visible: panel.modulate.a = 0.0
	is_open = true
	_set_interaction(true)
	show()
	Style.Motion.fade_to(panel, 1.0)

func close() -> void:
	if not is_open: return
	is_open = false
	_set_interaction(false)
	Style.Motion.fade_to(panel, 0.0).finished.connect(func():
		if not is_open: hide()
	)
	if is_instance_valid(anchor) and anchor.is_visible_in_tree(): anchor.grab_focus()

func _set_interaction(enabled: bool) -> void:
	panel.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
	content.mouse_filter = Control.MOUSE_FILTER_PASS if enabled else Control.MOUSE_FILTER_IGNORE
	for button in content.get_children():
		button.mouse_filter = Control.MOUSE_FILTER_STOP if enabled else Control.MOUSE_FILTER_IGNORE
		button.focus_mode = Control.FOCUS_ALL if enabled else Control.FOCUS_NONE

func _input(event: InputEvent) -> void:
	if not is_open: return
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed:
		if panel.get_global_rect().has_point(event.position): return
		if is_instance_valid(anchor) and anchor.get_global_rect().has_point(event.position): return
		close()
