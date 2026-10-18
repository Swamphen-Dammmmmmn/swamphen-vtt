extends PanelContainer

const Typography = preload("res://ui/theme/typography.gd")

signal entry_chosen(entry: Dictionary)
signal state_changed(category: String, opened: bool)
const Slot = preload("res://ui/components/creation_slot.gd")
const Preferences = preload("res://scripts/ui_preferences.gd")
const TokenStore = preload("res://scripts/token_library_store.gd")
const BUILTIN_BASIC := {"id": "builtin_basic", "title": "基础棋子", "builtin": true, "tooltip": "创建基础棋子", "parameters": {"size": 1, "base": "circle", "color": Color("2e7ae0")}}
const GAP := 8.0
const MIN_SLOT_HEIGHT := 64.0
var category := "basic"
var entries: Dictionary = {"basic": [], "advanced": []}
var memory: Dictionary = {"basic": {"query": "", "first": 0}, "advanced": {"query": "", "first": 0}}
var filtered: Array = []
var preferences: RefCounted
var title: Label
var search: LineEdit
var clear_button: Button
var header: HBoxContainer
var footer: HBoxContainer
var pager: HBoxContainer
var target_dimensions := Vector2.ZERO
var reveal_pending := false
var status: Label
var page_label: Label
var previous_button: Button
var next_button: Button
var slots: GridContainer
var scroll: ScrollContainer
var left_margin := 16.0
var motion: Tween
var columns := 1
var actual_rows := 1
var page_index := 0
var page_count := 1
var slot_height := 120.0
var rendered_mode := "pages"
var compact_height := false
var revision := 0
var relayout_pending := false
var library_error := ""
var library_warnings: Array = []
var additional_overhead := 0.0
var maximum_height_ratio := 1.0/3.0

func _ready() -> void:
	ProductCatalog.changed.connect(_catalog_changed)
	theme = GoUi.theme()
	focus_mode = Control.FOCUS_ALL
	add_theme_stylebox_override("panel", BoardUiStyle.card_face(BoardUiStyle.PANEL_PADDING))
	preferences = Preferences.shared()
	preferences.changed.connect(_reflow)
	var column := GoStyle.column(BoardUiStyle.CONTENT_GAP)
	add_child(column)
	header = GoStyle.row(8)
	header.custom_minimum_size.y = BoardUiStyle.ACTION_HEIGHT
	column.add_child(header)
	title = GoStyle.label("基础棋子")
	title.add_theme_font_size_override("font_size", Typography.SUBTITLE)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.size_flags_horizontal = Control.SIZE_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title)
	search = GoStyle.line_edit("搜索棋子名称")
	search.custom_minimum_size = Vector2(120, BoardUiStyle.ACTION_HEIGHT)
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.max_length = 80
	header.add_child(search)
	search.text_changed.connect(_search_changed)
	clear_button = GoStyle.button("清空", _clear_search)
	BoardUiStyle.action_button(clear_button)
	clear_button.focus_mode = Control.FOCUS_NONE
	clear_button.size_flags_horizontal = Control.SIZE_FILL
	clear_button.custom_minimum_size.x = 56
	header.add_child(clear_button)
	var close_button := GoStyle.button("", close, GoStyle.Tone.COMPACT)
	BoardUiStyle.action_button(close_button)
	GoStyle.apply_icon(close_button, GoIconSet.CLOSE, 16)
	close_button.tooltip_text = "收起创建栏"
	close_button.size_flags_horizontal = Control.SIZE_FILL
	close_button.custom_minimum_size.x = BoardUiStyle.ACTION_HEIGHT
	header.add_child(close_button)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	column.add_child(scroll)
	slots = GridContainer.new()
	slots.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	slots.add_theme_constant_override("h_separation", int(GAP))
	slots.add_theme_constant_override("v_separation", int(GAP))
	scroll.add_child(slots)
	footer = GoStyle.row(8)
	column.add_child(footer)
	status = GoStyle.label("")
	status.mouse_filter = Control.MOUSE_FILTER_PASS
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.add_theme_font_size_override("font_size", Typography.STATUS)
	status.autowrap_mode = TextServer.AUTOWRAP_OFF
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(status)
	pager = GoStyle.row(8)
	pager.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	footer.add_child(pager)
	var balance := Control.new()
	balance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(balance)
	previous_button = GoStyle.button("上一页", func(): _change_page(-1))
	BoardUiStyle.action_button(previous_button)
	previous_button.focus_mode = Control.FOCUS_NONE
	previous_button.size_flags_horizontal = Control.SIZE_FILL
	previous_button.custom_minimum_size.x = 72
	pager.add_child(previous_button)
	page_label = GoStyle.label("")
	page_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	page_label.size_flags_horizontal = Control.SIZE_FILL
	page_label.custom_minimum_size.x = 96
	pager.add_child(page_label)
	next_button = GoStyle.button("下一页", func(): _change_page(1))
	BoardUiStyle.action_button(next_button)
	next_button.focus_mode = Control.FOCUS_NONE
	next_button.size_flags_horizontal = Control.SIZE_FILL
	next_button.custom_minimum_size.x = 72
	pager.add_child(next_button)
	get_parent().resized.connect(_queue_reflow)
	get_window().size_changed.connect(_queue_reflow)
	_filter_entries()
	_reflow(0)
	hide()

