extends RefCounted

const LibraryPresentation = preload("res://ui/components/features/library/library_presentation.gd")

const Typography = preload("res://ui/theme/typography.gd")

const Style = preload("res://ui/components/page_style.gd")
const Field = preload("res://ui/components/page_field.gd")
const Notice = preload("res://ui/components/page_notice.gd")
const Page = preload("res://ui/components/page_shell.gd")
const ListItem = preload("res://ui/components/page_list_item.gd")
const TokenStore = preload("res://scripts/token_library_store.gd")
const AdvancedTokenCustomize = preload("res://ui/pages/advanced_token_customize.gd")
const TokenCustomize = preload("res://ui/pages/token_customize.gd")
const Modal = preload("res://ui/components/page_modal.gd")
const TagsPanel = preload("res://ui/components/token_tags_panel.gd")
const Rename = preload("res://ui/components/product_rename.gd")
const TokenLibrary = preload("res://ui/pages/token_library.gd")
const Preferences = preload("res://scripts/ui_preferences.gd")
const PlatformStore = preload("res://scripts/platform_library_store.gd")
const PlatformLibrary = preload("res://ui/pages/platform_library.gd")
const PlatformCustomize = preload("res://ui/pages/platform_customize.gd")
const MapStore = preload("res://scripts/map_library_store.gd")
const MapLibrary = preload("res://ui/pages/map_library.gd")
const MapCustomize = preload("res://ui/pages/map_customize.gd")
const AdventureStore = preload("res://scripts/adventure_library_store.gd")
const AdventureLibrary = preload("res://ui/pages/adventure_library.gd")
const AdventureCustomize = preload("res://ui/pages/adventure_customize.gd")
const IdentityPage = preload("res://ui/pages/identity_page.gd")
const SettingsPage = preload("res://ui/pages/settings_page.gd")

const TOPICS := [
	["启动、侧栏与镜头", "01-启动侧栏与镜头.md", "页面入口、工具切换与镜头操作"],
	["棋子信息与编辑", "02-棋子信息与编辑.md", "名称、生命值与护甲等级"],
	["棋子移动与路径编辑", "03-棋子移动与路径编辑.md", "添加、修改路径点与确认移动"],
	["测距", "04-测距.md", "创建测距、绑定棋子与修改节点"],
	["形状", "05-形状.md", "创建范围、旋转、移动与删除"],
	["设置与计算器", "06-设置与计算器.md", "团内距离算法与四则运算"],
	["输入与重叠操作", "07-输入与重叠操作.md", "输入归属、悬停操作与取消撤销"],
	["棋子创建与放置", "08-棋子创建与放置.md", "占地、底座、颜色、基础数值与放置确认"],
	["高级棋子定制", "09-高级棋子定制.md", "独立组件、地面范围、保存与编辑"],
	["地台创建与编辑", "10-地台创建与扩展.md", "材质、摆放区域、物件与保存"],
	["地图组合与保存", "11-地图组合与保存.md", "导入地台、位置高度、冲突与保存"],
	["冒险库与备团", "12-冒险库与备团.md", "添加地图、独立编辑与冒险整体保存"],
	["本地开团、切图与保存", "13-本地开团切图与保存.md", "打开冒险、游玩换图和进度保存"],
	["棋子托盘", "14-棋子托盘.md", "收纳、跨图放出、备用棋子与管理"],
	["本机身份", "15-本机身份.md", "昵称、身份码与多端使用"],
	["联机开团与加团", "16-联机开团与加团.md", "邀请码、权限、独立切图与断线恢复"]
]

static func populate(page: Page, route: String, detail: String, has_board: bool) -> void:
	match route:
		"home": _home(page, has_board)
		"adventures": _adventures(page, has_board)
		"join": _join(page)
		"network_room": _network_room(page)
		"network_settings": _network_settings(page)
		"identity": _identity(page)
		"customize": _customize(page)
		"token_library": _token_library(page, detail)
		"token_customize": _token_customize(page, detail)
		"platform_library": _platform_library(page)
		"platform_create": _platform_create(page,detail)
		"map_library": _map_library(page)
		"map_create": _map_create(page,detail)
		"adventure_library": _adventure_library(page)
		"adventure_create": _adventure_create(page,detail)
		"settings": _settings(page)
		"tutorials": _tutorials(page)
		"tutorial": _tutorial(page, detail)

