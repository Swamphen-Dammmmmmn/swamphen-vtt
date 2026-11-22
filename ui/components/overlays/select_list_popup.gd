# In-canvas single-choice list for the shared select control (FluentOptionButton).
# Plain Controls under a CanvasLayer of the main viewport: no PopupMenu, PopupPanel, Window or sub-viewport.
extends Control

signal chosen(index: int)
signal closed

const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
const Icons = preload("res://ui/theme/icons/library_icons.gd")

const CHECK_ICON := "res://ui/theme/icons/select_check.svg"
const GROUP := "select_list_popups"
const ITEM_VARIANT := "FluentSelectItem"
const GROUP_VARIANT := "FluentSelectGroup"
const PANEL_VARIANT := "FluentSelectPanel"
const RULE_VARIANT := "FluentSelectRule"
# Layer above the anchor's own layer and the page overlay layer that hosts command menus.
const LAYER_OFFSET := 2
const ROW_INSET := 2.0
const TYPE_AHEAD_RESET_MS := 800

static var _blank: Texture2D

var _layer: CanvasLayer
var _anchor: Button
var _panel: PanelContainer
var _scroll: ScrollContainer
var _items: VBoxContainer
var _backdrop: Control
var _buttons: Array[Button] = []
var _entries: Array = []
var _selected := -1
var _max_height := 0.0
var _connections: Array[Dictionary] = []
var _generation := 0
var _opened := false
var _active := false
var _keyboard_mode := false
var _anchor_rect := Rect2()
var _side := ""
var _outside_mouse := false
var _outside_finger := -1
var _typed := ""
var _typed_at := 0

# Builds the overlay for one anchor. The layer lives under the window root so no ancestor
# ScrollContainer, clip region or container of the anchor affects it; it is freed with the anchor.
func attach(anchor: Button) -> void:
	_anchor = anchor
	_layer = CanvasLayer.new()
	_layer.visible = false
	_layer.add_child(self)
	anchor.get_window().add_child(_layer)
	anchor.tree_exiting.connect(_anchor_exiting)

func _ready() -> void:
	add_to_group(GROUP)
	theme = FluentTheme.shared()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop = Control.new()
	_backdrop.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_backdrop)
	_backdrop.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_backdrop.gui_input.connect(_outside_input)
	_panel = PanelContainer.new()
	_panel.theme_type_variation = PANEL_VARIANT
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_panel.gui_input.connect(_panel_input)
	add_child(_panel)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	_scroll.add_theme_stylebox_override("panel", StyleBoxEmpty.new())
	_panel.add_child(_scroll)
	# Room inside the clipped scroll area so rounded row strokes keep their anti-aliased edge.
	var inset := MarginContainer.new()
	inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "top", "right", "bottom"]:
		inset.add_theme_constant_override("margin_" + side, int(ROW_INSET))
	_scroll.add_child(inset)
	_items = VBoxContainer.new()
	_items.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_items.add_theme_constant_override("separation", 0)
	inset.add_child(_items)
	hide()
	set_process(false)
	set_process_input(false)

func is_open() -> bool:
	return _opened

# entries: [{"text": String, "disabled": bool}]. selected: current index or -1.
func open(entries: Array, selected: int, keyboard := false, max_height := 0.0) -> void:
	if not is_inside_tree() or not is_instance_valid(_anchor) or not _anchor.is_visible_in_tree() or entries.is_empty(): return
	if _opened: close(false)
	for other in get_tree().get_nodes_in_group(GROUP):
		if other != self: other.close(false)
	_generation += 1
	_opened = true
	_active = false
	_keyboard_mode = keyboard
	_outside_mouse = false
	_outside_finger = -1
	_typed = ""
	_entries = entries
	_selected = selected
	_max_height = max_height
	_layer.layer = _anchor_layer() + LAYER_OFFSET
	_build_rows()
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
	_panel.modulate.a = 0.0
	_layer.visible = true
	show()
	set_process(true)
	set_process_input(true)
	_finish_open(_generation)

func close(restore_focus := true) -> void:
	if not _opened: return
	_opened = false
	_active = false
	_generation += 1
	_disconnect()
	hide()
	if is_instance_valid(_layer): _layer.visible = false
	set_process(false)
	set_process_input(false)
	_outside_mouse = false
	_outside_finger = -1
	_clear_rows()
	if restore_focus and is_instance_valid(_anchor) and _anchor.is_visible_in_tree() and not _anchor.is_queued_for_deletion():
		_anchor.grab_focus()
	closed.emit()

