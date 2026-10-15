extends MarginContainer

signal back_requested
const Style = preload("res://ui/components/page_style.gd")
const Layout = preload("res://ui/components/editor_layout.gd")
const GraphicsPanel = preload("res://ui/components/graphics_settings_panel.gd")
const Preferences = preload("res://scripts/ui_preferences.gd")
const CameraPreferences = preload("res://scripts/camera_preferences.gd")
const CATEGORIES := [["video", "视频"], ["interface", "界面"], ["camera", "镜头"], ["tutorial", "教程与提示"], ["audio", "音效"], ["network", "联机"], ["updates","关于与更新"]]
var camera_preferences: RefCounted
var camera_inputs: Dictionary = {}
var body: VBoxContainer
var scroll: ScrollContainer
var footer: Label
var buttons: Dictionary = {}
var category := ""
var preferences: RefCounted
var interface_inputs: Dictionary = {}

func _ready() -> void:
	if Mobile.enabled:
		Mobile.changed.connect(_fit_mobile)
		_fit_mobile.call_deferred()
	for edge in ["left", "right", "top", "bottom"]: add_theme_constant_override("margin_" + edge, 24)
	var page := Style.column(16)
	add_child(page)
	var header := HBoxContainer.new()
	header.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	header.custom_minimum_size.y = 44
	header.add_theme_constant_override("separation", 16)
	page.add_child(header)
	var back := Button.new()
	back.text = "返回"
	back.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	Style.button(back)
	header.add_child(back)
	back.pressed.connect(func(): back_requested.emit())
	var title := Style.text("软件设置", 28)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	header.add_child(title)
	var surface := Style.card()
	surface.size_flags_vertical = Control.SIZE_EXPAND_FILL
	page.add_child(surface)
	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 24)
	surface.add_child(columns)
	var navigation := ScrollContainer.new()
	navigation.custom_minimum_size.x = 180
	Layout.scroll(navigation)
	columns.add_child(navigation)
	var list := Style.column(8)
	navigation.add_child(list)
	for entry in CATEGORIES:
		var button := Button.new()
		button.text = "关于" if entry[0]=="updates" and Mobile.enabled else entry[1]
		button.toggle_mode = true
		# Keep the native pressed face persistent for the selected category.
		button.set_meta("page_motion_prepared", true)
		Style.card_button(button)
		list.add_child(button)
		buttons[entry[0]] = button
		button.pressed.connect(_select.bind(entry[0]))
	columns.add_child(VSeparator.new())
	var right := Style.column(12)
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	columns.add_child(right)
	scroll = ScrollContainer.new()
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	Layout.scroll(scroll)
	right.add_child(scroll)
	body = Style.column(12)
	body.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	scroll.add_child(body)
	footer = Layout.status()
	right.add_child(footer)
	preferences = Preferences.shared()
	preferences.storage_status_changed.connect(_interface_status)
	preferences.changed.connect(_sync_interface)
	Graphics.changed.connect(_video_status)
	camera_preferences = CameraPreferences.shared()
	camera_preferences.changed.connect(_sync_camera)
	var initial := "video"
	for entry in CATEGORIES:
		if OS.get_cmdline_user_args().has("--settings-tab=" + entry[0]): initial = entry[0]
	_select(initial)

func _select(key: String) -> void:
	if key == category:
		buttons[key].set_pressed_no_signal(true)
		return
	Graphics.cancel_display()
	category = key
	interface_inputs.clear()
	camera_inputs.clear()
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	for name in buttons: buttons[name].set_pressed_no_signal(name == key)
	scroll.scroll_vertical = 0
	if key == "video":
		var options := GraphicsPanel.new()
		body.add_child(options)
		options.state.hide()
		_video_status()
	elif key == "interface":
		_build_interface()
		_interface_status(preferences.storage_message, preferences.storage_failed)
	elif key == "network":
		preload("res://ui/pages/network_page.gd").add_settings(body)
		Layout.set_status(footer, "")
	elif key == "updates":
		if Mobile.enabled:
			body.add_child(Style.text("紫水鸡棋盘",24))
			body.add_child(Style.text(str(ProjectSettings.get_setting("application/config/version","")),16,true))
			body.add_child(Style.text("GNU GPL v3.0",16,true))
		else: body.add_child(preload("res://ui/components/software_update_panel.gd").new())
		Layout.set_status(footer, "")
	elif key == "camera":
		_build_camera()
	else:
		body.add_child(Style.text(buttons[key].text, 20))
		body.add_child(Style.text("此分类暂未开放。", 16, true))
		Layout.set_status(footer, "")
	Style.Motion.fade_in(body)

func _build_camera() -> void:
	body.add_child(Style.text("操作速度", 20))
	for entry in [["pan", "平移速度"], ["rotation", "旋转速度"], ["zoom", "缩放速度"]]:
		var labels: Array = []
		for value in CameraPreferences.SPEEDS: labels.append("%d%%" % roundi(value * 100))
		var input := _option(entry[1], labels)
		camera_inputs[entry[0]] = input
		input.item_selected.connect(_camera_speed.bind(entry[0]))
	var reverse := _option("缩放方向", ["正常", "反转"])
	camera_inputs["reverse_zoom"] = reverse
	reverse.item_selected.connect(func(index: int): camera_preferences.set_value("reverse_zoom", index == 1))
	body.add_child(HSeparator.new())
	body.add_child(Style.text("镜头平滑", 20))
	var smooth := _option("平滑过渡", ["关闭", "开启"])
	camera_inputs["smooth"] = smooth
	smooth.item_selected.connect(func(index: int): camera_preferences.set_value("smooth", index == 1))
	var strength := _option("平滑强度", ["轻微", "标准", "明显"])
	camera_inputs["strength"] = strength
	strength.item_selected.connect(func(index: int): camera_preferences.set_value("strength", index))
	var reset := Button.new()
	reset.text = "恢复镜头默认"
	Style.card_button(reset)
	body.add_child(reset)
	reset.pressed.connect(camera_preferences.reset_defaults)
	_sync_camera()

