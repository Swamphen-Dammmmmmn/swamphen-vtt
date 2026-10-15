extends VBoxContainer

signal create_requested
signal edit_requested(id: String)
signal delete_requested(data: Dictionary)
signal copy_requested(id: String)
signal rename_requested(id: String)
signal tags_requested(id: String)
signal upgrade_requested(id: String)

const Style = preload("res://ui/components/page_style.gd")
const Card = preload("res://ui/components/token_library_card.gd")
var entries: Array[Dictionary] = []
var selection_only := false
var error_message := ""
var selected_kind := "all"
var selected_tag := ""
var search: LineEdit
var tags: OptionButton
var grid: GridContainer
var summary: Label
var warning_label: Label
var empty_panel: PanelContainer
var empty_title: Label
var empty_detail: Label
var reset_button: Button
var type_buttons: Dictionary = {}

func _ready() -> void:
	ProductCatalog.changed.connect(_catalog_changed)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation", Style.ITEM_GAP)
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", Style.ITEM_GAP)
	add_child(header)
	search = LineEdit.new()
	search.placeholder_text = "搜索棋子名称"
	search.max_length = 80
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search.custom_minimum_size.y = Style.BUTTON_HEIGHT
	header.add_child(search)
	var create := Button.new()
	create.text = "创建棋子"
	Style.button(create, true)
	create.pressed.connect(func(): create_requested.emit())
	header.add_child(create)
	create.visible = not selection_only
	BoardUiStyle.style_controls(search, Style.BUTTON_HEIGHT)
	var filters := HFlowContainer.new()
	filters.add_theme_constant_override("h_separation", 8)
	filters.add_theme_constant_override("v_separation", 8)
	add_child(filters)
	for item in [["all", "全部类型"], ["basic", "基础棋子"], ["advanced", "高级棋子"]]:
		var key: String = item[0]
		var button := Button.new()
		button.text = item[1]
		button.toggle_mode = true
		button.pressed.connect(func():
			selected_kind = key
			_refresh()
		)
		filters.add_child(button)
		type_buttons[key] = button
	tags = OptionButton.new()
	tags.fit_to_longest_item = false
	tags.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	tags.custom_minimum_size.x = 160
	filters.add_child(tags)
	BoardUiStyle.style_controls(filters, Style.BUTTON_HEIGHT)
	tags.item_selected.connect(func(index: int):
		selected_tag = "" if index == 0 else str(tags.get_item_metadata(index))
		_refresh()
	)
	search.text_changed.connect(func(_value: String): _refresh())
	warning_label = Style.text("", 14)
	warning_label.add_theme_color_override("font_color", Color("b33c3c"))
	warning_label.hide()
	add_child(warning_label)
	summary = Style.text("", 14, true)
	add_child(summary)
	grid = GridContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation", Style.ITEM_GAP)
	grid.add_theme_constant_override("v_separation", Style.ITEM_GAP)
	add_child(grid)
	empty_panel = Style.card()
	add_child(empty_panel)
	var empty_content := Style.column(16)
	empty_panel.add_child(empty_content)
	empty_title = Style.text("", 24)
	empty_content.add_child(empty_title)
	empty_detail = Style.text("", 16, true)
	empty_content.add_child(empty_detail)
	reset_button = Button.new()
	reset_button.text = "清除搜索和筛选"
	Style.button(reset_button)
	reset_button.pressed.connect(_reset_filters)
	empty_content.add_child(reset_button)
	get_parent().get_parent().resized.connect(_fit_grid)
	resized.connect(_fit_grid)
	set_entries(entries,error_message)

