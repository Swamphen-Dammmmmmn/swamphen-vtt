extends VBoxContainer
const Style = preload("res://ui/components/page_style.gd")
const Store = preload("res://scripts/platform_library_store.gd")
const Rename = preload("res://ui/components/product_rename.gd")
const Modal = preload("res://ui/components/page_modal.gd")
const CardMenu = preload("res://ui/components/card_menu.gd")
signal create_requested
signal edit_requested(id: String)
var page: Control
var search: LineEdit
var grid: GridContainer
var note: Label
var empty: Label
var entries: Array = []

func _ready() -> void:
	ProductCatalog.changed.connect(_catalog_changed)
	add_theme_constant_override("separation",12)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation",12)
	add_child(header)
	search = LineEdit.new()
	search.placeholder_text = "搜索地台名称"
	search.custom_minimum_size.y = 44
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(search)
	search.text_changed.connect(func(_text: String): _refresh())
	var create := Button.new()
	create.text = "创建地台"
	Style.button(create,true)
	header.add_child(create)
	create.pressed.connect(func(): create_requested.emit())
	note = Style.text("",14,true)
	add_child(note)
	grid = GridContainer.new()
	grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_theme_constant_override("h_separation",12)
	grid.add_theme_constant_override("v_separation",12)
	add_child(grid)
	empty = Style.text("",20,true)
	add_child(empty)
	resized.connect(_fit)
	reload()

func reload() -> void:
	var loaded := Store.read_catalog()
	entries = loaded["entries"]
	print("地台库：%s，有效记录 %d，读取失败 %d" % [ProjectSettings.globalize_path(Store.DIRECTORY),entries.size(),loaded["warnings"].size()])
	for warning: String in loaded["warnings"]: push_warning(warning)
	note.text = loaded["error"]
	if not loaded["warnings"].is_empty():
		note.text += "有%d个地台未能读取，其他地台仍可使用；原文件已保留。" % loaded["warnings"].size()
	note.tooltip_text = "\n".join(PackedStringArray(loaded["warnings"]))
	note.visible = not note.text.is_empty()
	_refresh()
	if not loaded["error"].is_empty(): empty.hide()

func _refresh() -> void:
	for child in grid.get_children():
		grid.remove_child(child)
		child.queue_free()
	var query := search.text.strip_edges().to_lower()
	for record: Dictionary in entries:
		if not query.is_empty() and not str(record["title"]).to_lower().contains(query): continue
		_card(record)
	empty.visible = grid.get_child_count()==0
	empty.text = "" if entries.is_empty() else "没有符合搜索的地台。"
	empty.visible = not empty.text.is_empty()
	_fit.call_deferred()

func _card(record: Dictionary) -> void:
	var card := Style.card()
	card.custom_minimum_size.x = 220
	card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	grid.add_child(card)
	var column := Style.column(10)
	card.add_child(column)
	var picture := TextureRect.new()
	picture.custom_minimum_size.y = 150
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ProductCatalog.request_preview(record,picture)
	column.add_child(picture)
	var title := Style.text(record["title"],20)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.tooltip_text = record["title"]
	column.add_child(title)
	var data: Dictionary = record["summary"]
	if not record.get("pending",false):
		column.add_child(Style.text("%d × %d 英尺 · 厚 %d 英尺" % [data.get("width_feet",0),data.get("length_feet",0),data.get("thickness_feet",0)],14,true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	column.add_child(row)
	var edit := Button.new()
	edit.text = "编辑"
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Style.card_button(edit)
	row.add_child(edit)
	edit.pressed.connect(func(): edit_requested.emit(record["id"]))
	var more := Button.new()
	GoStyle.apply_icon(more,GoIconSet.MORE,18)
	more.tooltip_text = "更多操作"
	more.custom_minimum_size.x = 44
	Style.card_button(more)
	row.add_child(more)
	var menu := CardMenu.new()
	card.add_child(menu)
	menu.add_action("重命名",2)
	menu.add_action("复制",0)
	menu.add_action("删除…",1,false,true)
	more.pressed.connect(func(): menu.toggle_for(more))
	menu.action_requested.connect(func(action: int):
		if action==2:
			var modal := Rename.new()
			page.add_overlay(modal)
			modal.configure_product(record["title"],60,func(title: String): return Store.rename(record["id"],title))
			modal.name_saved.connect(reload)
		elif action==0:
			var result := Store.copy(record["id"])
			if result["ok"]: reload()
			else: _message("复制失败",result["message"])
		else: _delete(record)
	)
	Style.Motion.fade_in(card,Style.Motion.NOTICE_FADE)

func _delete(record: Dictionary) -> void:
	var modal := Modal.new()
	page.add_overlay(modal)
	modal.configure("删除地台？","删除“%s”后将从地台库移除，已经导入地图的独立副本不受影响。" % record["title"])
	modal.add_action("取消",modal.dismiss)
	modal.add_action("删除",func():
		var result := Store.delete(record["id"])
		modal.dismiss()
		if result["ok"]: reload()
		else: _message("删除失败",result["message"])
	,false,true,true)

func _message(title: String, message: String) -> void:
	var modal := Modal.new()
	page.add_overlay(modal)
	modal.configure(title,message)
	modal.add_action("返回地台库",modal.dismiss)

func _fit() -> void:
	grid.columns = maxi(1,floori((size.x+12)/(220+12)))


var catalog_refresh_queued := false
func _catalog_changed(kind: String) -> void:
	if kind!="platforms" or catalog_refresh_queued or not is_visible_in_tree(): return
	catalog_refresh_queued = true
	get_tree().create_timer(0.2).timeout.connect(_reload_catalog)
func _reload_catalog() -> void:
	catalog_refresh_queued = false
	reload()
