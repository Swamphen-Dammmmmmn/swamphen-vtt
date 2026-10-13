extends VBoxContainer
const Instance = preload("res://scripts/token_instance.gd")
const Footprint = preload("res://scripts/token_footprint.gd")
const Landing = preload("res://scripts/platform_landing.gd")
const Palette = preload("res://ui/components/creation_palette.gd")
const Creation = preload("res://ui/components/token_create.tscn")
const Modal = preload("res://ui/components/page_modal.gd")
const FullEditor = preload("res://ui/components/instance_token_editor.gd")
const Style = preload("res://ui/components/page_style.gd")
var editor: Control
var palette: PanelContainer
var creation: Control
var actions: ScrollContainer
const CurrentSelection = preload("res://ui/components/current_selection.gd")
const Overlap = preload("res://ui/components/overlap_actions.gd")
var current_selection: PanelContainer
var action_target := ""
var hover_ids: Array[String] = []
var layer: Node3D
var actors: Dictionary = {}
var draft := {}
var ghost: Node3D
var footprint: Node3D
var selected := ""
var moving := ""
var dragging := false
var candidate := Vector2i.ZERO
var valid := false
var footprint_cache := {}
var modal: Control
var full_editor: Control
var active := false

func _ready() -> void:
	add_theme_constant_override("separation",12)
	current_selection = CurrentSelection.new()
	add_child(current_selection)
	current_selection.cleared.connect(cancel)
	palette = Palette.new()
	editor.add_child(palette)
	palette.entry_chosen.connect(_choose)
	creation = Creation.instantiate()
	editor.add_child(creation)
	creation.placement_requested.connect(begin)
	actions = Overlap.new()
	editor.add_child(actions)
	actions.action_requested.connect(func(target: Dictionary, action: String, _anchor: Rect2):
		selected = target["id"]
		action_target = ""
		_refresh_selection_card()
		match action:
			"select":
				hover_ids.clear()
				hover_ids.append(selected)
				_show_actions()
			"edit": _edit()
			"move": _move()
			"copy": _copy()
			"delete": _delete()
	)
	actions.target_hovered.connect(func(target: Dictionary):
		action_target = target.get("id","")
		if action_target.is_empty(): _clear_footprint()
		else: _highlight()
	)
	layer = Node3D.new()
	editor.preview.world.add_child(layer)
	editor.values.get_or_add("tokens",[])
	refresh()

func refresh() -> void:
	for actor in actors.values(): actor.queue_free()
	actors.clear()
	for data: Dictionary in editor.values.get("tokens",[]):
		var actor := Instance.build(data)
		layer.add_child(actor)
		actor.position = _world(data["cell"],Footprint.dimensions(data))
		actors[data["id"]] = actor
	_refresh_selection_card()

func _refresh_selection_card() -> void:
	current_selection.configure(draft if not draft.is_empty() else ({} if selected.is_empty() else _data(selected)),"待放置" if not draft.is_empty() else ("待移动" if not moving.is_empty() else "已选中"))

func _data(id := "") -> Dictionary:
	for data: Dictionary in editor.values.get("tokens",[]):
		if data["id"]==((action_target if not action_target.is_empty() else selected) if id.is_empty() else id): return data
	return {}

func _world(cell: Vector2i, extent: Vector2i) -> Vector3:
	var origin: Vector2 = editor.values["grid_origin_feet"]/5.0
	return Vector3(origin.x+cell.x+extent.x/2.0,float(editor.values["top_feet"])/5.0,origin.y+cell.y+extent.y/2.0)

func _cell(point: Vector2):
	var at = editor.preview.top_point(point)
	if at==null: return null
	var local: Vector2 = (at-editor.values["grid_origin_feet"])/5.0
	return Vector2i(floori(local.x),floori(local.y))

func _fits(cell: Vector2i, extent: Vector2i) -> bool:
	if not Landing.bounds(editor.values).encloses(Rect2i(cell,extent)): return false
	var permitted := Landing.cells(editor.values)
	for z in range(cell.y,cell.y+extent.y):
		for x in range(cell.x,cell.x+extent.x):
			if not permitted.has(Vector2i(x,z)): return false
	return true

func set_active(key: String) -> void:
	cancel()
	active = key in ["object_select","token_basic","token_advanced"]
	visible = active
	if key in ["token_basic","token_advanced"]:
		palette.open(editor._panel_edge()+editor.panel.size.x+12,"basic" if key=="token_basic" else "advanced")

func _choose(entry: Dictionary) -> void:
	palette.close()
	if entry.get("builtin",false):
		creation.open_creation()
	else: begin(entry["parameters"])

func begin(parameters: Dictionary) -> void:
	cancel()
	draft = parameters.duplicate(true)
	_refresh_selection_card()
	ghost = Instance.build(draft,true)
	layer.add_child(ghost)
	ghost.hide()
	preload("res://ui/components/editor_layout.gd").set_status(editor.status,"" if not editor.values["landing_cells"].is_empty() else "请先在摆放区域工具中允许棋子摆放。",editor.values["landing_cells"].is_empty())
	editor._queue_fit()

