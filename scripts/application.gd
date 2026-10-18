extends Node

const PageScene = preload("res://ui/components/page_shell.tscn")
const Pages = preload("res://ui/pages/menu_pages.gd")
const PageStyle = preload("res://ui/components/page_style.gd")
const BoardScene = preload("res://scenes/main.tscn")
const Board = preload("res://scripts/main.gd")
const Page = preload("res://ui/components/page_shell.gd")
const MenuScene = preload("res://ui/components/adventure_menu.tscn")
const AdventureStore = preload("res://scripts/adventure_library_store.gd")
const Runtime = preload("res://scripts/adventure_runtime.gd")
const MapCollection = preload("res://ui/pages/session_map_collection.gd")
const Modal = preload("res://ui/components/page_modal.gd")
var adventure: Dictionary = {}
var update_badge: PanelContainer
var adventure_id := ""
var current_map_id := ""
var window_close_layer: CanvasLayer
var window_close_busy := false
var window_close_modes: Dictionary = {}
var session_modal: CanvasLayer
const TrayController = preload("res://scripts/adventure_tray_controller.gd")
var tray_controller: Node

const InstanceEditor = preload("res://ui/components/instance_token_editor.gd")
var token_edit_layer: CanvasLayer
var board: Board
var current_page: Page
var retained_network_page: Page
var network_settings_origin := "join"
var current_menu: Control
var current_route := "home"
var session_role := "dm"
var session_actor := "dm"
var member_connections: Dictionary = {}
var network_session: Node
var quitting := false
const Network = preload("res://scripts/network_session.gd")
const Members = preload("res://scripts/adventure_members.gd")

func reload_network_board() -> void:
	if board!=null and board.session_map_id==current_map_id and not _current_map().is_empty():
		board.network_readonly = session_role=="pl" and (not network_session.connected or current_map_id in network_session.locked)
		board.apply_network_content(_current_map()["data"],adventure["party"],adventure["runtime"]["maps"].get(current_map_id,{"shapes":[],"measurements":[],"platform_origins":{}}))
		tray_controller._refresh()
		refresh_network_map_collection()
		return
	var camera_state := {}
	var previous_route := current_route
	var previous_map := ""
	if board!=null:
		previous_map = board.session_map_id
		for key in ["focus","yaw","pitch","camera_distance","camera_render_focus","camera_render_angles","camera_render_distance"]: camera_state[key] = board.get(key)
		board.set_application_active(false)
		remove_child(board)
		board.queue_free()
		board = null
	if current_map_id.is_empty():
		_navigate("session_maps")
	elif previous_route=="board" or session_role=="pl" and previous_route=="join":
		_navigate("board")
	else:
		_create_network_board()
		board.set_application_active(false,previous_route in ["session_menu","session_end"])
	if board!=null:
		board.network_readonly = session_role=="pl" and (not network_session.connected or current_map_id in network_session.locked)
		if previous_map==current_map_id:
			for key in camera_state: board.set(key,camera_state[key])
	refresh_network_map_collection()

func _ready() -> void:
	if not preload("res://scripts/storage_paths.gd").failure.is_empty(): return
	get_tree().set_auto_accept_quit(false)
	Updates.restart_requested.connect(_request_software_restart)
	Updates.page_requested.connect(_open_updates)
	var notification_layer := CanvasLayer.new()
	notification_layer.layer = 102
	add_child(notification_layer)
	update_badge = preload("res://ui/components/software_update_badge.gd").new()
	update_badge.application = self
	notification_layer.add_child(update_badge)
	network_session = Network.new()
	network_session.application = self
	add_child(network_session)
	tray_controller = TrayController.new()
	tray_controller.application = self
	add_child(tray_controller)
	print("启动项目：%s；存档目录：%s" % [ProjectSettings.globalize_path("res://"),preload("res://scripts/storage_paths.gd").data_root()])
	BoardUiStyle.configure()
	$Pages/Root.theme = GoUi.theme()
	$Pages/Root/Background.color = PageStyle.BACKGROUND
	var startup := "home"
	for argument in OS.get_cmdline_user_args():
		if argument in ["--page=customize", "--page=join", "--page=network_settings", "--page=identity", "--page=token_library", "--page=token_customize", "--page=settings", "--page=platform_library", "--page=platform_create", "--page=map_library", "--page=map_create", "--page=adventure_library", "--page=adventure_create", "--page=adventures", "--page=adventure_play"]:
			startup = argument.trim_prefix("--page=")
	var detail := "advanced" if OS.get_cmdline_user_args().has("--advanced-token") and startup == "token_customize" else ""
	if startup=="adventure_play":
		var loaded := AdventureStore.read_catalog()
		if not loaded["entries"].is_empty(): _open_adventure(loaded["entries"][0]["id"])
		else: _navigate("adventures")
		return
	_navigate(startup, detail)
	_ready_ticket()

