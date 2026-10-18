extends CanvasLayer
signal action_requested(id: int)
const MenuTheme = preload("res://ui/theme/themes/command_menu_theme.gd")
var anchor: Control
var is_open := false
var fluent := false
var reference_style := false
var _popup: PopupMenu
var _dispatching := false
var _native_button: MenuButton

func _ready() -> void:
	add_to_group("token_card_menus")
	_popup = PopupMenu.new()
	add_child(_popup)
	_setup_popup()
	get_viewport().size_changed.connect(close)
	if Mobile.enabled: Mobile.changed.connect(close)

func _setup_popup() -> void:
	_popup.prefer_native_menu = false
	_popup.theme = MenuTheme.shared(fluent,reference_style,Mobile.enabled)
	_popup.id_pressed.connect(_activate)
	_popup.popup_hide.connect(_closed)

func bind_button(button: MenuButton) -> void:
	# Bind before adding actions; MenuButton handles mouse/keyboard opening itself.
	assert(_popup.item_count==0)
	_popup.queue_free()
	_native_button = button
	anchor = button
	_popup = button.get_popup()
	_setup_popup()
	button.about_to_popup.connect(func(): _popup.reset_size())
	_popup.about_to_popup.connect(_native_opened)

func _native_opened() -> void:
	for menu in get_tree().get_nodes_in_group("token_card_menus"):
		if menu!=self: menu.close()
	is_open = true
	# MenuButton applies the native viewport/screen transform before this signal.
	var at := _popup.position
	at.x = roundi((anchor.get_screen_transform()*Vector2(anchor.size.x,0)).x)-_popup.size.x
	_popup.position = at


func add_action(title: String, id: int, disabled := false, danger := false) -> void:
	_popup.add_item(title,id)
	var index := _popup.item_count-1
	_popup.set_item_disabled(index,disabled)
	if danger:
		_popup.set_item_icon(index,load("res://ui/theme/icons/library/trash.svg"))
		_popup.set_item_icon_max_width(index,14)
		_popup.set_item_icon_modulate(index,Color("b33c3c"))

func toggle_for(button: Control) -> void:
	if is_instance_valid(_native_button):
		if is_open: close()
		else: _native_button.show_popup()
		return
	if is_open:
		close()
		return
	for menu in get_tree().get_nodes_in_group("token_card_menus"):
		if menu!=self: menu.close()
	anchor = button
	show()
	_popup.theme = MenuTheme.shared(fluent,reference_style,Mobile.enabled)
	var bounds := Mobile.safe_rect(get_viewport().get_visible_rect().size) if Mobile.enabled else get_viewport().get_visible_rect()
	_popup.max_size = Vector2i(maxi(1,int(bounds.size.x-16)),maxi(1,int(bounds.size.y-16)))
	# Native text/icon measurement determines width; no fixed minimum or manual menu rows.
	_popup.reset_size()
	var dimensions := Vector2(_popup.size)
	var rect := button.get_global_rect()
	var at := Vector2(rect.end.x-dimensions.x,rect.end.y+6)
	if at.y+dimensions.y>bounds.end.y-8: at.y = rect.position.y-dimensions.y-6
	at.x = clampf(at.x,bounds.position.x+8,maxf(bounds.position.x+8,bounds.end.x-dimensions.x-8))
	at.y = clampf(at.y,bounds.position.y+8,maxf(bounds.position.y+8,bounds.end.y-dimensions.y-8))
	is_open = true
	_popup.popup(Rect2i(Vector2i(at.round()),Vector2i(dimensions)))

func close() -> void:
	if is_instance_valid(_popup): _popup.hide()
	is_open = false

func _closed() -> void:
	is_open = false
	if not _dispatching and is_instance_valid(anchor) and anchor.is_visible_in_tree() and anchor.focus_mode==Control.FOCUS_ALL: anchor.grab_focus()

func _activate(id: int) -> void:
	_dispatching = true
	_popup.hide()
	is_open = false
	action_requested.emit(id)
	_dispatching = false
