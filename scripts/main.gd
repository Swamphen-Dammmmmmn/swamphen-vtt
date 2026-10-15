extends Node3D
var mobile_touch: Node
signal full_token_edit_requested(data: Dictionary)
signal token_tray_requested(data: Dictionary)
signal tray_placement_completed(id: String)
var tray_placement_id := ""
var session_map: Dictionary = {}
var session_map_id := ""
const Members = preload("res://scripts/adventure_members.gd")
var session_party: Dictionary = Members.defaults()
var session_actor := "dm"
var network_readonly := false
var surfaces: RefCounted
var ground_renderer: Control
var placement_surface := ""
var session_distance_mode := 0
var session_load_error := ""
const SessionSurface = preload("res://scripts/session_surface.gd")
const MapPreview = preload("res://ui/components/map_preview.gd")
const Instance = preload("res://scripts/token_instance.gd")
const OrbitCamera = preload("res://scripts/orbit_camera.gd")

const Rules = preload("res://scripts/distance_rules.gd")
const RoutePlan = preload("res://scripts/route_plan.gd")
const MeasurementPlan = preload("res://scripts/measurement_plan.gd")
const CampaignSettings = preload("res://scripts/campaign_settings.gd")
const ShapePlan = preload("res://scripts/shape_plan.gd")
const BoardUI = preload("res://ui/board_ui.gd")
const UI_SCENE = preload("res://ui/board_ui.tscn")
const Footprint = preload("res://scripts/token_footprint.gd")
const Components = preload("res://scripts/token_components.gd")
const TokenAppearance = preload("res://scripts/token_appearance.gd")
const EnvironmentProfile = preload("res://scripts/environment_profile.gd")

enum Tool { SELECT, MEASURE, ROUTE, SHAPE, TOKEN_CREATE }
var token_draft: Dictionary = {}
var token_preview: Node3D
var token_footprint: MeshInstance3D
var token_placement_cell := Vector2i(-100, -100)
var token_placement_fixed := false
var token_cancel_anchor := Vector3.ZERO
var shape_plan := ShapePlan.new()
var shape_layer: Node3D
var entity_entries: Array[Dictionary] = []
var entity_anchor := Vector3.ZERO
var entity_timeout := 0.0
var highlighted_token := -1
var next_measurement_id := 1
var hover_shape := -1
var tool := Tool.SELECT
var tokens: Array[Dictionary] = []
var turn_control: Control
var next_token_id := 0
var camera: Camera3D
var ui: BoardUI
var focus := Vector3.ZERO
var yaw := 0.58
var pitch := 0.85
var camera_distance := 52.0
var camera_preferences = preload("res://scripts/camera_preferences.gd").shared()
var camera_render_focus := Vector3.ZERO
var camera_render_angles := Vector2(0.58, 0.85)
var camera_render_distance := 52.0
var camera_initialized := false
var camera_button := 0
var left_orbit_pending := false
var left_press_position := Vector2.ZERO
const LEFT_ORBIT_THRESHOLD := 8.0
var selected := -1
var hover_token := -1
var hover_timeout := 0.0
var campaign_settings := CampaignSettings.new()
var distance_mode: int:
	get:
		return campaign_settings.distance_mode
var movement_route := RoutePlan.new()
var measurement := MeasurementPlan.new()
var measurements: Array[MeasurementPlan] = []
var route: RoutePlan = movement_route
var selected_point := -1
var path_line: MeshInstance3D
var measurement_lines: Node3D
var hover_measurement := -1
var hover_measurement_point := -1
var measurement_edit_fixed := false
var deleted_measurement: Dictionary = {}
var point_markers: Node3D
var measure_start := Vector2i.ZERO
var measure_end := Vector2i.ZERO
var measure_has_start := false
var measure_finished := false
var measure_creating := false
var continuation_snapshot: Dictionary = {}
var creation_action_anchor := Vector3.ZERO
var shape_edit_anchor := Vector3.ZERO
var start_marker: MeshInstance3D
var end_marker: MeshInstance3D

func _ready() -> void:
	_mobile_attach.call_deferred()
	campaign_settings.persist_to_file = false
	campaign_settings.distance_mode = session_distance_mode
	campaign_settings.storage_message = "计距方式随当前冒险保存。"
	_build_world()
	for platform: Dictionary in session_map["platforms"]:
		surfaces.current = platform["id"]
		for data: Dictionary in platform["data"].get("tokens",[]):
			var previous_count := tokens.size()
			_add_token(data["title"],data["cell"]+surfaces.origin(platform),data["size"],data["color"],data["hp"],data["ac"],data["base"],data["max_hp"],data.get("kind","basic"),data.get("tags",[]),Footprint.dimensions(data),data.get("components",{}), data.get("materials", {}))
			if tokens.size()==previous_count:
				session_load_error = "部分棋子无法生成，已阻止覆盖保存。请返回后检查原冒险内容。"
				continue
			Instance.apply_parameters(tokens[-1],data)
			Instance.apply_orientation(tokens[-1]["node"],tokens[-1])
			tokens[-1]["persistent_id"] = data["id"]
			tokens[-1]["platform_id"] = platform["id"]
	var layer := CanvasLayer.new()
	add_child(layer)
	ui = UI_SCENE.instantiate() as BoardUI
	layer.add_child(ui)
	turn_control = preload("res://ui/components/token_turn_control.gd").new()
	ui.add_child(turn_control)
	turn_control.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	turn_control.z_index = 8
	ui.set_map_title(session_map["title"])
	ui.get_node("BoardInfo").hide()
	ui.tool_requested.connect(_on_tool)
	ui.token_placement_requested.connect(_begin_token_placement)
	ui.token_appearance_saved.connect(_save_token_appearance)
	ui.token_deletion_confirmed.connect(_delete_token)
	ui.token_placement_action_requested.connect(_on_token_placement_action)
	ui.shape_parameters_changed.connect(_on_shape_parameters)
	ui.shape_action_requested.connect(_on_shape_action)
	ui.configure_campaign_settings(campaign_settings)
	ui.campaign_mode_requested.connect(campaign_settings.select_distance_mode)
	campaign_settings.distance_mode_changed.connect(_on_campaign_mode_changed)
	ui.token_action_requested.connect(_on_token_action)
	ui.point_action_requested.connect(_on_point_action)
	ui.path_point_selected.connect(_select_path_point)
	ui.measurement_action_requested.connect(_on_measurement_action)
	ui.entity_action_requested.connect(_on_entity_action)
	ui.entity_hovered.connect(_highlight_entity)
	ui.entity_selection_requested.connect(_left_click)
	ui.token_renamed.connect(_rename_token)
	ui.token_stats_changed.connect(_update_token_stats)
	ui.token_notes_changed.connect(func(index: int,text: String):
		if can_operate_token(index): tokens[index]["notes"] = text.left(Instance.MAX_NOTES)
	)
	ui.route_action_requested.connect(_on_route_action)
	_update_status()

func _material(color: Color, unshaded: bool = false) -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = color
	mat.roughness = 0.85
	if unshaded:
		mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	if color.a < 1.0:
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return mat

func set_application_active(active: bool, keep_visible := false) -> void:
	if is_instance_valid(mobile_touch): mobile_touch.reset()
	# Navigation pauses editing without cancelling drafts or changing board data.
	camera_button = 0
	left_orbit_pending = false
	process_mode = Node.PROCESS_MODE_INHERIT if active else Node.PROCESS_MODE_DISABLED
	visible = active or keep_visible
	ui.visible = active or keep_visible
	camera.current = active or keep_visible
	ui.set_navigation_suspended(not active)
	if active: ui.set_map_navigation_active(false)
	if not active:
		turn_control.close()
		ui.suspend_pointer_input()
		_hide_navigation_popups(ui)

func _hide_navigation_popups(node: Node) -> void:
	if node is Popup:
		node.hide()
	for child in node.get_children():
		_hide_navigation_popups(child)

