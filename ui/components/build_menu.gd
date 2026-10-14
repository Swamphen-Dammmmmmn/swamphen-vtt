extends PanelContainer
const Style = preload("res://ui/components/page_style.gd")
const MenuScene = preload("res://ui/components/adventure_menu.tscn")
const PageScene = preload("res://ui/components/page_shell.tscn")
signal return_requested
signal menu_opened
var page: Control
var return_title := "返回产物库"
var modal: Control
var auxiliary: Control
var auxiliary_route := ""
var button: Button
var previous_focus: WeakRef
var save_title := ""
var product_title: Callable
signal save_requested
var save_button: Button
var state_label: Label
var menu_state: Label
var menu_product: Label
var last_state := ""
var saved_until := 0

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	offset_left = -140
	offset_right = -20
	offset_top = 18
	offset_bottom = 64
	add_theme_stylebox_override("panel",StyleBoxEmpty.new())
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	add_child(row)
	state_label = Style.text("",14,true)
	state_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	state_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	state_label.add_theme_stylebox_override("normal",BoardUiStyle.card_face(8))
	row.add_child(state_label)
	state_label.hide()
	button = Button.new()
	button.text = "菜单"
	button.tooltip_text = "编辑器菜单 · Esc"
	Style.button(button)
	GoStyle.apply_icon(button,GoIconSet.MENU,18)
	row.add_child(button)
	button.pressed.connect(open_menu)
	if not save_title.is_empty():
		save_button = Button.new()
		save_button.text = save_title
		Style.button(save_button,true)
		add_child(save_button)
		save_button.hide()
		save_button.pressed.connect(func(): save_requested.emit())
	row.minimum_size_changed.connect(func(): offset_left = -20-Mobile.margins.z-row.get_combined_minimum_size().x)

func open_menu() -> void:
	if is_instance_valid(modal): return
	menu_opened.emit()
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null: previous_focus = weakref(focused)
	modal = Control.new()
	page.add_overlay(modal)
	modal.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shade := ColorRect.new()
	shade.color = Color(0,0,0,0.28)
	modal.add_child(shade)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var menu := MenuScene.instantiate()
	modal.add_child(menu)
	menu.configure_editor(return_title)
	if is_instance_valid(save_button):
		menu_product = Style.text(str(product_title.call()) if product_title.is_valid() else "",18)
		menu_product.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		menu_product.autowrap_mode = TextServer.AUTOWRAP_OFF
		menu.content.add_child(menu_product)
		menu.content.move_child(menu_product,1)
		menu_state = Style.text(state_label.text,14,true)
		menu.content.add_child(menu_state)
		menu.content.move_child(menu_state,2)
		save_button.reparent(menu.content)
		menu.content.move_child(save_button,3)
		save_button.show()
	menu.action_requested.connect(func(action: String):
		match action:
			"resume": _close_menu()
			"return_library":
				_close_menu()
				return_requested.emit()
			"tutorials","settings": _show_auxiliary(action)
	)

func _close_menu() -> void:
	if is_instance_valid(save_button):
		save_button.hide()
		if save_button.get_parent()!=self: save_button.reparent(self)
	menu_state = null
	menu_product = null
	if is_instance_valid(auxiliary):
		auxiliary.hide()
		auxiliary.queue_free()
	auxiliary = null
	if is_instance_valid(modal):
		modal.hide()
		modal.queue_free()
	modal = null
	if previous_focus != null:
		var focused = previous_focus.get_ref()
		if is_instance_valid(focused) and focused.is_visible_in_tree(): focused.grab_focus()

func _show_auxiliary(route: String, detail := "") -> void:
	if is_instance_valid(auxiliary):
		auxiliary.hide()
		auxiliary.queue_free()
	auxiliary_route = route
	auxiliary = Control.new()
	page.add_overlay(auxiliary)
	auxiliary.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Style.BACKGROUND
	auxiliary.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var shell := PageScene.instantiate()
	auxiliary.add_child(shell)
	# Load after editor construction to avoid a preload cycle through MenuPages.
	var pages = load("res://ui/pages/menu_pages.gd")
	pages.populate(shell,route,detail,false)
	shell.navigation_requested.connect(func(destination: String, next_detail: String):
		if destination in ["tutorials","tutorial","settings"]: _show_auxiliary(destination,next_detail)
	)
	shell.back_requested.connect(_back_auxiliary)
	shell.reveal()

func _back_auxiliary() -> void:
	if auxiliary_route == "tutorial":
		_show_auxiliary("tutorials")
	elif is_instance_valid(auxiliary):
		auxiliary.hide()
		auxiliary.queue_free()
		auxiliary = null

func handle_escape() -> void:
	if is_instance_valid(auxiliary): _back_auxiliary()
	elif is_open(): _close_menu()
	else: open_menu()

func is_open() -> bool:
	return is_instance_valid(modal) and modal.visible

func _process(_delta: float) -> void:
	if not is_instance_valid(state_label): return
	if Mobile.enabled:
		offset_right = -20-Mobile.margins.z
		offset_left = offset_right-get_child(0).get_combined_minimum_size().x
		offset_top = 18+Mobile.margins.y
		offset_bottom = offset_top+48
	var state := state_label.text
	if state!=last_state:
		last_state = state
		saved_until = Time.get_ticks_msec()+2500 if state=="已保存" else 0
		state_label.add_theme_color_override("font_color",Color("b33c3c") if state=="保存失败" else Color("64748b"))
	state_label.visible = not state.is_empty() and (state!="已保存" or Time.get_ticks_msec()<saved_until)
	if is_instance_valid(menu_state):
		menu_state.text = state
		menu_state.add_theme_color_override("font_color",Color("b33c3c") if state=="保存失败" else Color("64748b"))
	if is_instance_valid(menu_product) and product_title.is_valid(): menu_product.text = str(product_title.call())