func cancel() -> void:
	if not moving.is_empty(): _finish_move(false)
	dragging = false
	moving = ""
	selected = ""
	action_target = ""
	hover_ids.clear()
	draft.clear()
	if is_instance_valid(ghost): ghost.queue_free()
	ghost = null
	_clear_footprint()
	if is_instance_valid(palette): palette.close()
	if is_instance_valid(creation): creation.close()
	if is_instance_valid(actions): actions.hide()
	if is_instance_valid(current_selection): _refresh_selection_card()

func blocked() -> bool:
	return (is_instance_valid(modal) and modal.visible) or is_instance_valid(full_editor) or (is_instance_valid(creation) and creation.visible)

func over_ui(point: Vector2) -> bool:
	return (palette.visible and palette.get_global_rect().has_point(point)) or (creation.visible and creation.get_global_rect().has_point(point)) or (actions.visible and actions.get_global_rect().has_point(point))

func pause() -> void:
	if not moving.is_empty(): _finish_move(false)
	if is_instance_valid(ghost): ghost.hide()
	_clear_footprint()
	actions.hide()

func _fade(node: Node, amount: float) -> void:
	if node is GeometryInstance3D: node.transparency = amount
	for child in node.get_children(): _fade(child,amount)

func _finish_move(commit: bool) -> void:
	var data := _data(moving)
	if commit and not data.is_empty():
		data["cell"] = candidate
		editor._mark_unsaved()
	if actors.has(moving):
		_fade(actors[moving],0.0)
		if not data.is_empty(): actors[moving].position = _world(data["cell"],Footprint.dimensions(data))
	moving = ""
	dragging = false
	if is_instance_valid(ghost): ghost.queue_free()
	ghost = null
	_clear_footprint()
	_refresh_selection_card()

func handle_pointer(event: InputEvent, on_ui: bool) -> bool:
	if not active or blocked(): return false
	if event is InputEventMouseButton and event.pressed and event.button_index==MOUSE_BUTTON_RIGHT and not moving.is_empty():
		_finish_move(false)
		return true
	if not event is InputEventMouseButton or event.button_index!=MOUSE_BUTTON_LEFT or not event.pressed or on_ui: return false
	if not moving.is_empty():
		_update_pointer(event.position)
		if valid: _finish_move(true)
		return true
	if not draft.is_empty():
		_update_pointer(event.position)
		if valid and editor.values["tokens"].size()<4096:
			var data := draft.duplicate(true)
			data["id"] = Crypto.new().generate_random_bytes(16).hex_encode()
			data["cell"] = candidate
			editor.values["tokens"].append(data)
			selected = data["id"]
			refresh()
			editor._mark_unsaved()
		return true
	var hits := _picks(event.position)
	action_target = ""
	hover_ids = hits
	selected = hits[0] if hits.size()==1 else ""
	_refresh_selection_card()
	_clear_footprint()
	if hits.is_empty(): actions.hide()
	else: _show_actions()
	return not hits.is_empty()

func _picks(point: Vector2) -> Array[String]:
	var camera: Camera3D = editor.preview.camera
	var screen: Vector2 = editor.preview.screen_point(point)
	var origin := camera.project_ray_origin(screen)
	var end := origin+camera.project_ray_normal(screen)*10000.0
	var hits: Array[Dictionary] = []
	for data: Dictionary in editor.values.get("tokens",[]):
		var actor: Node3D = actors.get(data["id"])
		if actor==null: continue
		var extent := Footprint.dimensions(data)
		var bounds: AABB = actor.get_meta("appearance_bounds",AABB(Vector3(-extent.x/2.0,0,-extent.y/2.0),Vector3(extent.x,float(data["size"]),extent.y)))
		var hit = bounds.intersects_segment(origin-actor.position,end-actor.position)
		if hit!=null:
			var distance := origin.distance_squared_to(hit+actor.position)
			hits.append({"id":data["id"],"distance":distance})
	hits.sort_custom(func(a: Dictionary,b: Dictionary): return a["distance"]<b["distance"])
	var result: Array[String] = []
	for hit in hits: result.append(hit["id"])
	return result

func _pick(point: Vector2) -> String:
	var hits := _picks(point)
	return "" if hits.is_empty() else hits[0]

func _update_pointer(point: Vector2) -> void:
	var cell = _cell(point)
	valid = false
	if cell==null:
		if ghost!=null: ghost.hide()
		_clear_footprint()
		return
	candidate = cell
	var data: Dictionary = _data(moving) if not moving.is_empty() else draft
	if data.is_empty(): return
	var extent := Footprint.dimensions(data)
	valid = _fits(candidate,extent)
	var node: Node3D = ghost
	node.show()
	node.position = _world(candidate,extent)
	var cache := {"cell":candidate,"extent":extent,"valid":valid}
	if cache==footprint_cache: return
	_clear_footprint()
	footprint_cache = cache
	footprint = editor.preview._rect_overlay(Rect2i(candidate,extent),Color("28785e") if valid else Color("c94343"),0.22,true)
	layer.add_child(footprint)