func _ready_ticket() -> void:
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--launch-ticket="):
			var ticket := argument.trim_prefix("--launch-ticket=")
			if ticket.length()!=32: continue
			var valid := true
			for character in ticket:
				if not character in "0123456789abcdef": valid = false
			if not valid: continue
			var directory := preload("res://scripts/storage_paths.gd").install_root().path_join("cache/sessions")
			DirAccess.make_dir_recursive_absolute(directory)
			var file := FileAccess.open(directory.path_join(ticket+".ready"),FileAccess.WRITE)
			if file!=null: file.store_string("ready"); file.flush()

func _request_software_restart(action: String) -> void:
	if is_instance_valid(session_modal) or is_instance_valid(token_edit_layer): return
	var modal := Modal.new()
	$Pages/Root.add_child(modal)
	var description := "退出程序并应用已准备的更新，用户数据保留。" if action=="apply" else "退出程序并恢复上个兼容版本，不回退存档。"
	if not adventure.is_empty(): description = "保存当前冒险后退出并继续。" if session_role=="dm" else "退出当前团并继续。"
	modal.configure("更新并重启" if action=="apply" else "恢复上个版本",description)
	modal.add_action("取消",modal.dismiss)
	modal.add_action("保存并继续" if not adventure.is_empty() and session_role=="dm" else "继续",func():
		if not adventure.is_empty() and session_role=="dm" and not _save_adventure(): return
		if Updates.apply(action)!=OK:
			modal.dismiss()
			_session_message("无法继续","无法启动更新程序，当前内容已保留。")
			return
		_quit_application()
	,true)

func _clear_page(keep_network_page := false) -> void:
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null:
		focused.release_focus()
	if current_menu != null:
		current_menu.hide()
		current_menu.queue_free()
		current_menu = null
	if current_page != null:
		current_page.hide()
		if keep_network_page:
			current_page.process_mode = Node.PROCESS_MODE_DISABLED
			retained_network_page = current_page
		else:
			current_page.clear_sensitive_fields()
			current_page.queue_free()
		current_page = null

func _discard_retained_network_page() -> void:
	if is_instance_valid(retained_network_page):
		retained_network_page.clear_sensitive_fields()
		retained_network_page.queue_free()
	retained_network_page = null
	network_settings_origin = "join"

