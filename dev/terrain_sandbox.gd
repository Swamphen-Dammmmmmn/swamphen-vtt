extends Node3D

const Style = preload("res://ui/components/page_style.gd")
const FlyCamera = preload("res://dev/terrain_fly_camera.gd")
const EnvironmentProfile = preload("res://scripts/environment_profile.gd")
const SAMPLES := 128
const SPACING := 0.25
const EDGE_MIN := 4
const EDGE_MAX := 124
const SAVE_PATH := "user://dev_terrain_sandbox.bin"
const TOOLS := ["抬高", "降低", "平滑", "草地", "沙地", "石头地", "地表开口", "恢复地表"]
const GROUND_COLORS := [Color("40b85a"), Color("d7bc7c"), Color("8b99aa")]

var terrain: Terrain3D
var camera: Camera3D
var height_map: Image
var control_map: Image
var color_map: Image
var panel: PanelContainer
var scroll: ScrollContainer
var body: VBoxContainer
var hud: Control
var status: Label
var speed_label: Label
var tool_select: OptionButton
var radius_input: SpinBox
var strength_input: SpinBox
var move_button: Button
var undo_button: Button
var redo_button: Button
var sides: MeshInstance3D
var surface_collision: CollisionShape3D
var platform: Node3D
var tunnel: Node3D
var tunnel_roof: MeshInstance3D
var moving := false
var painting := false
var stroke_changed := false
var stroke_before: Dictionary = {}
var undo_stack: Array[Dictionary] = []
var redo_stack: Array[Dictionary] = []
var hit := Vector3.ZERO
var hit_valid := false
var previous_hit := Vector3.ZERO
var previous_valid := false
var stroke_plane := Plane(Vector3.UP, 0.0)
var tick := 0.0
var tool := 0
var brush_radius := 2.0
var brush_strength := 1.0
var grid_on := true
var pointer_over_ui := false

func _ready() -> void:
	BoardUiStyle.configure()
	add_child(EnvironmentProfile.create())
	camera = FlyCamera.new()
	camera.position = Vector3(40, 27, 45)
	camera.current = true
	camera.near = 0.05
	camera.far = 400
	camera.fov = 55
	add_child(camera)
	camera.look_at(Vector3(16, 0, 16))
	camera.yaw = camera.rotation.y
	camera.pitch = camera.rotation.x
	_build_terrain()
	_build_examples()
	_build_ui()
	_reset_maps()
	_install_overlay()
	get_viewport().size_changed.connect(_fit_ui)
	get_window().focus_exited.connect(_release_interaction)
	_fit_ui.call_deferred()
	_set_status("Terrain3D 1.0.2 · 30×30 格 · 每格 5 英尺")

func _build_terrain() -> void:
	terrain = Terrain3D.new()
	terrain.name = "EditableTerrain3D"
	terrain.region_size = SAMPLES
	terrain.vertex_spacing = SPACING
	terrain.mesh_size = 32
	terrain.mesh_lods = 4
	# Runtime-generated assets have no resource path to reload on tree entry.
	terrain.free_editor_textures = false
	# Godot Physics emits non-finite normal warnings for the addon's NaN holes.
	# This small sandbox uses finite triangles that omit those cells instead.
	terrain.material = Terrain3DMaterial.new()
	terrain.material.world_background = 0
	terrain.material.auto_shader = false
	terrain.material.dual_scaling = false
	terrain.assets = Terrain3DAssets.new()
	for id in range(3):
		var asset := Terrain3DTextureAsset.new()
		asset.name = TOOLS[3 + id]
		var image := Image.create(32, 32, false, Image.FORMAT_RGBA8)
		for y in range(32):
			for x in range(32):
				var shade := 0.97 + 0.03 * sin(float(x * 13 + y * 29 + id * 17))
				var col: Color = GROUND_COLORS[id] * shade
				col.a = 0.5
				image.set_pixel(x, y, col)
		image.generate_mipmaps()
		asset.albedo_texture = ImageTexture.create_from_image(image)
		asset.roughness = 0.4
		asset.uv_scale = 0.5
		asset.detiling_rotation = 0.0
		asset.detiling_shift = 0.0
		terrain.assets.set_texture(id, asset)
	add_child(terrain)
	terrain.collision.mode = 0
	terrain.set_camera(camera)
	terrain.material.set_shader_param("enable_macro_variation", false)
	terrain.material.set_shader_param("flat_terrain_normals", false)
	sides = MeshInstance3D.new()
	sides.name = "SeparateTerrainSides"
	add_child(sides)
	var surface_body := StaticBody3D.new()
	surface_body.name = "FiniteTerrainCollision"
	add_child(surface_body)
	surface_collision = CollisionShape3D.new()
	surface_body.add_child(surface_collision)

