extends PanelContainer

const Typography = preload("res://ui/theme/typography.gd")
const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
const FluentButton = preload("res://ui/components/controls/fluent_button.gd")
const EditorPropertyTabs = preload("res://ui/components/navigation/editor_property_tabs.gd")
const EditorLayout = preload("res://ui/components/editor_layout.gd")

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
var embedded_in_topbar := false
var fluent := false
var close_button: Button
var category_tabs: EditorPropertyTabs
var main_column: VBoxContainer
var _scroll_inset: MarginContainer

func _ready() -> void:
	ProductCatalog.changed.connect(_catalog_changed)
	var use_fluent := fluent or embedded_in_topbar
	if use_fluent:
		fluent = true
		set_meta("style_owned", true)
		theme = FluentTheme.shared()
	else:
		theme = GoUi.theme()
	focus_mode = Control.FOCUS_ALL
	if embedded_in_topbar:
		add_theme_stylebox_override("panel", StyleBoxEmpty.new())
		size_flags_horizontal = Control.SIZE_EXPAND_FILL
	elif use_fluent:
		var face := FluentTheme.face(T.SURFACE, T.STROKE, T.ENTRY_RADIUS, 1)
		face.set_content_margin_all(14)
		add_theme_stylebox_override("panel", face)
	else:
		add_theme_stylebox_override("panel", BoardUiStyle.card_face(BoardUiStyle.PANEL_PADDING))
	preferences = Preferences.shared()
	preferences.changed.connect(_reflow)
	main_column = VBoxContainer.new()
	main_column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	main_column.add_theme_constant_override("separation", 10 if use_fluent else BoardUiStyle.CONTENT_GAP)
	add_child(main_column)
	header = HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	header.custom_minimum_size.y = 38.0 if use_fluent else BoardUiStyle.ACTION_HEIGHT
	main_column.add_child(header)
	title = Label.new() if use_fluent else GoStyle.label("基础棋子")
	title.text = "基础棋子"
	if use_fluent:
		title.add_theme_font_override("font", Typography.MEDIUM)
	title.add_theme_font_size_override("font_size", Typography.BODY if use_fluent else Typography.SUBTITLE)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.size_flags_horizontal = Control.SIZE_FILL
	title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header.add_child(title)
	if embedded_in_topbar and category in ["basic", "advanced"]:
		title.hide()
		category_tabs = EditorPropertyTabs.new()
		category_tabs.compact = true
		category_tabs.setup(["basic", "advanced"], ["基础棋子", "高级棋子"])
		category_tabs.custom_minimum_size = Vector2(216, 36)
		category_tabs.select_tab(category, false)
		category_tabs.tab_changed.connect(func(_idx: int, tab_id: String): switch_embedded_category(tab_id))
		header.add_child(category_tabs)
		header.move_child(category_tabs, 0)
	if use_fluent:
		search = LineEdit.new()
		search.placeholder_text = "搜索棋子名称"
		search.custom_minimum_size = Vector2(140, 36)
		search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		search.max_length = 80
		header.add_child(search)
		search.text_changed.connect(_search_changed)
		var clear_fluent := FluentButton.new()
		clear_fluent.text = "清空"
		clear_fluent.variant = "FluentCompact"
		clear_fluent.minimum_height = 36.0
		clear_fluent.custom_minimum_size.x = 60
		clear_fluent.pressed.connect(_clear_search)
		header.add_child(clear_fluent)
		clear_button = clear_fluent
		var close_fluent := FluentButton.new()
		close_fluent.variant = "FluentCompact"
		close_fluent.icon_path = "res://ui/theme/icons/close_tintable.svg"
		close_fluent.minimum_height = 36.0
		close_fluent.custom_minimum_size.x = 36
		close_fluent.tooltip_text = "收起创建栏"
		close_fluent.visible = not embedded_in_topbar
		close_fluent.pressed.connect(close)
		header.add_child(close_fluent)
		close_button = close_fluent
	else:
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
		close_button = GoStyle.button("", close, GoStyle.Tone.COMPACT)
		BoardUiStyle.action_button(close_button)
		GoStyle.apply_icon(close_button, GoIconSet.CLOSE, 16)
		close_button.tooltip_text = "收起创建栏"
		close_button.size_flags_horizontal = Control.SIZE_FILL
		close_button.custom_minimum_size.x = BoardUiStyle.ACTION_HEIGHT
		close_button.visible = not embedded_in_topbar
		header.add_child(close_button)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	scroll.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	if use_fluent:
		EditorLayout.scroll(scroll)
		scroll.follow_focus = true
	main_column.add_child(scroll)
	slots = GridContainer.new()
	slots.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN if embedded_in_topbar else Control.SIZE_SHRINK_CENTER
	slots.add_theme_constant_override("h_separation", int(GAP))
	slots.add_theme_constant_override("v_separation", int(GAP))
	if use_fluent:
		_scroll_inset = MarginContainer.new()
		_scroll_inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		for edge in ["left", "right", "top", "bottom"]:
			_scroll_inset.add_theme_constant_override("margin_" + edge, T.MODAL_BODY_DRAW_INSET)
		scroll.add_child(_scroll_inset)
		_scroll_inset.add_child(slots)
	else:
		scroll.add_child(slots)
	footer = HBoxContainer.new()
	footer.add_theme_constant_override("separation", 8)
	main_column.add_child(footer)
	status = Label.new() if use_fluent else GoStyle.label("")
	status.mouse_filter = Control.MOUSE_FILTER_PASS
	status.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	status.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	status.add_theme_font_size_override("font_size", Typography.STATUS)
	status.autowrap_mode = TextServer.AUTOWRAP_OFF
	status.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(status)
	pager = HBoxContainer.new()
	pager.add_theme_constant_override("separation", 8)
	pager.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	footer.add_child(pager)
	var balance := Control.new()
	balance.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	footer.add_child(balance)
	if use_fluent:
		var prev_fluent := FluentButton.new()
		prev_fluent.text = "上一页"
		prev_fluent.variant = "FluentCompact"
		prev_fluent.minimum_height = 32.0
		prev_fluent.custom_minimum_size.x = 72
		prev_fluent.pressed.connect(func(): _change_page(-1))
		pager.add_child(prev_fluent)
		previous_button = prev_fluent
		page_label = Label.new()
		page_label.theme_type_variation = &"FluentSecondary"
		page_label.add_theme_font_size_override("font_size", Typography.STATUS)
		page_label.autowrap_mode = TextServer.AUTOWRAP_OFF
		page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		page_label.custom_minimum_size.x = 88
		pager.add_child(page_label)
		var next_fluent := FluentButton.new()
		next_fluent.text = "下一页"
		next_fluent.variant = "FluentCompact"
		next_fluent.minimum_height = 32.0
		next_fluent.custom_minimum_size.x = 72
		next_fluent.pressed.connect(func(): _change_page(1))
		pager.add_child(next_fluent)
		next_button = next_fluent
	else:
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
	resized.connect(func():
		if embedded_in_topbar and absf(size.x - target_dimensions.x) > 8.0:
			_queue_reflow()
	)
	get_window().size_changed.connect(_queue_reflow)
	if not embedded_in_topbar:
		_filter_entries()
		_reflow(0)
		hide()
	else:
		_load_local_entries()
		_filter_entries()
		_queue_reflow()