func _box(parent: Node3D, dimensions: Vector3, at: Vector3, mat: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	var node := MeshInstance3D.new()
	node.mesh = mesh
	node.material_override = mat
	node.position = at
	parent.add_child(node)
	return node

func _build_world() -> void:
	surfaces = SessionSurface.new()
	surfaces.board = self
	surfaces.platforms = session_map["platforms"]
	ground_renderer = MapPreview.new()
	add_child(ground_renderer)
	ground_renderer.hide()
	ground_renderer.finish_platform_edit()
	ground_renderer.world.reparent(self)
	ground_renderer.viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	ground_renderer.camera.current = false
	ground_renderer.play_mode = true
	ground_renderer.set_map_grid(false)
	ground_renderer.set_permissions(false)
	for platform: Dictionary in session_map["platforms"]:
		var visual := platform.duplicate(true)
		visual["data"]["tokens"] = []
		ground_renderer.add_platform(visual)
	ground_renderer.apply_weather(session_map["environment"])
	camera = Camera3D.new()
	camera.projection = Camera3D.PROJECTION_PERSPECTIVE
	camera.fov = 45.0
	camera.current = true
	camera.near = 0.1
	camera.far = 1000000.0
	add_child(camera)
	if surfaces!=null:
		ground_renderer.camera = camera
		if not session_map["platforms"].is_empty():
			var bounds: AABB = preload("res://scripts/map_data.gd").bounds(session_map["platforms"][0])
			for platform: Dictionary in session_map["platforms"]: bounds = bounds.merge(preload("res://scripts/map_data.gd").bounds(platform))
			focus = bounds.get_center()/5
			camera_distance = maxf(12,bounds.size.length()/5*1.4)
	_update_camera()
	path_line = MeshInstance3D.new()
	path_line.material_override = _material(Color("86d4ed"), true)
	path_line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(path_line)
	measurement_lines = Node3D.new()
	add_child(measurement_lines)
	point_markers = Node3D.new()
	add_child(point_markers)
	shape_layer = Node3D.new()
	add_child(shape_layer)
	start_marker = _box(self, Vector3(0.92, 0.014, 0.92), Vector3.ZERO, _material(Color(0.36, 0.85, 0.85, 0.55), true))
	end_marker = _box(self, Vector3(0.92, 0.014, 0.92), Vector3.ZERO, _material(Color(0.95, 0.78, 0.4, 0.6), true))
	start_marker.hide()
	end_marker.hide()

func _build_token_actor(cell: Vector2i, size: int, color: Color, base: String, index: int, extent := Vector2i.ZERO, components: Dictionary = {}, materials: Dictionary = {}) -> Node3D:
	if extent == Vector2i.ZERO:
		extent = Vector2i.ONE * size
	var actor: Node3D
	if components.is_empty():
		actor = TokenAppearance.build(size, color, base, false, materials)
	else:
		var checked := Components.validate(components, extent)
		if not checked["ok"]:
			push_error(checked["message"])
			return null
		actor = Components.build(checked)
	add_child(actor)
	actor.position = _cell_world(cell,extent,tokens[index].get("platform_id","") if index<tokens.size() else "")
	var body := StaticBody3D.new()
	body.set_meta("rule_proxy",true)
	body.set_meta("token_index", index)
	var collider := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(extent.x * 0.9, size * 0.85 + 0.2, extent.y * 0.9)
	if actor.has_meta("appearance_bounds"):
		var bounds: AABB = actor.get_meta("appearance_bounds")
		shape.size.y = maxf(0.2, bounds.end.y)
		# Actual visible meshes get their own pick shapes; the rule proxy stays inside the footprint.
		for component in actor.get_children():
			if component is MeshInstance3D and component.visible:
				var component_body := StaticBody3D.new()
				component_body.set_meta("token_index", index)
				var component_collider := CollisionShape3D.new()
				var component_shape := ConvexPolygonShape3D.new()
				var vertices: PackedVector3Array = component.mesh.get_faces()
				for vertex in range(vertices.size()):
					vertices[vertex] = component.transform * vertices[vertex]
				component_shape.points = vertices
				component_collider.shape = component_shape
				component_body.add_child(component_collider)
				actor.add_child(component_body)
	collider.shape = shape
	collider.position.y = shape.size.y / 2.0
	body.add_child(collider)
	actor.add_child(body)
	return actor

func _add_token(title: String, cell: Vector2i, size: int, color: Color, hp: int = -1, ac: int = -1, base := "square", maximum: int = -1, kind := "basic", tags: Array = [], extent := Vector2i.ZERO, components: Dictionary = {}, materials: Dictionary = {}) -> void:
	if extent == Vector2i.ZERO:
		extent = Vector2i.ONE * size
	if not Footprint.valid({"width": extent.x, "length": extent.y}) or surfaces.find(cell,extent,surfaces.current).is_empty():
		push_error("棋子占地无效或超出地台。")
		return
	size = mini(extent.x, extent.y)
	if materials.is_empty() and components.is_empty(): materials = preload("res://scripts/token_surface.gd").basic_defaults(color)
	var actor := _build_token_actor(cell, size, color, base, tokens.size(), extent, components, materials)
	if actor == null:
		return
	tokens.append({"id": next_token_id, "title": title, "cell": cell, "size": size, "width": extent.x, "length": extent.y, "base": base, "color": color, "node": actor, "hp": hp, "max_hp": maximum if maximum >= 0 else hp, "ac": ac, "kind": kind, "tags": tags.duplicate(), "components": components.duplicate(true), "materials": materials.duplicate(true)})
	tokens[-1] = Instance.complete(tokens[-1])
	if surfaces!=null:
		tokens[-1]["persistent_id"] = preload("res://scripts/map_data.gd").new_id()
		tokens[-1]["platform_id"] = surfaces.current
	tokens[-1].merge(Instance.scene_values({}),true)
	next_token_id += 1

func _appearance_height(actor: Node3D, legacy_size: int) -> float:
	if actor.has_meta("appearance_bounds"):
		var bounds: AABB = actor.get_meta("appearance_bounds")
		return maxf(0.0, bounds.end.y)
	return legacy_size * 0.85

func _cell_world(cell: Vector2i, extent: Variant = Vector2i.ONE, platform_id := "") -> Vector3:
	var dimensions: Vector2i = extent if extent is Vector2i else Vector2i.ONE * int(extent)
	return surfaces.world(cell,dimensions,platform_id)

func _begin_token_placement(parameters: Dictionary) -> void:
	if not session_party["members"].has(session_actor) or not session_party["members"].has(parameters.get("owner_member",session_actor)): return
	if session_actor!="dm" and parameters.get("owner_member",session_actor)!=session_actor: return
	if not Footprint.valid(parameters):
		push_error("棋子占地必须是 1～15 整数格，宽和长必须同时提供。")
		return
	var extent := Footprint.dimensions(parameters)
	if parameters.get("kind", "basic") == "basic" and (extent.x != extent.y or extent.x > 5):
		push_error("基础棋子只能使用 1～5 格正方形占地。")
		return
	var component_data: Dictionary = parameters.get("components", {})
	if not component_data.is_empty():
		if parameters.get("kind", "basic") != "advanced":
			push_error("独立组件构成仅用于高级棋子。")
			return
		var checked := Components.validate(component_data, extent)
		if not checked["ok"]:
			push_error(checked["message"])
			return
		component_data = checked["components"]
	_on_tool("token_create")
	token_draft = parameters.duplicate(true)
	token_draft["width"] = extent.x
	token_draft["length"] = extent.y
	token_draft["size"] = mini(extent.x, extent.y)
	token_draft["components"] = component_data.duplicate(true)
	token_placement_fixed = false
	token_placement_cell = Vector2i(-100, -100)
	token_cancel_anchor = focus
	token_preview = TokenAppearance.build(int(token_draft["size"]), parameters["color"], parameters["base"], true, parameters.get("materials", {})) if component_data.is_empty() else Components.build(Components.validate(component_data, extent), true)
	Instance.apply_orientation(token_preview,token_draft)
	add_child(token_preview)
	token_preview.hide()
	token_footprint = MeshInstance3D.new()
	token_footprint.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(token_footprint)
	ui.release_keyboard_focus()
	_update_status()

func begin_tray_placement(parameters: Dictionary) -> void:
	_begin_token_placement(parameters)
	if not token_draft.is_empty(): tray_placement_id = parameters["id"]

func _token_placement_valid() -> bool:
	if token_draft.is_empty():
		return false
	return not surfaces.find(token_placement_cell,Footprint.dimensions(token_draft),placement_surface,true).is_empty() and _surface_token_count(placement_surface)<4096

func _surface_token_count(id: String) -> int:
	var count := 0
	for data: Dictionary in tokens:
		if data.get("platform_id", "")==id: count += 1
	return count

func _update_token_placement(mouse: Vector2) -> void:
	if token_draft.is_empty() or token_preview == null:
		return
	var cell := _mouse_cell(mouse)
	if cell == token_placement_cell and (surfaces==null or placement_surface==surfaces.current):
		return
	if surfaces!=null: placement_surface = surfaces.current
	token_placement_cell = cell
	if not _on_board(cell):
		token_preview.hide()
		token_footprint.hide()
	else:
		var extent := Footprint.dimensions(token_draft)
		token_preview.position = _cell_world(cell, extent)
		token_preview.show()
		var origin := _cell_world(cell,Vector2i.ZERO,placement_surface)
		var positions: Array[Vector3] = [origin, origin + Vector3(extent.x, 0, 0), origin + Vector3(extent.x, 0, extent.y), origin + Vector3(0, 0, extent.y), origin]
		token_footprint.mesh = _line_mesh(positions)
		token_footprint.material_override = _material(Color("429d86") if _token_placement_valid() else Color("b33c3c"), true)
		token_footprint.show()
	_update_status()

func _on_token_placement_action(action: String) -> void:
	if tool != Tool.TOKEN_CREATE or token_draft.is_empty():
		return
	if action == "confirm" and token_placement_fixed and _token_placement_valid():
		if surfaces!=null: surfaces.current = placement_surface
		var previous_count := tokens.size()
		_add_token(token_draft["title"], token_placement_cell, int(token_draft["size"]), token_draft["color"], int(token_draft["hp"]), int(token_draft["ac"]), token_draft["base"], int(token_draft["max_hp"]), token_draft.get("kind", "basic"), token_draft.get("tags", []), Footprint.dimensions(token_draft), token_draft.get("components", {}), token_draft.get("materials", {}))
		if tokens.size()==previous_count: return
		tokens[-1].merge(Instance.scene_values(token_draft),true)
		Instance.apply_orientation(tokens[-1]["node"],tokens[-1])
		if tray_placement_id.is_empty():
			session_party["owners"][tokens[-1]["persistent_id"]] = token_draft.get("owner_member",session_actor)
		if not tray_placement_id.is_empty():
			tokens[-1]["persistent_id"] = tray_placement_id
			tray_placement_completed.emit(tray_placement_id)
		selected = tokens.size() - 1
		_on_tool("select")
	elif action == "cancel":
		_on_tool("select")

func _clear_token_placement() -> void:
	for node in [token_preview, token_footprint]:
		if is_instance_valid(node):
			remove_child(node)
			node.queue_free()
	token_preview = null
	token_footprint = null
	token_draft.clear()
	tray_placement_id = ""
	token_placement_fixed = false
	token_placement_cell = Vector2i(-100, -100)
	ui.hide_token_placement_actions()

func _update_camera(delta := -1.0) -> void:
	pitch = OrbitCamera.clamp_pitch(pitch)
	if camera_preferences.values["smooth"] and camera_initialized:
		if delta < 0.0: return
		var response: float = [18.0, 10.0, 5.0][camera_preferences.values["strength"]]
		var weight := 1.0 - exp(-response * delta)
		camera_render_focus = camera_render_focus.lerp(focus, weight)
		camera_render_angles.x = lerpf(camera_render_angles.x, yaw, weight)
		camera_render_angles.y = lerpf(camera_render_angles.y, pitch, weight)
		camera_render_distance = lerpf(camera_render_distance, camera_distance, weight)
	else:
		camera_render_focus = focus
		camera_render_angles = Vector2(yaw, pitch)
		camera_render_distance = camera_distance
	camera_initialized = true
	camera_render_angles.y = OrbitCamera.clamp_pitch(camera_render_angles.y)
	var angle := camera_render_angles
	camera.position = camera_render_focus + Vector3(sin(angle.x) * cos(angle.y), sin(angle.y), cos(angle.x) * cos(angle.y)) * camera_render_distance
	camera.look_at(camera_render_focus)

func _orbit_focus() -> void:
	if selected<0 or selected>=tokens.size(): return
	var actor: Node3D = tokens[selected]["node"]
	var bounds: AABB = actor.get_meta("appearance_bounds",AABB(Vector3(-0.5,0,-0.5),Vector3.ONE))
	bounds = actor.global_transform*bounds
	focus = bounds.get_center()
	camera_distance = maxf(3,bounds.size.length()*2.0)
	camera_initialized = false
	_update_camera()

func _orbit_overview() -> void:
	if not session_map.get("platforms",[]).is_empty():
		var bounds: AABB = preload("res://scripts/map_data.gd").bounds(session_map["platforms"][0])
		for platform: Dictionary in session_map["platforms"]: bounds = bounds.merge(preload("res://scripts/map_data.gd").bounds(platform))
		focus = bounds.get_center()/5.0
		camera_distance = maxf(12,bounds.size.length()/5.0*1.4)
	else:
		focus = Vector3.ZERO
		camera_distance = 52
	camera_initialized = false
	_update_camera()

func _orbit_rotate(relative: Vector2, touch := false) -> void:
	var amount := OrbitCamera.rotation_delta(relative,get_viewport().get_visible_rect().size.y,touch)
	yaw -= amount.x
	pitch = OrbitCamera.clamp_pitch(pitch+amount.y)
	_update_camera()

func _orbit_pan(relative: Vector2, touch := false) -> void:
	focus += OrbitCamera.pan_delta(camera,camera_distance,relative,get_viewport().get_visible_rect().size.y,touch)
	_update_camera()

func _zoom_camera(direction: float) -> void:
	camera_distance = clampf(camera_distance*OrbitCamera.zoom_factor(pow(0.9,direction)),3.0,100000.0)
	_update_camera()

func _input(event: InputEvent) -> void:
	if is_instance_valid(mobile_touch) and mobile_touch.handle(event): return
	if is_instance_valid(turn_control) and turn_control.panel.visible:
		if turn_control.handle_pointer(event,ui.pointer_on_ui()):
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseButton and event.pressed and not ui.pointer_on_ui() and event.button_index==MOUSE_BUTTON_LEFT:
			turn_control.close()
	# Existing dialogs/popups get Esc before the adventure menu fallback.
	if event is InputEventKey and event.keycode == KEY_ESCAPE:
		return
	if event is InputEventKey and is_instance_valid(ui) and ui.keyboard_owned_by_ui():
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		if left_orbit_pending or camera_button == MOUSE_BUTTON_LEFT:
			var was_click := left_orbit_pending and camera_button == 0
			left_orbit_pending = false
			camera_button = 0
			if was_click and not ui.pointer_on_ui() and not ui.rename_open():
				_left_click(left_press_position)
			get_viewport().set_input_as_handled()
			return
	if event is InputEventMouseButton and not event.pressed and event.button_index == camera_button:
		camera_button = 0
	if is_instance_valid(ui) and ui.rename_open():
		return
	if event is InputEventMouseMotion and left_orbit_pending:
		if event.position.distance_to(left_press_position) < LEFT_ORBIT_THRESHOLD:
			return
		left_orbit_pending = false
		camera_button = MOUSE_BUTTON_LEFT
		ui.hide_token_actions()
	if event is InputEventMouseMotion and camera_button!=0:
		if OrbitCamera.mouse_rotates(camera_button): _orbit_rotate(event.relative)
		else: _orbit_pan(event.relative)
		get_viewport().set_input_as_handled()
	if event is InputEventKey and event.pressed and not event.echo:
		var handled := true
		if event.keycode==KEY_F:
			_orbit_focus()
		elif event.keycode == KEY_ENTER and tool in [Tool.ROUTE, Tool.MEASURE]:
			_on_route_action("confirm")
		elif event.keycode == KEY_ENTER and tool == Tool.SHAPE:
			_on_shape_action("confirm")
		elif event.keycode == KEY_ENTER and tool == Tool.TOKEN_CREATE:
			_on_token_placement_action("confirm")
		elif event.keycode == KEY_DELETE and tool == Tool.SHAPE:
			hover_shape = shape_plan.selected
			_on_shape_action("delete")
		elif (event.keycode == KEY_BACKSPACE or (event.keycode == KEY_Z and event.ctrl_pressed)) and tool in [Tool.ROUTE, Tool.MEASURE]:
			_on_route_action("undo")
		else:
			handled = false
		if handled:
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if Mobile.enabled and event is InputEventMouse and event.device in [InputEvent.DEVICE_ID_EMULATION,-421]: return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_escape()
		return
	if event is InputEventMouseButton and event.pressed:
		if ui.pointer_on_ui(): return
		if event.button_index==MOUSE_BUTTON_RIGHT and tool==Tool.TOKEN_CREATE and not tray_placement_id.is_empty():
			_on_tool("select")
			get_viewport().set_input_as_handled()
			return
		if event.button_index == MOUSE_BUTTON_LEFT:
			ui.release_keyboard_focus()
		match event.button_index:
			MOUSE_BUTTON_WHEEL_UP:
				_zoom_camera(1.0)
			MOUSE_BUTTON_WHEEL_DOWN:
				_zoom_camera(-1.0)
			MOUSE_BUTTON_RIGHT, MOUSE_BUTTON_MIDDLE:
				left_orbit_pending = false
				camera_button = event.button_index
				ui.hide_token_actions()
			MOUSE_BUTTON_LEFT:
				if camera_button != 0:
					return
				if not (Mobile.enabled and event.device==-420) and _can_start_left_orbit(event.position):
					left_orbit_pending = true
					left_press_position = event.position
				else: _left_click(event.position)

func _can_start_left_orbit(mouse: Vector2) -> bool:
	# Active editing tools own the left button; orbit starts only on selection-mode background.
	return tool==Tool.SELECT and not ui.pointer_on_ui() and _pick_token(mouse)<0

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		left_orbit_pending = false
		camera_button = 0

func _process(delta: float) -> void:
	if is_instance_valid(ui) and not ui.keyboard_owned_by_ui() and not ui.rename_open() and not turn_control.panel.visible:
		var editing_drag := Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and camera_button!=MOUSE_BUTTON_LEFT and not left_orbit_pending
		if not editing_drag:
			focus.y += OrbitCamera.lift_direction()*OrbitCamera.lift_step(camera_distance,delta)
	_update_camera(delta)
	if not is_instance_valid(ui):
		return
	var measurement_changed := measurement.resolve(tokens)
	if measurement_changed and tool == Tool.MEASURE and (not measure_finished or measurement.editing_index >= 0):
		_sync_point_markers()
		_render_route()
	_update_saved_measurements()
	var mouse := get_viewport().get_mouse_position()
	for index in range(tokens.size()):
		var actor: Node3D = tokens[index]["node"]
		var name_position: Vector3 = actor.position + Vector3.UP * (_appearance_height(actor, int(tokens[index]["size"])) + 0.45)
		var depth := -camera.to_local(name_position).z
		var info_zoom := minf(1.0, 52.0 / maxf(depth, 0.1))
		var screen := camera.unproject_position(name_position)
		var visible_name: bool = not camera.is_position_behind(name_position) and get_viewport().get_visible_rect().has_point(screen) and surfaces.visible_hit(name_position,screen)
		ui.show_token_name(index, tokens[index], screen, visible_name, index == selected, tool == Tool.SELECT, info_zoom, can_operate_token(index))
	if selected>=0 and selected<tokens.size() and tool in [Tool.SELECT,Tool.ROUTE]:
		turn_control.update_marker(tokens[selected]["node"],tokens[selected],self)
	else:
		turn_control.close()
		turn_control.update_marker(null,{},self)
	match tool:
		Tool.SELECT:
			pass
		Tool.TOKEN_CREATE:
			if not token_placement_fixed and camera_button == 0 and not ui.pointer_on_ui():
				_update_token_placement(mouse)
		Tool.ROUTE:
			_update_route_pointer(mouse)
			_update_route_ui()
		Tool.MEASURE:
			_update_route_pointer(mouse)
			_update_route_ui()
		Tool.SHAPE:
			if shape_plan.moving and camera_button == 0 and not left_orbit_pending and not ui.pointer_on_ui():
				var cell := _mouse_cell(mouse)
				if _on_board(cell):
					var previous_surface: String = shape_plan.draft.get("platform_id", "")
					var moved := shape_plan.move_to(_shape_grid_point(mouse))
					if moved or previous_surface!=shape_plan.draft.get("platform_id", ""): _render_shapes()
	_update_entity_hover(mouse, delta)

func _mouse_cell(mouse: Vector2) -> Vector2i:
	return surfaces.mouse_cell(mouse)

func _on_board(cell: Vector2i) -> bool:
	return not surfaces.find(cell).is_empty()

func _route_cell(mouse: Vector2) -> Vector2i:
	var cell := _mouse_cell(mouse)
	route.surface_context = surfaces.current
	return cell

func _route_extent() -> Vector2i:
	return Footprint.dimensions(tokens[selected]) if tool == Tool.ROUTE and selected >= 0 and selected < tokens.size() else Vector2i.ONE

func _measurement_endpoint(mouse: Vector2) -> Dictionary:
	var cell := _mouse_cell(mouse)
	var index := _pick_token(mouse)
	if index >= 0:
		var origin: Vector2i = tokens[index]["cell"]
		var last := origin + Footprint.dimensions(tokens[index]) - Vector2i.ONE
		cell = Vector2i(clampi(cell.x, origin.x, last.x), clampi(cell.y, origin.y, last.y))
	return {"cell": cell, "token_id": tokens[index]["id"] if index >= 0 else -1,"platform_id": tokens[index].get("platform_id","") if index>=0 else (surfaces.current if surfaces!=null else "")}

func _measurement_endpoint_name(endpoint: Dictionary) -> String:
	for token in tokens:
		if token["id"] == endpoint["token_id"]:
			return token["title"]
	var cell: Vector2i = endpoint["cell"]
	var platform: Dictionary = surfaces.item(endpoint.get("platform_id",""))
	if not platform.is_empty():
		var local: Vector2i = cell-surfaces.origin(platform)
		return "%s · 格 (%d, %d)" % [platform["data"]["title"],local.x+1,local.y+1]
	return "格 (%d, %d)" % [cell.x+1,cell.y+1]

func _measurement_summary(plan: MeasurementPlan = null) -> String:
	if plan == null:
		plan = measurement
	if plan.endpoints.is_empty():
		return "测距"
	return "%s → %s · %s" % [
		_measurement_endpoint_name(plan.endpoints[0]),
		_measurement_endpoint_name(plan.endpoints[-1]),
		_amount(Rules.route_feet(plan.points, distance_mode))
	]

func _update_saved_measurements() -> void:
	while measurement_lines.get_child_count() < measurements.size():
		var line := MeshInstance3D.new()
		line.material_override = _material(Color("e7c987"), true)
		line.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		measurement_lines.add_child(line)
	var labels: Array[Dictionary] = []
	var nodes: Array[Dictionary] = []
	for index in range(measurement_lines.get_child_count()):
		var line := measurement_lines.get_child(index) as MeshInstance3D
		line.hide()
		if index >= measurements.size():
			continue
		var plan := measurements[index]
		plan.resolve(tokens)
		if plan.points.size() < 2 or (tool == Tool.MEASURE and plan == measurement and (not measure_finished or plan.editing_index >= 0)):
			continue
		line.show()
		var highlighted := index == hover_measurement
		if not line.has_meta("highlighted") or line.get_meta("highlighted") != highlighted:
			line.material_override = _material(Color("81d7f3") if highlighted else Color("e7c987"), true)
			line.set_meta("highlighted", highlighted)
		for point in range(plan.points.size()):
			var at := _plan_world(plan,point)
			if not camera.is_position_behind(at):
				nodes.append({"at": camera.unproject_position(at + Vector3.UP * 0.14), "highlighted": highlighted and point == hover_measurement_point})
		var positions: Array[Vector3] = []
		for at in range(plan.points.size()): positions.append(_plan_world(plan,at))
		if not line.has_meta("points") or line.get_meta("points") != positions:
			line.mesh = _line_mesh(positions)
			line.set_meta("points", positions.duplicate())
		for segment in range(1, plan.points.size()):
			var midpoint := (_plan_world(plan,segment-1) + _plan_world(plan,segment)) / 2.0
			labels.append({"text": _amount(Rules.segment_feet(plan.points, segment, distance_mode)), "at": camera.unproject_position(midpoint), "visible": not camera.is_position_behind(midpoint), "index": -1})
		var end := _plan_world(plan,plan.points.size()-1)
		labels.append({"text": _measurement_summary(plan), "at": camera.unproject_position(end), "visible": not camera.is_position_behind(end), "index": index})
	ui.show_saved_measurements(labels)
	ui.show_saved_measurement_nodes(nodes)

func _pick_token(mouse: Vector2) -> int:
	var origin := camera.project_ray_origin(mouse)
	var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(mouse) * 1000000)
	var hit := get_world_3d().direct_space_state.intersect_ray(query)
	if not hit.is_empty() and hit["collider"].has_meta("token_index") and (surfaces==null or surfaces.visible_hit(hit["position"],mouse)):
		return int(hit["collider"].get_meta("token_index"))
	var cell := _mouse_cell(mouse)
	for index in range(tokens.size() - 1, -1, -1):
		if Footprint.space(tokens[index]).has_point(cell) and (surfaces==null or tokens[index].get("platform_id","")==surfaces.current):
			return index
	return -1