static func _button(title: String, action: Callable, primary := false, icon: StringName = &"", height := Style.BUTTON_HEIGHT, danger := false) -> Button:
	var button := Button.new()
	button.text = title
	Style.button(button, primary, height, danger)
	if not icon.is_empty():
		GoStyle.apply_icon(button, icon, 20)
	button.pressed.connect(action)
	return button

static func _route(page: Page, destination: String, detail := "") -> Callable:
	return func(): page.navigation_requested.emit(destination, detail)

static func _narrow(page: Page, width: float) -> VBoxContainer:
	var center := CenterContainer.new()
	center.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page.content.add_child(center)
	var column := Style.column()
	center.add_child(column)
	var fit := func(): column.custom_minimum_size.x = minf(width, center.size.x)
	center.resized.connect(fit)
	fit.call_deferred()
	return column

static func _home(page: Page, _has_board: bool) -> void:
	var home := preload("res://ui/components/features/home/home_screen.gd").new()
	page.use_fullscreen_content(home)
	page.notification_area_provider = home.notification_area
	home.navigation_requested.connect(func(destination: String, detail: String): page.navigation_requested.emit(destination, detail))

static func _adventures(page: Page, _has_board: bool) -> void:
	page.configure_library("选择冒险", "adventures", LibraryPresentation.Mode.SELECT)
	var library := AdventureLibrary.new()
	library.page = page
	library.mode = LibraryPresentation.Mode.SELECT
	library.show_management_action = true
	library.manage_requested.connect(_route(page,"adventure_library"))
	page.content.add_child(library)
	library.edit_requested.connect(func(id: String): page.navigation_requested.emit("open_adventure",id))

static func _join(page: Page) -> void:
	page.configure_fluent("加入团")

	# Create form panel
	var form_panel := preload("res://ui/components/layout/form_panel.gd").new()
	page.content.add_child(form_panel)

	# Create join form
	var join_form := preload("res://ui/components/features/network/join_form.gd").new()
	form_panel.content_area.add_child(join_form)

	var network: Node = page.get_tree().current_scene.network_session

	# Register sensitive fields
	page.register_sensitive_field(join_form.password_input())

	# Connect signals
	join_form.join_requested.connect(func(invite_code: String, password: String):
		network.join(invite_code, password)
		join_form.clear_password()
	)

	join_form.settings_requested.connect(func():
		page.navigation_requested.emit("network_settings", "")
	)

	# Connect network status updates
	network.status_changed.connect(join_form.update_network_status.bind(network))

	# Initialize status
	join_form.update_network_status(network.status, network)

static func _customize(page: Page) -> void:
	var hub := preload("res://ui/components/features/library/customize_hub.gd").new()
	page.use_fullscreen_content(hub)
	hub.back_requested.connect(func(): page.back_requested.emit())
	hub.navigation_requested.connect(func(destination: String, detail: String): page.navigation_requested.emit(destination, detail))