func set_query(value: String) -> void:
	if search != null:
		search.set_block_signals(true)
		search.text = value
		search.set_block_signals(false)
	_search_changed(value)

func query_text() -> String:
	return search.text if search != null else ""

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
	var bounds: Vector2 = get_viewport_rect().size if embedded_in_topbar else get_parent().size
	var width: float
	var panel_pad := 0.0 if embedded_in_topbar else BoardUiStyle.PANEL_PADDING * 2
	if embedded_in_topbar:
		slots.size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
		var parent_ctrl := get_parent() as Control
		var host_width: float = size.x if size.x > 64.0 else (parent_ctrl.size.x if parent_ctrl != null and parent_ctrl.size.x > 64.0 else bounds.x - 36.0)
		width = maxf(240.0, host_width)
	else:
		var start := minf(left_margin, maxf(16, bounds.x - 420))
		width = minf(BoardUiStyle.CREATION_PALETTE_WIDTH, maxf(0, bounds.x - start - 16))
	columns = maxi(1, int(floor((width - panel_pad - 16 + GAP) / (BoardUiStyle.CREATION_SLOT_WIDTH + GAP))))
	slots.columns = columns
	rendered_mode = preferences.creation_mode
	var paged := rendered_mode == "pages"
	previous_button.visible = paged and (not embedded_in_topbar or page_count > 1)
	next_button.visible = paged and (not embedded_in_topbar or page_count > 1)
	page_label.visible = paged and (not embedded_in_topbar or page_count > 1)
	var header_h := maxf(38.0 if fluent else BoardUiStyle.ACTION_HEIGHT, header.get_combined_minimum_size().y) if embedded_in_topbar else BoardUiStyle.ACTION_HEIGHT
	var overhead := panel_pad + header_h + (BoardUiStyle.ACTION_HEIGHT if paged else 20.0) + BoardUiStyle.CONTENT_GAP * 2 + additional_overhead
	var available := maxf(24, bounds.y - (72.0 if Mobile.enabled else (110.0 if embedded_in_topbar else 130.0)))
	var height_limit := minf(available, maxf(overhead + 24, available * maximum_height_ratio))
	var pixels: Vector2i = DisplayServer.window_get_size()
	var display_scale := maxf(0.25, minf(float(pixels.x) / maxf(1, bounds.x), float(pixels.y) / maxf(1, bounds.y)))
	var minimum_height := maxf(72.0, MIN_SLOT_HEIGHT / minf(1.0, display_scale)) if Mobile.enabled else MIN_SLOT_HEIGHT / minf(1.0, display_scale)
	var desired_rows := int(preferences.creation_rows)
	if embedded_in_topbar:
		var needed_rows := maxi(1, ceili(float(filtered.size()) / float(columns)))
		desired_rows = mini(desired_rows, needed_rows)
	actual_rows = clampi(int(floor((height_limit - overhead + GAP) / (minimum_height + GAP))), 1, desired_rows)
	slot_height = maxf(minimum_height, minf(BoardUiStyle.CREATION_SLOT_HEIGHT, floor((height_limit - overhead - GAP * (actual_rows - 1)) / actual_rows)))
	var inset_pad := float(T.MODAL_BODY_DRAW_INSET * 2) if _scroll_inset != null else 0.0
	var grid_height := 0.0
	if embedded_in_topbar and filtered.is_empty():
		grid_height = 0.0
	else:
		grid_height = minf(slot_height * actual_rows + GAP * (actual_rows - 1) + inset_pad, maxf(24, height_limit - overhead))
	compact_height = grid_height < slot_height and not (embedded_in_topbar and filtered.is_empty())
	scroll.visible = grid_height > 0.0 or not embedded_in_topbar
	scroll.custom_minimum_size.y = grid_height
	var capacity := columns * actual_rows
	page_count = maxi(1, ceili(float(filtered.size()) / capacity))
	page_index = clampi(int(anchor / capacity), 0, page_count - 1)
	if embedded_in_topbar:
		var show_pager := paged and page_count > 1
		previous_button.visible = show_pager
		next_button.visible = show_pager
		page_label.visible = show_pager
		pager.visible = show_pager
	_render_slots()
	var footer_visible := status.visible or pager.visible or not embedded_in_topbar
	footer.visible = footer_visible
	var effective_footer: float = (32.0 if pager.visible else (22.0 if status.visible else 0.0)) if embedded_in_topbar else (BoardUiStyle.ACTION_HEIGHT if paged else 20.0)
	var sep_total: float = (10.0 * (1.0 if grid_height > 0.0 else 0.0) + (10.0 if footer_visible else 0.0)) if embedded_in_topbar else float(BoardUiStyle.CONTENT_GAP * 2)
	var total_h: float = panel_pad + header_h + effective_footer + sep_total + additional_overhead + grid_height
	target_dimensions = Vector2(width, total_h)
	if embedded_in_topbar:
		custom_minimum_size.y = total_h
	else:
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
	var offset := page_index * capacity if rendered_mode == "pages" else 0
	var count: int
	if embedded_in_topbar:
		if rendered_mode == "pages":
			count = clampi(filtered.size() - offset, 0, capacity)
		else:
			count = filtered.size()
	else:
		count = capacity if rendered_mode == "pages" else maxi(capacity, ceili(float(filtered.size()) / columns) * columns)
	for index in range(count):
		var slot := Slot.new()
		slot.fluent = fluent
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
		status.text = "暂无已保存的高级棋子，可在定制 → 棋子库中创建" if (embedded_in_topbar and category == "advanced") else ""
	else:
		status.text = "%d 个自定义棋子" % custom_count
	status.tooltip_text = status.text + "；实际显示 %d 行，设置 %d 行。" % [actual_rows, preferences.creation_rows]
	status.add_theme_color_override("font_color", T.SECONDARY if fluent else Color("64748b"))
	if not library_error.is_empty():
		status.text = "棋子库读取失败" + (" · 内置棋子仍可用" if category == "basic" else "")
		status.tooltip_text = library_error
		status.add_theme_color_override("font_color", T.DANGER if fluent else Color("b33c3c"))
	elif not library_warnings.is_empty():
		status.text += " · %d 个文件未能读取" % library_warnings.size()
		status.tooltip_text += "\n" + "\n".join(PackedStringArray(library_warnings))
	if actual_rows < preferences.creation_rows and not filtered.is_empty() and ceili(float(filtered.size()) / float(columns)) > actual_rows:
		status.text += " · 当前 %d 行" % actual_rows
	status.visible = not status.text.is_empty()
	page_label.text = "第 %d / %d 页" % [page_index + 1, page_count]
	previous_button.disabled = page_index == 0
	next_button.disabled = page_index >= page_count - 1