func _reset_maps() -> void:
	_finish_stroke()
	height_map = Image.create(SAMPLES, SAMPLES, false, Image.FORMAT_RF)
	control_map = Image.create(SAMPLES, SAMPLES, false, Image.FORMAT_RF)
	color_map = Image.create(SAMPLES, SAMPLES, false, Image.FORMAT_RGBA8)
	color_map.fill(Color(1, 1, 1, 0.5))
	for z in range(SAMPLES):
		for x in range(SAMPLES):
			var point := Vector2(x, z) * SPACING
			var hill := 3.5 * exp(-point.distance_squared_to(Vector2(10, 10)) / 25.0)
			var terrace := 1.5 if point.x > 18 and point.y < 12 else 0.0
			height_map.set_pixel(x, z, Color(hill + terrace, 0, 0))
			var border := x < EDGE_MIN or z < EDGE_MIN or x > EDGE_MAX or z > EDGE_MAX
			var opening := point.x >= 20 and point.x <= 24 and point.y >= 19 and point.y <= 23
			_set_control(x, z, 4 if border or opening else 0)
	var maps: Array[Image] = [height_map, control_map, color_map]
	terrain.data.import_images(maps, Vector3.ZERO)
	_bind_maps()
	undo_stack.clear()
	redo_stack.clear()
	_rebuild_sides()
	_rebuild_collision()
	_sync_history()

func _bind_maps() -> void:
	var region := terrain.data.get_region(Vector2i.ZERO)
	height_map = region.height_map
	control_map = region.control_map
	color_map = region.color_map

func _install_overlay() -> void:
	terrain.material.shader_override_enabled = true
	var shader: Shader = terrain.material.shader_override
	var code := shader.code
	code = code.replace("// Defined Constants", "uniform bool sandbox_grid = true;\nuniform bool sandbox_brush = false;\nuniform vec3 sandbox_brush_position;\nuniform float sandbox_brush_radius = 2.0;\n// Defined Constants")
	code = code.replace("ALBEDO = mat.albedo_height.rgb * color_map.rgb * macrov;", """ALBEDO = mat.albedo_height.rgb * color_map.rgb * macrov;
	if (sandbox_grid) {
		vec2 q = v_vertex.xz - vec2(1.0);
		vec2 d = abs(fract(q + 0.5) - 0.5);
		float aa = max(max(fwidth(q.x), fwidth(q.y)), 0.005);
		float line = 1.0 - smoothstep(0.018, 0.018 + aa, min(d.x, d.y));
		ALBEDO = mix(ALBEDO, vec3(0.13, 0.23, 0.28), line * 0.55);
	}
	if (sandbox_brush) {
		float d = abs(length(v_vertex.xz - sandbox_brush_position.xz) - sandbox_brush_radius);
		float ring = 1.0 - smoothstep(0.04, 0.04 + max(fwidth(d), 0.01), d);
		ALBEDO = mix(ALBEDO, vec3(1.0, 0.66, 0.08), ring);
	}
""")
	shader.code = code

func _build_examples() -> void:
	platform = Node3D.new()
	platform.name = "IndependentPlatform"
	add_child(platform)
	_box(platform, Vector3(12, 4, 16), Vector3(8, 0.4, 4), Color("adbed0"), true)
	for x in [8.5, 15.5]:
		_box(platform, Vector3(x, 1.5, 16), Vector3(0.4, 4.6, 0.4), Color("64788b"))
	tunnel = Node3D.new()
	tunnel.name = "SeparateTunnelMesh"
	add_child(tunnel)
	_box(tunnel, Vector3(22, -3.2, 25), Vector3(5, 0.4, 12), Color("8f9bad"), true)
	_box(tunnel, Vector3(19.5, -1.5, 25), Vector3(0.3, 3, 12), Color("7b889a"))
	_box(tunnel, Vector3(24.5, -1.5, 25), Vector3(0.3, 3, 12), Color("7b889a"))
	tunnel_roof = _box(tunnel, Vector3(22, -0.25, 27.5), Vector3(5, 0.3, 7), Color("7b889a"))
	_box(self, Vector3(16, -4.3, 16), Vector3(30, 0.4, 30), Color("64788b"))

