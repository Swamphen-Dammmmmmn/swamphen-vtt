extends Node

const LibraryPresentation = preload("res://ui/components/features/library/library_presentation.gd")
const Members = preload("res://scripts/adventure_members.gd")
const Trays = preload("res://scripts/adventure_trays.gd")
const TrayPanel = preload("res://ui/components/adventure_tray_panel.gd")
const Modal = preload("res://ui/components/page_modal.gd")
const Shell = preload("res://ui/components/page_shell.tscn")
const Library = preload("res://ui/pages/token_library.gd")
const TokenStore = preload("res://scripts/token_library_store.gd")
const Editor = preload("res://ui/components/instance_token_editor.gd")
const Style = preload("res://ui/components/page_style.gd")
const Data = preload("res://scripts/map_data.gd")
var application: Node
var board: Node3D
var panel: Control
var overlay: CanvasLayer

func attach(scene: Node3D) -> void:
	board = scene
	panel = TrayPanel.new()
	panel.values = application.adventure["trays"]
	panel.z_index = 7
	board.ui.add_child(panel)
	panel.tray_action.connect(_action)
	panel.state_changed.connect(func(_key: String, opened: bool): board.ui.set_tray_navigation_active(opened))
	board.ui.tray_requested.connect(_toggle)
	board.ui.creation_palette.state_changed.connect(func(_category: String, opened: bool):
		if opened: panel.close()
	)
	board.token_tray_requested.connect(_collect)
	board.tray_placement_completed.connect(_placed)
	_refresh()

func blocked() -> bool:
	return is_instance_valid(overlay) or (is_instance_valid(panel) and is_instance_valid(panel.options) and panel.options.is_open)

func _refresh() -> void:
	if not is_instance_valid(panel): return
	panel.allowed_keys = []
	panel.permitted_ids = {}
	panel.personal_key = Members.tray_key(application.session_actor)
	panel.member_names = {}
	for member in application.adventure["party"]["members"]: panel.member_names[member] = application.adventure["party"]["members"][member]["nickname"]
	var count := 0
	for key in application.adventure["trays"]:
		if Members.can_tray(application.adventure["party"],application.session_actor,key):
			panel.allowed_keys.append(key)
			count += application.adventure["trays"][key].size()
			for token: Dictionary in application.adventure["trays"][key]:
				if Members.can_token(application.adventure["party"],application.session_actor,token["id"]): panel.permitted_ids[token["id"]] = true
	panel.refresh(application.adventure["trays"])
	board.ui.tray_button.text = "棋子托盘 · %d" % count

func _toggle() -> void:
	if blocked() or not application.adventure["party"]["members"].has(application.session_actor): return
	if panel.visible: panel.close(); return
	board.prepare_session_switch()
	board.ui.creation_palette.close()
	panel.open(board.ui.sidebar_right(),panel.category)

func _find(id: String) -> Dictionary:
	for key in application.adventure["trays"]:
		for data: Dictionary in application.adventure["trays"][key]:
			if data["id"]==id: return {"key":key,"token":data}
	return {}

func _action(action: String, id: String) -> void:
	if blocked() or application.session_role=="pl" and board.network_readonly: return
	if action=="add": _pick_library(); return
	var found := _find(id)
	if found.is_empty(): return
	var token: Dictionary = found["token"]
	if not Members.can_tray(application.adventure["party"],application.session_actor,found["key"]) or not Members.can_token(application.adventure["party"],application.session_actor,id): return
	match action:
		"place":
			panel.close()
			board.begin_tray_placement(token)
		"transfer":
			var target: String = "public" if found["key"]!="public" else Members.tray_key(application.session_actor)
			if not Members.can_store(application.adventure["party"],application.session_actor,id,target): return
			if not _room(target): return
			application.adventure["trays"][found["key"]].erase(token)
			application.adventure["trays"][target].append(token)
			_refresh()
		"copy":
			if not _room(found["key"]): return
			var copy := token.duplicate(true)
			copy["id"] = Data.new_id()
			application.adventure["party"]["owners"][copy["id"]] = application.adventure["party"]["owners"].get(id,"dm")
			copy["title"] = str(copy["title"]).left(35)+" · 副本"
			application.adventure["trays"][found["key"]].append(copy)
			panel.selected_id = copy["id"]
			_refresh()
		"delete":
			var dialog := _dialog("删除托盘棋子？","删除“%s”？棋子库原件不受影响。" % token["title"])
			dialog.add_action("取消",dialog.dismiss)
			dialog.add_action("删除",func():
				application.adventure["trays"][found["key"]].erase(token)
				dialog.dismiss()
				_refresh()
			,false,true,true)
		"edit": _edit(token)