func _clear_footprint() -> void:
	footprint_cache.clear()
	if is_instance_valid(footprint): footprint.queue_free()
	footprint = null

func _process(_delta: float) -> void:
	if not active or editor._camera_blocked() or editor.rotating:
		pause()
		return
	var point := get_global_mouse_position()
	if not draft.is_empty() or not moving.is_empty():
		if not editor._over_ui(point): _update_pointer(point)
		else:
			if ghost!=null: ghost.hide()
			valid = false
			_clear_footprint()
		return
	if not hover_ids.is_empty(): _position_actions()
	if actions.visible and actions.get_global_rect().grow(12).has_point(point): return
	action_target = ""
	if not editor._over_ui(point): action_target = _pick(point)
	if action_target.is_empty(): action_target = selected
	if not action_target.is_empty(): _highlight()
	else: _clear_footprint()

func _show_actions() -> void:
	if hover_ids.is_empty() and not selected.is_empty(): hover_ids = [selected]
	_position_actions()

func _position_actions() -> void:
	var entries: Array[Dictionary] = []
	var camera: Camera3D = editor.preview.camera
	var anchor := Vector2.ZERO
	for id in hover_ids:
		if not actors.has(id): continue
		var data := _data(id)
		var actor: Node3D = actors[id]
		var bounds: AABB = actor.get_meta("appearance_bounds",AABB(Vector3.ZERO,Vector3(1,float(data["size"]),1)))
		var at := actor.position+Vector3.UP*(bounds.end.y+0.25)
		if camera.is_position_behind(at): continue
		if entries.is_empty(): anchor = camera.unproject_position(at)*editor.preview.size/Vector2(editor.preview.viewport.size)+editor.preview.global_position
		entries.append({"id":id,"label":"棋子 · "+str(data["title"]),"actions": [["select","选择"]] if hover_ids.size()>1 else [["edit","编辑"],["move","移动"],["copy","复制"],["delete","删除"]]})
	if entries.is_empty(): actions.hide(); return
	actions.present(entries,anchor,editor.size,editor._panel_edge())

func _move() -> void:
	moving = selected
	var data := _data(moving)
	if data.is_empty(): moving = ""; return
	ghost = Instance.build(data,true)
	layer.add_child(ghost)
	ghost.hide()
	_fade(ghost,0.25)
	_fade(actors[moving],0.65)
	valid = false
	actions.hide()
	_refresh_selection_card()

func _copy() -> void:
	var data := _data().duplicate(true)
	data.erase("id")
	data.erase("cell")
	begin(data)

func _delete() -> void:
	var data := _data()
	if data.is_empty(): return
	var id: String = data["id"]
	modal = Modal.new()
	editor.page.add_overlay(modal)
	modal.configure("删除棋子？","删除“%s”？棋子库原件不受影响。" % data["title"])
	modal.add_action("取消",modal.dismiss)
	modal.add_action("删除",func():
		modal.dismiss()
		for index in range(editor.values["tokens"].size()):
			if editor.values["tokens"][index]["id"]==id:
				editor.values["tokens"].remove_at(index)
				break
		selected = ""
		action_target = ""
		hover_ids.clear()
		_clear_footprint()
		refresh()
		actions.hide()
		editor._mark_unsaved()
	,false,true,true)

func _edit() -> void:
	var data := _data().duplicate(true)
	if data.is_empty(): return
	pause()
	editor._release_camera()
	_open_editor(data)

func _open_editor(data: Dictionary) -> void:
	var id: String = data["id"]
	full_editor = FullEditor.new()
	full_editor.data = data
	editor.page.add_overlay(full_editor)
	editor.preview.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	editor.preview.set_process(false)
	full_editor.applied.connect(func(params: Dictionary):
		var target := _data(id)
		if target.is_empty() or Footprint.dimensions(target)!=Footprint.dimensions(params): return
		target.merge(params,true)
		refresh()
		editor._mark_unsaved()
	)
	full_editor.closed.connect(func():
		full_editor = null
		editor.preview.viewport.render_target_update_mode = SubViewport.UPDATE_ALWAYS
		editor.preview.set_process(true)
	)

func _highlight() -> void:
	var data := _data()
	if data.is_empty(): return
	var cache := {"highlight":data["id"],"cell":data["cell"],"extent":Footprint.dimensions(data)}
	if cache==footprint_cache: return
	_clear_footprint()
	footprint_cache = cache
	footprint = editor.preview._rect_overlay(Rect2i(data["cell"],Footprint.dimensions(data)),Color("2563a6"),0.18,true)
	layer.add_child(footprint)