func _box(parent: Node3D, at: Vector3, dimensions: Vector3, color: Color, with_grid := false) -> MeshInstance3D:
	var model := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	model.mesh = mesh
	model.position = at
	if with_grid:
		var shader := Shader.new()
		shader.code = """shader_type spatial;
varying vec3 wp;
varying vec3 wn;
uniform vec4 tint : source_color;
void vertex(){wp=(MODEL_MATRIX*vec4(VERTEX,1.0)).xyz; wn=MODEL_NORMAL_MATRIX*NORMAL;}
void fragment(){
 vec2 q=wp.xz-vec2(1.0);
 vec2 d=abs(fract(q+0.5)-0.5);
 float aa=max(max(fwidth(q.x),fwidth(q.y)),0.005);
 float line=(1.0-smoothstep(0.018,0.018+aa,min(d.x,d.y)))*step(0.9,wn.y);
 ALBEDO=mix(tint.rgb,vec3(0.13,0.23,0.28),line*0.55); ROUGHNESS=0.85;
}"""
		var material := ShaderMaterial.new()
		material.shader = shader
		material.set_shader_parameter("tint", color)
		model.material_override = material
	else:
		var material := StandardMaterial3D.new()
		material.albedo_color = color
		material.roughness = 0.85
		model.material_override = material
	parent.add_child(model)
	return model

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = Control.new()
	canvas.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.theme = GoUi.theme()
	panel = Style.card()
	hud.add_child(panel)
	panel.position = Vector2(20, 20)
	var column := Style.column()
	panel.add_child(column)
	column.add_child(Style.text("地形编辑验证", 24))
	column.add_child(Style.text("Terrain3D · 独立开发沙盒", 14, true))
	scroll = ScrollContainer.new()
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)
	body = Style.column(10)
	scroll.add_child(body)
	move_button = _button(body, "移动模式", _toggle_move)
	move_button.toggle_mode = true
	body.add_child(Style.text("编辑工具"))
	tool_select = OptionButton.new()
	tool_select.custom_minimum_size.y = 40
	for value in TOOLS: tool_select.add_item(value)
	body.add_child(tool_select)
	tool_select.item_selected.connect(func(index: int): _finish_stroke(); tool = index)
	radius_input = _number(body, "笔刷半径 · 格", 0.75, 6.0, 0.25, brush_radius)
	radius_input.value_changed.connect(func(value: float): brush_radius = value)
	strength_input = _number(body, "笔刷强度", 0.1, 4.0, 0.1, brush_strength)
	strength_input.value_changed.connect(func(value: float): brush_strength = value)
	var history := HBoxContainer.new()
	body.add_child(history)
	undo_button = _button(history, "撤销", _undo)
	redo_button = _button(history, "重做", _redo)
	_check(body, "显示五英尺网格", true, func(value: bool): grid_on = value; terrain.material.set_shader_param("sandbox_grid", value))
	_check(body, "显示独立平台", true, func(value: bool): platform.visible = value)
	_check(body, "显示洞道示例", true, func(value: bool): tunnel.visible = value)
	_check(body, "显示洞道屋顶", true, func(value: bool): tunnel_roof.visible = value)
	var files := HBoxContainer.new()
	body.add_child(files)
	_button(files, "保存沙盒", _save)
	_button(files, "读取沙盒", _load_saved)
	_button(body, "恢复初始地形", func(): _reset_maps(); _set_status("已恢复初始地形，撤销记录已清空"))
	speed_label = Style.text("基础速度：8.0 格／秒", 14, true)
	body.add_child(speed_label)
	camera.speed_changed.connect(func(value: float): speed_label.text = "基础速度：%.1f 格／秒" % value)
	body.add_child(Style.text("移动：WASD，Q/E 升降\n按住右键转向，Shift 加速，Ctrl 减速\n移动时滚轮调速度，编辑时滚轮调笔刷", 14, true))
	body.add_child(Style.text("开口仅移除地表。洞道和平台是独立模型，本轮没有体块挖削。", 14, true))
	status = Style.text("", 14, true)
	column.add_child(status)

func _button(parent: Container, title: String, action: Callable) -> Button:
	var button := Button.new()
	button.text = title
	button.focus_mode = Control.FOCUS_NONE
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Style.card_button(button, 40)
	parent.add_child(button)
	button.pressed.connect(action)
	return button

