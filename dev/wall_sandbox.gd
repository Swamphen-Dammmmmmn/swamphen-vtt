extends Node3D

const Generator = preload("res://scripts/scenery/wall_generator.gd")
const Joiner = preload("res://scripts/scenery/wall_joiner.gd")
const Parameters = preload("res://scripts/scenery/wall_parameters.gd")
const SandboxPanel = preload("res://ui/components/features/editor/wall_sandbox_panel.gd")
const FlyCamera = preload("res://dev/terrain_fly_camera.gd")
const Appearance = preload("res://scripts/token_appearance.gd")
const SampleLabel = preload("res://ui/components/features/editor/wall_sample_label.gd")
const Tokens = preload("res://ui/theme/tokens/fluent_tokens.gd")
const Modal = preload("res://ui/components/page_modal.gd")
const TextureBank = preload("res://scripts/scenery/plank_texture_bank.gd")
const BarkBank = preload("res://scripts/scenery/bark_texture_bank.gd")
const EXTENT := Vector2(8, 6)

@export_dir var capture_directory := "res://artifacts/wall-horizontal-planks-2026-10-24/"
@export var capture_initial := false
@export_enum("全景", "转角近景", "直线近景", "门窗近景") var view_mode := 0
@export var initial_surface := "planks_horizontal"
@export var initial_overrides: Dictionary = {}
@export var initial_placing := true
var _values := Parameters.defaults(0, "planks_horizontal")
var _result: Dictionary = {}
var _panel: SandboxPanel
var _hud: Control
var _camera: Camera3D
var _walls: Node3D
var _samples: Node3D
var _ghost: MeshInstance3D
var _entries: Array[Dictionary] = []
var _committed_parts: Array[Dictionary] = []
var _showing_join_preview := false
var _proposal: Dictionary = {}
var _proposal_key := ""
var _revision := 0
var _initialized := false
var _generation_busy := false
var _proposal_pending := false
const INITIAL_COUNT := 7
var _turns := 0
var _placing := true
var _can_place := false
var _press_origin := Vector2.ZERO
var _pressed := false
var _dragged := false
var _modal: Control

func _ready() -> void:
	_values = _initial_recipe()
	_placing = initial_placing
	DisplayServer.window_set_title("紫水鸡棋盘 · 墙壁三件套灰模沙盒")
	_make_environment()
	_make_ground()
	_walls = Node3D.new()
	_walls.name = "Walls"
	add_child(_walls)
	_samples = Node3D.new()
	_samples.name = "SampleLabelsAndReference"
	add_child(_samples)
	_camera = FlyCamera.new()
	_camera.current = true
	_camera.near = 0.05
	_camera.far = 150
	_camera.fov = 44
	add_child(_camera)
	_camera.set_enabled(true)
	get_window().focus_exited.connect(_cancel_input)
	_ghost = MeshInstance3D.new()
	_ghost.name = "PlacementPreview"
	_ghost.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var ghost_material := StandardMaterial3D.new()
	ghost_material.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	ghost_material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ghost_material.albedo_color = Color(0.15, 0.55, 0.85, 0.4)
	_ghost.material_override = ghost_material
	add_child(_ghost)
	_hud = Control.new()
	_hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(_hud)
	_panel = SandboxPanel.new()
	_panel.popup_host = _hud
	_panel.set_values(_values)
	_hud.add_child(_panel)
	_panel.set_placing(_placing)
	_panel.visible = view_mode == 0
	_panel.parameter_changed.connect(_change)
	_panel.rotation_requested.connect(_rotate)
	_panel.undo_requested.connect(_undo)
	_panel.reset_requested.connect(_reset)
	_panel.frame_requested.connect(_frame)
	_panel.mode_changed.connect(_set_placing)
	_panel.status_detail_requested.connect(_show_status)
	get_viewport().size_changed.connect(_fit_panel)
	_fit_panel()
	await _reset()
	await _regenerate()
	_frame()
	_initialized = true
	print("WALL_SANDBOX_READY grid_feet=5 initial_walls=", INITIAL_COUNT, " surface=", initial_surface, " origin=left_floor desktop_authoring=true")
	_set_window_title()
	if capture_initial: _capture()