func _navigate(destination: String, detail := "") -> void:
	if is_instance_valid(window_close_layer) or window_close_busy: return
	if is_instance_valid(tray_controller) and tray_controller.blocked(): return
	if current_route=="join" and destination!="join" and network_session.active and not network_session.hosting and not network_session.connected: network_session.close()
	if destination in ["camera_focus","camera_overview"]:
		if is_instance_valid(board):
			if destination=="camera_focus": board._orbit_focus()
			else: board._orbit_overview()
		_navigate("board")
		return
	if destination=="open_adventure":
		_open_adventure(detail)
		return
	if destination=="switch_map":
		_switch_map(detail)
		return
	if destination=="save_session":
		if _save_adventure() and is_instance_valid(current_menu): current_menu.show_saved()
		return
	if current_page != null and current_page.has_meta("identity_editor"):
		var identity_editor: Control = current_page.get_meta("identity_editor")
		if identity_editor.guard_leave(func(): _navigate(destination,detail)): return
	if current_page != null and current_page.has_meta("adventure_editor"):
		var adventure_editor: Control = current_page.get_meta("adventure_editor")
		if adventure_editor.guard_leave(func(): _navigate(destination,detail)): return
	if current_page != null and current_page.has_meta("token_editor"):
		var editor: Control = current_page.get_meta("token_editor")
		if editor.guard_leave(func(): _navigate(destination, detail)):
			return
	if current_page != null and current_page.has_meta("platform_editor"):
		var platform_editor: Control = current_page.get_meta("platform_editor")
		if platform_editor.guard_leave(func(): _navigate(destination,detail)):
			return
	if current_page != null and current_page.has_meta("map_editor"):
		var map_editor: Control = current_page.get_meta("map_editor")
		if map_editor.guard_leave(func(): _navigate(destination,detail)):
			return
	if destination == "quit":
		_quit_application()
		return
	if destination == "end_session":
		if session_role=="dm" and not adventure.is_empty() and not _save_adventure(): return
		_end_session()
		return
	# An active session can only reach the home page through its end flow.
	if destination == "home" and (board != null or not adventure.is_empty()):
		destination = "session_menu"
	var keep_network_page := current_route in ["join", "network_room"] and destination == "network_settings"
	if keep_network_page: network_settings_origin = current_route
	var restore_network_page := current_route == "network_settings" and destination == network_settings_origin and is_instance_valid(retained_network_page)
	if not keep_network_page and not restore_network_page: _discard_retained_network_page()
	_clear_page(keep_network_page)
	current_route = destination
	if destination == "board":
		$Pages/Root.hide()
		if board == null:
			var map := _current_map()
			if map.is_empty():
				_navigate("session_maps")
				return
			_create_network_board()
		board.network_readonly = session_role=="pl" and (not network_session.connected or network_session.operation_pending or network_session.awaiting_snapshot or current_map_id in network_session.locked)
		board.set_application_active(true)
		return
	if board != null:
		if is_instance_valid(tray_controller.panel): tray_controller.panel.close()
		board.set_application_active(false, destination in ["session_menu", "session_end"])
	$Pages/Root.show()
	$Pages/Root/Background.modulate.a = 1.0
	if destination in ["session_menu", "session_end"]:
		$Pages/Root/Background.color = Color(0, 0, 0, 0.28)
		current_menu = MenuScene.instantiate()
		$Pages/Root.add_child(current_menu)
		current_menu.action_requested.connect(_navigate)
		current_menu.configure(session_role,destination=="session_end",adventure.get("title","冒险"))
		return
	$Pages/Root/Background.color = PageStyle.BACKGROUND
	if restore_network_page:
		current_page = retained_network_page
		retained_network_page = null
		current_page.process_mode = Node.PROCESS_MODE_INHERIT
		current_page.show()
		return
	current_page = PageScene.instantiate()
	$Pages/Root.add_child(current_page)
	current_page.navigation_requested.connect(_navigate)
	current_page.back_requested.connect(_back)
	if destination=="session_maps":
		current_page.configure(adventure.get("title","冒险"),"地图集")
		var collection := MapCollection.new()
		collection.entries = adventure.get("maps",[])
		collection.current_id = current_map_id
		collection.network = network_session
		collection.party = adventure.get("party",{})
		collection.host_mode = session_role=="dm"
		current_page.content.add_child(collection)
		collection.map_chosen.connect(_switch_map)
		if collection.entries.is_empty():
			var leave := Button.new()
			leave.text = "返回冒险选择"
			PageStyle.button(leave)
			current_page.content.add_child(leave)
			leave.pressed.connect(func(): _end_session(); _navigate("adventures"))
	else: Pages.populate(current_page, destination, detail, board != null)
	current_page.reveal()

func _back() -> void:
	if current_route=="session_maps":
		_navigate("board" if board!=null else "session_menu")
	elif current_route=="network_room":
		_navigate("session_menu")
	elif current_route=="network_settings":
		_navigate(network_settings_origin)
	elif current_route == "adventure_create":
		_navigate("adventure_library")
	elif current_route == "adventure_library":
		_navigate("customize")
	elif current_route == "token_customize":
		_navigate("token_library")
	elif current_route == "token_library":
		_navigate("customize")
	elif current_route == "platform_create":
		_navigate("platform_library")
	elif current_route == "platform_library":
		_navigate("customize")
	elif current_route == "map_create":
		_navigate("map_library")
	elif current_route == "map_library":
		_navigate("customize")
	elif current_route == "tutorial":
		_navigate("tutorials")
	else:
		_navigate("session_menu" if board != null else "home")

