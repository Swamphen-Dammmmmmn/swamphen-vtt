extends Node3D

# Temporary composition/input adapter. Reusable editing lives in Workspace.
const Workspace = preload("res://scripts/scenery/wall_opening_workspace.gd")
const Overlay = preload("res://scripts/scenery/wall_opening_overlay.gd")
const Data = preload("res://scripts/scenery/wall_layout_data.gd")
const W = preload("res://scripts/scenery/wall_parameters.gd")
const P = preload("res://scripts/scenery/opening_parameters.gd")
const SandboxPanel = preload("res://ui/components/features/editor/opening_sandbox_panel.gd")
const FlyCamera = preload("res://dev/terrain_fly_camera.gd")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
const Modal = preload("res://ui/components/page_modal.gd")

@export var capture_initial := false
@export var enable_navigation := true
@export var primary_surface := "planks_horizontal"
@export_dir var capture_directory := "res://artifacts/wall-opening-layout-2026-10-25/"
var _workspace: Workspace
var _overlay: Overlay
var _camera: FlyCamera
var _panel: SandboxPanel
var _ready_for_input := false
var _pressed := false
var _dragging := false
var _pressed_id := ""
var _press_face := 1
var _press_origin := Vector2.ZERO
var _touches := {}
var _blocked_touch := false
var _modal: Control

func _ready() -> void:
	_environment()
	_camera=FlyCamera.new()
	_camera.near=0.03
	_camera.far=100
	_camera.fov=45
	_camera.current=true
	add_child(_camera)
	_workspace=Workspace.new()
	_workspace.name="OpeningWorkspace"
	add_child(_workspace)
	_overlay=Overlay.new()
	add_child(_overlay)
	var hud := Control.new()
	hud.mouse_filter=Control.MOUSE_FILTER_IGNORE
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(hud)
	_panel=SandboxPanel.new()
	hud.add_child(_panel)
	_panel.set_anchors_and_offsets_preset(Control.PRESET_LEFT_WIDE)
	_panel.offset_left=T.GAP
	_panel.offset_top=T.GAP
	_panel.offset_bottom=-T.GAP
	_panel.offset_right=T.GAP+T.SETTINGS_FIELD_COMPACT_WIDTH
	_panel.create_requested.connect(_create)
	_panel.update_requested.connect(_update_record)
	_panel.delete_requested.connect(func(id: String): _report(await _workspace.execute({"op":"remove_opening","id":id})))
	_panel.undo_requested.connect(func(): _report(await _workspace.undo()))
	_panel.redo_requested.connect(func(): _report(await _workspace.redo()))
	_panel.cancel_requested.connect(_cancel_input)
	_panel.frame_requested.connect(_frame)
	_panel.status_detail_requested.connect(_details)
	_workspace.layout_changed.connect(func(_layout: Dictionary, _reason: String, _revision: int): _refresh())
	_workspace.selection_changed.connect(func(_id: String): _refresh())
	_workspace.busy_changed.connect(func(_busy: bool): _refresh())
	_workspace.operation_failed.connect(func(message: String): _panel.set_status(message,true))
	_workspace.preview_changed.connect(_on_preview)
	get_window().focus_exited.connect(_focus_lost)
	var result := await _workspace.replace_layout(_initial_layout(),"初始样板",true)
	if not result.ok:
		push_error(result.message)
		return
	_frame()
	_refresh()
	_ready_for_input=true
	_panel.set_status("选择门窗拖动，或点击放置木门 / 木窗")
	DisplayServer.window_set_title("墙面门窗布局 · "+W.SURFACE_TITLES[W.SURFACES.find(primary_surface)]+" · 双轴拖动 / 撤销重做")
	print("WALL_OPENING_LAYOUT_READY walls=3 openings=3")
	if capture_initial:
		await get_tree().create_timer(1.5).timeout
		await RenderingServer.frame_post_draw
		print("WALL_OPENING_LAYOUT_CAPTURE=",get_viewport().get_texture().get_image().save_png(capture_directory.path_join("initial.png")))

func _initial_layout() -> Dictionary:
	var front := W.defaults(0,primary_surface)
	front.length=15.0
	var side := W.defaults(0,"planks_vertical" if primary_surface=="planks_horizontal" else primary_surface)
	side.length=10.0
	var logs := W.defaults(0,"logs_round")
	logs.length=15.0
	var door := P.defaults("wood_door")
	door.offset=-4.0
	var window := P.defaults("wood_window")
	window.offset=3.5
	var side_window := P.defaults("wood_window")
	return {"version":1,"walls":[
		{"id":"front","parameters":front,"transform":Transform3D(Basis.IDENTITY,Vector3(-1.5,0,0)),
			"openings":[{"id":"door-front","spec":door},{"id":"window-front","spec":window}]},
		{"id":"side","parameters":side,"transform":Transform3D(Basis(Vector3.UP,PI*0.5),Vector3(1.5,0,0)),
			"openings":[{"id":"window-side","spec":side_window}]},
		{"id":"logs","parameters":logs,"transform":Transform3D(Basis.IDENTITY,Vector3(-1.5,0,-3)),"openings":[]}]}

