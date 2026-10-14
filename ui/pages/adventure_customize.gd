extends VBoxContainer
const Style = preload("res://ui/components/page_style.gd")
const Data = preload("res://scripts/adventure_data.gd")
const Store = preload("res://scripts/adventure_library_store.gd")
const MapStore = preload("res://scripts/map_library_store.gd")
const MapEditor = preload("res://ui/pages/map_customize.gd")
const MapLibrary = preload("res://ui/pages/map_library.gd")
const Shell = preload("res://ui/components/page_shell.tscn")
const Modal = preload("res://ui/components/page_modal.gd")
const Rename = preload("res://ui/components/product_rename.gd")
const CardMenu = preload("res://ui/components/card_menu.gd")
signal return_requested
var page: Control
var values := Data.defaults()
var edit_id := ""
var saved_signature := ""
var name_input: LineEdit
var search: LineEdit
var grid: GridContainer
var empty: Label
var save_state: Label
var save_button: Button
var child_editor: Control
var picker: Control
var modal: Control
var accepted_leave := false
var saving := false
var returning_map := false
var current_save_state := "未保存"

func _ready() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_constant_override("separation",16)
	var row := Style.column(8)
	add_child(row)
	var name_label := Style.text("冒险名称",16)
	name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	row.add_child(name_label)
	name_input = LineEdit.new()
	name_input.text = values["title"]
	name_input.max_length = 60
	name_input.custom_minimum_size.y = 44
	name_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_input)
	name_input.text_changed.connect(func(text: String): values["title"] = text; _mark_unsaved())
	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation",12)
	add_child(header)
	search = LineEdit.new()
	search.placeholder_text = "搜索冒险内地图"
	search.custom_minimum_size.y = 44
	search.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	header.add_child(search)
	search.text_changed.connect(func(_text: String): _refresh())
	header.add_child(_button("添加地图",_pick_map,true))
	grid = GridContainer.new()
	grid.add_theme_constant_override("h_separation",12)
	grid.add_theme_constant_override("v_separation",12)
	add_child(grid)
	empty = Style.text("",18,true)
	add_child(empty)
	var header_actions := HBoxContainer.new()
	header_actions.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header_actions.add_theme_constant_override("separation",12)
	page.get_node("Layout/Header").add_child(header_actions)
	save_state = Style.text("",14,true)
	save_state.autowrap_mode = TextServer.AUTOWRAP_OFF
	save_state.custom_minimum_size.x = 64
	save_state.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	header_actions.add_child(save_state)
	save_button = _button("保存冒险",_save,true)
	header_actions.add_child(save_button)
	if not edit_id.is_empty(): saved_signature = Store.signature(values)
	resized.connect(_fit)
	_refresh()
	_mark_unsaved()

func _button(title: String, action: Callable, primary := false) -> Button:
	var button := Button.new()
	button.text = title
	Style.button(button,primary)
	button.pressed.connect(action)
	return button

func _refresh() -> void:
	for node in grid.get_children():
		grid.remove_child(node)
		node.queue_free()
	var query := search.text.strip_edges().to_lower()
	for item: Dictionary in values["maps"]:
		if query.is_empty() or str(item["data"]["title"]).to_lower().contains(query): _card(item)
	empty.visible = grid.get_child_count()==0
	empty.text = "" if values["maps"].is_empty() else "没有符合搜索的地图。"
	empty.visible = not empty.text.is_empty()
	_fit.call_deferred()

func _fit() -> void:
	grid.columns = maxi(1,floori((size.x+12)/252))
	for card in grid.get_children(): card.custom_minimum_size.x = maxf(220,(size.x-12*(grid.columns-1))/grid.columns)