static func _token_library(page: Page, detail := "") -> void:
	page.configure_library("棋子库", "tokens")
	if detail == "saved":
		var success := Notice.new()
		page.content.add_child(success)
		success.show_message("棋子已保存到本地。")
	var library := TokenLibrary.new()
	library.page = page
	page.content.add_child(library)
	var loaded := TokenStore.read_catalog()
	var records: Array[Dictionary] = []
	for record in loaded["entries"]: records.append(record)
	library.set_entries(records, loaded["error"], loaded["warnings"])
	library.rename_requested.connect(func(id: String):
		var loaded_record := TokenStore.get_record(id)
		if not loaded_record["ok"]:
			var error_modal := Modal.new()
			page.add_overlay(error_modal)
			error_modal.configure("无法重命名",loaded_record["message"])
			error_modal.add_action("关闭",error_modal.dismiss)
			return
		var modal := Rename.new()
		page.add_overlay(modal)
		modal.configure_product(loaded_record["record"]["title"],40,func(title: String): return TokenStore.rename(id,title))
		modal.name_saved.connect(func(): _refresh_token_library(page))
	)
	library.tags_requested.connect(func(id: String):
		for data: Dictionary in library.entries:
			if data["id"]!=id: continue
			var tags_panel := TagsPanel.new()
			page.add_overlay(tags_panel)
			tags_panel.configure_token(data["title"],data["kind"],data["tags"])
			return
	)
	library.copy_requested.connect(func(id: String):
		var result := TokenStore.copy(id)
		if not result["ok"]:
			var modal := Modal.new()
			page.add_overlay(modal)
			modal.configure("复制失败", result["message"])
			modal.add_action("关闭", modal.dismiss)
			return
		var refreshed := TokenStore.read_catalog()
		var entries: Array[Dictionary] = []
		for record in refreshed["entries"]: entries.append(record)
		library.set_entries(entries, refreshed["error"], refreshed["warnings"])
	)
	library.edit_requested.connect(func(id: String): page.navigation_requested.emit("token_customize", id))
	library.upgrade_requested.connect(func(id: String): _choose_upgrade(page, id))
	library.delete_requested.connect(func(data: Dictionary):
		var modal := Modal.new()
		page.add_overlay(modal)
		modal.configure("删除棋子？", "确定删除“%s”？删除后无法恢复。已放入冒险的复制件不受影响。" % data["title"])
		modal.add_action("取消", modal.dismiss)
		var confirm := modal.add_action("确认删除", Callable(), false, true, true)
		confirm.pressed.connect(func():
			confirm.disabled = true
			var result := TokenStore.delete(data["id"])
			if not result["ok"]:
				modal.set_error(result["message"])
				confirm.disabled = false
				return
			modal.dismiss()
			var refreshed := TokenStore.read_catalog()
			var entries: Array[Dictionary] = []
			for record in refreshed["entries"]: entries.append(record)
			library.set_entries(entries, refreshed["error"], refreshed["warnings"])
		)
	)
	library.create_requested.connect(func():
		var modal := Modal.new()
		page.add_overlay(modal)
		modal.configure("创建棋子", "选择要创建的棋子类型。")
		modal.add_action("创建基础棋子", _route(page, "token_customize"))
		modal.add_action("创建高级棋子", _route(page, "token_customize", "advanced"))
		modal.add_action("取消", modal.dismiss)
	)

static func _choose_upgrade(page: Page, id: String) -> void:
	var loaded := TokenStore.get_record(id)
	if not loaded["ok"] or loaded["record"]["kind"] != "basic":
		var error := Modal.new()
		page.add_overlay(error)
		error.configure("无法升级", loaded["message"] if not loaded["ok"] else "只有基础棋子可以升级。")
		error.add_action("关闭", error.dismiss)
		return
	var record: Dictionary = loaded["record"]
	var modal := Modal.new()
	page.add_overlay(modal)
	modal.configure("升级“%s”" % record["title"], "继承占地、外观、名称、标签和初始数值。升级完成后留在棋子库；已放入冒险的棋子不受影响。")
	var copy_button := modal.add_action("生成高级副本", Callable(), true)
	var convert_button := modal.add_action("转换原棋子…", Callable())
	var cancel_button := modal.add_action("取消", modal.dismiss)
	copy_button.pressed.connect(func():
		for button in [copy_button, convert_button, cancel_button]: button.disabled = true
		var result := TokenStore.upgrade(id)
		if not result["ok"]:
			modal.set_error(result["message"])
			for button in [copy_button, convert_button, cancel_button]: button.disabled = false
			return
		modal.dismiss()
		_refresh_token_library(page)
	)
	convert_button.pressed.connect(func():
		modal.dismiss()
		_confirm_upgrade(page, id, record["title"])
	)

static func _confirm_upgrade(page: Page, id: String, title: String) -> void:
	var modal := Modal.new()
	page.add_overlay(modal)
	modal.configure("转换原棋子？", "将“%s”转换为高级棋子，保留原编号。确认后立即保存转换结果，原基础版本不再保留；需要保留原件时请取消并选择生成高级副本。" % title)
	var cancel := modal.add_action("取消", modal.dismiss)
	var confirm := modal.add_action("确认转换", Callable(), false, true, true)
	confirm.pressed.connect(func():
		confirm.disabled = true
		cancel.disabled = true
		var result := TokenStore.upgrade(id, true)
		if not result["ok"]:
			modal.set_error(result["message"])
			confirm.disabled = false
			cancel.disabled = false
			return
		modal.dismiss()
		_refresh_token_library(page)
	)