func set_entries(key: String, data: Array) -> void:
	if not entries.has(key):
		return
	entries[key] = data.duplicate(true)
	if category == key:
		var anchor := _visible_index()
		_filter_entries()
		_reflow(anchor)

func _load_local_entries() -> void:
	var loaded := TokenStore.read_catalog()
	library_error = loaded["error"]
	library_warnings = loaded["warnings"]
	entries["basic"] = []
	entries["advanced"] = []
	for record in loaded["entries"]:
		var key: String = record["kind"]
		if not entries.has(key): continue
		var item: Dictionary = record.duplicate(true)
		item["builtin"] = false
		item["tooltip"] = str(record["title"])
		entries[key].append(item)

func _filter_entries() -> void:
	filtered.clear()
	if category == "basic":
		filtered.append(BUILTIN_BASIC)
	var query := search.text.strip_edges().to_lower()
	for entry in entries[category]:
		if query.is_empty() or str(entry.get("title", "")).to_lower().contains(query):
			filtered.append(entry)
	clear_button.disabled = search.text.is_empty()

func _clear_search() -> void:
	search.text = ""
	_search_changed("")

func _search_changed(value: String) -> void:
	memory[category]["query"] = value
	_filter_entries()
	_reflow(0)

func _visible_index() -> int:
	if rendered_mode == "pages":
		return page_index * columns * actual_rows
	return int(floor(float(scroll.scroll_vertical) / (slot_height + GAP))) * columns

func _queue_reflow() -> void:
	if relayout_pending:
		return
	relayout_pending = true
	_reflow_deferred.call_deferred()

func _reflow_deferred() -> void:
	relayout_pending = false
	_reflow()