func _card(item: Dictionary) -> void:
	var card := Style.card()
	card.custom_minimum_size.x = 240
	grid.add_child(card)
	var column := Style.column(10)
	card.add_child(column)
	var picture := TextureRect.new()
	picture.custom_minimum_size.y = 150
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var thumbnail: Image = item.get("thumbnail")
	if thumbnail!=null: picture.texture = ImageTexture.create_from_image(thumbnail)
	column.add_child(picture)
	var title := Style.text(item["data"]["title"],20)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.tooltip_text = title.text
	column.add_child(title)
	column.add_child(Style.text("%d 块地台" % item["data"]["platforms"].size(),14,true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	column.add_child(row)
	var edit := _button("编辑地图",func(): _edit_map(item))
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(edit)
	var more := _button("",func(): pass)
	GoStyle.apply_icon(more,GoIconSet.MORE,18)
	more.tooltip_text = "更多操作"
	more.custom_minimum_size.x = 44
	row.add_child(more)
	var options := CardMenu.new()
	card.add_child(options)
	options.add_action("重命名",0)
	var index: int = values["maps"].find(item)
	options.add_action("前移",1,index<=0)
	options.add_action("后移",2,index>=values["maps"].size()-1)
	options.add_action("移出冒险…",3,false,true)
	more.pressed.connect(func(): options.toggle_for(more))
	options.action_requested.connect(func(action: int):
		match action:
			0: _rename_map(item)
			1,2:
				var from: int = values["maps"].find(item)
				var to: int = from+(-1 if action==1 else 1)
				if to>=0 and to<values["maps"].size():
					values["maps"].remove_at(from)
					values["maps"].insert(to,item)
					_refresh()
					_mark_unsaved()
			3: _remove_map(item)
	)
	Style.Motion.fade_in(card,Style.Motion.NOTICE_FADE)

func _rename_map(item: Dictionary) -> void:
	modal = Rename.new()
	page.add_overlay(modal)
	modal.configure_product(item["data"]["title"],60,func(title: String):
		item["data"]["title"] = title
		return {"ok":true}
	)
	modal.name_saved.connect(func(): _refresh(); _mark_unsaved())

func _remove_map(item: Dictionary) -> void:
	modal = Modal.new()
	page.add_overlay(modal)
	modal.configure("移出冒险？","将“%s”及其中内容移出当前冒险，地图库原件不受影响。" % item["data"]["title"])
	modal.add_action("取消",modal.dismiss)
	modal.add_action("移出",func():
		values["maps"].erase(item)
		modal.dismiss()
		_refresh()
		_mark_unsaved()
	,false,true,true)

func _pick_map() -> void:
	if is_instance_valid(picker): return
	if values["maps"].size()>=64:
		_message("无法添加","当前冒险最多包含64张地图。")
		return
	picker = Control.new()
	page.add_overlay(picker)
	picker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Style.BACKGROUND
	picker.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shell := Shell.instantiate()
	picker.add_child(shell)
	shell.configure("添加地图","从地图库复制到冒险，后续修改与原件独立。")
	shell.back_requested.connect(_close_picker)
	var library := MapLibrary.new()
	library.page = shell
	library.selection_only = true
	shell.content.add_child(library)
	library.edit_requested.connect(func(id: String):
		var loaded := MapStore.get_record(id)
		if not loaded["ok"]:
			_message("无法添加",loaded["message"])
			return
		values["maps"].append(Data.import_map(loaded["record"]))
		_close_picker()
		_refresh()
		_mark_unsaved()
	)
	shell.reveal()

func _close_picker() -> void:
	if is_instance_valid(picker): picker.hide(); picker.queue_free()
	picker = null

func _edit_map(item: Dictionary) -> void:
	if is_instance_valid(child_editor): return
	child_editor = MapEditor.new()
	child_editor.page = page
	child_editor.values = item["data"]
	child_editor.edit_id = item["id"]
	child_editor.container_save_title = "保存到冒险库"
	child_editor.container_return_title = "返回冒险地图集"
	child_editor.container_product_name = func(): return values["title"]
	child_editor.save_state_provider = _save_status
	child_editor.external_blocked = func(): return returning_map or (is_instance_valid(modal) and modal.visible)
	child_editor.save_delegate = func(data: Dictionary, image: Image):
		item["data"] = data
		item["thumbnail"] = _small_preview(image)
		return _save()
	page.add_overlay(child_editor)
	child_editor.content_changed.connect(_mark_unsaved)
	child_editor._refresh_save_state()
	child_editor.return_requested.connect(func(): _return_map(item))

func _small_preview(image: Image) -> Image:
	if image==null or image.is_empty(): return null
	var small: Image = image.duplicate()
	var scale := minf(320.0/small.get_width(),200.0/small.get_height())
	small.resize(maxi(1,roundi(small.get_width()*scale)),maxi(1,roundi(small.get_height()*scale)),Image.INTERPOLATE_LANCZOS)
	return small

func _return_map(item: Dictionary) -> void:
	if returning_map or child_editor.saving: return
	if is_instance_valid(child_editor.platform_editor):
		child_editor._return_to_combination()
		return
	returning_map = true
	child_editor._cancel_operation()
	child_editor._release_camera()
	child_editor.preview.highlight("")
	var blocker := Control.new()
	page.add_overlay(blocker)
	blocker.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	child_editor.set_process_input(false)
	child_editor.set_process_unhandled_input(false)
	child_editor.set_process(false)
	await get_tree().process_frame
	await RenderingServer.frame_post_draw
	item["thumbnail"] = _small_preview(child_editor.preview.viewport.get_texture().get_image())
	item["data"] = child_editor.values
	child_editor.hide()
	child_editor.queue_free()
	child_editor = null
	blocker.queue_free()
	returning_map = false
	_refresh()
	_mark_unsaved()

func _mark_unsaved() -> void:
	current_save_state = "已保存" if not saved_signature.is_empty() and Store.signature(values)==saved_signature else "未保存"
	save_state.text = current_save_state
	if is_instance_valid(child_editor): child_editor._refresh_save_state()

func _save_status() -> String:
	return current_save_state

func _save() -> bool:
	if saving: return false
	var focused := get_viewport().gui_get_focus_owner()
	if focused!=null: focused.release_focus()
	saving = true
	save_button.disabled = true
	var result := Store.save(values,edit_id)
	saving = false
	save_button.disabled = false
	if not result["ok"]:
		current_save_state = "保存失败"
		save_state.text = "保存失败"
		if is_instance_valid(child_editor):
			child_editor.save_state.text = "保存失败"
			if is_instance_valid(child_editor.platform_editor): child_editor.platform_editor.save_state.text = "保存失败"
		_message("保存失败",result["message"])
		return false
	edit_id = result["id"]
	saved_signature = Store.signature(values)
	_mark_unsaved()
	return true

func _message(title: String, text: String) -> void:
	modal = Modal.new()
	page.add_overlay(modal)
	modal.configure(title,text)
	modal.add_action("继续编辑",modal.dismiss)

func has_unsaved_changes() -> bool:
	if is_instance_valid(child_editor) and child_editor.has_unsaved_changes(): return true
	if edit_id.is_empty() and values["maps"].is_empty() and values["title"] == "冒险": return false
	return saved_signature.is_empty() or Store.signature(values) != saved_signature

func guard_leave(action: Callable) -> bool:
	if saving or is_instance_valid(child_editor) or is_instance_valid(picker): return true
	if accepted_leave or (not saved_signature.is_empty() and Store.signature(values)==saved_signature): return false
	if edit_id.is_empty() and values["maps"].is_empty() and values["title"]=="冒险": return false
	if is_instance_valid(modal) and modal.visible: return true
	modal = Modal.new()
	page.add_overlay(modal)
	modal.configure("有未保存的修改","返回前是否保存冒险？")
	modal.add_action("继续编辑",modal.dismiss)
	modal.add_action("保存并返回",func():
		modal.dismiss()
		if _save(): accepted_leave = true; action.call()
	,true)
	modal.add_action("放弃修改并返回",func(): accepted_leave = true; modal.dismiss(); action.call(),false,true,true)
	return true

func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(child_editor) or (is_instance_valid(modal) and modal.visible): return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode==KEY_ESCAPE:
			if is_instance_valid(picker): _close_picker()
			else: return_requested.emit()
			get_viewport().set_input_as_handled()
		elif event.ctrl_pressed and event.keycode==KEY_S and not is_instance_valid(picker):
			_save()
			get_viewport().set_input_as_handled()