func _number(parent: Container, title: String, minimum: float, maximum: float, step: float, initial: float) -> SpinBox:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Style.text(title, 14)
	label.custom_minimum_size.x = 148
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	var field := SpinBox.new()
	field.min_value = minimum
	field.max_value = maximum
	field.step = step
	field.value = initial
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.custom_minimum_size = Vector2(100, 40)
	row.add_child(field)
	return field

func _check(parent: Container, title: String, initial: bool, action: Callable) -> void:
	var check := CheckButton.new()
	check.text = title
	check.button_pressed = initial
	check.focus_mode = Control.FOCUS_NONE
	check.custom_minimum_size.y = 36
	parent.add_child(check)
	check.toggled.connect(action)

func _fit_ui() -> void:
	if panel == null: return
	var bounds := hud.size
	panel.size.x = minf(360, maxf(280, bounds.x - 40))
	scroll.custom_minimum_size.y = minf(body.get_combined_minimum_size().y, maxf(100, bounds.y - 200))
	panel.reset_size()
	panel.size.x = minf(360, maxf(280, bounds.x - 40))

func _toggle_move() -> void:
	_finish_stroke()
	moving = move_button.button_pressed
	camera.set_enabled(moving)
	var focus := get_viewport().gui_get_focus_owner()
	if moving and focus != null: focus.release_focus()
	move_button.text = "返回地形编辑" if moving else "移动模式"
	tool_select.disabled = moving
	_set_status("移动模式 · 右键转向，WASD 移动" if moving else "编辑模式 · 左键按住涂抹")

func _input(event: InputEvent) -> void:
	# Releases must be observed even if the pointer ended over a UI control.
	if event is InputEventMouseButton and not event.pressed:
		if event.button_index == MOUSE_BUTTON_RIGHT: camera.release_mouse()
		if event.button_index == MOUSE_BUTTON_LEFT: _finish_stroke()
	if event is InputEventMouseMotion and camera.turning:
		camera.turn(event.relative)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.pressed:
		var wheel := 1.0 if event.button_index == MOUSE_BUTTON_WHEEL_UP else -1.0
		if event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			if moving: camera.change_speed(wheel)
			else: radius_input.value = clampf(brush_radius + wheel * 0.25, 0.75, 6.0)
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_RIGHT and moving:
			var focus := get_viewport().gui_get_focus_owner()
			if focus != null: focus.release_focus()
			camera.begin_turn()
			get_viewport().set_input_as_handled()
		elif event.button_index == MOUSE_BUTTON_LEFT and moving:
			var focus := get_viewport().gui_get_focus_owner()
			if focus != null: focus.release_focus()
		elif event.button_index == MOUSE_BUTTON_LEFT and not moving and hit_valid:
			stroke_plane = Plane(Vector3.UP, hit.y)
			stroke_before = _snapshot()
			painting = true
			stroke_changed = false
			previous_valid = false
			tick = 0.05
			var focus := get_viewport().gui_get_focus_owner()
			if focus != null: focus.release_focus()
			get_viewport().set_input_as_handled()

func _process(delta: float) -> void:
	if terrain == null or height_map == null: return
	pointer_over_ui = get_viewport().gui_get_hovered_control() != null
	hit_valid = not moving and not pointer_over_ui and DisplayServer.window_is_focused()
	if hit_valid: hit_valid = _find_edit_point()
	terrain.material.set_shader_param("sandbox_brush", hit_valid)
	if hit_valid:
		terrain.material.set_shader_param("sandbox_brush_position", hit)
		terrain.material.set_shader_param("sandbox_brush_radius", brush_radius)
	if painting and not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT): _finish_stroke()
	if painting and hit_valid:
		tick += delta
		if tick >= 0.05:
			var duration := minf(tick, 0.1)
			tick = 0
			var steps := 1
			if previous_valid: steps = clampi(ceili(previous_hit.distance_to(hit) / maxf(0.25, brush_radius * 0.25)), 1, 32)
			for i in range(steps):
				var point := previous_hit.lerp(hit, float(i + 1) / steps) if previous_valid else hit
				_apply_brush(point, duration / steps)
			previous_hit = hit
			previous_valid = true
			_refresh_maps(0 if tool < 3 else 1)
	elif painting:
		previous_valid = false
		tick = 0