# The local storage step supplies validated records; no demo assets or file writes here.
func set_entries(data: Array[Dictionary], read_error := "", warnings: Array = []) -> void:
	entries = data.duplicate(true)
	error_message = read_error
	if tags == null:
		return
	warning_label.visible = not warnings.is_empty()
	warning_label.text = "有 %d 个棋子文件未能读取；其他棋子仍可使用，原文件已保留。" % warnings.size()
	warning_label.tooltip_text = "\n".join(PackedStringArray(warnings))
	preload("res://ui/components/editor_layout.gd").error_details(warning_label)
	var available: Array[String] = []
	for entry in entries:
		for tag in entry.get("tags", []):
			if not str(tag).is_empty() and not available.has(str(tag)):
				available.append(str(tag))
	available.sort()
	tags.clear()
	tags.add_item("全部分类标签")
	for tag in available:
		tags.add_item(tag)
		tags.set_item_metadata(tags.item_count - 1, tag)
	if not selected_tag.is_empty() and not available.has(selected_tag):
		selected_tag = ""
	tags.select(0 if selected_tag.is_empty() else available.find(selected_tag) + 1)
	tags.disabled = available.is_empty()
	_refresh()

func _reset_filters() -> void:
	search.text = ""
	selected_kind = "all"
	selected_tag = ""
	tags.select(0)
	_refresh()

func _refresh() -> void:
	for key in type_buttons:
		var button: Button = type_buttons[key]
		button.set_pressed_no_signal(key == selected_kind)
		BoardUiStyle.action_button(button, Style.BUTTON_HEIGHT, key == selected_kind)
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	var query := search.text.strip_edges().to_lower()
	var count := 0
	if error_message.is_empty():
		for entry in entries:
			if selected_kind != "all" and entry["kind"] != selected_kind:
				continue
			if not query.is_empty() and not str(entry["title"]).to_lower().contains(query):
				continue
			if not selected_tag.is_empty() and not entry.get("tags", []).has(selected_tag):
				continue
			var card := Card.new()
			card.selection_only = selection_only
			grid.add_child(card)
			card.configure(entry)
			card.edit_requested.connect(func(id: String): edit_requested.emit(id))
			card.delete_requested.connect(func(data: Dictionary): delete_requested.emit(data))
			card.copy_requested.connect(func(id: String): copy_requested.emit(id))
			card.rename_requested.connect(func(id: String): rename_requested.emit(id))
			card.tags_requested.connect(func(id: String): tags_requested.emit(id))
			card.upgrade_requested.connect(func(id: String): upgrade_requested.emit(id))
			count += 1
	grid.visible = count > 0
	empty_panel.visible = count == 0
	reset_button.visible = error_message.is_empty() and (not query.is_empty() or selected_kind != "all" or not selected_tag.is_empty())
	if not error_message.is_empty():
		empty_title.text = "棋子库读取失败"
		empty_detail.text = error_message + "\n原有文件不会在此页面被覆盖。"
		summary.text = "无法展示本地棋子"
	elif entries.is_empty():
		empty_title.text = "尚未保存棋子"
		empty_detail.text = ""
		empty_panel.hide()
		summary.text = "0 个本地棋子"
	else:
		empty_title.text = "没有符合条件的棋子"
		empty_detail.text = ""
		summary.text = "显示 %d / %d 个棋子" % [count, entries.size()]
	empty_detail.visible = not empty_detail.text.is_empty()
	_fit_grid.call_deferred()

func _fit_grid() -> void:
	if grid == null:
		return
	var gap := float(Style.ITEM_GAP)
	var available := maxf(1, get_parent().get_parent().size.x - 16)
	grid.columns = maxi(1, int(floor((available + gap) / (Style.LIBRARY_CARD_WIDTH + gap))))
	var card_width := minf(Style.LIBRARY_CARD_WIDTH, available)
	for card in grid.get_children():
		card.custom_minimum_size.x = card_width

var catalog_refresh_queued := false
func _catalog_changed(kind: String) -> void:
	if kind!="tokens" or catalog_refresh_queued or not is_visible_in_tree(): return
	catalog_refresh_queued = true
	get_tree().create_timer(0.2).timeout.connect(_reload_catalog)
func _reload_catalog() -> void:
	catalog_refresh_queued = false
	var loaded: Dictionary = load("res://scripts/token_library_store.gd").read_catalog()
	var records: Array[Dictionary] = []
	for record in loaded.entries: records.append(record)
	set_entries(records,loaded.error,loaded.warnings)
