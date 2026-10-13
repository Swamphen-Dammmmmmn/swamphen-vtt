extends "res://ui/components/creation_palette.gd"
const Style = preload("res://ui/components/page_style.gd")
const CardMenu = preload("res://ui/components/card_menu.gd")
signal tray_action(action: String, id: String)
var values: Dictionary = {"dm":[],"public":[]}
var member_names: Dictionary = {}
var permitted_ids: Dictionary = {}
var personal_key := "dm"
var allowed_keys: Array = []
var chooser_keys: Array = []
var selected_id := ""
var chooser: OptionButton
var selected_label: Label
var place_button: Button
var transfer_button: Button
var more_button: Button
var options: CanvasLayer
var search_row: HBoxContainer
var compact_header := false
var selection_row: HBoxContainer

func _init() -> void:
	category = "dm"
	entries = {"dm":[],"public":[]}
	memory = {"dm":{"query":"","first":0},"public":{"query":"","first":0}}
	additional_overhead = 52.0
	maximum_height_ratio = 0.45

func _ready() -> void:
	super._ready()
	title.hide()
	chooser = OptionButton.new()
	chooser.add_item("DM 托盘")
	chooser.add_item("公共托盘")
	Style.button(chooser)
	header.add_child(chooser)
	header.move_child(chooser,0)
	chooser.item_selected.connect(func(index: int): open(left_margin,chooser_keys[index]))
	var add := Button.new()
	add.text = "从库添加"
	Style.button(add)
	header.add_child(add)
	header.move_child(add,header.get_child_count()-2)
	add.pressed.connect(func(): tray_action.emit("add",""))
	search_row = HBoxContainer.new()
	search_row.add_theme_constant_override("separation",8)
	get_child(0).add_child(search_row)
	get_child(0).move_child(search_row,1)
	search_row.hide()
	var row := HBoxContainer.new()
	selection_row = row
	row.add_theme_constant_override("separation",8)
	get_child(0).add_child(row)
	get_child(0).move_child(row,get_child(0).get_child_count()-2)
	selected_label = Style.text("",14,true)
	selected_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	selected_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	selected_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	selected_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(selected_label)
	place_button = _action_button(row,"放置","place",true)
	transfer_button = _action_button(row,"转移","transfer")
	more_button = _action_button(row,"⋯","")
	more_button.custom_minimum_size.x = 44
	options = CardMenu.new()
	add_child(options)
	options.add_action("编辑棋子",0)
	options.add_action("复制",1)
	options.add_action("删除…",2,false,true)
	more_button.pressed.connect(func(): options.toggle_for(more_button))
	options.action_requested.connect(func(index: int): tray_action.emit(["edit","copy","delete"][index],selected_id))
	_sync_selection()

func _reflow(anchor: int = -1) -> void:
	if is_instance_valid(search_row):
		var available: float = get_parent().size.x-minf(left_margin,maxf(16,get_parent().size.x-420))-16
		var compact := available<620
		if compact!=compact_header:
			compact_header = compact
			search.reparent(search_row if compact else header)
			clear_button.reparent(search_row if compact else header)
			if not compact:
				header.move_child(search,2)
				header.move_child(clear_button,3)
		search_row.visible = compact
		additional_overhead = (52.0 if compact else 0.0) + (52.0 if is_instance_valid(selection_row) and selection_row.visible else 0.0)
	super._reflow(anchor)

func _action_button(parent: Control, text: String, action: String, primary := false) -> Button:
	var button := Button.new()
	button.text = text
	Style.button(button,primary)
	parent.add_child(button)
	if not action.is_empty(): button.pressed.connect(func(): tray_action.emit(action,selected_id))
	return button

func refresh(data: Dictionary) -> void:
	values = data
	chooser_keys = []
	for key in values:
		if not allowed_keys.is_empty() and key not in allowed_keys: continue
		chooser_keys.append(key)
		if not memory.has(key): memory[key] = {"query":"","first":0}
	if category not in chooser_keys: category = chooser_keys[0]
	chooser.clear()
	for key in chooser_keys: chooser.add_item(tray_title(key))
	chooser.select(chooser_keys.find(category))
	_load_local_entries()
	_filter_entries()
	if not _selected_exists(): selected_id = ""
	_reflow()
	_sync_selection()

func _load_local_entries() -> void:
	for key in values:
		entries[key] = []
		for data: Dictionary in values[key]:
			entries[key].append({"id":data["id"],"title":data["title"],"parameters":data,"tooltip":data["title"]})

func _filter_entries() -> void:
	filtered.clear()
	if search==null: return
	var query := search.text.strip_edges().to_lower()
	for entry: Dictionary in entries[category]:
		if query.is_empty() or str(entry["title"]).to_lower().contains(query): filtered.append(entry)
	clear_button.disabled = search.text.is_empty()

func _render_slots() -> void:
	super._render_slots()
	status.text = "%d 枚棋子" % values[category].size() if not values[category].is_empty() else ""
	status.visible = not status.text.is_empty()
	status.tooltip_text = "实际显示%d行，设置%d行。" % [actual_rows,preferences.creation_rows]
	for slot in slots.get_children():
		if not slot.entry.is_empty():
			slot.toggle_mode = true
			slot.set_pressed_no_signal(slot.entry["id"]==selected_id)

func _choose_entry(data: Dictionary) -> void:
	selected_id = data["id"]
	for slot in slots.get_children(): slot.set_pressed_no_signal(slot.entry.get("id","")==selected_id)
	_sync_selection()

func _selected_exists() -> bool:
	for data: Dictionary in values[category]:
		if data["id"]==selected_id: return true
	return false

func _sync_selection() -> void:
	if selected_label==null: return
	transfer_button.text = "移至公共托盘" if category!="public" else "移至"+tray_title(personal_key)
	var found := false
	for data: Dictionary in values[category]:
		if data["id"]!=selected_id: continue
		found = true
		selected_label.text = "%s · HP %s · AC %s" % [data["title"],("%d/%d" % [data["hp"],data["max_hp"]]) if data["hp"]>=0 else "—",str(data["ac"]) if data["ac"]>=0 else "—"]
		selected_label.tooltip_text = selected_label.text
	if not found: selected_label.text = ""; selected_label.tooltip_text = ""
	if selection_row.visible != found:
		selection_row.visible = found
		_reflow()
	for button in [place_button,transfer_button,more_button]: button.disabled = not found or not permitted_ids.has(selected_id)

func open(margin: float, key: String) -> void:
	if key!=category: selected_id = ""
	super.open(margin,key)
	chooser.select(chooser_keys.find(category))
	_sync_selection()

func close() -> void:
	if is_instance_valid(options):
		options.close()
		options.hide()
	super.close()

func tray_title(key: String) -> String:
	if key=="dm": return "DM 托盘"
	if key=="public": return "公共托盘"
	return str(member_names.get(key.trim_prefix("member:"),"成员"))+"的托盘"
