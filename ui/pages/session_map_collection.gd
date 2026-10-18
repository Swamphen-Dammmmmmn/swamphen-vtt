extends VBoxContainer

const Typography = preload("res://ui/theme/typography.gd")
const Style = preload("res://ui/components/page_style.gd")
signal map_chosen(id: String)
var entries: Array = []
var current_id := ""
var network: Node
var party: Dictionary = {}
var host_mode := true
var search: LineEdit
var grid: GridContainer
var empty: Label

func _ready() -> void:
	add_theme_constant_override("separation",16)
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	search = LineEdit.new()
	search.placeholder_text = "搜索冒险内地图"
	search.custom_minimum_size.y = 44
	add_child(search)
	search.text_changed.connect(func(_text: String): _refresh())
	grid = GridContainer.new()
	grid.add_theme_constant_override("h_separation",12)
	grid.add_theme_constant_override("v_separation",12)
	add_child(grid)
	empty = Style.text("",Typography.SUBTITLE,true)
	add_child(empty)
	resized.connect(_fit)
	_refresh()

func _refresh() -> void:
	for node in grid.get_children(): grid.remove_child(node); node.queue_free()
	for item: Dictionary in entries:
		if not search.text.strip_edges().is_empty() and not str(item["data"]["title"]).to_lower().contains(search.text.strip_edges().to_lower()): continue
		var card := Style.card()
		card.custom_minimum_size.x = 220
		grid.add_child(card)
		var column := Style.column(10)
		card.add_child(column)
		var image := TextureRect.new()
		image.custom_minimum_size.y = 150
		image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		if item.get("thumbnail")!=null: image.texture = ImageTexture.create_from_image(item["thumbnail"])
		column.add_child(image)
		var title := Style.text(item["data"]["title"],Typography.SECTION)
		title.autowrap_mode = TextServer.AUTOWRAP_OFF
		title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		title.tooltip_text = title.text
		column.add_child(title)
		column.add_child(Style.text("当前地图" if item["id"]==current_id else "%d 块地台" % item["data"]["platforms"].size(),Typography.CAPTION,true))
		var people: Array[String] = []
		for member in party.get("positions",{}):
			if party["positions"][member]==item["id"] and (member=="dm" or (is_instance_valid(network) and member in (network.peer_members.values() if host_mode else network.online_members))):
				people.append(str(party["members"][member]["nickname"]))
		if not people.is_empty(): column.add_child(Style.text(" · ".join(people),Typography.CAPTION,true))
		if host_mode and is_instance_valid(network) and network.active:
			var visible := CheckButton.new()
			visible.text = "向PL开放"
			visible.set_pressed_no_signal(item["id"] in network.accessible)
			Style.button(visible)
			column.add_child(visible)
			visible.toggled.connect(func(value: bool): network.set_map_access(item["id"],value))
			var locked := CheckButton.new()
			locked.text = "锁定PL操作"
			locked.set_pressed_no_signal(item["id"] in network.locked)
			Style.button(locked)
			column.add_child(locked)
			locked.toggled.connect(func(value: bool): network.set_map_locked(item["id"],value))
		var button := Button.new()
		button.text = "返回当前地图" if item["id"]==current_id else "进入地图"
		Style.button(button,item["id"]==current_id)
		column.add_child(button)
		button.pressed.connect(func(): map_chosen.emit(item["id"]))
		Style.Motion.fade_in(card)
	empty.visible = grid.get_child_count()==0
	empty.text = "这个冒险还没有地图，请先在冒险库添加地图。" if entries.is_empty() else "没有符合搜索的地图。"
	_fit.call_deferred()

func _fit() -> void:
	grid.columns = maxi(1,floori((size.x+12)/232))
