extends MarginContainer

const Style = preload("res://ui/components/page_style.gd")
signal action_requested(action: String)
var panel: PanelContainer
var scroll: ScrollContainer
var content: VBoxContainer

func _ready() -> void:
	theme = GoUi.theme()
	for edge in ["left", "right", "top", "bottom"]:
		add_theme_constant_override("margin_" + edge, 32)
	var center := CenterContainer.new()
	add_child(center)
	panel = Style.card()
	center.add_child(panel)
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(scroll)
	content = Style.column(12)
	scroll.add_child(content)
	resized.connect(_fit)
	content.minimum_size_changed.connect(func(): _fit.call_deferred())
	_fit.call_deferred()

var save_notice: Label

func configure(role: String, confirming := false, title := "冒险") -> void:
	content.add_child(Style.text("保存并结束团" if confirming else "冒险菜单",24))
	content.add_child(Style.text(title+" · "+("DM" if role=="dm" else "PL"),14,true))
	save_notice = Style.text("",14,true)
	content.add_child(save_notice)
	save_notice.hide()
	if confirming:
		content.add_child(Style.text("保存当前冒险进度并返回主菜单。" if role=="dm" else "退出当前连接并返回主菜单。",16,true))
		_add_action("保存并结束团" if role=="dm" else "退出团","end_session",true)
		_add_action("继续冒险","board")
	else:
		_add_action("继续冒险","board",false,GoIconSet.PLAY)
		_add_action("地图集","session_maps",false,GoIconSet.MAP)
		if role=="dm":
			_add_action("联机房间","network_room",false,GoIconSet.USERS)
		content.add_child(HSeparator.new())
		_add_action("软件设置","settings",false,GoIconSet.SETTINGS)
		_add_action("教程","tutorials",false,GoIconSet.HELP)
		content.add_child(HSeparator.new())
		if role=="dm":
			_add_action("保存冒险","save_session",true)
		_add_action("保存并结束团" if role=="dm" else "退出团","session_end",false,GoIconSet.LOGOUT)
	Style.Motion.fade_in(self)

func show_saved() -> void:
	save_notice.text = "冒险进度已保存。"
	save_notice.show()
	Style.Motion.fade_in(save_notice)

func _add_action(title: String, action: String, primary := false, icon: StringName = &"", danger := false) -> void:
	var button := Button.new()
	button.text = title
	Style.button(button, primary, 44, danger)
	if not icon.is_empty():
		GoStyle.apply_icon(button, icon, 18)
	content.add_child(button)
	button.pressed.connect(func(): action_requested.emit(action))

func _fit() -> void:
	if Mobile.enabled:
		var safe := Mobile.safe_rect(size)
		add_theme_constant_override("margin_left",roundi(safe.position.x)+24)
		add_theme_constant_override("margin_top",roundi(safe.position.y)+24)
		add_theme_constant_override("margin_right",roundi(size.x-safe.end.x)+24)
		add_theme_constant_override("margin_bottom",roundi(size.y-safe.end.y)+24)
	if panel == null:
		return
	panel.custom_minimum_size.x = minf(440, maxf(0,Mobile.safe_rect(size).size.x-64))
	var natural := content.get_combined_minimum_size().y
	scroll.custom_minimum_size.y = minf(natural, maxf(0,Mobile.safe_rect(size).size.y-104))

func configure_editor(return_title: String) -> void:
	content.add_child(Style.text("编辑器菜单",24))
	_add_action("继续编辑","resume",false,GoIconSet.PLAY)
	_add_action("教程","tutorials",false,GoIconSet.HELP)
	_add_action("软件设置","settings",false,GoIconSet.SETTINGS)
	content.add_child(HSeparator.new())
	_add_action(return_title,"return_library",false,GoIconSet.LOGOUT)
	Style.Motion.fade_in(self)