func _end_session() -> void:
	network_session.close()
	session_role = "dm"
	session_actor = "dm"
	_clear_page()
	if board != null:
		board.set_application_active(false)
		remove_child(board)
		board.queue_free()
		board = null
	member_connections.clear()
	adventure.clear()
	adventure_id = ""
	current_map_id = ""
	_navigate("home")

func remote_session_ended(active_close: bool) -> void:
	if quitting: return
	if session_role!="pl" and (current_route!="join" or not adventure.is_empty()): return
	_restore_window_close_modes()
	window_close_busy = false
	for key in ["session_modal","token_edit_layer","window_close_layer"]:
		var layer: CanvasLayer = get(key)
		if is_instance_valid(layer):
			layer.hide()
			layer.queue_free()
		set(key,null)
	if is_instance_valid(tray_controller.overlay):
		tray_controller.overlay.hide()
		tray_controller.overlay.queue_free()
		tray_controller.overlay = null
	if is_instance_valid(tray_controller.panel): tray_controller.panel.close()
	_end_session()
	_session_message("团已关闭" if active_close else "连接已断开","DM 主动关闭了团。" if active_close else "与 DM 的连接已断开，团已结束。","确定")

func _unhandled_input(event: InputEvent) -> void:
	if is_instance_valid(window_close_layer) or window_close_busy: return
	if tray_controller.blocked(): return
	if is_instance_valid(session_modal) or is_instance_valid(token_edit_layer): return
	if event is InputEventKey and event.pressed and not event.echo and board!=null and current_route=="board" and not is_instance_valid(token_edit_layer) and not is_instance_valid(session_modal):
		if board.ui.session_shortcuts_blocked() or get_viewport().gui_get_focus_owner() is LineEdit or get_viewport().gui_get_focus_owner() is TextEdit: return
		if event.ctrl_pressed and event.keycode in [KEY_PAGEUP,KEY_PAGEDOWN]:
			var index := 0
			for at in range(adventure["maps"].size()):
				if adventure["maps"][at]["id"]==current_map_id: index = at
			index += -1 if event.keycode==KEY_PAGEUP else 1
			if index>=0 and index<adventure["maps"].size(): _switch_map(adventure["maps"][index]["id"])
			get_viewport().set_input_as_handled()
			return
		if event.ctrl_pressed and event.keycode==KEY_S:
			_save_adventure()
			get_viewport().set_input_as_handled()
			return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		if current_route == "session_menu":
			get_viewport().set_input_as_handled()
			_navigate("board")
		elif current_route == "session_end":
			get_viewport().set_input_as_handled()
			_navigate("session_menu")
		elif current_route in ["session_maps", "network_settings"]:
			get_viewport().set_input_as_handled()
			_back()
		elif Mobile.enabled and event.device == -420:
			get_viewport().set_input_as_handled()
			if current_route == "home": _request_window_close()
			else: _back()

func _current_map() -> Dictionary:
	for map: Dictionary in adventure.get("maps",[]):
		if map["id"]==current_map_id: return map
	return {}

func _open_adventure(id: String) -> void:
	if board!=null or not adventure.is_empty(): return
	var loaded := AdventureStore.get_record(id)
	if not loaded["ok"]: _session_message("无法打开冒险",loaded["message"]); return
	adventure = loaded["record"]["parameters"]
	adventure["party"] = Members.normalized(adventure)
	member_connections.clear()
	adventure_id = id
	current_map_id = adventure["runtime"]["current_map_id"]
	if current_map_id.is_empty() and not adventure["maps"].is_empty(): current_map_id = adventure["maps"][0]["id"]
	adventure["runtime"]["current_map_id"] = current_map_id
	Members.set_map(adventure,session_actor,current_map_id)
	_navigate("board" if not current_map_id.is_empty() else "session_maps")
	if board!=null and not board.session_load_error.is_empty():
		var message := board.session_load_error
		_end_session()
		_navigate("adventures")
		_session_message("无法完整打开冒险",message)

func _capture_map() -> void:
	if board==null: return
	board.prepare_session_switch()
	board.export_session_tokens()
	adventure["party"] = Members.normalized(adventure)
	board.session_party = adventure["party"]
	adventure["runtime"]["distance_mode"] = board.distance_mode
	adventure["runtime"]["maps"][current_map_id] = Runtime.capture(board)