func _create(preset: String) -> void:
	_cancel_input()
	_report(_workspace.begin_create(P.defaults(preset)))
	_panel.set_status("指向墙面预览；点击确认；右键或Esc取消")
	_refresh()

func _update_record(id: String, wall_id: String, spec: Dictionary, anchor: Vector2) -> void:
	var layout := _workspace.snapshot()
	var wi := Data.find_wall(layout,wall_id)
	if wi<0: return
	var positioned := Data.at_anchor(layout.walls[wi].parameters,spec,anchor)
	_report(await _workspace.execute({"op":"update_opening","id":id,"wall_id":wall_id,"spec":positioned}))

func _refresh() -> void:
	if _panel==null or _workspace==null: return
	if not _workspace.has_preview(): _panel.show_record(_workspace.snapshot(),_workspace.selected_record())
	_panel.set_workspace_state(_workspace.is_busy(),_workspace.has_preview(),_workspace.can_undo(),_workspace.can_redo())
	_overlay.show_selection(_workspace.snapshot(),_workspace.selected_id())
	_update_camera()

func _on_preview(preview: Dictionary) -> void:
	_overlay.show_preview(preview)
	_panel.set_workspace_state(_workspace.is_busy(),_workspace.has_preview(),_workspace.can_undo(),_workspace.can_redo())
	if not preview.is_empty():
		_panel.set_status("有效预览 · 松手确认" if preview.ok else preview.message,not preview.ok)
	_update_camera()

func _report(result: Dictionary) -> void:
	if result.ok: _panel.set_status(result.get("message","") if not result.get("message","").is_empty() else "修改已应用，可撤销")
	else: _panel.set_status(result.message,true)
	_refresh()

func _ray(position: Vector2) -> Dictionary:
	return {"origin":_camera.project_ray_origin(position),"direction":_camera.project_ray_normal(position)}

func _aim(position: Vector2) -> void:
	if not _workspace.has_preview() or _workspace.is_busy(): return
	var ray := _ray(position)
	_workspace.aim_ray(ray.origin,ray.direction,_panel.snap_step())

# _input sees release/cancel even over GUI; only unhandled press may claim scene.
func _input(event: InputEvent) -> void:
	if not _ready_for_input: return
	if event is InputEventKey and event.pressed and not event.echo and event.keycode==KEY_ESCAPE:
		if _workspace.has_preview() or _pressed:
			_cancel_input()
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_RIGHT:
		if event.pressed and (_workspace.has_preview() or _pressed) and not _over_ui():
			_cancel_input()
			get_viewport().set_input_as_handled()
		elif not event.pressed: _camera.release_mouse()
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed and _pressed:
		_release(event.position,not _over_ui(event.position))
		get_viewport().set_input_as_handled()
	if event is InputEventScreenTouch and not event.pressed and _touches.has(event.index):
		_touches.erase(event.index)
		if not _blocked_touch and _pressed: _release(event.position,not _over_ui(event.position))
		if _touches.is_empty():
			_blocked_touch=false
			_update_camera()
		get_viewport().set_input_as_handled()
	if event is InputEventScreenTouch and event.pressed:
		_touches[event.index]=event.position
		if _touches.size()>1:
			_blocked_touch=true
			_cancel_input()
			get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if not _ready_for_input or _workspace.is_busy() or _modal!=null: return
	if event is InputEventMouseButton:
		if event.button_index==MOUSE_BUTTON_LEFT and event.pressed: _press(event.position)
		elif event.button_index==MOUSE_BUTTON_RIGHT and event.pressed and not _workspace.has_preview():
			get_viewport().gui_release_focus()
			_camera.begin_turn()
	elif event is InputEventMouseMotion:
		if _camera.turning: _camera.turn(event.relative)
		else: _motion(event.position)
	elif event is InputEventScreenTouch and event.pressed and not _blocked_touch:
		_press(event.position)
	elif event is InputEventScreenDrag and not _blocked_touch:
		_motion(event.position)
	elif event is InputEventKey and event.pressed and not event.echo:
		var focus := get_viewport().gui_get_focus_owner()
		if focus is LineEdit or focus is TextEdit: return
		if event.ctrl_pressed and event.keycode in [KEY_Z,KEY_Y]:
			if _workspace.can_redo() and (event.keycode==KEY_Y or event.shift_pressed): _report(await _workspace.redo())
			elif _workspace.can_undo() and event.keycode==KEY_Z: _report(await _workspace.undo())
			get_viewport().set_input_as_handled()

