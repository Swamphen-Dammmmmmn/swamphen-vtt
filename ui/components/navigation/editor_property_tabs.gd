# Editor property tabs component
extends HBoxContainer

signal tab_changed(index: int, tab_id: String)

const ET = preload("res://ui/theme/tokens/editor_tokens.gd")
const TabsTheme = preload("res://ui/theme/themes/editor_tabs_theme.gd")
const ButtonFocus = preload("res://ui/components/button_focus.gd")

var _tabs: Array[Dictionary] = [] # {id: String, title: String, button: Button}
var _current_index := 0

# Configuration before tree entry
var _config_tabs: Array[Dictionary] = [] # {id: String, title: String}
var _pending_selected := ""
var _built := false
var compact := false # Configure before entering the tree; toolbar density only.

func _init() -> void:
	add_theme_constant_override("separation", 0)
	custom_minimum_size.y = ET.TAB_HEIGHT

func _ready() -> void:
	_built = true
	# Apply deferred tabs
	for tab_config in _config_tabs:
		_add_tab_internal(tab_config.id, tab_config.title, tab_config.get("visible", true))
	_config_tabs.clear()
	if _pending_selected.is_empty() or not select_tab(_pending_selected, false):
		_ensure_visible_selection()

func add_tab(tab_id: String, title: String) -> void:
	if not _find_tab(tab_id).is_empty():
		push_error("EditorPropertyTabs: duplicate tab id " + tab_id)
		return
	if _built:
		_add_tab_internal(tab_id, title)
	else:
		_config_tabs.append({"id": tab_id, "title": title})

func setup(tab_ids: Array, tab_titles: Array) -> void:
	"""Setup multiple tabs at once. Can be called before or after _ready()."""
	if tab_ids.size() != tab_titles.size():
		push_error("EditorPropertyTabs: tab_ids and tab_titles must have the same length")
		return
	for i in tab_ids.size():
		add_tab(tab_ids[i], tab_titles[i])

func _add_tab_internal(tab_id: String, title: String, shown := true) -> void:
	var button := Button.new()
	button.text = title
	button.custom_minimum_size.y = ET.TAB_HEIGHT
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	button.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var focus := ButtonFocus.new()
	button.add_child(focus)

	# Bind identity, not the original index: tabs may be reordered later.
	button.pressed.connect(func(): select_tab(tab_id))
	button.visible = shown
	add_child(button)

	_tabs.append({"id": tab_id, "title": title, "button": button, "focus": focus, "visible": shown})
	_update_tab_styles()

	_ensure_visible_selection()

func select_tab(tab_id: String, emit_signal := true) -> bool:
	if not _built:
		var config := _find_tab(tab_id)
		if config.is_empty() or not config.get("visible", true): return false
		_pending_selected = tab_id
		return true
	for i in range(_tabs.size()):
		if _tabs[i].id == tab_id and _tabs[i].visible:
			_select_tab(i, emit_signal)
			return true
	return false

func set_tab_title(tab_id: String, title: String) -> bool:
	var tab := _find_tab(tab_id)
	if tab.is_empty(): return false
	tab.title = title
	if tab.has("button"): tab.button.text = title
	return true

func set_tab_visible(tab_id: String, shown: bool) -> bool:
	var tab := _find_tab(tab_id)
	if tab.is_empty(): return false
	tab.visible = shown
	if tab.has("button"):
		tab.button.visible = shown
		_ensure_visible_selection()
		_update_tab_styles()
	return true

func set_tab_order(tab_ids: Array) -> bool:
	var source: Array[Dictionary] = _tabs if _built else _config_tabs
	if tab_ids.size() != source.size(): return false
	var ordered: Array[Dictionary] = []
	var seen := {}
	for id in tab_ids:
		var tab := _find_tab(str(id))
		if tab.is_empty() or seen.has(str(id)): return false
		seen[str(id)] = true
		ordered.append(tab)
	if not _built:
		_config_tabs = ordered
		return true
	var selected := get_current_tab_id()
	_tabs = ordered
	for i in range(_tabs.size()): move_child(_tabs[i].button, i)
	select_tab(selected, false)
	_update_tab_styles()
	return true

func _find_tab(tab_id: String) -> Dictionary:
	for tab in (_tabs if _built else _config_tabs):
		if tab.id == tab_id: return tab
	return {}

func _ensure_visible_selection() -> void:
	if _current_index >= 0 and _current_index < _tabs.size() and _tabs[_current_index].visible: return
	_current_index = -1
	for i in range(_tabs.size()):
		if _tabs[i].visible:
			_select_tab(i, false)
			return

func get_current_tab_id() -> String:
	if not _built: return _pending_selected
	if _current_index >= 0 and _current_index < _tabs.size():
		return _tabs[_current_index].id
	return ""

func _select_tab(index: int, emit_signal := true) -> void:
	if index < 0 or index >= _tabs.size():
		return

	var changed := _current_index != index
	_current_index = index
	_update_tab_styles()

	if emit_signal and changed:
		tab_changed.emit(index, _tabs[index].id)

func _update_tab_styles() -> void:
	var visible_indices: Array[int] = []
	for i in range(_tabs.size()):
		if _tabs[i].visible: visible_indices.append(i)
	for i in range(_tabs.size()):
		var btn: Button = _tabs[i].button
		var is_selected := i == _current_index
		var visible_index := visible_indices.find(i)
		var is_first := visible_index == 0
		var is_last := visible_index == visible_indices.size() - 1

		var next_selected := not is_last and visible_indices[visible_index + 1] == _current_index
		btn.theme = TabsTheme.for_segment(is_selected, is_first, is_last, next_selected, compact)
		btn.theme_type_variation = &"EditorSegment"
		_tabs[i].focus.refresh_theme_face()