func _token_anchor(index: int) -> Vector2:
	var actor: Node3D = tokens[index]["node"]
	return camera.unproject_position(actor.position + Vector3.UP * (_appearance_height(actor, int(tokens[index]["size"])) + 0.9)) - Vector2(0, 12)

func _left_click(mouse: Vector2) -> void:
	if tool==Tool.SELECT or (tool==Tool.SHAPE and not shape_plan.dirty()) or (tool==Tool.MEASURE and not measure_creating and measurement.editing_index<0):
		_select_at_pointer(mouse)
		return
	match tool:
		Tool.TOKEN_CREATE:
			if not token_placement_fixed:
				_update_token_placement(mouse)
				if _token_placement_valid():
					token_placement_fixed = true
					if not tray_placement_id.is_empty():
						_on_token_placement_action("confirm")
						return
					_update_status()
		Tool.SHAPE:
			if shape_plan.moving:
				var cell := _mouse_cell(mouse)
				if _on_board(cell):
					shape_plan.fix_position(_shape_grid_point(mouse))
			elif not shape_plan.dirty():
				shape_plan.select(_pick_shape(mouse))
			_shape_changed()
		Tool.SELECT:
			selected = _pick_token(mouse)
			_refresh_selection()
			if selected < 0:
				hover_token = -1
				ui.hide_token_actions()
		Tool.MEASURE:
			if measurement.editing_index >= 0:
				if measurement_edit_fixed:
					return
				var endpoint := _measurement_endpoint(mouse)
				if _on_board(endpoint["cell"]):
					measurement.replace_endpoint(measurement.editing_index, endpoint)
					measurement_edit_fixed = true
					measurement.resolve(tokens)
					_sync_point_markers()
					_render_route()
					_update_status()
				return
			if not measure_creating:
				return
			if route.points.is_empty() or measure_finished:
				var cell := _mouse_cell(mouse)
				if not _on_board(cell) and _pick_token(mouse) < 0:
					return
				ui.clear_overlays()
				_clear_measurement_hover()
				if measure_finished:
					measurement = MeasurementPlan.new()
					route = measurement
				measurement.begin_endpoint(_measurement_endpoint(mouse))
				if not measurements.has(measurement):
					measurement.display_id = next_measurement_id
					next_measurement_id += 1
					measurements.append(measurement)
				measurement.resolve(tokens)
				measure_finished = false
				selected_point = -1
				_sync_point_markers()
				_render_route()
				_update_status()
			else:
				var endpoint := _measurement_endpoint(mouse)
				if _on_board(endpoint["cell"]):
					if measurement.endpoints.size()>=256:
						ui.set_status("每条测距最多256个节点。")
						return
					measurement.add_endpoint(endpoint)
					measurement.resolve(tokens)
					_sync_point_markers()
					_render_route()
					_update_status()
		Tool.ROUTE:
			_click_route(mouse)

