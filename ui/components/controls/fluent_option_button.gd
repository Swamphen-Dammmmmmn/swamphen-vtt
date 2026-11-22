# Shared select control: a Button trigger plus an in-canvas list (select_list_popup.gd).
# Replaces the native OptionButton/PopupMenu path; no Window or PopupMenu is created.
# Selection is silent when set by code; item_selected fires only for a user-confirmed change.
extends Button

signal item_selected(index: int)

const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
const Icons = preload("res://ui/theme/icons/library_icons.gd")
const SelectListPopup = preload("res://ui/components/overlays/select_list_popup.gd")
const ButtonFocus = preload("res://ui/components/button_focus.gd")

const TRIGGER_VARIANT := "FluentSelectTrigger"
const CHEVRON_ICON := "res://ui/theme/icons/property_group_down.svg"
const CHEVRON_INSET := 12.0

var selected: int:
	get: return _selected
	set(value): select(value)
var item_count: int:
	get: return _items.size()
# Optional cap for the open list height (0 = limited only by the screen); longer lists scroll.
var max_list_height := 0.0

var _items: Array[Dictionary] = []
var _selected := -1
var _popup: SelectListPopup
var _opened_by_key := false
var _chevron: TextureRect

func _init() -> void:
	set_meta("style_owned", true)
	theme_type_variation = TRIGGER_VARIANT
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	clip_text = true
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	custom_minimum_size.y = T.BUTTON_HEIGHT
	focus_mode = Control.FOCUS_ALL

func _ready() -> void:
	theme = FluentTheme.shared()
	add_child(ButtonFocus.new())
	gui_input.connect(_trigger_input)
	resized.connect(_sync_tooltip)
	# A child control draws above the button face; _draw on the button itself would sit below it.
	_chevron = TextureRect.new()
	_chevron.texture = Icons.texture(CHEVRON_ICON)
	_chevron.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_chevron.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_chevron.stretch_mode = TextureRect.STRETCH_KEEP_CENTERED
	_chevron.anchor_left = 1.0
	_chevron.anchor_right = 1.0
	_chevron.anchor_top = 0.5
	_chevron.anchor_bottom = 0.5
	var half := T.SELECT_CHEVRON_SIZE * 0.5
	_chevron.offset_left = -CHEVRON_INSET - T.SELECT_CHEVRON_SIZE
	_chevron.offset_right = -CHEVRON_INSET
	_chevron.offset_top = -half
	_chevron.offset_bottom = half
	add_child(_chevron)

func _notification(what: int) -> void:
	# The face redraws when the disabled state flips; keep the chevron dimmed in step with it.
	if what == NOTIFICATION_DRAW and _chevron != null: _chevron.modulate.a = 0.4 if disabled else 1.0

func add_item(label: String, id := -1) -> void:
	_close_for_change()
	_items.append({"text": label, "id": id if id >= 0 else _items.size(), "disabled": false, "separator": false})
	# Same as the native control: the first added item becomes the selection.
	if _selected < 0 and not _items[-1].separator: _selected = _items.size() - 1
	_refresh()

# Group heading row: not selectable and not focusable, but counted like any other item.
func add_separator(label := "") -> void:
	_close_for_change()
	_items.append({"text": label, "id": -1, "disabled": true, "separator": true})
	_refresh()

func is_item_separator(index: int) -> bool:
	return _valid(index) and bool(_items[index].separator)

func clear() -> void:
	_close_for_change()
	_items.clear()
	_selected = -1
	_refresh()

func select(index: int) -> void:
	if index < -1 or index >= _items.size() or (index >= 0 and _items[index].separator):
		push_error("FluentOptionButton: invalid index %d (count %d)" % [index, _items.size()])
		return
	if index != _selected: _close_for_change()
	_selected = index
	_refresh()

func get_item_text(index: int) -> String:
	return str(_items[index].text) if _valid(index) else ""

func get_item_id(index: int) -> int:
	return int(_items[index].id) if _valid(index) else -1

func get_selected_id() -> int:
	return get_item_id(_selected)

func set_item_disabled(index: int, value: bool) -> void:
	if not _valid(index): return
	_close_for_change()
	_items[index].disabled = value

func is_item_disabled(index: int) -> bool:
	return _valid(index) and bool(_items[index].disabled)

func is_popup_open() -> bool:
	return is_instance_valid(_popup) and _popup.is_open()

func open_popup(keyboard := false) -> void:
	if disabled or _items.is_empty() or not is_visible_in_tree(): return
	if not is_instance_valid(_popup):
		_popup = SelectListPopup.new()
		_popup.attach(self)
		_popup.chosen.connect(_on_chosen)
	_popup.open(_items, _selected, keyboard, max_list_height)

func close_popup() -> void:
	# Closes the list only; the selection and signals are unchanged and focus is not moved.
	if is_instance_valid(_popup): _popup.close(false)

func _pressed() -> void:
	if is_popup_open(): close_popup()
	else: open_popup(_opened_by_key)

func _trigger_input(event: InputEvent) -> void:
	# Remember how the press began so keyboard opening starts with the focus ring visible.
	if event is InputEventKey and event.pressed: _opened_by_key = true
	elif event is InputEventMouseButton or event is InputEventScreenTouch: _opened_by_key = false

func _on_chosen(index: int) -> void:
	if index == _selected or not _valid(index): return
	_selected = index
	_refresh()
	item_selected.emit(index)

func _valid(index: int) -> bool:
	return index >= 0 and index < _items.size()

func _close_for_change() -> void:
	# The open list is a snapshot of the data; any change underneath it invalidates it.
	close_popup()

func _refresh() -> void:
	text = get_item_text(_selected)
	_sync_tooltip()

func _sync_tooltip() -> void:
	# Text room is the width left after the face margins (the right margin already holds the chevron).
	var room := size.x - get_theme_stylebox("normal").get_minimum_size().x
	var shown := get_theme_font("font").get_string_size(text, HORIZONTAL_ALIGNMENT_LEFT, -1, get_theme_font_size("font_size")).x
	tooltip_text = text if not text.is_empty() and shown > room else ""