func _camera_speed(index: int, key: String) -> void:
	camera_preferences.set_value(key, CameraPreferences.SPEEDS[index])

func _sync_camera() -> void:
	if category != "camera": return
	for key in camera_inputs:
		var value: Variant = camera_preferences.values[key]
		var index: int = CameraPreferences.SPEEDS.find(float(value)) if key in ["pan", "rotation", "zoom"] else int(value)
		camera_inputs[key].select(index)
	camera_inputs["strength"].disabled = not camera_preferences.values["smooth"]
	Layout.set_status(footer, camera_preferences.status, camera_preferences.failed)

func _build_interface() -> void:
	body.add_child(Style.text("界面大小", 20))
	_preference("ui_scale", "整体界面缩放", Preferences.UI_SCALES)
	_preference("info_scale", "棋子信息栏", Preferences.INFO_SCALES)
	_preference("floating_text", "对象浮窗文字", Preferences.TEXT_SCALES)
	body.add_child(Style.text("信息栏和浮窗在整体界面缩放之外额外调整；信息栏仍保留镜头缩放限制。", 14, true))
	body.add_child(HSeparator.new())
	body.add_child(Style.text("动效", 20))
	var motion := _option("过渡动画", ["标准", "减弱", "关闭"])
	interface_inputs["motion"] = motion
	motion.item_selected.connect(func(index: int): preferences.set_option("motion", index))
	body.add_child(HSeparator.new())
	body.add_child(Style.text("底部创建栏", 20))
	var rows := _option("显示行数", ["1 行", "2 行", "3 行"])
	interface_inputs["creation_rows"] = rows
	rows.item_selected.connect(func(index: int): preferences.set_rows(index + 1))
	var mode := _option("浏览方式", ["分页", "上下滚动"])
	interface_inputs["creation_mode"] = mode
	mode.item_selected.connect(func(index: int): preferences.set_mode("pages" if index == 0 else "scroll"))
	body.add_child(Style.text("共用于基础棋子、高级棋子及后续地景。窗口空间不足时暂时减少实际行数，空间恢复后使用原设置。", 14, true))
	var reset := Button.new()
	reset.text = "恢复界面默认"
	Style.card_button(reset)
	body.add_child(reset)
	reset.pressed.connect(preferences.reset_defaults)
	_sync_interface()

func _preference(key: String, title: String, choices: Array) -> void:
	var labels: Array = []
	for value in choices: labels.append("%d%%" % roundi(value * 100))
	var input := _option(title, labels)
	interface_inputs[key] = input
	input.item_selected.connect(func(index: int): preferences.set_option(key, float(choices[index])))

func _sync_interface() -> void:
	if category != "interface": return
	for key in interface_inputs:
		var choices: Array = Preferences.UI_SCALES if key == "ui_scale" else (Preferences.INFO_SCALES if key == "info_scale" else Preferences.TEXT_SCALES)
		var value: int
		if key == "motion": value = preferences.motion
		elif key == "creation_rows": value = preferences.creation_rows - 1
		elif key == "creation_mode": value = 0 if preferences.creation_mode == "pages" else 1
		else: value = choices.find(preferences.get(key))
		interface_inputs[key].select(value)

func _option(title: String, items: Array) -> OptionButton:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 16)
	body.add_child(row)
	row.add_child(Style.field_label(title))
	row.get_child(0).size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var option := OptionButton.new()
	option.size_flags_horizontal = Control.SIZE_SHRINK_END
	option.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.resized.connect(func(): option.custom_minimum_size.x = clampf(row.size.x * 0.45, 160, 400))
	for item in items: option.add_item(item)
	row.add_child(option)
	BoardUiStyle.style_controls(row, 44)
	return option

func _video_status() -> void:
	if category == "video": Layout.set_status(footer, Graphics.status)

func _interface_status(message: String, failed: bool) -> void:
	if category == "interface": Layout.set_status(footer, message, failed)

func _exit_tree() -> void:
	if camera_preferences != null and camera_preferences.changed.is_connected(_sync_camera): camera_preferences.changed.disconnect(_sync_camera)
	if Graphics.changed.is_connected(_video_status): Graphics.changed.disconnect(_video_status)
	if preferences != null and preferences.storage_status_changed.is_connected(_interface_status): preferences.storage_status_changed.disconnect(_interface_status)
	if preferences != null and preferences.changed.is_connected(_sync_interface): preferences.changed.disconnect(_sync_interface)

func _fit_mobile() -> void:
	var safe := Mobile.safe_rect(size)
	add_theme_constant_override("margin_left",roundi(safe.position.x)+24)
	add_theme_constant_override("margin_top",roundi(safe.position.y)+24)
	add_theme_constant_override("margin_right",roundi(size.x-safe.end.x)+24)
	add_theme_constant_override("margin_bottom",roundi(size.y-safe.end.y)+24)