func _click_route(mouse: Vector2) -> void:
	if route.editing_index > 0:
		if not _on_board(_mouse_cell(mouse)) and (tool != Tool.MEASURE or _pick_token(mouse) < 0):
			return
		route.update_edit(_route_cell(mouse))
		if tool == Tool.MEASURE:
			measurement.replace_endpoint(route.editing_index, _measurement_endpoint(mouse))
		route.finish_edit()
		selected_point = -1
		ui.hide_point_actions()
	elif _pick_path_point(mouse) > 0:
		selected_point = _pick_path_point(mouse)
	elif selected_point > 0:
		selected_point = -1
		ui.hide_point_actions()
	else:
		var cell := _mouse_cell(mouse)
		if not _on_board(cell) and (tool != Tool.MEASURE or _pick_token(mouse) < 0):
			return
		selected_point = -1
		ui.hide_point_actions()
		if tool == Tool.MEASURE:
			measurement.add_endpoint(_measurement_endpoint(mouse))
		else:
			route.add_point(_route_cell(mouse))
	if tool == Tool.MEASURE:
		measurement.resolve(tokens)
	_sync_point_markers()
	_render_route()
	_update_status()

func _on_token_action(action: String) -> void:
	if tool != Tool.SELECT or ui.displayed_token < 0 or ui.displayed_token >= tokens.size():
		return
	var data := tokens[ui.displayed_token]
	if not can_operate_token(ui.displayed_token): return
	if action == "turn":
		selected = ui.displayed_token
		_clear_entity_hover()
		var token_id: int = data["id"]
		turn_control.open(data["node"],data,camera,func(point: Vector2): return point,func(quarter: int,offset: float):
			if not can_operate_token(selected) or tokens[selected]["id"]!=token_id: return
			data["quarter_turn"] = quarter
			data["model_yaw_deg"] = offset
		,func(): return can_operate_token(selected) and tokens[selected]["id"]==token_id,camera.unproject_position(data["node"].position)+Vector2(30,-120))
		return
	turn_control.close()
	if action == "store":
		token_tray_requested.emit(data.duplicate(true))
		return
	if action == "appearance":
		ui.clear_overlays()
		_clear_entity_hover()
		full_token_edit_requested.emit(data.duplicate(true))
		return
	if action == "copy":
		var copy := {"title": data["title"], "size": data["size"], "width": Footprint.dimensions(data).x, "length": Footprint.dimensions(data).y, "base": data["base"], "color": data["color"], "hp": data["hp"], "max_hp": data["max_hp"], "ac": data["ac"], "kind": data.get("kind", "basic"), "tags": data.get("tags", []).duplicate(), "components": data.get("components", {}).duplicate(true), "materials": data.get("materials", {}).duplicate(true), "owner_member":session_party["owners"].get(data["persistent_id"],"dm")}
		copy.merge(Instance.scene_values(data),true)
		_begin_token_placement(copy)
		return
	if action == "delete":
		var count := 0
		for plan in measurements:
			if _measurement_bound_to(plan, int(data["id"])):
				count += 1
		ui.open_token_delete(data, count)
		return
	if action == "rename":
		ui.open_rename(ui.displayed_token, tokens[ui.displayed_token]["title"])
		return
	if action in ["hp", "ac"]:
		ui.open_stats(ui.displayed_token, tokens[ui.displayed_token], action)
		return
	if action != "move":
		return
	selected = ui.displayed_token
	tool = Tool.ROUTE
	route = movement_route
	ui.clear_overlays()
	ui.set_tool("route")
	route.surface_context = tokens[selected].get("platform_id","")
	route.begin(tokens[selected]["cell"])
	selected_point = -1
	_sync_point_markers()
	_refresh_selection()
	_update_status()

func _save_token_appearance(token_id: int, parameters: Dictionary) -> void:
	var index := _entity_index({"kind": "token", "id": token_id})
	if index < 0 or not can_operate_token(index):
		return
	var data := tokens[index]
	if not data.get("components", {}).is_empty():
		return
	data["color"] = parameters["color"]
	data["base"] = parameters["base"]
	data["materials"] = parameters.get("materials", preload("res://scripts/token_surface.gd").basic_defaults(data["color"])).duplicate(true)
	var old_actor: Node3D = data["node"]
	remove_child(old_actor)
	old_actor.queue_free()
	data["node"] = _build_token_actor(data["cell"], int(data["size"]), data["color"], data["base"], index, Footprint.dimensions(data), {}, data.get("materials", {}))
	Instance.apply_orientation(data["node"],data)
	_refresh_selection()

func _endpoints_bound_to(endpoints: Array, token_id: int) -> bool:
	for endpoint in endpoints:
		if int(endpoint.get("token_id", -1)) == token_id:
			return true
	return false

func _measurement_bound_to(plan: MeasurementPlan, token_id: int) -> bool:
	return _endpoints_bound_to(plan.endpoints, token_id) or int(plan.original_endpoint.get("token_id", -1)) == token_id

func _delete_token(token_id: int) -> void:
	var index := _entity_index({"kind": "token", "id": token_id})
	if tool != Tool.SELECT or index < 0 or not can_operate_token(index):
		return
	# Remove references before resolving endpoints can turn them into terrain points.
	for at in range(measurements.size() - 1, -1, -1):
		if _measurement_bound_to(measurements[at], token_id):
			measurements.remove_at(at)
	if _measurement_bound_to(measurement, token_id):
		measurement = MeasurementPlan.new()
		measure_finished = false
		measurement_edit_fixed = false
		continuation_snapshot.clear()
	if not deleted_measurement.is_empty() and _endpoints_bound_to(deleted_measurement["endpoints"], token_id):
		deleted_measurement.clear()
		ui.hide_measurement_undo()
	var actor: Node3D = tokens[index]["node"]
	remove_child(actor)
	actor.queue_free()
	tokens.remove_at(index)
	selected = -1 if selected == index else (selected - 1 if selected > index else selected)
	hover_token = -1
	hover_timeout = 0
	for at in range(tokens.size()):
		var node: Node3D = tokens[at]["node"]
		for child in node.find_children("*", "StaticBody3D", true, false):
			child.set_meta("token_index", at)
	ui.reset_after_token_removal(token_id)
	_clear_entity_hover()
	_clear_measurement_hover()
	_refresh_selection()
	_update_saved_measurements()
	_update_status()

func _rename_token(index: int, title: String) -> void:
	if index >= 0 and index < tokens.size() and can_operate_token(index):
		tokens[index]["title"] = title

func _update_token_stats(index: int, hp: int, maximum: int, ac: int, temporary: int) -> void:
	if index >= 0 and index < tokens.size() and can_operate_token(index):
		tokens[index]["hp"] = hp
		tokens[index]["max_hp"] = maximum
		tokens[index]["ac"] = ac
		tokens[index]["temp_hp"] = temporary

func _update_route_pointer(mouse: Vector2) -> void:
	if tool == Tool.MEASURE:
		if measurement.editing_index >= 0 and not measurement_edit_fixed and not ui.pointer_on_ui() and camera_button == 0 and _on_board(_mouse_cell(mouse)):
			var cell := _route_cell(mouse)
			if measurement.points[measurement.editing_index] != cell or measurement.endpoints[measurement.editing_index]["token_id"] >= 0 or measurement.point_surfaces[measurement.editing_index]!=surfaces.current:
				measurement.update_edit(cell)
				measurement.resolve(tokens)
				_sync_point_markers()
				_render_route()
		return
	if route.editing_index > 0:
		if not ui.pointer_on_ui() and camera_button == 0 and _on_board(_mouse_cell(mouse)):
			var cell := _route_cell(mouse)
			if cell != route.points[route.editing_index] or route.point_surfaces[route.editing_index]!=surfaces.current:
				route.update_edit(cell)
				_sync_point_markers()
				_render_route()

func _select_path_point(index: int) -> void:
	if tool not in [Tool.ROUTE, Tool.MEASURE] or measure_finished and tool == Tool.MEASURE or route.editing_index > 0 or index <= 0 or index >= route.points.size():
		return
	selected_point = index
	_update_route_ui()
	_update_status()

func _pick_path_point(mouse: Vector2) -> int:
	var size := _route_extent()
	var closest := -1
	var radius := 20.0
	for index in range(1, route.points.size()):
		if camera.is_position_behind(_plan_world(route,index,size)):
			continue
		var at := camera.unproject_position(_plan_world(route,index,size) + Vector3.UP * 0.14)
		var distance := at.distance_to(mouse)
		if distance < radius:
			closest = index
			radius = distance
	return closest