func _position_layout() -> void:
	if embedded_in_topbar:
		return
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
	if not embedded_in_topbar:
		close()
	entry_chosen.emit(chosen)

func _settle_layout(expected_revision: int, anchor: int) -> void:
	if revision != expected_revision:
		return
	# Containers invalidate minimum sizes while rebuilding. Settle before drawing.
	if not embedded_in_topbar and (motion == null or not motion.is_valid()):
		size = target_dimensions
		_position_layout()
	_restore_scroll(expected_revision, anchor)
	if not embedded_in_topbar and reveal_pending and visible:
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

func switch_embedded_category(key: String) -> void:
	if not entries.has(key):
		return
	memory[category]["first"] = _visible_index()
	category = key
	if search != null:
		search.set_block_signals(true)
		search.text = memory[category]["query"]
		search.set_block_signals(false)
	if title != null:
		title.text = "基础棋子" if category == "basic" else "高级棋子"
	_refresh_category_switcher()
	_load_local_entries()
	_filter_entries()
	_reflow(int(memory[category]["first"]))
	state_changed.emit(category, visible)

func _refresh_category_switcher() -> void:
	if is_instance_valid(category_tabs):
		category_tabs.select_tab(category, false)

func open(margin: float, key: String) -> void:
	memory[category]["first"] = _visible_index()
	category = key
	left_margin = margin
	search.set_block_signals(true)
	search.text = memory[category]["query"]
	search.set_block_signals(false)
	title.text = "基础棋子" if category == "basic" else "高级棋子"
	_refresh_category_switcher()
	_load_local_entries()
	_filter_entries()
	show()
	if not embedded_in_topbar:
		get_parent().move_child(self, get_parent().get_child_count() - 1)
		reveal_pending = true
	_reflow(int(memory[category]["first"]))
	if not embedded_in_topbar:
		grab_focus()
		modulate.a = 0.0
	else:
		modulate.a = 1.0
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
	if not is_visible_in_tree():
		return
	var focused := get_viewport().gui_get_focus_owner()
	if event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE and focused != null and (focused == self or is_ancestor_of(focused)):
		if embedded_in_topbar:
			focused.release_focus()
		else:
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
	if kind!=expected or not is_visible_in_tree() or catalog_refresh_queued: return
	catalog_refresh_queued = true
	get_tree().create_timer(0.2).timeout.connect(_reload_catalog)
func _reload_catalog() -> void:
	catalog_refresh_queued = false
	if not is_visible_in_tree(): return
	var anchor := _visible_index()
	_load_local_entries()
	_filter_entries()
	_reflow(anchor)