func _switch_map(id: String) -> void:
	if session_role=="pl":
		network_session.switch_map(id)
		return
	var found := false
	for map: Dictionary in adventure.get("maps",[]):
		if map["id"]==id: found = true
	if not found or is_instance_valid(token_edit_layer) or is_instance_valid(session_modal) or tray_controller.blocked(): return
	if current_map_id==id and board!=null: _navigate("board"); return
	if board!=null and not board.session_load_error.is_empty():
		_session_message("无法切换地图",board.session_load_error)
		return
	_capture_map()
	if board!=null:
		board.set_application_active(false)
		remove_child(board)
		board.queue_free()
		board = null
	current_map_id = id
	Members.set_map(adventure,session_actor,id)
	adventure["runtime"]["current_map_id"] = id
	_navigate("board")

func _save_adventure() -> bool:
	if session_role!="dm": return false
	if adventure.is_empty() or is_instance_valid(token_edit_layer) or is_instance_valid(session_modal) or tray_controller.blocked(): return false
	if board!=null and not board.session_load_error.is_empty():
		_session_message("无法保存冒险",board.session_load_error)
		return false
	_capture_map()
	var result := AdventureStore.save(adventure,adventure_id)
	if not result["ok"]:
		_session_message("保存失败",result["message"])
		return false
	print("冒险进度已保存：%s" % adventure_id)
	return true

func _session_message(title: String, message: String, action_title := "继续") -> void:
	if is_instance_valid(session_modal): return
	if board!=null: board.set_application_active(false,true)
	session_modal = CanvasLayer.new()
	session_modal.layer = 110
	add_child(session_modal)
	var modal := Modal.new()
	modal.theme = GoUi.theme()
	session_modal.add_child(modal)
	modal.configure(title,message)
	modal.add_action(action_title,modal.dismiss)
	modal.dismissed.connect(func():
		session_modal.queue_free()
		session_modal = null
		if board!=null and current_route=="board": board.set_application_active(true)
	)

func _request_board_token_edit(data: Dictionary) -> void:
	if is_instance_valid(token_edit_layer): return
	token_edit_layer = CanvasLayer.new()
	token_edit_layer.layer = 100
	add_child(token_edit_layer)
	board.set_application_active(false)
	var editor := InstanceEditor.new()
	editor.data = data
	token_edit_layer.add_child(editor)
	editor.applied.connect(func(params: Dictionary): board.apply_full_token_edit(int(data["id"]),params))
	editor.closed.connect(func():
		token_edit_layer.queue_free()
		token_edit_layer = null
		board.set_application_active(true)
	)

func _create_network_board() -> void:
	var map := _current_map()
	board = BoardScene.instantiate()
	board.session_map = map["data"]
	board.session_map_id = current_map_id
	board.session_party = adventure["party"]
	board.session_actor = session_actor
	board.network_readonly = session_role=="pl" and (not network_session.connected or current_map_id in network_session.locked)
	board.session_distance_mode = adventure["runtime"].get("distance_mode",0)
	add_child(board)
	board.ui.menu_requested.connect(func(): _navigate("session_menu"))
	board.ui.map_collection_requested.connect(func(): _navigate("session_maps"))
	board.full_token_edit_requested.connect(_request_board_token_edit)
	Runtime.restore(board,adventure["runtime"]["maps"].get(current_map_id,{}))
	tray_controller.attach(board)

func refresh_network_map_collection() -> void:
	if current_route=="session_maps" and is_instance_valid(current_page):
		for child in current_page.content.get_children():
			if child is MapCollection:
				child.entries = adventure.get("maps",[])
				child.party = adventure.get("party",{})
				child.current_id = current_map_id
				child._refresh()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST and Mobile.enabled and is_node_ready():
		if Mobile._keyboard_height() > 0:
			DisplayServer.virtual_keyboard_hide()
			return
		var back := InputEventKey.new()
		back.keycode = KEY_ESCAPE
		back.pressed = true
		back.device = -420
		Input.parse_input_event(back)
		return
	if what == NOTIFICATION_WM_CLOSE_REQUEST and is_node_ready():
		_request_window_close()

func _window_editor() -> Control:
	if not is_instance_valid(current_page): return null
	for key in ["identity_editor", "adventure_editor", "token_editor", "platform_editor", "map_editor"]:
		if current_page.has_meta(key): return current_page.get_meta(key)
	return null