func _on_point_action(action: String) -> void:
	if selected_point <= 0 or selected_point >= route.points.size():
		return
	if action == "move":
		route.start_edit(selected_point)
	elif action == "delete":
		route.delete_point(selected_point)
	selected_point = -1
	ui.hide_point_actions()
	_sync_point_markers()
	_render_route()
	_update_status()

func _on_route_action(action: String) -> void:
	if tool == Tool.ROUTE and not can_operate_token(selected): return
	if tool not in [Tool.ROUTE, Tool.MEASURE]:
		return
	if tool == Tool.MEASURE and not measure_creating and measurement.editing_index < 0:
		return
	if tool == Tool.ROUTE and route.editing_index > 0 and action == "cancel":
		route.cancel_edit()
		selected_point = -1
		_sync_point_markers()
		_render_route()
		_update_status()
		return
	if tool == Tool.MEASURE and measurement.editing_index >= 0:
		if action == "confirm" and measurement_edit_fixed:
			measurement.finish_edit()
		elif action == "cancel":
			measurement.cancel_edit()
		else:
			return
		measurement_edit_fixed = false
		measure_finished = true
		measurement.resolve(tokens)
		_clear_lines()
		ui.clear_overlays()
		_clear_measurement_hover()
		_sync_point_markers()
		_update_status()
		return
	match action:
		"confirm":
			if route.points.size() <= 1 or route.editing_index > 0:
				return
			if tool == Tool.MEASURE:
				measurement.completed = true
				continuation_snapshot.clear()
				measurement.waypoint_endpoints.clear()
				measure_creating = false
				measure_finished = true
				selected_point = -1
				_clear_lines()
				ui.clear_overlays()
				_sync_point_markers()
				_update_route_ui()
				_update_status()
				return
			var end: Vector2i = route.points[-1]
			if surfaces!=null:
				var target: String = route.point_surfaces[-1] if not route.point_surfaces.is_empty() else ""
				if target!=tokens[selected].get("platform_id", "") and _surface_token_count(target)>=4096:
					ui.set_status("目标地台最多保存4096枚棋子。")
					return
				if surfaces.find(end,Footprint.dimensions(tokens[selected]),target,true).is_empty():
					ui.set_status("目标位置未允许摆放或棋子占地越界。")
					return
				tokens[selected]["platform_id"] = target
				surfaces.current = target
			tokens[selected]["cell"] = end
			tokens[selected]["node"].position = _cell_world(end,Footprint.dimensions(tokens[selected]),tokens[selected].get("platform_id",""))
			_leave_route()
		"cancel":
			if tool == Tool.MEASURE:
				_clear_measure()
			else:
				_leave_route()
		"undo":
			if route.editing_index > 0:
				return
			if tool == Tool.MEASURE and not _can_undo_measure_point():
				return
			route.undo_point()
			if tool == Tool.MEASURE:
				measurement.resolve(tokens)
			selected_point = -1
			ui.hide_point_actions()
			_sync_point_markers()
			_render_route()
			_update_status()

func _leave_route() -> void:
	route.reset()
	selected_point = -1
	_clear_lines()
	_sync_point_markers()
	tool = Tool.SELECT
	ui.clear_overlays()
	ui.set_tool("select")
	hover_timeout = 0.3
	_refresh_selection()
	_update_status()

func _update_route_ui() -> void:
	if tool == Tool.MEASURE and not measure_creating and measurement.editing_index < 0:
		return
	if tool == Tool.MEASURE and measurement.editing_index >= 0:
		ui.clear_overlays()
		var anchors: Array[Vector2] = []
		for index in range(measurement.points.size()):
			anchors.append(camera.unproject_position(_plan_world(measurement,index) + Vector3.UP * 0.14))
		ui.show_path_points(anchors, -1, true)
		return
	if route.points.is_empty():
		return
	var size := _route_extent()
	var last: Vector2i = route.points[-1]
	var panel_cell := route.original_cell if route.editing_index > 0 else last
	var end_at := camera.unproject_position((_cell_world(panel_cell,size,route.original_surface) if route.editing_index>0 else _plan_world(route,route.points.size()-1,size))+Vector3.UP*0.2)
	ui.show_route(_amount(Rules.route_feet(route.points, distance_mode)), route.points.size() > 1, route.editing_index > 0, end_at)
	ui.set_measure_card(tool == Tool.MEASURE, measure_finished, route.editing_index > 0)
	if tool == Tool.MEASURE:
		ui.set_measure_summary(_measurement_summary())
		ui.set_measure_undo_available(_can_undo_measure_point())
	var point_anchors: Array[Vector2] = []
	for index in range(1, route.points.size()):
		point_anchors.append(camera.unproject_position(_plan_world(route,index,size) + Vector3.UP * 0.14))
	var active_point := route.editing_index if route.editing_index > 0 else selected_point
	ui.show_path_points(point_anchors, active_point, route.editing_index > 0)
	var segment_amounts: Array[String] = []
	var segment_anchors: Array[Vector2] = []
	for index in range(1, route.points.size()):
		var midpoint := (_plan_world(route,index-1,size) + _plan_world(route,index,size)) / 2.0
		if not camera.is_position_behind(midpoint):
			segment_amounts.append(_amount(Rules.segment_feet(route.points, index, distance_mode)))
			segment_anchors.append(camera.unproject_position(midpoint))
	ui.show_segments(segment_amounts, segment_anchors)
	if selected_point > 0 and selected_point < route.points.size():
		var at := camera.unproject_position(_plan_world(route,selected_point,size) + Vector3.UP * 0.2)
		ui.show_point_actions(at)
	else:
		ui.hide_point_actions()
	ui.hide_distance()

func _sync_point_markers() -> void:
	for child in point_markers.get_children():
		point_markers.remove_child(child)
		child.queue_free()
	if tool not in [Tool.ROUTE, Tool.MEASURE]:
		return
	if tool == Tool.MEASURE and not measure_creating and measurement.editing_index < 0:
		return
	# The origin stays in 3D; editable points use fixed-size UI buttons.
	for index in range(mini(route.points.size(), 1)):
		var marker := MeshInstance3D.new()
		var mesh := CylinderMesh.new()
		mesh.top_radius = 0.18
		mesh.bottom_radius = 0.18
		mesh.height = 0.06
		mesh.radial_segments = 24
		marker.mesh = mesh
		marker.material_override = _material(Color("eebd6a") if index == selected_point or index == route.editing_index else Color("ecf5fd"), true)
		marker.position = _plan_world(route,index,_route_extent()) + Vector3.UP * 0.14
		marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		point_markers.add_child(marker)

func _render_route() -> void:
	if tool == Tool.MEASURE and not measure_creating and measurement.editing_index < 0:
		path_line.mesh = null
		return
	if route.points.is_empty():
		return
	var positions: Array[Vector3] = []
	var size := _route_extent()
	for at in range(route.points.size()):
		positions.append(_plan_world(route,at,size))
	path_line.mesh = _line_mesh(positions)

func _line_mesh(positions: Array[Vector3], dashed: bool = false) -> ImmediateMesh:
	if positions.size() < 2:
		return null
	var mesh := ImmediateMesh.new()
	var has_vertices := false
	mesh.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
	for index in range(1, positions.size()):
		var from := positions[index - 1] + Vector3.UP * 0.1
		var to := positions[index] + Vector3.UP * 0.1
		var delta := to - from
		var length := delta.length()
		if length < 0.001:
			continue
		var side := delta.normalized().cross(Vector3.UP)
		if side.length_squared()<0.0001: side = delta.normalized().cross(Vector3.FORWARD)
		side = side.normalized()*0.035
		var sections := ceili(length / 0.45) if dashed else 1
		for section in range(sections):
			var start := float(section) / sections
			var end := minf(start + 0.65 / sections, 1.0) if dashed else 1.0
			var a := from.lerp(to, start)
			var b := from.lerp(to, end)
			for vertex: Vector3 in [a - side, b - side, b + side, a - side, b + side, a + side]:
				mesh.surface_add_vertex(vertex)
			has_vertices = true
	if has_vertices:
		mesh.surface_end()
		return mesh
	return null

func _draw_measure() -> void:
	start_marker.position = _cell_world(measure_start) + Vector3.UP * 0.04
	end_marker.position = _cell_world(measure_end) + Vector3.UP * 0.05
	start_marker.show()
	end_marker.show()
	var positions: Array[Vector3] = [_cell_world(measure_start), _cell_world(measure_end)]
	path_line.mesh = _line_mesh(positions)

func _clear_lines() -> void:
	path_line.mesh = null
	start_marker.hide()
	end_marker.hide()

func _on_tool(request: String) -> void:
	if is_instance_valid(turn_control): turn_control.close()
	if network_readonly and request!="select": return
	if (tool == Tool.MEASURE and request == "measure") or (tool == Tool.SHAPE and request == "shape") or (tool == Tool.SELECT and request == "select"):
		ui.set_tool(request)
		return
	if tool == Tool.TOKEN_CREATE:
		_clear_token_placement()
	if tool == Tool.MEASURE and measure_creating:
		_clear_measure()
	_clear_entity_hover()
	_clear_measurement_hover()
	if tool == Tool.MEASURE and measurement.editing_index >= 0:
		measurement.cancel_edit()
		measurement_edit_fixed = false
	if tool == Tool.SHAPE and request == "shape":
		ui.set_tool(request)
		return
	_clear_shape_hover()
	if tool == Tool.SHAPE:
		shape_plan.clear_draft()
		_render_shapes()
	if tool == Tool.ROUTE:
		_leave_route()
	elif tool == Tool.MEASURE and measurement.editing_index > 0:
		measurement.cancel_edit()
		measurement.resolve(tokens)
	selected_point = -1
	_clear_lines()
	ui.clear_overlays()
	tool = Tool.MEASURE if request == "measure" else (Tool.SHAPE if request == "shape" else (Tool.TOKEN_CREATE if request == "token_create" else Tool.SELECT))
	route = measurement if tool == Tool.MEASURE else movement_route
	_sync_point_markers()
	if tool == Tool.MEASURE:
		measurement.resolve(tokens)
		if not measure_finished:
			_render_route()
		_update_route_ui()
	ui.set_tool(request)
	if tool == Tool.SHAPE:
		_shape_changed()
	_refresh_selection()
	_update_status()

func _escape() -> void:
	if turn_control.panel.visible:
		turn_control.close()
		return
	ui.menu_requested.emit()

func _on_campaign_mode_changed(_index: int) -> void:
	if tool in [Tool.ROUTE, Tool.MEASURE]:
		_update_route_ui()
	_update_status()

func _can_undo_measure_point() -> bool:
	var minimum := 1 if continuation_snapshot.is_empty() else (continuation_snapshot["points"] as Array).size()
	return measurement.points.size() > minimum

