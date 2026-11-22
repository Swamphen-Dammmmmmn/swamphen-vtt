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
var _title_label: Label
var _footer: Control
var _body_inset: MarginContainer
var _busy := false
var _original_dismiss_enabled := true
var _layout_frames := 0
var _default_focus_requested := false

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

	if document_variant:
		_setup_document_variant()
	else:
		_setup_normal_variant()

	resized.connect(_request_fit)
	if Mobile.enabled: Mobile.changed.connect(_request_fit)
	content.minimum_size_changed.connect(_request_fit)
	grab_focus()
	_request_fit()
	Style.Motion.fade_in(panel)

func _setup_document_variant() -> void:
	panel = PanelContainer.new()
	add_child(panel)
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
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)
	content = Style.column(T.GAP)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mount_scroll_content()
	_document_actions = HBoxContainer.new()
	_document_actions.alignment = BoxContainer.ALIGNMENT_END
	_document_actions.add_theme_constant_override("separation", T.GAP / 2)
	layout.add_child(_document_actions)

func _setup_normal_variant() -> void:
	theme = FluentTheme.shared()
	panel = PanelContainer.new()
	add_child(panel)
	var face := FluentTheme.face(T.SURFACE, T.STROKE, T.RADIUS)
	for edge in ["left", "right", "top", "bottom"]:
		face.set("content_margin_" + edge, T.FORM_PADDING)
	panel.add_theme_stylebox_override("panel", face)

	var layout := VBoxContainer.new()
	layout.add_theme_constant_override("separation", T.GAP)
	panel.add_child(layout)

	# Title (fixed at top)
	_title_label = Label.new()
	_title_label.add_theme_font_override("font", Typography.MEDIUM)
	_title_label.add_theme_font_size_override("font_size", Typography.SECTION)
	_title_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	layout.add_child(_title_label)

	# Scrollable content area
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	layout.add_child(scroll)

	content = VBoxContainer.new()
	content.add_theme_constant_override("separation", T.GAP)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mount_scroll_content()

	# Footer for actions - use HFlowContainer for wrapping
	_footer = HFlowContainer.new()
	_footer.alignment = FlowContainer.ALIGNMENT_END
	_footer.add_theme_constant_override("h_separation", T.GAP / 2)
	_footer.add_theme_constant_override("v_separation", T.GAP / 2)
	layout.add_child(_footer)

func _mount_scroll_content() -> void:
	# ScrollContainer clips at its rect. Keep focus/rounded-AA pixels inside it,
	# including when the final field ends exactly at the body's minimum height.
	_body_inset = MarginContainer.new()
	_body_inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for edge in ["left", "right", "top", "bottom"]:
		_body_inset.add_theme_constant_override("margin_" + edge, T.MODAL_BODY_DRAW_INSET)
	scroll.add_child(_body_inset)
	_body_inset.add_child(content)

func configure(title: String, description: String) -> void:
	if document_variant:
		_document_title.text = title
		if not description.is_empty():
			var body := Label.new()
			body.text = description
			body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			body.add_theme_font_size_override("font_size", Typography.BODY)
			body.mouse_filter = Control.MOUSE_FILTER_IGNORE
			content.add_child(body)
	else:
		if _title_label: _title_label.text = title
		if not description.is_empty():
			var body := Label.new()
			body.text = description
			body.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
			body.add_theme_font_size_override("font_size", Typography.BODY)
			content.add_child(body)
	_request_fit()

func add_content(control: Control) -> void:
	if content: content.add_child(control)

func add_action(title: String, action: Callable, primary := false, enabled := true, danger := false) -> Button:
	var button: Button = FluentButton.new()
	button.text = title
	button.variant = "FluentDangerOutline" if danger else ("FluentPrimary" if primary else "FluentButton")
	if document_variant:
		button.custom_minimum_size.x = T.DOCUMENT_ACTION_WIDTH
	button.disabled = not enabled
	if action.is_valid(): button.pressed.connect(action)

	# If already busy, store the original state and disable
	if _busy:
		button.set_meta("_original_disabled", enabled == false)
		button.disabled = true

	var action_container := _document_actions if document_variant else _footer
	if action_container: action_container.add_child(button)
	button.set_meta("modal_danger", danger)
	button.set_meta("modal_primary", primary)
	_request_fit()
	if not _default_focus_requested:
		_default_focus_requested = true
		_focus_default.call_deferred()
	return button