func _find_edit_point() -> bool:
	var mouse := get_viewport().get_mouse_position()
	var origin := camera.project_ray_origin(mouse)
	var direction := camera.project_ray_normal(mouse)
	if painting:
		var projected: Variant = stroke_plane.intersects_ray(origin, direction)
		if projected == null: return false
		var point: Vector3 = projected
		if point.x < 1 or point.z < 1 or point.x >= 31 or point.z >= 31: return false
		hit = Vector3(point.x, _height_at(point.x, point.z), point.z)
		return true
	# Sample the underlying height field so a removed patch can still be restored.
	var previous := origin
	var previous_gap := INF
	for i in range(800):
		var point := origin + direction * (float(i) * 0.25)
		if point.x < 1 or point.z < 1 or point.x >= 31 or point.z >= 31:
			previous_gap = INF
			continue
		var gap := point.y - _height_at(point.x, point.z)
		if gap <= 0 and previous_gap >= 0 and is_finite(previous_gap):
			var fraction := previous_gap / maxf(0.0001, previous_gap - gap)
			hit = previous.lerp(point, fraction)
			return true
		previous_gap = gap
		previous = point
	return false

func _height_at(x: float, z: float) -> float:
	var pixel := Vector2(x, z) / SPACING
	var ix := clampi(floori(pixel.x), 0, SAMPLES - 2)
	var iz := clampi(floori(pixel.y), 0, SAMPLES - 2)
	var a := lerpf(height_map.get_pixel(ix, iz).r, height_map.get_pixel(ix + 1, iz).r, pixel.x - ix)
	var b := lerpf(height_map.get_pixel(ix, iz + 1).r, height_map.get_pixel(ix + 1, iz + 1).r, pixel.x - ix)
	return lerpf(a, b, pixel.y - iz)

func _apply_brush(point: Vector3, duration: float) -> void:
	var center := Vector2(point.x, point.z) / SPACING
	var radius := brush_radius / SPACING
	var source := height_map.duplicate() as Image if tool == 2 else height_map
	var control_bytes := control_map.get_data() if tool >= 3 else PackedByteArray()
	for z in range(maxi(EDGE_MIN, floori(center.y - radius)), mini(EDGE_MAX + 1, ceili(center.y + radius) + 1)):
		for x in range(maxi(EDGE_MIN, floori(center.x - radius)), mini(EDGE_MAX + 1, ceili(center.x + radius) + 1)):
			var distance := Vector2(x, z).distance_to(center) / radius
			if distance >= 1: continue
			# Even radial polynomial: zero slope at both the center and the rim.
			var weight := pow(1.0 - distance * distance, 3.0)
			if tool < 3:
				var old := source.get_pixel(x, z).r
				var value := old
				if tool == 2:
					var average := 0.0
					for dz in range(-1, 2):
						for dx in range(-1, 2): average += source.get_pixel(x + dx, z + dz).r
					value = lerpf(old, average / 9.0, clampf(weight * brush_strength * duration * 8, 0, 1))
				else:
					value = clampf(old + (1 if tool == 0 else -1) * weight * brush_strength * duration, -3.5, 12)
				if not is_equal_approx(value, old):
					height_map.set_pixel(x, z, Color(value, 0, 0))
					stroke_changed = true
			else:
				var offset := (z * SAMPLES + x) * 4
				var bits := control_bytes.decode_u32(offset)
				var changed := bits
				if tool < 6:
					var target := tool - 3
					var base := (bits >> 27) & 31
					var overlay := (bits >> 22) & 31
					var blend := (bits >> 14) & 255
					if base == target:
						blend = maxi(0, blend - maxi(1, roundi(weight * brush_strength * duration * 500)))
					else:
						if overlay != target:
							if blend > 127: base = overlay
							blend = 0
							overlay = target
						blend = mini(255, blend + maxi(1, roundi(weight * brush_strength * duration * 500)))
					changed = (base << 27) | (overlay << 22) | (blend << 14) | (bits & 4)
				elif distance < 0.85:
					changed = bits | 4 if tool == 6 else bits & ~4
				if changed != bits:
					control_bytes.encode_u32(offset, changed)
					stroke_changed = true
	if tool >= 3:
		control_map.set_data(SAMPLES, SAMPLES, false, Image.FORMAT_RF, control_bytes)

func _set_control(x: int, z: int, bits: int) -> void:
	var bytes := PackedByteArray()
	bytes.resize(4)
	bytes.encode_u32(0, bits)
	control_map.set_pixel(x, z, Color(bytes.decode_float(0), 0, 0))