func focus_item(index: int, keyboard := true) -> void:
	if index < 0 or index >= _buttons.size() or _buttons[index].disabled: return
	_set_keyboard_mode(keyboard)
	_buttons[index].grab_focus()
	_scroll.ensure_control_visible(_buttons[index])

func _exit_tree() -> void:
	close(false)

func _anchor_exiting() -> void:
	close(false)
	if is_instance_valid(_layer): _layer.queue_free()

func _anchor_layer() -> int:
	var layer := _anchor.get_canvas_layer_node()
	return layer.layer if layer != null else 0

func _watch(source: Signal, callback: Callable) -> void:
	source.connect(callback)
	_connections.append({"source": source, "callback": callback})

func _disconnect() -> void:
	for connection in _connections:
		var source: Signal = connection.source
		if not source.is_null() and is_instance_valid(source.get_object()) and source.is_connected(connection.callback): source.disconnect(connection.callback)
	_connections.clear()

func _valid_session(generation: int) -> bool:
	return is_inside_tree() and not is_queued_for_deletion() and _opened and generation == _generation and is_instance_valid(_anchor) and not _anchor.is_queued_for_deletion() and _anchor.is_visible_in_tree()

func _row_height() -> float:
	return T.SELECT_TOUCH_ROW_HEIGHT if Mobile.enabled else T.SELECT_ROW_HEIGHT

func _clear_rows() -> void:
	_buttons.clear()
	if _items == null: return
	for child in _items.get_children():
		_items.remove_child(child)
		child.queue_free()
	_scroll.custom_minimum_size = Vector2.ZERO
	_scroll.scroll_vertical = 0

func _build_rows() -> void:
	_clear_rows()
	var check := Icons.texture(CHECK_ICON)
	for index in _entries.size():
		var entry: Dictionary = _entries[index]
		var row := Button.new()
		var heading := bool(entry.get("separator", false))
		row.theme_type_variation = GROUP_VARIANT if heading else ITEM_VARIANT
		row.text = str(entry.get("text", ""))
		row.clip_text = true
		row.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		row.alignment = HORIZONTAL_ALIGNMENT_LEFT
		row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		if heading:
			# Group heading: keeps its index slot, but takes no pointer or keyboard focus.
			row.disabled = true
			row.focus_mode = Control.FOCUS_NONE
			row.mouse_filter = Control.MOUSE_FILTER_IGNORE
			row.custom_minimum_size.y = _row_height() * T.SELECT_GROUP_RATIO if not row.text.is_empty() else T.SELECT_RULE_HEIGHT
			if row.text.is_empty(): row.add_child(_rule())
		else:
			row.icon = check if index == _selected else _blank_icon()
			row.disabled = bool(entry.get("disabled", false))
			row.focus_mode = Control.FOCUS_ALL
			row.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
			row.custom_minimum_size.y = _row_height()
			row.pressed.connect(_activate.bind(index, _generation))
			row.gui_input.connect(_row_input)
		_buttons.append(row)
		_items.add_child(row)
	_set_keyboard_mode(_keyboard_mode)

# One-pixel divider drawn inside an empty heading row (separator without a title).
func _rule() -> Panel:
	var line := Panel.new()
	line.theme_type_variation = RULE_VARIANT
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	line.anchor_right = 1.0
	line.offset_left = 8.0
	line.offset_right = -8.0
	line.offset_top = floorf(T.SELECT_RULE_HEIGHT * 0.5)
	line.offset_bottom = line.offset_top + 1.0
	return line

static func _blank_icon() -> Texture2D:
	if _blank == null: _blank = ImageTexture.create_from_image(Image.create_empty(32, 32, false, Image.FORMAT_RGBA8))
	return _blank

func _set_keyboard_mode(enabled: bool) -> void:
	_keyboard_mode = enabled
	for row in _buttons:
		if enabled: row.remove_theme_stylebox_override("focus")
		else: row.add_theme_stylebox_override("focus", StyleBoxEmpty.new())

