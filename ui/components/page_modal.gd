extends Control

const Typography = preload("res://ui/theme/typography.gd")

const Style = preload("res://ui/components/page_style.gd")
const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
const FluentButton = preload("res://ui/components/controls/fluent_button.gd")
signal dismissed
var content: VBoxContainer
var panel: PanelContainer
var scroll: ScrollContainer
var previous_focus: WeakRef
var dismiss_enabled := true
var document_variant := false
var _document_title: Label
var _document_actions: HBoxContainer
var _error_label: Label

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
	panel = PanelContainer.new() if document_variant else Style.card()
	add_child(panel)
	var body_parent: Control = panel
	if document_variant:
		theme = FluentTheme.shared()
		var face := FluentTheme.face(T.SURFACE, T.STROKE, T.RADIUS)
		for edge in ["left", "right", "top", "bottom"]:
			face.set("content_margin_" + edge, T.FORM_PADDING)
		panel.add_theme_stylebox_override("panel", face)
		var layout := VBoxContainer.new()
		layout.add_theme_constant_override("separation", T.GAP)
		panel.add_child(layout)
		_document_title = Label.new()
		_document_title.add_theme_font_override("font", Typography.MEDIUM)
		_document_title.add_theme_font_size_override("font_size", Typography.SECTION)
		_document_title.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		layout.add_child(_document_title)
		body_parent = layout
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	body_parent.add_child(scroll)
	content = Style.column(16)
	scroll.add_child(content)
	if document_variant:
		_document_actions = HBoxContainer.new()
		_document_actions.alignment = BoxContainer.ALIGNMENT_END
		body_parent.add_child(_document_actions)
	resized.connect(_fit)
	if Mobile.enabled: Mobile.changed.connect(_fit)
	content.minimum_size_changed.connect(func(): _fit.call_deferred())
	grab_focus()
	Style.Motion.fade_in(panel)

func configure(title: String, description: String) -> void:
	if document_variant:
		_document_title.text = title
		var body := Label.new()
		body.text = description
		body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		body.add_theme_font_size_override("font_size", Typography.BODY)
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_child(body)
	else:
		content.add_child(Style.text(title, Typography.DIALOG_TITLE))
		content.add_child(Style.text(description, Typography.BODY, true))
	_fit.call_deferred()

func add_action(title: String, action: Callable, primary := false, enabled := true, danger := false) -> Button:
	var button: Button = FluentButton.new() if document_variant else Button.new()
	button.text = title
	if document_variant:
		button.variant = "FluentDanger" if danger else ("FluentPrimary" if primary else "FluentButton")
		button.custom_minimum_size.x = T.DOCUMENT_ACTION_WIDTH
	else:
		Style.button(button, primary, Style.BUTTON_HEIGHT, danger)
	button.disabled = not enabled
	if action.is_valid(): button.pressed.connect(action)
	if document_variant: _document_actions.add_child(button)
	else: content.add_child(button)
	return button

func set_error(message: String) -> void:
	if _error_label == null:
		_error_label = Style.text("", Typography.CAPTION)
		_error_label.add_theme_color_override("font_color", T.DANGER)
		_error_label.hide()
		content.add_child(_error_label)
		# Match the existing error slot: after title/description, before actions.
		content.move_child(_error_label, mini(1 if document_variant else 2, content.get_child_count() - 1))
	if message.is_empty():
		_error_label.hide()
	else:
		_error_label.text = message
		_error_label.show()

func dismiss() -> void:
	if not dismiss_enabled: return
	hide()
	if previous_focus != null:
		var focused = previous_focus.get_ref()
		if is_instance_valid(focused) and focused.is_visible_in_tree(): focused.grab_focus()
	dismissed.emit()
	queue_free()

func _fit() -> void:
	var safe := Mobile.safe_rect(size)
	if document_variant:
		panel.size = Vector2(minf(T.DOCUMENT_WIDTH, maxf(1, safe.size.x - T.FORM_PADDING * 2)), minf(T.DOCUMENT_HEIGHT, maxf(1, safe.size.y - T.FORM_PADDING * 2)))
		panel.position = safe.position + (safe.size - panel.size) / 2
		return
	panel.custom_minimum_size.x = minf(460, maxf(1,safe.size.x-32))
	scroll.custom_minimum_size.y = minf(content.get_combined_minimum_size().y, maxf(1,safe.size.y-72))
	panel.reset_size()
	panel.position = safe.position+(safe.size-panel.size)/2

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		dismiss()
		get_viewport().set_input_as_handled()