func _window_instance(root: Node) -> Control:
	if not is_instance_valid(root): return null
	if root is InstanceEditor and root.is_visible_in_tree() and not root.is_queued_for_deletion(): return root
	for child in root.get_children():
		var found := _window_instance(child)
		if found != null: return found
	return null

func _visible_confirmation(root: Node) -> bool:
	if root is Modal and root.is_visible_in_tree(): return true
	for child in root.get_children():
		if _visible_confirmation(child): return true
	return false

func _window_editor_busy(root: Node) -> bool:
	if not is_instance_valid(root): return false
	if root.get("saving") == true or root.get("returning_map") == true: return true
	for child in root.get_children():
		if _window_editor_busy(child): return true
	return false

func _request_window_close() -> void:
	if window_close_busy or is_instance_valid(window_close_layer) or _visible_confirmation(self): return
	var editor := _window_editor()
	if _window_editor_busy(editor): return
	var instance := _window_instance(self)
	var dirty: bool = editor != null and editor.has_unsaved_changes()
	if instance != null: dirty = dirty or instance.editor.has_unsaved_changes()
	if adventure.is_empty() and not dirty:
		_quit_application()
		return
	window_close_layer = CanvasLayer.new()
	window_close_layer.layer = 150
	add_child(window_close_layer)
	var modal := Modal.new()
	modal.theme = GoUi.theme()
	window_close_layer.add_child(modal)
	var description := "是否保存当前修改后退出？已保存的内容会保留。"
	if not adventure.is_empty():
		description = "是否保存当前冒险后退出？" if session_role == "dm" else "退出当前团并关闭软件。"
		if instance != null and instance.editor.has_unsaved_changes():
			description += "保存会先应用棋子修改。" if session_role == "dm" else "尚未应用的棋子修改将放弃。"
	modal.configure("退出软件", description)
	modal.add_action("取消", modal.dismiss)
	if (adventure.is_empty() or session_role == "dm") and (editor == null or editor.get("created") != false):
		modal.add_action("保存并退出", func():
			window_close_busy = true
			modal.dismiss_enabled = false
			for child in modal.content.get_children():
				if child is Button: child.disabled = true
			var succeeded: bool = await _save_for_window_close(editor, instance)
			if succeeded:
				_quit_application()
			else:
				window_close_busy = false
				modal.dismiss_enabled = true
				modal.dismiss()
		, true)
	modal.add_action("不保存退出" if adventure.is_empty() or session_role == "dm" else "退出软件", _quit_application, false, true, true)
	modal.dismissed.connect(func():
		_restore_window_close_modes()
		if is_instance_valid(window_close_layer): window_close_layer.queue_free()
		window_close_layer = null
	)
	# Disable underlying input while retaining the page, camera and editor state.
	window_close_modes.clear()
	for node in [$Pages, board, token_edit_layer, tray_controller.overlay]:
		if is_instance_valid(node):
			window_close_modes[node] = node.process_mode
			node.process_mode = Node.PROCESS_MODE_DISABLED

func _restore_window_close_modes() -> void:
	for node in window_close_modes:
		if is_instance_valid(node): node.process_mode = window_close_modes[node]
	window_close_modes.clear()

func _save_for_window_close(editor: Control, instance: Control) -> bool:
	if is_instance_valid(instance):
		if not instance.editor._save(): return false
		instance.hide()
		instance.closed.emit()
		instance.queue_free()
	if not adventure.is_empty():
		if is_instance_valid(tray_controller.overlay): tray_controller._close_overlay()
		if is_instance_valid(tray_controller.panel): tray_controller.panel.close()
		return _save_adventure()
	if editor == null: return true
	# A map embedded in the adventure saves through its existing parent delegate.
	if is_instance_valid(editor.get("child_editor")):
		return await editor.child_editor._save()
	return await editor._save()

func _quit_application() -> void:
	if quitting: return
	_discard_retained_network_page()
	if is_instance_valid(current_page): current_page.clear_sensitive_fields()
	quitting = true
	window_close_busy = true
	network_session.close()
	await network_session.transport.wait_for_close()
	get_tree().quit()

func _open_updates() -> void:
	if is_instance_valid(session_modal) or is_instance_valid(token_edit_layer): return
	_navigate("settings")
	if current_route=="settings" and current_page!=null and current_page.has_meta("settings_editor"):
		current_page.get_meta("settings_editor")._select("updates")