static func _token_customize(page: Page, id := "") -> void:
	var record: Dictionary = {}
	if not id.is_empty() and id != "advanced":
		var loaded := TokenStore.get_record(id)
		if not loaded["ok"]:
			page.configure("无法编辑棋子", loaded["message"])
			page.content.add_child(_button("返回棋子库", _route(page, "token_library")))
			return
		record = loaded["record"]
	var advanced: bool = id == "advanced" or record.get("kind") == "advanced"
	page.configure("创建高级棋子" if advanced else "创建基础棋子", "")
	var editor = AdvancedTokenCustomize.new() if advanced else TokenCustomize.new()
	editor.editing_record = record
	editor.page = page
	page.use_fullscreen_content(editor)
	page.set_meta("token_editor", editor)
	editor.return_requested.connect(_route(page, "token_library"))

static func _settings(page: Page) -> void:
	var settings := SettingsPage.new()
	page.set_meta("settings_editor",settings)
	page.use_fullscreen_content(settings)
	settings.back_requested.connect(func(): page.back_requested.emit())

static func _tutorials(page: Page) -> void:
	page.configure("教程", "按主题阅读当前已实现的操作说明。")
	for index in range(TOPICS.size()):
		var topic: Array = TOPICS[index]
		var item := ListItem.new()
		page.content.add_child(item)
		item.setup(topic[0], topic[2], "阅读")
		item.opened.connect(_route(page, "tutorial", str(index)))

static func _tutorial(page: Page, detail: String) -> void:
	var index := clampi(detail.to_int(), 0, TOPICS.size() - 1)
	var topic: Array = TOPICS[index]
	page.configure(topic[0], "操作教程")
	var path: String = "res://docs/教程/" + topic[1]
	if not FileAccess.file_exists(path):
		page.content.add_child(Style.text("教程文件暂不可用。", Typography.BODY, true))
		return
	var source := FileAccess.get_file_as_string(path)
	var link_pattern := RegEx.new()
	link_pattern.compile("\\[([^\\]]+)\\]\\([^)]*\\)")
	var paragraph := PackedStringArray()
	for raw_line in source.split("\n"):
		var line: String = raw_line.strip_edges()
		if line.begins_with("# "):
			continue
		if line.is_empty() or line.begins_with("## ") or line.begins_with("### "):
			_flush_paragraph(page, paragraph)
			paragraph.clear()
			if line.begins_with("#"):
				page.content.add_child(Style.text(line.trim_prefix("### ").trim_prefix("## "), Typography.SECTION))
		else:
			line = link_pattern.sub(line, "$1", true).replace("**", "").replace("`", "")
			if not line.begins_with("| ---"):
				paragraph.append(line)
	_flush_paragraph(page, paragraph)

static func _flush_paragraph(page: Page, lines: PackedStringArray) -> void:
	if lines.is_empty():
		return
	var panel := Style.card()
	panel.add_child(Style.text("\n".join(lines)))
	page.content.add_child(panel)

static func _refresh_token_library(page: Page) -> void:
	var loaded := TokenStore.read_catalog()
	var entries: Array[Dictionary] = []
	for record in loaded["entries"]: entries.append(record)
	for child in page.content.get_children():
		if child is TokenLibrary:
			child.set_entries(entries, loaded["error"], loaded["warnings"])

static func _platform_library(page: Page) -> void:
	page.configure_library("地台库", "platforms")
	var library := PlatformLibrary.new()
	library.page = page
	page.content.add_child(library)
	library.create_requested.connect(_route(page,"platform_create"))
	library.edit_requested.connect(func(id: String): page.navigation_requested.emit("platform_create",id))

static func _platform_create(page: Page, id := "") -> void:
	page.configure("创建地台" if id.is_empty() else "编辑地台", "")
	var editor := PlatformCustomize.new()
	editor.page = page
	if not id.is_empty():
		var loaded := PlatformStore.get_record(id)
		if not loaded["ok"]:
			editor.free()
			page.content.add_child(Style.text(loaded["message"],Typography.SECTION))
			page.content.add_child(_button("返回地台库",_route(page,"platform_library")))
			return
		editor.values = loaded["record"]["parameters"]
		editor.edit_id = id
	page.use_fullscreen_content(editor)
	page.set_meta("platform_editor",editor)
	editor.return_requested.connect(_route(page,"platform_library"))

