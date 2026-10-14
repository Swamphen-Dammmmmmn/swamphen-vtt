extends PanelContainer
const Style = preload("res://ui/components/page_style.gd")
const Layout = preload("res://ui/components/editor_layout.gd")
const EXPANDED_WIDTH := 152.0
const COLLAPSED_WIDTH := 104.0
signal tool_selected(key: String)
signal category_changed(key: String)
signal layout_changed
var expanded := true
var body: VBoxContainer
var scroll: ScrollContainer
var buttons: Dictionary = {}
var collapse: Button
var fold_tween: Tween
var category_index := 0
var categories := ["地台","物件"]
var defaults := ["select","object_select"]
var category_buttons: Array[Button] = []
var picker: PopupMenu
var previous: Button
var next: Button
var page_number: Label

func _ready() -> void:
	add_theme_stylebox_override("panel",BoardUiStyle.card_face(8))
	var column := Style.column(8)
	add_child(column)
	collapse = Button.new()
	Style.card_button(collapse)
	column.add_child(collapse)
	collapse.pressed.connect(func(): set_expanded(not expanded))
	var category_host := VBoxContainer.new()
	column.add_child(category_host)
	picker = PopupMenu.new()
	add_child(picker)
	for index in range(categories.size()):
		picker.add_item(categories[index],index)
		var button := Button.new()
		button.text = categories[index]
		Style.card_button(button,36)
		GoStyle.apply_icon(button,[GoIconSet.MAP,GoIconSet.TARGET][index],18)
		category_host.add_child(button)
		button.pressed.connect(_open_picker)
		category_buttons.append(button)
	picker.id_pressed.connect(_change_category)
	var paging := HBoxContainer.new()
	paging.add_theme_constant_override("separation",2)
	column.add_child(paging)
	previous = _arrow(false)
	paging.add_child(previous)
	previous.pressed.connect(func(): _change_category(category_index-1))
	page_number = Style.text("",12,true)
	page_number.autowrap_mode = TextServer.AUTOWRAP_OFF
	page_number.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_number.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	page_number.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	paging.add_child(page_number)
	next = _arrow(true)
	paging.add_child(next)
	next.pressed.connect(func(): _change_category(category_index+1))
	column.add_child(HSeparator.new())
	scroll = ScrollContainer.new()
	column.add_child(scroll)
	Layout.scroll(scroll)
	body = Style.column(8)
	scroll.add_child(body)
	_build_body()
	_update_header()

func _arrow(right: bool) -> Button:
	var button := Button.new()
	Style.card_button(button,32)
	button.icon = preload("res://ui/icons/chevron_right.svg") if right else preload("res://ui/icons/chevron_left.svg")
	button.expand_icon = true
	button.add_theme_constant_override("icon_max_width",14)
	button.custom_minimum_size.x = 28
	# Compact page arrows still retain the shared border and corner radius.
	for state in ["normal","hover","pressed","hover_pressed","disabled"]:
		var face := button.get_theme_stylebox(state).duplicate() as StyleBoxFlat
		face.content_margin_left = 4
		face.content_margin_right = 4
		button.add_theme_stylebox_override(state,face)
	return button

func _button(title: String, icon: StringName, parent: Control) -> Button:
	var button := Button.new()
	button.text = title
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Style.card_button(button)
	GoStyle.apply_icon(button,icon,18)
	parent.add_child(button)
	return button

func _build_body() -> void:
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	buttons.clear()
	var items: Array
	match category_index:
		0: items = [["select","地台属性",GoIconSet.TARGET,true],["expand","扩展",GoIconSet.EXPAND,true],["paint","地面绘制",GoIconSet.EDIT,true],["landing","摆放区域",GoIconSet.MAP,true]]
		1: items = [["object_select","选择物件",GoIconSet.TARGET,true],["token_basic","基础棋子",GoIconSet.PLUS,true],["token_advanced","高级棋子",GoIconSet.PLUS,true],["scenery_create","创建景观",GoIconSet.PLUS,false],["floor_create","铺设地板",GoIconSet.MAP,false],["wall_create","搭建墙壁",GoIconSet.MAP,false]]
	var group := ButtonGroup.new()
	if Mobile.enabled: items.append(["mobile_camera","镜头",GoIconSet.TARGET,true])
	for item in items:
		var button := _button(item[1],item[2],body)
		button.toggle_mode = true
		button.button_group = group
		button.disabled = not item[3]
		button.tooltip_text = "待接入" if button.disabled else ""
		button.button_pressed = item[0]==defaults[category_index]
		buttons[item[0]] = button
		button.pressed.connect(func(): tool_selected.emit(item[0]))

func _change_category(index: int) -> void:
	if index<0 or index>=categories.size() or index==category_index: return
	category_index = index
	_build_body()
	_update_header()
	if expanded: Style.Motion.fade_in(body,0.12)
	category_changed.emit(defaults[index])
	layout_changed.emit()

func _open_picker() -> void:
	var button := category_buttons[category_index]
	picker.position = Vector2i(button.get_global_rect().position+Vector2(0,button.size.y))
	picker.reset_size()
	picker.popup()

func _update_header() -> void:
	collapse.text = "收起" if expanded else ""
	collapse.icon = preload("res://ui/icons/chevron_left.svg") if expanded else preload("res://ui/icons/chevron_right.svg")
	collapse.expand_icon = true
	collapse.add_theme_constant_override("icon_max_width",20)
	for i in range(category_buttons.size()):
		category_buttons[i].visible = i==category_index
		category_buttons[i].text = categories[i] if expanded else ""
		category_buttons[i].tooltip_text = categories[i]+" · 切换分类"
	previous.disabled = category_index==0
	next.disabled = category_index==categories.size()-1
	page_number.text = "%d/%d" % [category_index+1,categories.size()]

func toolbar_width() -> float:
	return EXPANDED_WIDTH if expanded else COLLAPSED_WIDTH

func fit(available_height: float) -> void:
	var fixed := 44+36+32+8+16+4*8
	scroll.custom_minimum_size.y = minf(body.get_combined_minimum_size().y,maxf(1,available_height-fixed))
	size = Vector2(toolbar_width(),0)

func set_expanded(active: bool) -> void:
	if expanded==active: return
	if fold_tween!=null and fold_tween.is_valid(): fold_tween.kill()
	expanded = active
	_update_header()
	if active:
		scroll.show()
		scroll.modulate.a = 0
		Layout.enabled(scroll,true)
		layout_changed.emit()
	else:
		Layout.enabled(scroll,false)
	fold_tween = create_tween().set_parallel(true)
	for node in [scroll]: fold_tween.tween_property(node,"modulate:a",1.0 if active else 0.0,Style.Motion.duration(0.16))
	fold_tween.finished.connect(func():
		scroll.visible = expanded
		layout_changed.emit()
	)

func is_popup_open() -> bool:
	return picker!=null and picker.visible