func _press(position: Vector2) -> void:
	if _blocked_touch or _camera.turning: return
	get_viewport().gui_release_focus()
	_pressed=true
	_dragging=false
	_press_origin=position
	_pressed_id=""
	if _workspace.has_preview():
		_aim(position)
		return
	var ray := _ray(position)
	var hit := _workspace.pick_ray(ray.origin,ray.direction)
	if hit.ok:
		_pressed_id=hit.opening_id
		_press_face=hit.face
	_workspace.select_opening(_pressed_id)

func _motion(position: Vector2) -> void:
	if _over_ui(position): return
	var mobile := get_node_or_null("/root/Mobile")
	var threshold := float(mobile.touch_units(6.0)) if mobile!=null and not _touches.is_empty() else 4.0
	if _pressed and not _pressed_id.is_empty() and not _dragging and position.distance_to(_press_origin)>threshold:
		var ray := _ray(_press_origin)
		var result := _workspace.begin_move(_pressed_id,ray.origin,ray.direction,_press_face)
		_dragging=result.ok
	if _workspace.has_preview(): _aim(position)

func _release(position: Vector2, allowed: bool) -> void:
	_pressed=false
	_pressed_id=""
	if not _workspace.has_preview(): return
	if not allowed:
		_cancel_input()
		return
	_aim(position)
	if _workspace.preview().get("ok",false): _report(await _workspace.commit_preview())
	else:
		var message: String = _workspace.preview().get("message","位置无效")
		_cancel_input()
		_panel.set_status(message,true)
	_dragging=false

func _over_ui(position := Vector2.INF) -> bool:
	var point := get_viewport().get_mouse_position() if position==Vector2.INF else position
	# Touch release is checked geometrically; it does not depend on mouse emulation.
	return _panel.get_global_rect().has_point(point) or _panel.is_popup_open() or _modal!=null

func _focus_lost() -> void:
	_touches.clear()
	_blocked_touch=false
	_cancel_input()

func _cancel_input() -> void:
	_pressed=false
	_dragging=false
	_pressed_id=""
	if _camera!=null: _camera.release_mouse()
	if _workspace!=null: _workspace.cancel_preview()
	if _panel!=null:
		_panel.close_popups()
		_refresh()

func _update_camera() -> void:
	if _camera!=null:
		var shortcut := Input.is_physical_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_ALT) or Input.is_physical_key_pressed(KEY_META)
		_camera.set_enabled(enable_navigation and not shortcut and not _workspace.is_busy() and not _workspace.has_preview() and _modal==null and not _blocked_touch)

func _process(_delta: float) -> void:
	if _ready_for_input: _update_camera()

func _details(message: String) -> void:
	_cancel_input()
	_modal=Modal.new()
	add_child(_modal)
	_modal.configure("布局详情",message)
	_modal.add_action("关闭",_modal.dismiss)
	_modal.dismissed.connect(func(): _modal=null; _update_camera())
	_update_camera()

func _frame() -> void:
	if _workspace!=null and (_workspace.has_preview() or _workspace.is_busy()): return
	_camera.position=Vector3(5.2,4.4,7.3)
	_camera.look_at(Vector3(0.25,0.9,-0.6))
	_camera.yaw=_camera.rotation.y
	_camera.pitch=_camera.rotation.x
	_camera.base_speed=3.0
	_update_camera()

func _environment() -> void:
	var environment := WorldEnvironment.new()
	environment.environment=Environment.new()
	environment.environment.background_mode=Environment.BG_COLOR
	environment.environment.background_color=Color("c4c7cc")
	environment.environment.ambient_light_source=Environment.AMBIENT_SOURCE_COLOR
	environment.environment.ambient_light_color=Color.WHITE
	environment.environment.ambient_light_energy=0.65
	add_child(environment)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees=Vector3(-45,-30,0)
	sun.shadow_enabled=true
	add_child(sun)
	var ground := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size=Vector3(12,0.1,12)
	ground.mesh=mesh
	ground.position.y=-0.05
	var material := StandardMaterial3D.new()
	material.albedo_color=Color("d8dadd")
	material.roughness=1.0
	ground.material_override=material
	add_child(ground)
	var lines := ImmediateMesh.new()
	lines.surface_begin(Mesh.PRIMITIVE_LINES)
	for coordinate in range(-6,7):
		lines.surface_add_vertex(Vector3(coordinate,0.002,-6))
		lines.surface_add_vertex(Vector3(coordinate,0.002,6))
		lines.surface_add_vertex(Vector3(-6,0.002,coordinate))
		lines.surface_add_vertex(Vector3(6,0.002,coordinate))
	lines.surface_end()
	var grid := MeshInstance3D.new()
	grid.mesh=lines
	var grid_material := StandardMaterial3D.new()
	grid_material.shading_mode=BaseMaterial3D.SHADING_MODE_UNSHADED
	grid_material.albedo_color=Color("aeb4bc")
	grid.material_override=grid_material
	add_child(grid)