func _set_window_title() -> void:
	# Apply after the startup helper restores the project's default debug title.
	await get_tree().create_timer(0.25).timeout
	var title: String = Parameters.SURFACE_TITLES[Parameters.SURFACES.find(initial_surface)]
	var texture_title := "树皮" if initial_surface=="logs_bark" else "单板木纹"
	var layers := BarkBank.COLORS.get_layers() if initial_surface=="logs_bark" else TextureBank.COLORS.get_layers()
	DisplayServer.window_set_title("墙壁沙盒 · %s · %s%d种" % [title,texture_title,layers])

func _initial_recipe(kind := 0) -> Dictionary:
	var parameters := Parameters.defaults(kind, initial_surface)
	parameters.merge(initial_overrides, true)
	return parameters

func _make_environment() -> void:
	var world := WorldEnvironment.new()
	world.environment = Environment.new()
	world.environment.background_mode = Environment.BG_COLOR
	world.environment.background_color = Color("c4c7cc")
	world.environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	world.environment.ambient_light_color = Color.WHITE
	world.environment.ambient_light_energy = 0.6
	world.environment.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	add_child(world)
	var sun := DirectionalLight3D.new()
	sun.rotation_degrees = Vector3(-48, -35, 0)
	sun.light_energy = 1.2
	sun.shadow_enabled = true
	add_child(sun)

func _make_ground() -> void:
	var ground := MeshInstance3D.new()
	var box := BoxMesh.new()
	box.size = Vector3(EXTENT.x * 2, 0.3, EXTENT.y * 2)
	ground.mesh = box
	ground.position.y = -0.15
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("92969c")
	material.roughness = 1.0
	ground.material_override = material
	add_child(ground)
	var grid := ImmediateMesh.new()
	var ink := StandardMaterial3D.new()
	ink.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	ink.albedo_color = Color("737880")
	grid.surface_begin(Mesh.PRIMITIVE_LINES, ink)
	for x in range(-int(EXTENT.x), int(EXTENT.x) + 1):
		grid.surface_add_vertex(Vector3(x, 0.003, -EXTENT.y))
		grid.surface_add_vertex(Vector3(x, 0.003, EXTENT.y))
	for z in range(-int(EXTENT.y), int(EXTENT.y) + 1):
		grid.surface_add_vertex(Vector3(-EXTENT.x, 0.003, z))
		grid.surface_add_vertex(Vector3(EXTENT.x, 0.003, z))
	grid.surface_end()
	var lines := MeshInstance3D.new()
	lines.mesh = grid
	lines.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(lines)

func _reset() -> void:
	if _generation_busy: return
	_cancel_input()
	_set_generation_busy(true)
	for child in _samples.get_children():
		_samples.remove_child(child)
		child.queue_free()
	var entries: Array[Dictionary] = []
	var wall_length := float(_initial_recipe().length) * Parameters.FEET
	for i in 3:
		var position := Vector3(-5.0 + i * 3.0, 0, -2)
		var parameters := _initial_recipe(i)
		entries.append({"parameters": parameters, "transform": Transform3D(Basis.IDENTITY, position)})
		var label := SampleLabel.new()
		label.text = Parameters.TITLES[i]
		label.position = position + Vector3(wall_length * 0.5, 2.3, 0)
		_samples.add_child(label)
	for side in 2:
		var position := Vector3(-3 + wall_length * side, 0, 2)
		var parameters := _initial_recipe()
		entries.append({"parameters": parameters, "transform": Transform3D(Basis(Vector3.UP, PI * 0.5 * side), position)})
	for segment in 2:
		var parameters := _initial_recipe()
		entries.append({"parameters": parameters, "transform": Transform3D(Basis.IDENTITY, Vector3(1 + wall_length * segment, 0, 2))})
	var reference := Appearance.build(1, Color("646b75"), "circle")
	reference.position = Vector3(0, 0, 3.5)
	_samples.add_child(reference)
	var joined := await Joiner.build(entries)
	if not joined.ok:
		push_error(joined.message)
		_set_generation_busy(false)
		return
	_commit(entries, joined)
	_set_generation_busy(false)
	_panel.set_count(0)
	_update_status()