static func _map_library(page: Page) -> void:
	page.configure_library("地图库", "maps")
	var library := MapLibrary.new()
	library.page = page
	page.content.add_child(library)
	library.create_requested.connect(_route(page,"map_create"))
	library.edit_requested.connect(func(id: String): page.navigation_requested.emit("map_create",id))

static func _adventure_library(page: Page) -> void:
	page.configure_library("冒险库", "adventures")
	var library := AdventureLibrary.new()
	library.page = page
	page.content.add_child(library)
	library.create_requested.connect(_route(page,"adventure_create"))
	library.edit_requested.connect(func(id: String): page.navigation_requested.emit("adventure_create",id))

static func _adventure_create(page: Page, id := "") -> void:
	page.configure("创建冒险" if id.is_empty() else "编辑冒险","地图集合")
	var editor := AdventureCustomize.new()
	editor.page = page
	if not id.is_empty():
		var loaded := AdventureStore.get_record(id)
		if not loaded["ok"]:
			editor.free()
			page.content.add_child(Style.text(loaded["message"],Typography.SECTION))
			page.content.add_child(_button("返回冒险库",_route(page,"adventure_library")))
			return
		editor.values = loaded["record"]["parameters"]
		editor.edit_id = id
	page.set_meta("adventure_editor",editor)
	page.content.add_child(editor)
	editor.return_requested.connect(_route(page,"adventure_library"))

static func _map_create(page: Page, id := "") -> void:
	page.configure("创建地图" if id.is_empty() else "编辑地图","")
	var editor := MapCustomize.new()
	editor.page = page
	if not id.is_empty():
		var loaded := MapStore.get_record(id)
		if not loaded["ok"]:
			editor.free()
			page.content.add_child(Style.text(loaded["message"],Typography.SECTION))
			page.content.add_child(_button("返回地图库",_route(page,"map_library")))
			return
		editor.values = loaded["record"]["parameters"]
		editor.edit_id = id
	page.use_fullscreen_content(editor)
	page.set_meta("map_editor",editor)
	editor.return_requested.connect(_route(page,"map_library"))

static func _identity(page: Page) -> void:
	var identity := IdentityPage.new()
	identity.page = page
	page.set_meta("identity_editor",identity)
	page.content.add_child(identity)

static func _network_room(page: Page) -> void:
	page.configure_fluent("联机房间")

	# Create form panel
	var form_panel := preload("res://ui/components/layout/form_panel.gd").new()
	page.content.add_child(form_panel)

	# Create host form
	var host_form := preload("res://ui/components/features/network/host_form.gd").new()
	form_panel.content_area.add_child(host_form)

	var network: Node = page.get_tree().current_scene.network_session

	# Register sensitive password field
	page.register_sensitive_field(host_form.password_input())

	# Connect signals using bound methods to avoid accessing freed nodes
	host_form.open_requested.connect(network.open_host)
	host_form.close_requested.connect(network.close)
	host_form.copy_requested.connect(func():
		if not network.room_code.is_empty():
			DisplayServer.clipboard_set(network.room_code)
	)
	host_form.settings_requested.connect(func():
		page.navigation_requested.emit("network_settings", "")
	)

	# Connect network status updates using bound method
	network.status_changed.connect(host_form.update_network_status.bind(network))

	# Initialize status
	host_form.update_network_status(network.status, network)

static func _network_settings(page: Page) -> void:
	page.configure_fluent("连接设置")

	# Create form panel
	var form_panel := preload("res://ui/components/layout/form_panel.gd").new()
	page.content.add_child(form_panel)

	# Create connection settings form
	var settings_form := preload("res://ui/components/features/network/connection_settings_form.gd").new()
	form_panel.content_area.add_child(settings_form)

	# Load current settings
	var Settings = preload("res://scripts/network_settings.gd")
	var options := Settings.read()
	settings_form.load_settings(options["address"], options["certificate"])

	# Connect save signal
	settings_form.save_requested.connect(func(address: String, certificate_path: String):
		var error := Settings.save(address, certificate_path)
		if error == OK:
			settings_form.set_result(true, "已保存，下次连接生效")
		else:
			settings_form.set_result(false, "无法保存，请检查地址和公开证书。")
	)