func _reflow(anchor: int = -1) -> void:
	if slots == null:
		return
	if anchor < 0:
		anchor = _visible_index()
	if motion != null and motion.is_valid():
		motion.kill()
		modulate.a = 1.0
	var bounds: Vector2 = get_parent().size
	var start := minf(left_margin, maxf(16, bounds.x - 420))
	var width := minf(BoardUiStyle.CREATION_PALETTE_WIDTH, maxf(0, bounds.x - start - 16))
	columns = maxi(1, int(floor((width - BoardUiStyle.PANEL_PADDING * 2 - 16 + GAP) / (BoardUiStyle.CREATION_SLOT_WIDTH + GAP))))
	slots.columns = columns
	rendered_mode = preferences.creation_mode
	var paged := rendered_mode == "pages"
	previous_button.visible = paged
	next_button.visible = paged
	page_label.visible = paged
	var overhead := BoardUiStyle.PANEL_PADDING * 2 + BoardUiStyle.ACTION_HEIGHT + (BoardUiStyle.ACTION_HEIGHT if paged else 20.0) + BoardUiStyle.CONTENT_GAP * 2 + additional_overhead
	var available := maxf(24, bounds.y - (72.0 if Mobile.enabled else 130.0))
	var height_limit := minf(available, maxf(overhead + 24, available * maximum_height_ratio))
	var pixels: Vector2i = DisplayServer.window_get_size()
	var display_scale := maxf(0.25, minf(float(pixels.x) / maxf(1, bounds.x), float(pixels.y) / maxf(1, bounds.y)))
	var minimum_height := maxf(72.0, MIN_SLOT_HEIGHT / minf(1.0, display_scale)) if Mobile.enabled else MIN_SLOT_HEIGHT / minf(1.0, display_scale)
	actual_rows = clampi(int(floor((height_limit - overhead + GAP) / (minimum_height + GAP))), 1, int(preferences.creation_rows))
	slot_height = maxf(minimum_height, minf(BoardUiStyle.CREATION_SLOT_HEIGHT, floor((height_limit - overhead - GAP * (actual_rows - 1)) / actual_rows)))
	var grid_height := minf(slot_height * actual_rows + GAP * (actual_rows - 1), maxf(24, height_limit - overhead))
	compact_height = grid_height < slot_height
	scroll.custom_minimum_size.y = grid_height
	var capacity := columns * actual_rows
	page_count = maxi(1, ceili(float(filtered.size()) / capacity))
	page_index = clampi(int(anchor / capacity), 0, page_count - 1)
	_render_slots()
	target_dimensions = Vector2(width, overhead + grid_height)
	size = target_dimensions
	_position_layout()
	memory[category]["first"] = page_index * capacity if paged else anchor
	revision += 1
	_settle_layout.call_deferred(revision, anchor)

func _render_slots() -> void:
	for child in slots.get_children():
		slots.remove_child(child)
		child.queue_free()
	var capacity := columns * actual_rows
	var count := capacity if rendered_mode == "pages" else maxi(capacity, ceili(float(filtered.size()) / columns) * columns)
	var offset := page_index * capacity if rendered_mode == "pages" else 0
	for index in range(count):
		var slot := Slot.new()
		slots.add_child(slot)
		slot.set_slot_height(slot_height)
		var data: Dictionary = filtered[offset + index] if offset + index < filtered.size() else {}
		slot.configure(data)
		if not data.is_empty():
			slot.pressed.connect(func(): _choose_entry(data))
	var custom_count := filtered.size() - (1 if category == "basic" else 0)
	if not search.text.strip_edges().is_empty() and custom_count == 0:
		status.text = "没有匹配的自定义棋子"
	elif entries[category].is_empty():
		status.text = ""
	else:
		status.text = "%d 个自定义棋子" % custom_count
	status.tooltip_text = status.text + "；实际显示 %d 行，设置 %d 行。" % [actual_rows, preferences.creation_rows]
	status.add_theme_color_override("font_color", Color("64748b"))
	if not library_error.is_empty():
		status.text = "棋子库读取失败" + (" · 内置棋子仍可用" if category == "basic" else "")
		status.tooltip_text = library_error
		status.add_theme_color_override("font_color", Color("b33c3c"))
	elif not library_warnings.is_empty():
		status.text += " · %d 个文件未能读取" % library_warnings.size()
		status.tooltip_text += "\n" + "\n".join(PackedStringArray(library_warnings))
	if actual_rows < preferences.creation_rows:
		status.text += " · 当前 %d 行" % actual_rows
	status.visible = not status.text.is_empty()
	page_label.text = "第 %d / %d 页" % [page_index + 1, page_count]
	previous_button.disabled = page_index == 0
	next_button.disabled = page_index >= page_count - 1

func _position_layout() -> void:
	var bounds: Vector2 = get_parent().size
	var start := minf(left_margin, maxf(16, bounds.x - 420))
	position = Vector2(start + maxf(0, bounds.x - start - 16 - size.x) / 2, maxf(16, bounds.y - size.y - 66))