func _local_anchor_rect() -> Rect2:
	return get_global_transform_with_canvas().affine_inverse() * (_anchor.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, _anchor.size))

func _finish_open(generation: int) -> void:
	await get_tree().process_frame
	if not _valid_session(generation): return
	_fit()
	# One more frame so the scroll container has laid the rows out before scrolling to the selection.
	await get_tree().process_frame
	if not _valid_session(generation): return
	_center_on(_selected if _selected >= 0 else 0)
	_panel.modulate.a = 1.0
	_active = true
	var first := _selected
	if first < 0 or first >= _buttons.size() or _buttons[first].disabled: first = _first_enabled()
	focus_item(first, _keyboard_mode)

func _first_enabled() -> int:
	for index in _buttons.size():
		if not _buttons[index].disabled: return index
	return -1

func _center_on(index: int) -> void:
	if index < 0 or index >= _buttons.size(): return
	var row := _buttons[index]
	_scroll.scroll_vertical = maxi(0, int(row.position.y + row.size.y * 0.5 - _scroll.size.y * 0.5 + ROW_INSET))

func _fit() -> void:
	var bounds := get_viewport_rect()
	if Mobile.enabled: bounds = Mobile.safe_rect(bounds.size)
	var local_bounds: Rect2 = get_global_transform_with_canvas().affine_inverse() * bounds
	var edge := minf(T.SELECT_EDGE_MARGIN, minf(local_bounds.size.x, local_bounds.size.y) * 0.25)
	var safe := local_bounds.grow(-edge)
	var chrome := _panel.get_theme_stylebox("panel").get_minimum_size()
	_anchor_rect = _local_anchor_rect()
	var row_height := _row_height()
	var content_height := ROW_INSET * 2.0
	for row in _buttons: content_height += row.custom_minimum_size.y
	# Widest row: text + check slot + gap + row padding.
	var natural_width := 0.0
	var text_widths: Array[float] = []
	for row in _buttons:
		var font: Font = row.get_theme_font("font")
		var font_size: int = row.get_theme_font_size("font_size")
		var text_width := font.get_string_size(row.text, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		text_widths.append(text_width)
		natural_width = maxf(natural_width, row.get_theme_stylebox("normal").get_minimum_size().x + T.SELECT_MARK_SIZE + T.SELECT_ITEM_GAP + text_width)
	# Callers may cap the visible list; longer content scrolls inside it.
	var natural_height := minf(content_height, _max_height) if _max_height > 0.0 else content_height
	# Prefer below the trigger, then above; otherwise scroll inside the larger side.
	var below := safe.end.y - (_anchor_rect.end.y + T.SELECT_GAP) - chrome.y
	var above := _anchor_rect.position.y - T.SELECT_GAP - safe.position.y - chrome.y
	var height := natural_height
	if natural_height <= below: _side = "below"
	elif natural_height <= above: _side = "above"
	else:
		_side = "below" if below >= above else "above"
		height = maxf(row_height + ROW_INSET * 2.0, floorf(below if _side == "below" else above))
	var bar := 0.0
	# The scroll bar takes its own width plus the container's separation from the rows.
	if height < content_height: bar = _scroll.get_v_scroll_bar().get_combined_minimum_size().x + _scroll.get_theme_constant("scrollbar_v_separation")
	var cap := minf(maxf(T.SELECT_MAX_WIDTH, _anchor_rect.size.x), safe.size.x)
	var width := ceilf(minf(maxf(_anchor_rect.size.x, natural_width + ROW_INSET * 2.0 + bar + chrome.x), cap))
	height = ceilf(height)
	for index in _buttons.size():
		var room := width - chrome.x - ROW_INSET * 2.0 - bar - _buttons[index].get_theme_stylebox("normal").get_minimum_size().x - T.SELECT_MARK_SIZE - T.SELECT_ITEM_GAP
		# Clipped text stays readable through the tooltip.
		_buttons[index].tooltip_text = _buttons[index].text if text_widths[index] > room else ""
	_scroll.custom_minimum_size = Vector2(width - chrome.x, height)
	_panel.custom_minimum_size = Vector2.ZERO
	_panel.size = Vector2(width, height + chrome.y)
	var at := Vector2(_anchor_rect.position.x, _anchor_rect.end.y + T.SELECT_GAP)
	if _side == "above": at.y = _anchor_rect.position.y - T.SELECT_GAP - _panel.size.y
	at.x = clampf(at.x, safe.position.x, maxf(safe.position.x, safe.end.x - _panel.size.x))
	at.y = clampf(at.y, safe.position.y, maxf(safe.position.y, safe.end.y - _panel.size.y))
	_panel.position = at.round()

func _process(_delta: float) -> void:
	if not _valid_session(_generation) or _anchor.disabled:
		close(false)
		return
	if not _local_anchor_rect().is_equal_approx(_anchor_rect):
		close()
		return
	var focused := get_viewport().gui_get_focus_owner()
	# Another control (a modal, a text field) took over; stop intercepting its keyboard input.
	if _active and focused != null and focused != _anchor and not _panel.is_ancestor_of(focused): close(false)

func _outside_input(event: InputEvent) -> void:
	# The backdrop consumes the whole click; only a press that starts here closes the list, so the
	# release that opened it (on the trigger) never counts.
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
	# Gaps in the panel also consume pointer input; dragging inside is handled by the scroll container.
	if event is InputEventMouseButton or event is InputEventScreenTouch: _panel.accept_event()

func _row_input(event: InputEvent) -> void:
	if event is InputEventMouseButton or (event is InputEventMouseMotion and event.relative != Vector2.ZERO): _set_keyboard_mode(false)

func _input(event: InputEvent) -> void:
	if not _active or not event is InputEventKey or not event.pressed: return
	if event.keycode == KEY_ESCAPE:
		if event.echo: return
		get_viewport().set_input_as_handled()
		close()
		return
	if event.keycode == KEY_TAB:
		# Focus returns to the trigger first; the unhandled Tab then moves on from there.
		if not event.echo: close()
		return
	var direction := 0
	var edge := false
	match event.keycode:
		KEY_DOWN: direction = 1
		KEY_UP: direction = -1
		KEY_HOME: direction = 1; edge = true
		KEY_END: direction = -1; edge = true
	if direction != 0:
		_set_keyboard_mode(true)
		_focus_step(direction, edge)
		get_viewport().set_input_as_handled()
	elif event.is_action("ui_accept"):
		# Enter and Space activate the focused row through its own button; only recover focus if lost.
		if not _buttons.has(get_viewport().gui_get_focus_owner()):
			_set_keyboard_mode(true)
			_focus_step(1, true)
			get_viewport().set_input_as_handled()
	elif event.unicode > 32 and not event.ctrl_pressed and not event.alt_pressed and not event.meta_pressed:
		_type_ahead(char(event.unicode))
		get_viewport().set_input_as_handled()

func _focus_step(direction: int, edge := false) -> void:
	if _buttons.is_empty(): return
	var index := _buttons.find(get_viewport().gui_get_focus_owner())
	if edge or index < 0: index = -1 if direction > 0 else _buttons.size()
	for offset in range(1, _buttons.size() + 1):
		var next := posmod(index + direction * offset, _buttons.size())
		if not _buttons[next].disabled:
			focus_item(next)
			return

func _type_ahead(character: String) -> void:
	var now := Time.get_ticks_msec()
	if now - _typed_at > TYPE_AHEAD_RESET_MS: _typed = ""
	_typed_at = now
	_typed += character.to_lower()
	var current := _buttons.find(get_viewport().gui_get_focus_owner())
	# A single new letter moves on from the current row; a growing prefix may keep it.
	var first_offset := 1 if _typed.length() == 1 else 0
	for step in _buttons.size():
		var index := posmod(current + first_offset + step, _buttons.size())
		if not _buttons[index].disabled and _buttons[index].text.to_lower().begins_with(_typed):
			focus_item(index)
			return

func _activate(index: int, generation: int) -> void:
	# A row belongs to the session that created it; a late callback from an old row does nothing.
	if not _valid_session(generation) or not _active or index < 0 or index >= _buttons.size() or _buttons[index].disabled: return
	close()
	chosen.emit(index)

func _anchor_visibility() -> void:
	if not is_instance_valid(_anchor) or not _anchor.is_visible_in_tree(): close(false)

func _geometry_changed() -> void:
	close()

func _window_focus_lost() -> void:
	close(false)

func _page_scrolled(_value: float) -> void:
	close()
