extends Control

const Style = preload("res://ui/components/page_style.gd")
signal dismissed
var content: VBoxContainer
var panel: PanelContainer
var scroll: ScrollContainer
var previous_focus: WeakRef
var dismiss_enabled := true

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	z_index = 30
	focus_mode = Control.FOCUS_ALL
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null: previous_focus = weakref(focused)
	var shade := ColorRect.new()
	shade.color = Color(0, 0, 0, 0.28)
	add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	shade.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			dismiss()
	)
	panel = Style.card()
	add_child(panel)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	content = Style.column(16)
	scroll.add_child(content)
	resized.connect(_fit)
	content.minimum_size_changed.connect(func(): _fit.call_deferred())
	grab_focus()
	Style.Motion.fade_in(panel)

func configure(title: String, description: String) -> void:
	content.add_child(Style.text(title, 24))
	content.add_child(Style.text(description, 16, true))
	_fit.call_deferred()

func add_action(title: String, action: Callable, primary := false, enabled := true, danger := false) -> Button:
	var button := Button.new()
	button.text = title
	Style.button(button, primary, Style.BUTTON_HEIGHT, danger)
	button.disabled = not enabled
	if action.is_valid(): button.pressed.connect(action)
	content.add_child(button)
	return button

func dismiss() -> void:
	if not dismiss_enabled: return
	hide()
	if previous_focus != null:
		var focused = previous_focus.get_ref()
		if is_instance_valid(focused) and focused.is_visible_in_tree(): focused.grab_focus()
	dismissed.emit()
	queue_free()

func _fit() -> void:
	panel.custom_minimum_size.x = minf(460, maxf(1, size.x - 32))
	scroll.custom_minimum_size.y = minf(content.get_combined_minimum_size().y, maxf(1, size.y - 72))
	panel.reset_size()
	panel.position = (size - panel.size) / 2

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		dismiss()
		get_viewport().set_input_as_handled()