func _clear_measure() -> void:
	measure_creating = false
	if continuation_snapshot.get("plan") == measurement:
		measurement.points.assign(continuation_snapshot["points"])
		measurement.endpoints.assign(continuation_snapshot["endpoints"])
		measurement.point_surfaces.clear()
		for endpoint: Dictionary in measurement.endpoints: measurement.point_surfaces.append(endpoint.get("platform_id",""))
		measurement.waypoint_endpoints.clear()
		measurement.completed = true
		measurement.resolve(tokens)
	else:
		measurements.erase(measurement)
	continuation_snapshot.clear()
	measurement = MeasurementPlan.new()
	route = measurement if tool == Tool.MEASURE else movement_route
	measure_finished = false
	measurement_edit_fixed = false
	_clear_measurement_hover()
	selected_point = -1
	_clear_lines()
	_sync_point_markers()
	ui.clear_overlays()
	_update_status()

func _amount(distance: float) -> String:
	return "%.2f 英尺" % distance if distance_mode == Rules.Mode.STRAIGHT else "%.0f 英尺" % distance

func _refresh_selection() -> void:
	for index in range(tokens.size()):
		var actor: Node3D = tokens[index]["node"]
		var base := actor.get_child(0) as MeshInstance3D
		var highlighted := (index == selected and tool != Tool.MEASURE) or index == highlighted_token
		var components: Dictionary = tokens[index].get("components", {})
		if components.is_empty():
			_set_token_mesh_highlight(base, highlighted)
		else:
			for name in ["base", "standee"]:
				var mesh := actor.get_node("Base" if name == "base" else "Standee") as MeshInstance3D
				_set_token_mesh_highlight(mesh, highlighted)

func _set_token_mesh_highlight(mesh: MeshInstance3D, highlighted: bool) -> void:
	if mesh == null or mesh.mesh == null: return
	if not mesh.has_meta("selection_materials"):
		var source := mesh.get_active_material(0)
		# Acrylic and invisible image carriers use ShaderMaterial. Replacing them
		# with a generic opaque material destroys both alpha and shader parameters.
		if not source is BaseMaterial3D: return
		var lightened := source.duplicate() as BaseMaterial3D
		lightened.albedo_color = source.albedo_color.lightened(0.4)
		mesh.set_meta("selection_materials", {"normal": mesh.material_override, "highlight": lightened})
	var materials: Dictionary = mesh.get_meta("selection_materials")
	var target: Material = materials["highlight"] if highlighted else materials["normal"]
	if mesh.material_override != target: mesh.material_override = target

func _update_status() -> void:
	ui.update_measure_state(measure_creating, not measurement.points.is_empty(), measurement.editing_index >= 0)
	ui.set_status("")

func _shape_grid_point(mouse: Vector2) -> Vector2:
	var hit: Dictionary = surfaces.hit(mouse)
	if hit.is_empty(): return Vector2(-10000,-10000)
	if not shape_plan.draft.is_empty() and shape_plan.moving: shape_plan.draft["platform_id"] = hit["id"]
	surfaces.current = hit["id"]
	var at: Vector3 = hit["point"]
	return Vector2(at.x+15,at.z+15)

func _on_shape_parameters(parameters: Dictionary) -> void:
	if network_readonly: return
	shape_plan.update_parameters(parameters)
	_shape_changed()

func _on_shape_action(action: String) -> void:
	if network_readonly and action not in ["cancel","forget_delete"]: return
	if action in ["move", "delete", "edit"] and hover_shape >= 0:
		if not _can_operate_tool("shapes",int(shape_plan.shapes[hover_shape].get("display_id",0))): return
		shape_plan.select(hover_shape)
	match action:
		"new":
			_clear_entity_hover()
			ui.release_keyboard_focus()
			_clear_shape_hover()
			if not shape_plan.new_shape(ui.shape_parameters()):
				ui.set_status("当前地图最多保存100个形状。")
				return
			shape_edit_anchor = _shape_origin_world(shape_plan.draft)
		"move":
			if shape_plan.draft.is_empty():
				return
			tool = Tool.SHAPE
			ui.set_tool("shape")
			ui.close_shape_editor()
			ui.hide_token_actions()
			_clear_shape_hover()
			shape_edit_anchor = _shape_origin_world(shape_plan.draft)
			shape_plan.start_move()
		"edit":
			if shape_plan.draft.is_empty():
				return
			tool = Tool.SHAPE
			ui.set_tool("shape")
			ui.hide_token_actions()
			_clear_shape_hover()
			ui.open_shape_editor()
		"confirm": shape_plan.commit()
		"cancel": shape_plan.cancel()
		"delete":
			if shape_plan.selected < 0:
				return
			shape_plan.delete_selected()
			_clear_shape_hover()
			ui.show_shape_undo()
		"undo_delete":
			if shape_plan.undo_delete():
				_clear_shape_hover()
				ui.hide_shape_undo()
		"forget_delete": shape_plan.forget_delete()
	_shape_changed()

func _shape_changed() -> void:
	if not shape_plan.dirty():
		ui.hide_shape_actions()
	_render_shapes()
	ui.update_shape_state(shape_plan)
	_update_status()

func _render_shapes() -> void:
	while shape_layer.get_child_count() < shape_plan.shapes.size() + 1:
		var root := Node3D.new()
		shape_layer.add_child(root)
		for index in range(2):
			var surface := MeshInstance3D.new()
			surface.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			root.add_child(surface)
	for index in range(shape_layer.get_child_count()):
		var root := shape_layer.get_child(index) as Node3D
		root.hide()
		if index < shape_plan.shapes.size():
			if index != shape_plan.selected:
				_update_shape_mesh(root, shape_plan.shapes[index], 1 if index == hover_shape else 0)
		elif index == shape_plan.shapes.size() and not shape_plan.draft.is_empty():
			_update_shape_mesh(root, shape_plan.draft, 2 if shape_plan.dirty() else 1)

func _update_shape_mesh(root: Node3D, data: Dictionary, style: int) -> void:
	root.show()
	root.position.y = surfaces.height(data.get("platform_id","")) if surfaces!=null else 0.0
	var signature := {"data": data.duplicate(), "style": style}
	if root.has_meta("signature") and root.get_meta("signature") == signature:
		return
	root.set_meta("signature", signature)
	var polygon := ShapePlan.polygon(data)
	var indices := Geometry2D.triangulate_polygon(polygon)
	var fill := ImmediateMesh.new()
	if not indices.is_empty():
		fill.surface_begin(Mesh.PRIMITIVE_TRIANGLES)
		for index in indices:
			var point: Vector2 = polygon[index]
			fill.surface_add_vertex(Vector3(point.x - 15, 0.035, point.y - 15))
		fill.surface_end()
	var vertices: Array[Vector3] = []
	for point in polygon:
		vertices.append(Vector3(point.x - 15, 0.045, point.y - 15))
	vertices.append(vertices[0])
	var color := Color("e6b957") if style == 2 else (Color("4eade8") if style == 1 else Color("6cafd5"))
	var fill_color := color
	fill_color.a = 0.18 if style > 0 else 0.10
	var fill_node := root.get_child(0) as MeshInstance3D
	fill_node.mesh = fill
	fill_node.material_override = _material(fill_color, true)
	var outline := root.get_child(1) as MeshInstance3D
	outline.mesh = _line_mesh(vertices)
	outline.material_override = _material(color, true)

func _pick_shape(mouse: Vector2) -> int:
	for index in range(shape_plan.shapes.size() - 1, -1, -1):
		var at := _shape_plane_point(mouse,shape_plan.shapes[index])
		if at==Vector2(-10000,-10000): continue
		var polygon := ShapePlan.polygon(shape_plan.shapes[index])
		if Geometry2D.is_point_in_polygon(at, polygon):
			return index
		for edge in range(polygon.size()):
			var a := _shape_vertex(polygon[edge],shape_plan.shapes[index])
			var next: Vector2 = polygon[(edge + 1) % polygon.size()]
			var b := _shape_vertex(next,shape_plan.shapes[index])
			if camera.is_position_behind(a) or camera.is_position_behind(b):
				continue
			var closest := Geometry2D.get_closest_point_to_segment(mouse, camera.unproject_position(a), camera.unproject_position(b))
			if closest.distance_squared_to(mouse) <= 49:
				return index
	return -1

func _clear_shape_hover() -> void:
	var had_hover := hover_shape >= 0
	hover_shape = -1
	ui.hide_shape_actions()
	if had_hover:
		_render_shapes()

func _shape_origin_world(data: Dictionary) -> Vector3:
	var origin := ShapePlan.get_origin(data)
	return Vector3(origin.x-15,surfaces.height(data.get("platform_id","")) if surfaces!=null else 0.0,origin.y-15)

func _entity_index(target: Dictionary) -> int:
	match target.get("kind", ""):
		"token":
			for index in range(tokens.size()):
				if tokens[index]["id"] == target.get("id"):
					return index
		"shape":
			for index in range(shape_plan.shapes.size()):
				if shape_plan.shapes[index].get("display_id") == target.get("id"):
					return index
		"measure":
			for index in range(measurements.size()):
				if measurements[index] == target.get("plan"):
					return index
	return -1

func _highlight_entity(target: Dictionary) -> void:
	var index := _entity_index(target)
	var token_index := index if target.get("kind") == "token" else -1
	var shape_index := index if target.get("kind") == "shape" else -1
	var measure_index := index if target.get("kind") == "measure" else -1
	var point := int(target.get("point", -1)) if measure_index >= 0 else -1
	if highlighted_token == token_index and hover_shape == shape_index and hover_measurement == measure_index and hover_measurement_point == point:
		return
	highlighted_token = token_index
	hover_shape = shape_index
	hover_measurement = measure_index
	hover_measurement_point = point
	_refresh_selection()
	_render_shapes()

func _can_operate_tool(category: String, display: int) -> bool:
	if network_readonly: return false
	if session_actor=="dm": return true
	var network: Node = get_parent().get("network_session")
	if network==null: return false
	return network.tool_owners.get("%s:%s:%d" % [session_map_id,category,display],"dm")==session_actor

func _on_entity_action(target: Dictionary, action: String) -> void:
	var index := _entity_index(target)
	if action=="select_entity" and index>=0:
		var entry := {}
		for candidate in entity_entries:
			if candidate["kind"]==target["kind"] and candidate["id"]==target["id"] and candidate.get("point",-1)==target.get("point",-1):
				entry = candidate.duplicate()
				break
		if entry.is_empty(): return
		entry["actions"] = entry["selection_actions"]
		entry.erase("selection_actions")
		entity_entries.clear()
		entity_entries.append(entry)
		entity_anchor = entry["anchor"]
		_select_entity(entry)
		_position_entity_group()
		return
	if index < 0:
		_clear_entity_hover()
		return
	match target["kind"]:
		"token":
			ui.displayed_token = index
			_on_token_action(action)
		"shape":
			hover_shape = index
			_on_shape_action(action)
		"measure":
			var point := int(target["point"])
			if point >= measurements[index].points.size():
				_clear_entity_hover()
				return
			hover_measurement = index
			hover_measurement_point = point
			_on_measurement_action(action)
	if target["kind"]=="token" and action in ["rename","hp","ac","delete"]:
		ui.hide_entity_actions()
	else:
		_clear_entity_hover()

func _clear_entity_hover() -> void:
	entity_entries.clear()
	entity_timeout = 0
	ui.hide_entity_actions()
	_highlight_entity({})