func _commit(entries: Array[Dictionary], joined: Dictionary) -> void:
	# Resolve and validate the entire connected arrangement before replacing anything.
	for child in _walls.get_children():
		_walls.remove_child(child)
		child.queue_free()
	_entries = entries.duplicate(true)
	_committed_parts = joined.parts.duplicate()
	_showing_join_preview = false
	for i in _entries.size():
		var wall := Generator.instantiate_wall(joined.parts[i])
		wall.transform = _entries[i].transform
		_walls.add_child(wall)
	_revision += 1
	_proposal_key = ""
	_panel.set_count(maxi(0, _entries.size() - INITIAL_COUNT))

func _change(key: String, value: Variant) -> void:
	if _generation_busy: return
	_cancel_input()
	_values[key] = value
	if key == "kind":
		_values.opening_height = Parameters.defaults(int(value)).opening_height
	if key == "surface":
		var defaults := Parameters.defaults(int(_values.kind), value)
		_values.color = defaults.color
		_values.thickness = defaults.thickness
	_panel.set_values(_values)
	if key == "color":
		_revision += 1
		_proposal_key = ""
		if _result.get("ok", false):
			_result = Generator.recolor(_result, value)
			_ghost.mesh = _result.mesh
			_update_status()
		return
	await _regenerate()

func _regenerate() -> void:
	_set_generation_busy(true)
	_revision += 1
	_proposal_key = ""
	_result = await Generator.build(_values.duplicate(true))
	_set_generation_busy(false)
	if not _result.ok:
		_ghost.visible = false
		_can_place = false
		_panel.set_status(_result.message + "；修正后才能摆放", true)
		return
	_ghost.mesh = _result.mesh
	_update_status()
	print("WALL_GENERATED kind=", _values.kind, " triangles=", _result.triangles, " bounds=", _result.bounds)

func _rotate() -> void:
	_cancel_input()
	_turns = (_turns + 1) % 4
	_panel.set_orientation(_turns * 90)

func _set_placing(value: bool) -> void:
	_cancel_input()
	_placing = value
	_panel.set_placing(value)
	_update_status()

func _undo() -> void:
	if _generation_busy: return
	_cancel_input()
	if _entries.size() <= INITIAL_COUNT: return
	_set_generation_busy(true)
	var entries: Array[Dictionary] = _entries.duplicate(true)
	entries.pop_back()
	var joined := await Joiner.build(entries)
	if not joined.ok:
		_panel.set_status(joined.message, true)
		_set_generation_busy(false)
		return
	_commit(entries, joined)
	_set_generation_busy(false)
	_update_status()

func _update_status() -> void:
	if not _result.get("ok", false): return
	_panel.set_status("%s · %d 三角面 · 已摆放%d件" % [Parameters.TITLES[int(_values.kind)], _result.triangles, maxi(0, _entries.size() - INITIAL_COUNT)])

func _show_status(message: String) -> void:
	if is_instance_valid(_modal): return
	_cancel_input()
	_modal = Modal.new()
	_hud.add_child(_modal)
	_modal.configure("沙盒状态", message)
	_modal.add_action("关闭", _modal.dismiss, true)