func _room(key: String) -> bool:
	if application.adventure["trays"][key].size()<Trays.LIMIT: return true
	var dialog := _dialog("托盘已满","每个托盘最多保存4096枚棋子。")
	dialog.add_action("继续",dialog.dismiss)
	return false

func _collect(data: Dictionary) -> void:
	if blocked() or not Members.can_token(application.adventure["party"],application.session_actor,data["persistent_id"]): return
	var count := 0
	for plan in board.measurements:
		if board._measurement_bound_to(plan,int(data["id"])): count += 1
	var message := "将“%s”收入哪个托盘？" % data["title"]
	if count>0: message += "\n与它绑定的%d条测距将从当前地图移除。" % count
	var dialog := _dialog("收纳棋子",message)
	for key: String in application.adventure["trays"]:
		if not Members.can_store(application.adventure["party"],application.session_actor,data["persistent_id"],key): continue
		dialog.add_action(panel.tray_title(key),func(): _collect_into(data,key,dialog),false,application.adventure["trays"][key].size()<Trays.LIMIT)
	dialog.add_action("取消",dialog.dismiss)

func _collect_into(data: Dictionary, key: String, dialog: Control) -> void:
	if application.adventure["trays"][key].size()>=Trays.LIMIT or not Members.can_store(application.adventure["party"],application.session_actor,data["persistent_id"],key): return
	var token := Trays.token(data)
	token["id"] = data["persistent_id"]
	board._delete_token(int(data["id"]))
	board.export_session_tokens()
	application.adventure["trays"][key].append(token)
	dialog.dismiss()
	_refresh()
	panel.open(board.ui.sidebar_right(),key)

func _placed(id: String) -> void:
	var found := _find(id)
	if found.is_empty(): return
	application.adventure["trays"][found["key"]].erase(found["token"])
	board.export_session_tokens()
	_refresh()

func _overlay(keep_board := true) -> CanvasLayer:
	board.set_application_active(false,keep_board)
	panel.options.close()
	overlay = CanvasLayer.new()
	overlay.layer = 100
	application.add_child(overlay)
	return overlay

func _close_overlay() -> void:
	if is_instance_valid(overlay): overlay.queue_free()
	overlay = null
	if is_instance_valid(board): board.set_application_active(true)

func _dialog(title: String, message: String) -> Control:
	var layer := _overlay()
	var dialog := Modal.new()
	dialog.theme = GoUi.theme()
	layer.add_child(dialog)
	dialog.configure(title,message)
	dialog.dismissed.connect(_close_overlay)
	return dialog

func _edit(token: Dictionary) -> void:
	var layer := _overlay(false)
	var editor := Editor.new()
	editor.tray_mode = true
	editor.data = token.duplicate(true)
	layer.add_child(editor)
	editor.applied.connect(func(parameters: Dictionary):
		token.merge(parameters,true)
		token.merge(Trays.token(token),true)
		_refresh()
	)
	editor.closed.connect(_close_overlay)

func _pick_library() -> void:
	var key: String = panel.category
	if not Members.can_tray(application.adventure["party"],application.session_actor,key) or not _room(key): return
	var layer := _overlay(false)
	var root := Control.new()
	layer.add_child(root)
	root.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var background := ColorRect.new()
	background.color = Style.BACKGROUND
	root.add_child(background)
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	var page := Shell.instantiate()
	root.add_child(page)
	page.configure_library("从棋子库添加", "tokens", LibraryPresentation.Mode.SELECT)
	page.back_requested.connect(_close_overlay)
	var library := Library.new()
	library.mode = LibraryPresentation.Mode.SELECT
	library.page = page
	page.content.add_child(library)
	var loaded := TokenStore.read_catalog()
	var records: Array[Dictionary] = []
	for entry in loaded["entries"]: records.append(entry)
	library.set_entries(records,loaded["error"],loaded["warnings"])
	library.edit_requested.connect(func(id: String):
		var record := TokenStore.get_record(id)
		if not record["ok"]:
			var error := Modal.new()
			page.add_overlay(error)
			error.configure("无法添加",record["message"])
			error.add_action("继续",error.dismiss)
			return
		var token := Trays.from_library(record["record"])
		application.adventure["party"]["owners"][token["id"]] = key.trim_prefix("member:") if key.begins_with("member:") else application.session_actor
		application.adventure["trays"][key].append(token)
		_close_overlay()
		panel.selected_id = token["id"]
		_refresh()
	)
	page.reveal()