func set_error(message: String) -> void:
	if _error_label == null:
		_error_label = Label.new()
		_error_label.add_theme_font_size_override("font_size", Typography.CAPTION)
		_error_label.add_theme_color_override("font_color", T.DANGER)
		_error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		_error_label.hide()
		# Place error after first child (description) if it exists
		var target_index := mini(1, content.get_child_count())
		content.add_child(_error_label)
		if target_index < content.get_child_count():
			content.move_child(_error_label, target_index)
	if message.is_empty():
		_error_label.hide()
	else:
		_error_label.text = message
		_error_label.show()

func set_busy(busy: bool) -> void:
	if busy == _busy: return  # Already in desired state

	if busy:
		# Entering busy state
		_original_dismiss_enabled = dismiss_enabled
		_busy = true
		dismiss_enabled = false
		var action_container := _document_actions if document_variant else _footer
		if action_container:
			for child in action_container.get_children():
				if child is Button:
					var button := child as Button
					button.set_meta("_original_disabled", button.disabled)
					button.disabled = true
	else:
		# Exiting busy state
		_busy = false
		dismiss_enabled = _original_dismiss_enabled
		var action_container := _document_actions if document_variant else _footer
		if action_container:
			for child in action_container.get_children():
				if child is Button:
					var button := child as Button
					var was_disabled: bool = button.get_meta("_original_disabled", false)
					button.disabled = was_disabled
					button.remove_meta("_original_disabled")

func dismiss() -> void:
	if not dismiss_enabled: return
	hide()
	if previous_focus != null:
		var focused = previous_focus.get_ref()
		if is_instance_valid(focused) and focused.is_visible_in_tree(): focused.grab_focus()
	dismissed.emit()
	queue_free()

func _focus_default() -> void:
	_default_focus_requested = false
	if not is_inside_tree() or not is_visible_in_tree(): return
	var focused := get_viewport().gui_get_focus_owner()
	# An input or an explicitly focused action takes precedence.
	if focused != null and focused != self: return
	var actions: Control = _document_actions if document_variant else _footer
	var fallback: Button
	for child in actions.get_children():
		if child is Button and not child.disabled and not child.get_meta("modal_danger", false):
			if fallback == null: fallback = child
			if not child.get_meta("modal_primary", false):
				child.grab_focus()
				return
	if fallback != null: fallback.grab_focus()

func _request_fit() -> void:
	# Containers settle over consecutive frames; no suspended layout coroutine.
	_layout_frames = 3
	set_process(true)

func _process(_delta: float) -> void:
	_layout_frames -= 1
	_do_fit()
	if _layout_frames <= 0: set_process(false)

func _do_fit() -> void:
	if not is_inside_tree() or panel == null: return
	var safe := Mobile.safe_rect(size)
	var available := (safe.size - Vector2.ONE * T.FORM_PADDING * 2).max(Vector2.ONE)
	if document_variant:
		panel.size = Vector2(minf(T.DOCUMENT_WIDTH, available.x), minf(T.DOCUMENT_HEIGHT, available.y))
	else:
		var width := minf(T.FORM_WIDTH, available.x)
		panel.custom_minimum_size.x = width
		panel.size.x = width
		var overhead := T.FORM_PADDING * 2 + T.GAP * 2 + _title_label.get_combined_minimum_size().y + _footer.get_combined_minimum_size().y
		var body_height := minf(_body_inset.get_combined_minimum_size().y, maxf(0, minf(T.MODAL_MAX_HEIGHT, available.y) - overhead))
		scroll.custom_minimum_size.y = body_height
		panel.size = Vector2(width, overhead + body_height)
	panel.position = safe.position + (safe.size - panel.size) / 2

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		dismiss()
		get_viewport().set_input_as_handled()