func _entity_candidates(mouse: Vector2) -> Array[Dictionary]:
	var result: Array[Dictionary] = []
	if tool == Tool.SELECT:
		var cell := _mouse_cell(mouse)
		var ray_tokens: Array[int] = []
		var origin := camera.project_ray_origin(mouse)
		var query := PhysicsRayQueryParameters3D.create(origin, origin + camera.project_ray_normal(mouse) * 1000000)
		var excluded: Array[RID] = []
		for attempt in range(tokens.size() * 3):
			query.exclude = excluded
			var hit := get_world_3d().direct_space_state.intersect_ray(query)
			if hit.is_empty() or not hit["collider"].has_meta("token_index"):
				break
			if surfaces!=null and not surfaces.visible_hit(hit["position"],mouse): break
			ray_tokens.append(int(hit["collider"].get_meta("token_index")))
			excluded.append(hit["rid"])
		var card := ui.token_index_under_pointer()
		for index in range(tokens.size()):
			var data := tokens[index]
			var actor: Node3D = data["node"]
			var count := int(data["size"])
			if ray_tokens.has(index) or index == card or (Footprint.space(data).has_point(cell) and (surfaces==null or data.get("platform_id","")==surfaces.current)):
				result.append({"kind": "token", "id": data["id"], "label": "棋子 · " + data["title"], "appearance_available": data.get("components", {}).is_empty(), "anchor": actor.position + Vector3.UP * (_appearance_height(actor, count) + 0.45), "actions": [["move", "移动"], ["turn", "转向"], ["more", "更多"]]})
	for index in range(shape_plan.shapes.size()) if tool == Tool.SHAPE else []:
		var data := shape_plan.shapes[index]
		var at := _shape_plane_point(mouse,data)
		if at==Vector2(-10000,-10000): continue
		var polygon := ShapePlan.polygon(data)
		var hit := Geometry2D.is_point_in_polygon(at, polygon)
		for edge in range(polygon.size()):
			if hit:
				break
			var a := _shape_vertex(polygon[edge],data)
			var next: Vector2 = polygon[(edge + 1) % polygon.size()]
			var b := _shape_vertex(next,data)
			if not camera.is_position_behind(a) and not camera.is_position_behind(b):
				hit = Geometry2D.get_closest_point_to_segment(mouse, camera.unproject_position(a), camera.unproject_position(b)).distance_squared_to(mouse) <= 49
		if hit:
			var names := ["圆形", "扇形", "矩形", "直线"]
			result.append({"kind": "shape", "id": data["display_id"], "label": "%s %d" % [names[int(data["kind"])], data["display_id"]], "anchor": _shape_vertex(at,data), "actions": [["move", "移动"], ["delete", "删除"], ["more", "更多"]]})
	for candidate in _measurement_candidates(mouse) if tool == Tool.MEASURE else []:
		var plan := measurements[int(candidate["index"])]
		var point := int(candidate["point"])
		result.append({"kind": "measure", "id": plan.display_id, "plan": plan, "point": point, "label": "测距 %d · %s" % [plan.display_id, "节点 %d" % (point + 1) if point >= 0 else "整条"], "anchor": candidate["anchor"], "actions": [["move_node", "移动"], ["delete_node", "删除节点"]] if point >= 0 else [["continue", "继续绘制"], ["delete_measure", "删除整条"]]})
	var preferred := "shape" if tool == Tool.SHAPE else ("measure" if tool == Tool.MEASURE else "token")
	for entry: Dictionary in result:
		if entry["kind"] in ["shape","measure"] and not _can_operate_tool("shapes" if entry["kind"]=="shape" else "measurements",int(entry["id"])):
			entry["actions"] = []
	result.sort_custom(func(a: Dictionary, b: Dictionary):
		if (a["kind"] == preferred) != (b["kind"] == preferred):
			return a["kind"] == preferred
		if a["kind"] != b["kind"]:
			return a["kind"] < b["kind"]
		return int(a["id"]) < int(b["id"])
	)
	return result

func _update_entity_hover(mouse: Vector2, _delta: float) -> void:
	if tool == Tool.TOKEN_CREATE:
		_clear_entity_hover()
		ui.hide_shape_actions()
		ui.hide_measurement_actions()
		var at := _cell_world(token_placement_cell, Footprint.dimensions(token_draft)) + Vector3.UP * (_appearance_height(token_preview, int(token_draft["size"])) + 0.45) if token_placement_fixed else token_cancel_anchor
		ui.show_token_placement_actions(_action_screen(at), token_placement_fixed)
		return
	ui.hide_token_placement_actions()
	if tool == Tool.SHAPE and shape_plan.dirty():
		_clear_entity_hover()
		var at := shape_edit_anchor if shape_plan.moving else _shape_origin_world(shape_plan.draft)
		ui.show_shape_actions(_action_screen(at), not shape_plan.moving and shape_plan.position_ready, shape_plan.moving)
		return
	if tool == Tool.MEASURE and measurement.editing_index >= 0:
		_clear_entity_hover()
		var at := _plan_world(measurement,measurement.editing_index) if measurement_edit_fixed else _cell_world(measurement.original_cell,Vector2i.ONE,measurement.original_surface)
		ui.show_measurement_actions(_action_screen(at), "measure_confirm" if measurement_edit_fixed else "measure_move_cancel")
		return
	if tool == Tool.MEASURE and measure_creating and measurement.points.is_empty():
		_clear_entity_hover()
		ui.show_measurement_actions(_action_screen(creation_action_anchor), "measure_wait")
		return
	ui.hide_shape_actions()
	ui.hide_measurement_actions()
	if tool == Tool.ROUTE or (tool == Tool.MEASURE and measure_creating):
		_clear_entity_hover()
		return
	if ui.rename_open() or camera_button != 0 or left_orbit_pending or ui.pointer_on_creation_palette():
		ui.hide_entity_actions()
		return
	if not entity_entries.is_empty(): _position_entity_group()
	if ui.entity_surface_under_pointer(): return
	var candidates: Array[Dictionary] = []
	if not ui.pointer_on_ui() or ui.token_index_under_pointer()>=0:
		candidates = _entity_candidates(mouse)
	_highlight_entity(candidates[0] if not candidates.is_empty() else (entity_entries[0] if entity_entries.size()==1 else {}))

func _select_entity(entry: Dictionary) -> void:
	var index := _entity_index(entry)
	selected = index if entry.get("kind")=="token" else -1
	if entry.get("kind")=="shape": shape_plan.select(index)
	_highlight_entity(entry)
	_refresh_selection()

func _select_at_pointer(mouse: Vector2) -> void:
	var candidates := _entity_candidates(mouse)
	_clear_entity_hover()
	selected = -1
	if tool==Tool.SHAPE: shape_plan.select(-1)
	if candidates.is_empty():
		_refresh_selection()
		return
	entity_anchor = candidates[0]["anchor"]
	if candidates.size()==1:
		entity_entries = candidates
		_select_entity(candidates[0])
	else:
		for candidate in candidates:
			var entry := candidate.duplicate()
			entry["selection_actions"] = candidate["actions"]
			entry["actions"] = [["select_entity","选择"]]
			entity_entries.append(entry)
		_refresh_selection()
	_position_entity_group()

func _action_screen(at: Vector3) -> Vector2:
	return get_viewport().get_visible_rect().size * Vector2(0.6, 0.5) if camera.is_position_behind(at) else camera.unproject_position(at)

func _position_entity_group() -> void:
	if entity_entries.is_empty():
		return
	var first := entity_entries[0]
	var index := _entity_index(first)
	if index < 0:
		_clear_entity_hover()
		return
	if first["kind"]=="token":
		var actor: Node3D = tokens[index]["node"]
		entity_anchor = actor.position+Vector3.UP*(_appearance_height(actor,int(tokens[index]["size"]))+0.45)
		first["label"] = "棋子 · "+str(tokens[index]["title"])
	if first["kind"] == "measure" and int(first["point"]) >= 0:
		var point := int(first["point"])
		if point < measurements[index].points.size():
			entity_anchor = _plan_world(measurements[index],point)
	var screen := camera.unproject_position(entity_anchor)
	var below: bool = entity_entries.size() == 1 and first["kind"] == "token"
	if below:
		var card := ui.get_node("TokenNames").get_child(index) as Control
		screen = card.get_global_rect().get_center() + Vector2(0, card.get_global_rect().size.y / 2)
	ui.show_entity_actions(entity_entries, screen, below)

func _measurement_candidates(mouse: Vector2) -> Array[Dictionary]:
	var candidates: Array[Dictionary] = []
	for index in range(measurements.size() - 1, -1, -1):
		var plan := measurements[index]
		if not plan.completed or plan.editing_index >= 0 or plan.points.size() < 2:
			continue
		var nearest_point := -1
		var node_distance := 144.0
		for point in range(plan.points.size()):
			var world := _plan_world(plan,point) + Vector3.UP * 0.14
			if camera.is_position_behind(world):
				continue
			var distance := camera.unproject_position(world).distance_squared_to(mouse)
			if distance <= node_distance:
				nearest_point = point
				node_distance = distance
		if nearest_point >= 0:
			candidates.append({"index": index, "point": nearest_point, "distance": node_distance, "anchor": _plan_world(plan,nearest_point)})
			continue
		var line_distance := 64.0
		var line_anchor := Vector3.ZERO
		var found := false
		for point in range(1, plan.points.size()):
			var a := _plan_world(plan,point-1)
			var b := _plan_world(plan,point)
			if camera.is_position_behind(a) or camera.is_position_behind(b):
				continue
			var closest := Geometry2D.get_closest_point_to_segment(mouse, camera.unproject_position(a), camera.unproject_position(b))
			var distance := closest.distance_squared_to(mouse)
			if distance <= line_distance:
				found = true
				line_distance = distance
				var weight := 0.5
				var screen_a := camera.unproject_position(a)
				var screen_b := camera.unproject_position(b)
				if screen_a.distance_squared_to(screen_b)>0.001: weight = clampf((closest-screen_a).dot(screen_b-screen_a)/screen_a.distance_squared_to(screen_b),0,1)
				line_anchor = a.lerp(b,weight)
		if found:
			candidates.append({"index": index, "point": -1, "distance": line_distance, "anchor": line_anchor})
	candidates.sort_custom(func(a: Dictionary, b: Dictionary):
		if (a["point"] >= 0) != (b["point"] >= 0):
			return a["point"] >= 0
		if not is_equal_approx(a["distance"], b["distance"]):
			return a["distance"] < b["distance"]
		return a["index"] > b["index"]
	)
	return candidates

func _clear_measurement_hover() -> void:
	hover_measurement = -1
	hover_measurement_point = -1
	ui.hide_measurement_actions()

func _activate_measurement(index: int) -> void:
	var plan := measurements[index]
	_on_tool("measure")
	measurement = plan
	route = plan
	measure_finished = plan.completed
	selected_point = -1
	ui.clear_overlays()
	_clear_lines()
	ui.release_keyboard_focus()