func _fit_panel() -> void:
	var safe := Mobile.safe_rect(get_viewport().get_visible_rect().size)
	var inset := float(Tokens.FORM_PADDING)
	var width := minf(Tokens.SETTINGS_FIELD_COMPACT_WIDTH, safe.size.x - inset * 2)
	_panel.set_minimum_width(width)
	_panel.position = safe.position + Vector2.ONE * inset
	_panel.size = Vector2(width, safe.size.y - inset * 2)

func _frame() -> void:
	_cancel_input()
	var corner_x := -3.0 + float(_initial_recipe().length) * Parameters.FEET
	var positions := [Vector3(12, 11, 16), Vector3(-0.2, 5, 5.5), Vector3(3.1, 2.6, 5.6), Vector3(-1.5, 2.5, -7.5)]
	var targets := [Vector3(-2, 0, 0), Vector3(corner_x - 0.4, 1, 1.7), Vector3(2, 1, 2), Vector3(-1.5, 1, -2)]
	_camera.position = positions[view_mode]
	_camera.look_at(targets[view_mode])
	_camera.yaw = _camera.rotation.y
	_camera.pitch = _camera.rotation.x
	_camera.base_speed = 6.0

func _cancel_input() -> void:
	_pressed = false
	_dragged = false
	_can_place = false
	if is_instance_valid(_ghost): _ghost.visible = false
	if is_instance_valid(_camera): _camera.release_mouse()
	_restore_join_preview()

func _restore_join_preview() -> void:
	if not _showing_join_preview: return
	for i in _committed_parts.size():
		var wall_mesh := _walls.get_child(i).get_node("WallMesh") as MeshInstance3D
		wall_mesh.mesh = _committed_parts[i].mesh
	_showing_join_preview = false

func _blocked() -> bool:
	var focus := get_viewport().gui_get_focus_owner()
	return _generation_busy or not DisplayServer.window_is_focused() or _panel.is_popup_open() or is_instance_valid(_modal) or focus is LineEdit or focus is TextEdit or Input.is_physical_key_pressed(KEY_CTRL) or Input.is_physical_key_pressed(KEY_ALT) or Input.is_physical_key_pressed(KEY_META)

func _set_generation_busy(value: bool) -> void:
	_generation_busy = value
	if value:
		_revision += 1
		_proposal_key = ""
	_panel.set_generation_busy(value)

func _process(_delta: float) -> void:
	if not _initialized: return
	var blocked := _blocked()
	_camera.set_enabled(not blocked)
	if blocked:
		_cancel_input()
		return
	_update_ghost()