func _choose_entry(data: Dictionary) -> void:
	var chosen := data.duplicate(true)
	if data.has("catalog_kind"):
		var loaded: Dictionary = load(ProductCatalog.STORES[data.catalog_kind]).get_record(data.id)
		if not loaded.ok:
			library_error = loaded.message
			status.text = loaded.message
			status.show()
			return
		chosen = loaded.record.duplicate(true)
		chosen["builtin"] = false
		if data.catalog_kind=="tokens":
			chosen.parameters["title"] = chosen.title
			chosen.parameters["kind"] = chosen.kind
			chosen.parameters["tags"] = chosen.tags.duplicate()
	close()
	entry_chosen.emit(chosen)

func _settle_layout(expected_revision: int, anchor: int) -> void:
	if revision != expected_revision:
		return
	# Containers invalidate minimum sizes while rebuilding. Settle before drawing.
	if motion == null or not motion.is_valid():
		size = target_dimensions
		_position_layout()
	_restore_scroll(expected_revision, anchor)
	if reveal_pending and visible:
		reveal_pending = false
		_animate_open()

func _restore_scroll(expected_revision: int, anchor: int) -> void:
	if revision != expected_revision:
		return
	scroll.scroll_vertical = int(anchor / columns) * int(slot_height + GAP) if rendered_mode == "scroll" else 0

func _change_page(direction: int) -> void:
	if rendered_mode != "pages":
		return
	var next_page := clampi(page_index + direction, 0, page_count - 1)
	if next_page != page_index:
		_reflow(next_page * columns * actual_rows)

func open(margin: float, key: String) -> void:
	memory[category]["first"] = _visible_index()
	category = key
	left_margin = margin
	search.set_block_signals(true)
	search.text = memory[category]["query"]
	search.set_block_signals(false)
	title.text = "基础棋子" if category == "basic" else "高级棋子"
	_load_local_entries()
	_filter_entries()
	show()
	get_parent().move_child(self, get_parent().get_child_count() - 1)
	reveal_pending = true
	_reflow(int(memory[category]["first"]))
	grab_focus()
	modulate.a = 0.0
	state_changed.emit(category, true)

func _animate_open() -> void:
	var target := position
	position.y += 10
	motion = create_tween().set_parallel(true)
	motion.set_trans(Tween.TRANS_QUAD).set_ease(Tween.EASE_OUT)
	motion.tween_property(self, "modulate:a", 1.0, preload("res://ui/components/page_motion.gd").duration(BoardUiStyle.FADE_TIME))
	motion.tween_property(self, "position", target, preload("res://ui/components/page_motion.gd").duration(BoardUiStyle.FADE_TIME))

func close() -> void:
	reveal_pending = false
	memory[category]["first"] = _visible_index()
	if motion != null and motion.is_valid():
		motion.kill()
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and (focused == self or is_ancestor_of(focused)):
		focused.release_focus()
	hide()
	state_changed.emit(category, false)

func _input(event: InputEvent) -> void:
	if not visible:
		return
	var focused := get_viewport().gui_get_focus_owner()
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and focused != null and (focused == self or is_ancestor_of(focused)):
		close()
		get_viewport().set_input_as_handled()
	elif event is InputEventMouseButton and event.pressed and scroll.get_global_rect().has_point(event.position) and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
		var direction := -1 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1
		if rendered_mode == "pages" and not compact_height:
			_change_page(direction)
		else:
			scroll.scroll_vertical += direction * int(slot_height + GAP)
		get_viewport().set_input_as_handled()

var catalog_refresh_queued := false
func _catalog_changed(kind: String) -> void:
	var expected := "platforms" if category=="platform" else "tokens"
	if kind!=expected or not visible or catalog_refresh_queued: return
	catalog_refresh_queued = true
	get_tree().create_timer(0.2).timeout.connect(_reload_catalog)
func _reload_catalog() -> void:
	catalog_refresh_queued = false
	if not visible: return
	var anchor := _visible_index()
	_load_local_entries()
	_filter_entries()
	_reflow(anchor)