func _refresh_maps(map_type: int = 3) -> void:
	var region := terrain.data.get_region(Vector2i.ZERO)
	region.set_modified(true)
	region.calc_height_range()
	terrain.data.update_maps(map_type)

func _finish_stroke() -> void:
	if not painting: return
	painting = false
	if stroke_changed:
		undo_stack.append(stroke_before)
		if undo_stack.size() > 32: undo_stack.pop_front()
		redo_stack.clear()
		_rebuild_sides()
		_rebuild_collision()
	stroke_before = {}
	previous_valid = false
	_sync_history()

func _snapshot() -> Dictionary:
	return {"version": 2, "height": height_map.get_data(), "control": control_map.get_data(), "color": color_map.get_data()}

func _restore(snapshot: Dictionary) -> void:
	height_map = Image.create_from_data(SAMPLES, SAMPLES, false, Image.FORMAT_RF, snapshot["height"])
	control_map = Image.create_from_data(SAMPLES, SAMPLES, false, Image.FORMAT_RF, snapshot["control"])
	color_map = Image.create_from_data(SAMPLES, SAMPLES, false, Image.FORMAT_RGBA8, snapshot["color"])
	var region := terrain.data.get_region(Vector2i.ZERO)
	var maps: Array[Image] = [height_map, control_map, color_map]
	region.set_maps(maps)
	_refresh_maps()
	_rebuild_sides()
	_rebuild_collision()

func _undo() -> void:
	_finish_stroke()
	if undo_stack.is_empty(): return
	redo_stack.append(_snapshot())
	_restore(undo_stack.pop_back())
	_sync_history()

func _redo() -> void:
	_finish_stroke()
	if redo_stack.is_empty(): return
	undo_stack.append(_snapshot())
	_restore(redo_stack.pop_back())
	_sync_history()

func _sync_history() -> void:
	if undo_button == null: return
	undo_button.disabled = undo_stack.is_empty()
	redo_button.disabled = redo_stack.is_empty()

func _save() -> void:
	_finish_stroke()
	var file := FileAccess.open(SAVE_PATH + ".tmp", FileAccess.WRITE)
	if file == null:
		_set_status("保存失败：无法写入沙盒文件")
		return
	file.store_var(_snapshot(), false)
	file.flush()
	var error := file.get_error()
	file.close()
	if error == OK: error = DirAccess.rename_absolute(ProjectSettings.globalize_path(SAVE_PATH + ".tmp"), ProjectSettings.globalize_path(SAVE_PATH))
	_set_status("已保存独立沙盒，下次可读取" if error == OK else "保存失败，错误码：%d" % error)

func _load_saved() -> void:
	_finish_stroke()
	if not FileAccess.file_exists(SAVE_PATH):
		_set_status("还没有保存过地形沙盒")
		return
	var file := FileAccess.open(SAVE_PATH, FileAccess.READ)
	if file == null:
		_set_status("无法读取沙盒文件")
		return
	if file.get_length() > 250000:
		_set_status("沙盒文件大小异常，未读取")
		return
	var saved: Variant = file.get_var(false)
	file.close()
	if not _valid_snapshot(saved):
		_set_status("沙盒文件内容无效，当前地形已保留")
		return
	undo_stack.append(_snapshot())
	if undo_stack.size() > 32: undo_stack.pop_front()
	redo_stack.clear()
	_restore(_upgrade_snapshot(saved))
	_sync_history()
	_set_status("已读取沙盒，可以撤销此次读取")

func _valid_snapshot(value: Variant) -> bool:
	if not value is Dictionary or value.get("version") not in [1, 2]: return false
	var count := 64 if value["version"] == 1 else SAMPLES
	for key in ["height", "control", "color"]:
		if not value.get(key) is PackedByteArray or value[key].size() != count * count * 4: return false
	var heights: PackedByteArray = value["height"]
	var controls: PackedByteArray = value["control"]
	for i in range(count * count):
		var h := heights.decode_float(i * 4)
		var bits := controls.decode_u32(i * 4)
		if not is_finite(h) or h < -3.5 or h > 12: return false
		if ((bits >> 27) & 31) > 2 or ((bits >> 22) & 31) > 2: return false
		var low := 2 if count == 64 else EDGE_MIN
		var high := 62 if count == 64 else EDGE_MAX
		if i % count < low or i % count > high or i / count < low or i / count >= high + 1:
			if (bits & 4) == 0: return false
	return true