func _on_measurement_action(action: String) -> void:
	if network_readonly and action not in ["cancel_creation","cancel_node","forget_measure"]: return
	if action not in ["new","undo_measure","forget_measure","cancel_creation","confirm_node","cancel_node"] and hover_measurement>=0 and hover_measurement<measurements.size() and not _can_operate_tool("measurements",measurements[hover_measurement].display_id): return
	if action == "new":
		if measurements.size()>=256:
			ui.set_status("当前地图最多保存256条测距。")
			return
		if measurement.editing_index >= 0 or measure_creating:
			return
		_clear_entity_hover()
		continuation_snapshot.clear()
		measurement = MeasurementPlan.new()
		route = measurement
		measure_finished = false
		measure_creating = true
		creation_action_anchor = focus
		ui.clear_overlays()
		_clear_lines()
		ui.release_keyboard_focus()
		_update_status()
		return
	if action == "forget_measure":
		deleted_measurement.clear()
		return
	if action == "undo_measure":
		if deleted_measurement.is_empty():
			return
		var plan: MeasurementPlan = deleted_measurement["plan"]
		if not measurements.has(plan) and measurements.size()>=256:
			ui.set_status("当前地图已达到256条测距上限，请先移除一条再恢复。")
			return
		plan.points.assign(deleted_measurement["points"])
		plan.endpoints.assign(deleted_measurement["endpoints"])
		plan.point_surfaces.clear()
		for endpoint: Dictionary in plan.endpoints: plan.point_surfaces.append(endpoint.get("platform_id",""))
		plan.completed = true
		if not measurements.has(plan):
			measurements.insert(clampi(deleted_measurement["index"], 0, measurements.size()), plan)
		deleted_measurement.clear()
		ui.hide_measurement_undo()
		_clear_measurement_hover()
		return
	if action == "cancel_creation":
		_on_route_action("cancel")
		return
	if action in ["confirm_node", "cancel_node"]:
		_on_route_action("confirm" if action == "confirm_node" else "cancel")
		return
	if hover_measurement < 0 or hover_measurement >= measurements.size():
		return
	var index := hover_measurement
	var point := hover_measurement_point
	var plan := measurements[index]
	if action in ["delete_node", "delete_measure"]:
		deleted_measurement = {"plan": plan, "index": index, "points": plan.points.duplicate(), "endpoints": plan.endpoints.duplicate(true)}
		if action == "delete_node" and point >= 0:
			plan.delete_point(point)
		if action == "delete_measure" or plan.points.size() < 2:
			measurements.erase(plan)
			if measurement == plan:
				measurement = MeasurementPlan.new()
				if tool == Tool.MEASURE:
					route = measurement
				measure_finished = false
		plan.resolve(tokens)
		_clear_measurement_hover()
		ui.show_measurement_undo()
		_update_status()
		return
	_activate_measurement(index)
	if deleted_measurement.get("plan") == plan:
		deleted_measurement.clear()
		ui.hide_measurement_undo()
	if action == "continue":
		continuation_snapshot = {"plan": plan, "points": plan.points.duplicate(), "endpoints": plan.endpoints.duplicate(true)}
		plan.waypoint_endpoints.clear()
		measure_creating = true
		plan.completed = false
		measure_finished = false
	elif action == "move_node" and point >= 0:
		plan.start_edit(point)
		measurement_edit_fixed = false
	_sync_point_markers()
	_render_route()
	_update_status()



func apply_full_token_edit(token_id: int, parameters: Dictionary) -> void:
	var index := _entity_index({"kind":"token","id":token_id})
	if index<0 or not can_operate_token(index): return
	var data: Dictionary = tokens[index]
	if Footprint.dimensions(parameters)!=Footprint.dimensions(data): return
	var actor := _build_token_actor(data["cell"],int(parameters["size"]),parameters["color"],parameters["base"],index,Footprint.dimensions(data),parameters.get("components",{}),parameters.get("materials",{}))
	if actor==null: return
	var old: Node3D = data["node"]
	remove_child(old)
	old.queue_free()
	var scene := Instance.scene_values(data)
	data.merge(parameters,true)
	data.merge(scene,true)
	data["node"] = actor
	Instance.apply_orientation(actor,data)
	_refresh_selection()
	_update_saved_measurements()

func _plan_world(plan: RoutePlan, index: int, extent := Vector2i.ONE) -> Vector3:
	var platform_id := plan.point_surfaces[index] if index<plan.point_surfaces.size() else ""
	var measured := plan as MeasurementPlan
	if measured!=null and index<measured.endpoints.size():
		platform_id = measured.endpoints[index].get("platform_id",platform_id)
		for data: Dictionary in tokens:
			if data["id"]==measured.endpoints[index].get("token_id",-1): platform_id = data.get("platform_id",platform_id)
	return _cell_world(plan.points[index],extent,platform_id)

func prepare_session_switch() -> void:
	if tool==Tool.ROUTE: _leave_route()
	if measurement.editing_index>=0: measurement.cancel_edit()
	if measure_creating: _clear_measure()
	shape_plan.clear_draft()
	_clear_token_placement()
	_on_tool("select")
	ui.clear_overlays()

func export_session_tokens() -> void:
	if surfaces==null: return
	for platform: Dictionary in session_map["platforms"]: platform["data"]["tokens"] = []
	for token: Dictionary in tokens:
		var platform: Dictionary = surfaces.item(token.get("platform_id",""))
		if platform.is_empty(): continue
		var data := token.duplicate(true)
		data.erase("node")
		data["id"] = data["persistent_id"]
		if not session_party["owners"].has(data["id"]): session_party["owners"][data["id"]] = session_actor
		data["cell"] -= surfaces.origin(platform)
		data.erase("persistent_id")
		data.erase("platform_id")
		platform["data"]["tokens"].append(data)

func _shape_vertex(point: Vector2, data: Dictionary) -> Vector3:
	return Vector3(point.x-15,surfaces.height(data.get("platform_id","")) if surfaces!=null else 0.0,point.y-15)

func _shape_plane_point(mouse: Vector2, data: Dictionary) -> Vector2:
	var point: Variant = Plane(Vector3.UP,surfaces.height(data.get("platform_id",""))).intersects_ray(camera.project_ray_origin(mouse),camera.project_ray_normal(mouse))
	if point==null or not surfaces.visible_hit(point,mouse): return Vector2(-10000,-10000)
	return Vector2(point.x+15,point.z+15)

func can_operate_token(index: int) -> bool:
	return not network_readonly and index>=0 and index<tokens.size() and Members.can_token(session_party,session_actor,tokens[index]["persistent_id"])

func apply_network_content(data: Dictionary, party: Dictionary, state: Dictionary) -> void:
	var Wire = preload("res://scripts/network_wire.gd")
	var current := {"maps":[{"id":session_map_id,"data":session_map}],"trays":{}}
	var incoming := {"maps":[{"id":session_map_id,"data":data}],"trays":{}}
	export_session_tokens()
	var same: bool = Wire.canonical(Wire.indexed(current))==Wire.canonical(Wire.indexed(incoming)) and Wire.canonical(preload("res://scripts/adventure_runtime.gd").capture(self))==Wire.canonical(state)
	var old_layout := session_map.duplicate(true)
	var new_layout := data.duplicate(true)
	for platform: Dictionary in old_layout["platforms"]:
		platform["data"]["tokens"] = []
		platform["data"] = preload("res://scripts/platform_library_store.gd").signature(platform["data"])
	for platform: Dictionary in new_layout["platforms"]:
		platform["data"]["tokens"] = []
		platform["data"] = preload("res://scripts/platform_library_store.gd").signature(platform["data"])
	var can_update: bool = Wire.canonical(old_layout)==Wire.canonical(new_layout) and Wire.canonical(preload("res://scripts/adventure_runtime.gd").capture(self))==Wire.canonical(state)
	var incoming_tokens := {}
	for platform: Dictionary in data["platforms"]:
		for token: Dictionary in platform["data"].get("tokens",[]): incoming_tokens[token["id"]] = {"token":token,"platform":platform}
	can_update = can_update and incoming_tokens.size()==tokens.size()
	for token: Dictionary in tokens:
		if not incoming_tokens.has(token["persistent_id"]): can_update = false
	session_map = data
	session_party = party
	surfaces.platforms = data["platforms"]
	if same: return
	if can_update:
		for index in range(tokens.size()):
			var current_token: Dictionary = tokens[index]
			var incoming_token: Dictionary = incoming_tokens[current_token["persistent_id"]]["token"]
			var platform: Dictionary = incoming_tokens[current_token["persistent_id"]]["platform"]
			var rebuilt: bool = current_token["color"]!=incoming_token["color"] or current_token["base"]!=incoming_token["base"] or Footprint.dimensions(current_token)!=Footprint.dimensions(incoming_token) or Wire.canonical(current_token.get("components",{}))!=Wire.canonical(incoming_token.get("components",{})) or Wire.canonical(current_token.get("materials",{}))!=Wire.canonical(incoming_token.get("materials",{}))
			if [current_token["hp"],current_token["max_hp"],current_token.get("temp_hp",0)]!=[incoming_token["hp"],incoming_token["max_hp"],incoming_token.get("temp_hp",0)]:
				ui.get_node("StatsDialog").history.erase(current_token["id"])
				if ui.get_node("StatsDialog").token_index==index: ui.get_node("StatsDialog").hide()
			var raw := incoming_token.duplicate(true)
			raw.erase("id")
			raw["cell"] += surfaces.origin(platform)
			current_token.merge(raw,true)
			current_token["platform_id"] = platform["id"]
			if rebuilt:
				turn_control.close()
				var previous: Node3D = current_token["node"]
				previous.queue_free()
				current_token["node"] = _build_token_actor(current_token["cell"],int(current_token["size"]),current_token["color"],current_token["base"],index,Footprint.dimensions(current_token),current_token.get("components",{}), current_token.get("materials", {}))
			current_token["node"].position = _cell_world(current_token["cell"],Footprint.dimensions(current_token),platform["id"])
			Instance.apply_orientation(current_token["node"],current_token)
		_refresh_selection()
		return
	var previous_tool: String = ui.current_tool
	prepare_session_switch()
	for token: Dictionary in tokens:
		remove_child(token["node"])
		token["node"].queue_free()
	tokens.clear()
	selected = -1
	hover_token = -1
	ui.reset_after_token_removal(-1)
	ui.get_node("StatsDialog").history.clear()
	for platform: Dictionary in session_map["platforms"]:
		surfaces.current = platform["id"]
		for token: Dictionary in platform["data"].get("tokens",[]):
			var before := tokens.size()
			_add_token(token["title"],token["cell"]+surfaces.origin(platform),token["size"],token["color"],token["hp"],token["ac"],token["base"],token["max_hp"],token.get("kind","basic"),token.get("tags",[]),Footprint.dimensions(token),token.get("components",{}), token.get("materials", {}))
			if tokens.size()==before:
				session_load_error = "未能完整生成同步棋子。"
				continue
			Instance.apply_parameters(tokens[-1],token)
			Instance.apply_orientation(tokens[-1]["node"],tokens[-1])
			tokens[-1]["persistent_id"] = token["id"]
			tokens[-1]["platform_id"] = platform["id"]
	shape_plan = ShapePlan.new()
	measurements.clear()
	measurement = MeasurementPlan.new()
	measure_finished = false
	next_measurement_id = 1
	deleted_measurement.clear()
	ui.hide_measurement_undo()
	ui.hide_shape_undo()
	_clear_lines()
	preload("res://scripts/adventure_runtime.gd").restore(self,state)
	_refresh_selection()
	_on_tool(previous_tool if previous_tool in ["select","measure","shape"] else "select")

func _mobile_attach() -> void:
	if Mobile.enabled: mobile_touch = preload("res://ui/components/mobile_scene_input.gd").attach(self,"board")