func _update_ghost() -> void:
	_can_place = false
	_ghost.visible = false
	if _proposal_pending or not _placing or not _result.get("ok", false) or _camera.turning or get_viewport().gui_get_hovered_control() != null:
		_restore_join_preview()
		return
	var mouse := get_viewport().get_mouse_position()
	var origin := _camera.project_ray_origin(mouse)
	var direction := _camera.project_ray_normal(mouse)
	var hit: Variant = Plane(Vector3.UP, 0).intersects_ray(origin, direction)
	if hit == null:
		_restore_join_preview()
		return
	_ghost.position = Vector3(roundf(hit.x), 0, roundf(hit.z))
	_ghost.rotation.y = _turns * PI * 0.5
	var box: AABB = _ghost.transform * _result.bounds
	var on_board := box.position.x >= -EXTENT.x - 0.001 and box.end.x <= EXTENT.x + 0.001 and box.position.z >= -EXTENT.y - 0.001 and box.end.z <= EXTENT.y + 0.001
	var duplicate := false
	for child in _walls.get_children():
		if not child is StaticBody3D: continue
		# Same segment in either direction is an accidental duplicate, even with a different opening.
		var length := float(child.get_meta("wall_parameters").length) * Parameters.FEET
		var end: Vector3 = child.transform * Vector3(length, 0, 0)
		var ghost_end: Vector3 = _ghost.transform * Vector3(float(_values.length) * Parameters.FEET, 0, 0)
		if (child.position.is_equal_approx(_ghost.position) and end.is_equal_approx(ghost_end)) or (child.position.is_equal_approx(ghost_end) and end.is_equal_approx(_ghost.position)):
			duplicate = true
	var key := "%d:%d:%d:%d" % [roundi(hit.x), roundi(hit.z), _turns, _revision]
	if key != _proposal_key:
		var revision := _revision
		var entries: Array[Dictionary] = _entries.duplicate(true)
		entries.append({"parameters": _values.duplicate(true), "transform": _ghost.transform})
		_proposal_pending = true
		var proposal := await Joiner.build(entries)
		_proposal_pending = false
		if revision != _revision or _blocked() or not _placing:
			return
		_proposal = proposal
		_proposal_key = key
		# Re-evaluate the current cursor next frame; never commit the old cursor's result.
		return
	if _proposal_key == key:
		_ghost.mesh = _proposal.parts.back().mesh if _proposal.ok else _result.mesh
		if not _proposal.ok: _panel.set_status(_proposal.message, true)
		else: _update_status()
	if _proposal.ok:
		for i in _proposal.parts.size():
			var transform: Transform3D = _entries[i].transform if i < _entries.size() else _ghost.transform
			box = transform * _proposal.parts[i].bounds
			on_board = on_board and box.position.x >= -EXTENT.x - 0.001 and box.end.x <= EXTENT.x + 0.001 and box.position.z >= -EXTENT.y - 0.001 and box.end.z <= EXTENT.y + 0.001
	_can_place = on_board and not duplicate and _proposal.ok
	if _can_place:
		# Show the neighbouring end cuts too, without changing committed geometry/collision.
		for i in _entries.size():
			var wall_mesh := _walls.get_child(i).get_node("WallMesh") as MeshInstance3D
			wall_mesh.mesh = _proposal.parts[i].mesh
		_showing_join_preview = true
	else:
		_restore_join_preview()
	_ghost.visible = true
	var material := _ghost.material_override as StandardMaterial3D
	material.albedo_color = Color(0.15, 0.55, 0.85, 0.4) if _can_place else Color(0.85, 0.15, 0.15, 0.4)

func _input(event: InputEvent) -> void:
	if not _initialized: return
	if event is InputEventMouseMotion:
		if _pressed and event.position.distance_to(_press_origin) > Mobile.touch_units(8): _dragged = true
		if _camera.turning:
			_camera.turn(event.relative)
			get_viewport().set_input_as_handled()
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT: _camera.release_mouse()
		if event.button_index == MOUSE_BUTTON_LEFT and (get_viewport().gui_get_hovered_control() != null or _blocked()): _pressed = false

func _unhandled_input(event: InputEvent) -> void:
	if not _initialized: return
	if _blocked(): return
	if event is InputEventKey and event.pressed and not event.echo:
		if event.keycode == KEY_R: _rotate()
		elif event.keycode == KEY_ESCAPE: _set_placing(false)
		else: return
		get_viewport().set_input_as_handled()
	if not event is InputEventMouseButton: return
	if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		_pressed = false
		_camera.begin_turn()
		get_viewport().set_input_as_handled()
	if event.button_index == MOUSE_BUTTON_LEFT:
		if event.pressed:
			_press_origin = event.position
			_pressed = _placing
			_dragged = false
		else:
			_update_ghost()
			if _pressed and not _dragged and _can_place:
				var entries: Array[Dictionary] = _entries.duplicate(true)
				entries.append({"parameters": _values.duplicate(true), "transform": _ghost.transform})
				_commit(entries, _proposal)
				_update_status()
			_pressed = false

func _capture() -> void:
	await get_tree().create_timer(1.5).timeout
	await RenderingServer.frame_post_draw
	var file: String = ["initial.png", "corner.png", "straight.png", "openings.png"][view_mode]
	print("WALL_CAPTURE result=", get_viewport().get_texture().get_image().save_png(capture_directory.path_join(file)))