func _upgrade_snapshot(value: Dictionary) -> Dictionary:
	if value["version"] == 2: return value
	var old_height := Image.create_from_data(64, 64, false, Image.FORMAT_RF, value["height"])
	var old_color := Image.create_from_data(64, 64, false, Image.FORMAT_RGBA8, value["color"])
	var old_control: PackedByteArray = value["control"]
	var new_height := Image.create(SAMPLES, SAMPLES, false, Image.FORMAT_RF)
	var new_color := Image.create(SAMPLES, SAMPLES, false, Image.FORMAT_RGBA8)
	var new_control := PackedByteArray()
	new_control.resize(SAMPLES * SAMPLES * 4)
	for z in range(SAMPLES):
		for x in range(SAMPLES):
			var position := Vector2(x, z) * 0.5
			var ix := mini(floori(position.x), 62)
			var iz := mini(floori(position.y), 62)
			var fx := clampf(position.x - ix, 0, 1)
			var fz := clampf(position.y - iz, 0, 1)
			for pair in [[old_height, new_height], [old_color, new_color]]:
				var source: Image = pair[0]
				var target: Image = pair[1]
				var a := source.get_pixel(ix, iz).lerp(source.get_pixel(ix + 1, iz), fx)
				var b := source.get_pixel(ix, iz + 1).lerp(source.get_pixel(ix + 1, iz + 1), fx)
				target.set_pixel(x, z, a.lerp(b, fz))
			var nx := mini(roundi(position.x), 63)
			var nz := mini(roundi(position.y), 63)
			var bits := old_control.decode_u32((nz * 64 + nx) * 4)
			if x < EDGE_MIN or z < EDGE_MIN or x > EDGE_MAX or z > EDGE_MAX: bits |= 4
			new_control.encode_u32((z * SAMPLES + x) * 4, bits)
	return {"version": 2, "height": new_height.get_data(), "control": new_control, "color": new_color.get_data()}

func _rebuild_sides() -> void:
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	for edge in range(4):
		for i in range(EDGE_MAX - EDGE_MIN):
			var a := Vector2(1 + i * SPACING, 1)
			var b := Vector2(1 + (i + 1) * SPACING, 1)
			match edge:
				1: a = Vector2(31, 1 + i * SPACING); b = Vector2(31, 1 + (i + 1) * SPACING)
				2: a = Vector2(31 - i * SPACING, 31); b = Vector2(31 - (i + 1) * SPACING, 31)
				3: a = Vector2(1, 31 - i * SPACING); b = Vector2(1, 31 - (i + 1) * SPACING)
			var top_a := Vector3(a.x, _height_at(a.x, a.y), a.y)
			var top_b := Vector3(b.x, _height_at(b.x, b.y), b.y)
			var low_a := Vector3(a.x, -4.1, a.y)
			var low_b := Vector3(b.x, -4.1, b.y)
			for vertex in [top_a, low_a, top_b, top_b, low_a, low_b]: surface.add_vertex(vertex)
	surface.generate_normals()
	sides.mesh = surface.commit()
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("8e9b92")
	material.roughness = 1.0
	material.cull_mode = BaseMaterial3D.CULL_DISABLED
	sides.material_override = material

func _release_interaction() -> void:
	_finish_stroke()
	camera.release_mouse()

func _rebuild_collision() -> void:
	var faces := PackedVector3Array()
	var controls := control_map.get_data()
	for z in range(EDGE_MIN, EDGE_MAX):
		for x in range(EDGE_MIN, EDGE_MAX):
			var corners := [Vector2i(x, z), Vector2i(x + 1, z), Vector2i(x, z + 1), Vector2i(x + 1, z + 1)]
			var points: Array[Vector3] = []
			var hole := false
			for corner in corners:
				if (controls.decode_u32((corner.y * SAMPLES + corner.x) * 4) & 4) != 0:
					hole = true
					break
				points.append(Vector3(corner.x * SPACING, height_map.get_pixelv(corner).r, corner.y * SPACING))
			if hole: continue
			for index in [0, 2, 1, 1, 2, 3]: faces.append(points[index])
	if faces.is_empty():
		surface_collision.shape = null
	else:
		var shape := ConcavePolygonShape3D.new()
		shape.set_faces(faces)
		surface_collision.set_deferred("shape", shape)

func _set_status(message: String) -> void:
	if status != null: status.text = message
