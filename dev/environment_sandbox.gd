extends Node3D

const Style = preload("res://ui/components/page_style.gd")
const Layout = preload("res://ui/components/editor_layout.gd")
const ColorWell = preload("res://ui/components/color_well.gd")
const Appearance = preload("res://scripts/token_appearance.gd")
const PanelScene = preload("res://ui/components/utility_panel.tscn")
const Controls = preload("res://dev/environment_controls.gd")
const EnvironmentProfile = preload("res://scripts/environment_profile.gd")
const GraphicsPanel = preload("res://ui/components/graphics_settings_panel.gd")
const Modal = preload("res://ui/components/page_modal.gd")
const Acrylic = preload("res://scripts/token_acrylic.gd")
const Components = preload("res://scripts/token_components.gd")
const Contour = preload("res://scripts/token_contour.gd")
const Sticker = preload("res://scripts/token_sticker.gd")

var settings: Dictionary = {}
var inputs: Dictionary = {}
var sliders: Dictionary = {}
var syncing := true
var environment_root: Node3D
var environment: Environment
var sky_material: ShaderMaterial
var main_light: DirectionalLight3D
var matte_materials: Array[StandardMaterial3D] = []
var clear_materials: Array[StandardMaterial3D] = []
var acrylic_materials: Array[ShaderMaterial] = []
var camera: Camera3D
var orbit := Vector2(0.55, 0.65)
var distance := 22.0
var target := Vector3(0, 0.8, 1.5)
var rotating := false
var hud: Control
var panel: PanelContainer
var dream_parameters: Control
var dream_controls_enabled := false

func _ready() -> void:
	BoardUiStyle.configure()
	settings = _defaults()
	_build_environment()
	_build_samples()
	_build_ui()
	_sync_controls()
	_apply()
	Graphics.changed.connect(_apply)
	_update_camera()
	get_viewport().size_changed.connect(_fit_panel)
	_fit_panel.call_deferred()

func _defaults() -> Dictionary:
	var data := EnvironmentProfile.defaults()
	data.merge({"matte_roughness": 0.85, "clear_roughness": 0.25, "clear_alpha": 0.25})
	var acrylic := Acrylic.defaults()
	data.merge({"acrylic_opacity": acrylic["opacity"], "acrylic_roughness": acrylic["roughness"], "acrylic_color": Color(acrylic["color"])})
	return data

func _build_environment() -> void:
	var root := EnvironmentProfile.create()
	environment_root = root
	var world: WorldEnvironment = root.get_node("WorldEnvironment")
	environment = world.environment
	sky_material = environment.sky.sky_material
	main_light = root.get_node("DirectionalLight3D")
	add_child(root)
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 45
	camera.near = 0.05
	camera.far = 200
	add_child(camera)

func _build_ui() -> void:
	var canvas := CanvasLayer.new()
	add_child(canvas)
	hud = Control.new()
	canvas.add_child(hud)
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.theme = GoUi.theme()
	panel = PanelScene.instantiate()
	panel.set_script(Controls)
	hud.add_child(panel)
	panel.panel_closed.connect(_close_colors)
	var body: VBoxContainer = panel.content()
	body.add_child(Style.text("水鸡棋盘光照 · GDQuest 卡通天空", 14, true))
	var sky_body := _section(body, "天空与云", false)
	_color(sky_body, "天空顶部", "g_top")
	_color(sky_body, "地平线", "g_bottom")
	_knob(sky_body, "云量", "g_clouds", 0, 1, 0.05)
	_knob(sky_body, "高层云量", "g_high_clouds", 0, 1, 0.05)
	var light_body := _section(body, "光照", false)
	_color(light_body, "主光颜色", "g_light")
	_knob(light_body, "主光强度", "g_energy", 0, 5, 0.05)
	_knob(light_body, "方位 · °", "g_azimuth", -180, 180, 1)
	_knob(light_body, "高度 · °", "g_altitude", 5, 85, 1)
	_toggle(light_body, "阴影", "g_shadow")
	_knob(light_body, "阴影浓度", "g_shadow_opacity", 0, 1, 0.05)
	_color(light_body, "补光颜色", "g_ambient")
	_knob(light_body, "补光强度", "g_ambient_energy", 0, 2, 0.05)
	_knob(light_body, "天空补光占比", "g_sky_contribution", 0, 1, 0.05)
	var dream_body := _section(body, "梦幻感", true)
	_toggle(dream_body, "启用梦幻柔光", "dream_on")
	dream_parameters = Style.column(12)
	dream_body.add_child(dream_parameters)
	_knob(dream_parameters, "柔光强度", "dream_intensity", 0, 0.8, 0.01)
	_knob(dream_parameters, "光晕扩散范围", "dream_spread", 0, 1, 0.05)
	_knob(dream_parameters, "亮部阈值", "dream_threshold", 0.2, 3, 0.05)
	_knob(dream_parameters, "全画面参与量", "dream_bloom", 0, 0.1, 0.005)
	var image_body := _section(body, "画面色彩", false)
	_knob(image_body, "曝光", "g_exposure", 0.1, 3, 0.05)
	_knob(image_body, "饱和度", "g_saturation", 0.5, 1.5, 0.05)
	var sample_body := _section(body, "观察材质", false)
	_knob(sample_body, "哑光样件粗糙度", "matte_roughness", 0.05, 1, 0.05)
	_knob(sample_body, "透明板粗糙度", "clear_roughness", 0.05, 1, 0.05)
	_knob(sample_body, "透明板不透明度", "clear_alpha", 0.05, 1, 0.05)
	var acrylic_body := _section(body, "亚克力样件", false)
	_knob(acrylic_body, "板体不透明度", "acrylic_opacity", 0, 0.6, 0.01)
	_knob(acrylic_body, "表面粗糙度", "acrylic_roughness", 0.05, 0.8, 0.01)
	_color(acrylic_body, "板体颜色", "acrylic_color")
	var reset := Button.new()
	reset.text = "恢复默认环境"
	Style.card_button(reset)
	panel.editor_footer.add_child(reset)
	reset.pressed.connect(_reset)
	var reopen := Button.new()
	reopen.text = "环境参数"
	Style.card_button(reopen)
	hud.add_child(reopen)
	reopen.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	reopen.offset_left = -152
	reopen.offset_right = -24
	reopen.offset_top = 24
	reopen.offset_bottom = 68
	reopen.pressed.connect(func(): panel.open())
	var graphics_button := Button.new()
	graphics_button.text = "画面设置"
	Style.card_button(graphics_button)
	hud.add_child(graphics_button)
	graphics_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	graphics_button.offset_left = -292
	graphics_button.offset_right = -164
	graphics_button.offset_top = 24
	graphics_button.offset_bottom = 68
	graphics_button.pressed.connect(func():
		var modal := Modal.new()
		hud.add_child(modal)
		modal.configure("画面设置", "与软件设置共用本机配置。")
		modal.content.add_child(GraphicsPanel.new())
		modal.add_action("关闭", modal.dismiss)
	)
	panel.open()
	panel._style_content.call_deferred()

func _reset() -> void:
	_close_colors()
	settings = _defaults()
	_sync_controls()
	_apply()

func _changed(key: String, value: Variant) -> void:
	if syncing: return
	settings[key] = value
	_apply()

func _apply() -> void:
	Graphics.apply_environment(environment)
	EnvironmentProfile.apply(environment_root, settings)
	main_light.shadow_enabled = settings["g_shadow"] and Graphics.values["shadow"] > 0
	environment.glow_enabled = Graphics.values["glow"]
	var dream: bool = settings["dream_on"]
	if dream != dream_controls_enabled:
		Layout.enabled(dream_parameters, dream)
		dream_controls_enabled = dream
	_apply_sample_materials()
	panel.set_editor_status(("梦幻柔光：开启" if dream else "梦幻柔光：关闭 · 光照基线") + " · " + RenderingServer.get_current_rendering_method())


func _material(color: Color, metallic := false) -> StandardMaterial3D:
	var material := StandardMaterial3D.new()
	material.albedo_color = color
	material.roughness = 0.25 if metallic else 0.85
	material.metallic = 1.0 if metallic else 0.0
	if not metallic: matte_materials.append(material)
	return material

func _mesh(mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	add_child(instance)
	return instance

func _box(dimensions: Vector3, at: Vector3, material: Material) -> MeshInstance3D:
	var mesh := BoxMesh.new()
	mesh.size = dimensions
	return _mesh(mesh, at, material)

func _sphere(radius: float, facets := false) -> Mesh:
	var mesh := SphereMesh.new()
	mesh.radius = radius
	mesh.height = radius * 2
	mesh.radial_segments = 10 if facets else 48
	mesh.rings = 5 if facets else 24
	if not facets: return mesh
	var surface := SurfaceTool.new()
	surface.begin(Mesh.PRIMITIVE_TRIANGLES)
	var faces := mesh.get_faces()
	for index in range(0, faces.size(), 3):
		var normal := (faces[index + 2] - faces[index]).cross(faces[index + 1] - faces[index]).normalized()
		surface.set_normal(normal)
		for vertex in range(3): surface.add_vertex(faces[index + vertex])
	return surface.commit()

func _label(title: String, at: Vector3) -> void:
	var text := TextMesh.new()
	text.text = title
	text.font = GoUi.theme().default_font
	text.font_size = 64
	text.pixel_size = 0.006
	text.depth = 0.0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("334155")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var instance := _mesh(text, at, material)
	instance.rotation.x = -PI / 2
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

func _build_samples() -> void:
	_box(Vector3(16, 0.2, 12), Vector3(0, -0.1, 0), _material(Color("a9b1b9")))
	var grid := _material(Color("778491"))
	for x in range(-8, 9): _box(Vector3(0.018, 0.005, 12), Vector3(x, 0.004, 0), grid)
	for z in range(-6, 7): _box(Vector3(16, 0.005, 0.018), Vector3(0, 0.004, z), grid)
	var rock := _mesh(_sphere(1.0, true), Vector3(-5, 0.75, -2), _material(Color("8c8c81")))
	rock.scale = Vector3(1.3, 0.8, 0.85)
	rock.rotation.y = 0.4
	_label("块面岩石", Vector3(-5, 0.015, -0.6))
	var trunk := CylinderMesh.new()
	trunk.top_radius = 0.16
	trunk.bottom_radius = 0.24
	trunk.height = 1.5
	trunk.radial_segments = 6
	_mesh(trunk, Vector3(-2.0, 0.75, -2), _material(Color("765647")))
	for sample in [[Vector3(-2, 2.0, -2), 1.05], [Vector3(-2.6, 1.65, -2.1), 0.65], [Vector3(-1.5, 1.8, -1.9), 0.65]]:
		_mesh(_sphere(sample[1], true), sample[0], _material(Color("40b85a")))
	_label("块面树", Vector3(-2, 0.015, -0.6))
	var wall := _material(Color("c1bba9"))
	for y in range(3):
		for x in range(4): _box(Vector3(0.72, 0.46, 0.38), Vector3(0.5 + x * 0.76, 0.25 + y * 0.5, -2.0), wall)
	_label("墙壁", Vector3(1.65, 0.015, -0.6))
	var tiles := _material(Color("9b9686"))
	for z in range(2):
		for x in range(2): _box(Vector3(0.93, 0.07, 0.93), Vector3(4.5 + x, 0.035, -2.5 + z), tiles)
	_label("地板", Vector3(5, 0.015, -0.6))
	var token := Appearance.build(1, Color("2e7ae0"), "circle")
	token.position = Vector3(-5, 0, 2)
	token.scale = Vector3.ONE * 1.5
	add_child(token)
	_label("基础棋子", Vector3(-5, 0.015, 3.8))
	_mesh(_sphere(0.75), Vector3(-2.2, 0.75, 2), _material(Color("cdcdcd")))
	_label("圆滑哑光", Vector3(-2.2, 0.015, 3.8))
	_mesh(_sphere(0.75, true), Vector3(0.1, 0.75, 2), _material(Color("cdcdcd")))
	_label("块面哑光", Vector3(0.1, 0.015, 3.8))
	_mesh(_sphere(0.75), Vector3(2.3, 0.75, 2), _material(Color("bdb4a0"), true))
	_label("金属", Vector3(2.3, 0.015, 3.8))
	for x in [4.4, 5.0]:
		var clear := StandardMaterial3D.new()
		clear.albedo_color = Color(0.75, 0.9, 1, 0.25)
		clear.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		clear.cull_mode = BaseMaterial3D.CULL_DISABLED
		clear_materials.append(clear)
		var plate := _box(Vector3(1.5, 2.4, 0.12), Vector3(x, 1.2, 2.1 if x == 4.4 else 1.6), clear)
		plate.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	# Opaque color patches behind the transparent samples reveal tint and ordering.
	for index in range(3):
		_box(Vector3(0.4, 0.8, 0.04), Vector3(4.05 + index * 0.42, 1.2, 1.25), _material([Color("cc5353"), Color("578563"), Color("466fb2")][index]))
	_label("透明与重叠", Vector3(4.9, 0.015, 3.8))
	var colors := [Color("e64c4c"), Color("40b85a"), Color("347fe0"), Color("e8c238")]
	for index in range(colors.size()):
		var x := -1.8 + index * 1.2
		_box(Vector3(0.9, 0.3, 0.55), Vector3(x, 0.15, 4.5), _material(colors[index]))
		var reference := StandardMaterial3D.new()
		reference.albedo_color = colors[index]
		reference.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		var block := _box(Vector3(0.9, 0.3, 0.55), Vector3(x, 0.15, 5.3), reference)
		block.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	_label("受光色", Vector3(-4.4, 0.015, 4.5))
	_label("不受光参考", Vector3(-4.4, 0.015, 5.3))
	_build_acrylic_samples()

func _build_acrylic_samples() -> void:
	_box(Vector3(16, 0.2, 4), Vector3(0, -0.1, 8), _material(Color("a9b1b9")))
	var grid := _material(Color("778491"))
	for x in range(-8, 9): _box(Vector3(0.018, 0.005, 4), Vector3(x, 0.004, 8), grid)
	for z in range(6, 11): _box(Vector3(16, 0.005, 0.018), Vector3(0, 0.004, z), grid)
	var texture := _acrylic_sample_texture()
	for index in range(4):
		var raw := Components.defaults()
		raw["base"]["width_ft"] = 8.0
		raw["base"]["length_ft"] = 8.0
		raw["standee"].merge({"presentation": "image", "width_ft": 8.0, "height_ft": 10.0, "thickness_ft": 0.4, "acrylic": Acrylic.defaults(), "contour": _acrylic_sample_contour(index == 2)})
		var checked := Components.validate(raw, Vector2i(3, 3), false)
		if not checked["ok"]:
			push_error(checked["message"])
			continue
		var sample := Components.build(checked)
		acrylic_materials.append(sample.get_node("Standee").material_override)
		sample.position = Vector3(-5.3 + index * 3.5, 0, 7.5)
		add_child(sample)
		if index == 1:
			var standee := sample.get_node("Standee") as MeshInstance3D
			var settings := Sticker.face_defaults()
			Sticker._attach_layer(standee, settings, texture, 1.6, 2.0, 0.08, false, false, false, false)
			Sticker._attach_layer(standee, Sticker.mirror_face(settings), texture, 1.6, 2.0, 0.08, true, true, false, false)
		if index == 3:
			var other := Components.build(checked)
			acrylic_materials.append(other.get_node("Standee").material_override)
			other.position = sample.position + Vector3(0.4, 0, -0.5)
			other.rotation.y = 0.2
			add_child(other)
		_label(["无图亚克力", "合成印刷图案", "孔洞与连接", "亚克力重叠"][index], Vector3(sample.position.x, 0.015, 9.2))

func _acrylic_sample_contour(with_hole: bool) -> Dictionary:
	const COLUMNS := 40
	const ROWS := 50
	var mask := PackedByteArray()
	mask.resize(COLUMNS * ROWS)
	for y in range(1, ROWS - 1):
		for x in range(1, COLUMNS - 1):
			var point := Vector2((x - 19.5) / 18.0, (y - 24.5) / 23.0)
			var inside := point.length_squared() < 1.0
			if with_hole:
				var hole := Vector2((x - 19.5) / 6.0, (y - 15.0) / 6.0).length_squared() < 1.0
				inside = inside and not hole
				# Lower gap retains a narrow bridge through its center.
				if y in [34, 35] and absf(x - 19.5) > 2.0: inside = false
			mask[y * COLUMNS + x] = 1 if inside else 0
	return {"version": 3, "smooth_pct": 40.0, "columns": COLUMNS, "rows": ROWS, "pitch": [0.2, 0.2], "origin": [-4.0, -5.0], "mask": Contour._pack(mask), "signature": "0".repeat(64), "connected": with_hole, "parts": 1}

func _acrylic_sample_texture() -> Texture2D:
	var image := Image.create(160, 200, false, Image.FORMAT_RGBA8)
	image.fill(Color.TRANSPARENT)
	for y in range(200):
		for x in range(160):
			var head := Vector2((x - 80.0) / 25.0, (y - 50.0) / 25.0).length_squared() <= 1.0
			var body := Vector2((x - 80.0) / 38.0, (y - 115.0) / 55.0).length_squared() <= 1.0
			if head or body: image.set_pixel(x, y, Color("e8bd8a") if head else Color("237fb8"))
	image.generate_mipmaps()
	return ImageTexture.create_from_image(image)

func _section(parent: Control, title: String, expanded: bool) -> VBoxContainer:
	var fold := GoStyle.foldable(title, true, null, not expanded)
	Layout.fold(fold)
	parent.add_child(fold)
	var body := Style.column(12)
	fold.add_child(body)
	return body

func _color(parent: Control, title: String, key: String) -> void:
	var input := ColorWell.new()
	input.popup_host = hud
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Layout.field(parent, title).add_child(input)
	Style.card_button(input)
	inputs[key] = input
	input.color_changed.connect(func(value: Color): _changed(key, value))

func _toggle(parent: Control, title: String, key: String) -> void:
	var row := HBoxContainer.new()
	parent.add_child(row)
	var label := Style.text(title)
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(label)
	var input := CheckButton.new()
	row.add_child(input)
	inputs[key] = input
	input.toggled.connect(func(value: bool): _changed(key, value))

func _knob(parent: Control, title: String, key: String, minimum: float, maximum: float, step: float) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	Layout.field(parent, title).add_child(row)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	slider.custom_minimum_size.y = 28
	row.add_child(slider)
	var input := SpinBox.new()
	input.min_value = minimum
	input.max_value = maximum
	input.step = step
	input.custom_minimum_size = Vector2(96, 44)
	row.add_child(input)
	inputs[key] = input
	sliders[key] = slider
	slider.value_changed.connect(func(value: float):
		input.set_value_no_signal(value)
		_changed(key, value)
	)
	input.value_changed.connect(func(value: float):
		slider.set_value_no_signal(value)
		_changed(key, value)
	)

func _apply_sample_materials() -> void:
	for material in matte_materials: material.roughness = settings["matte_roughness"]
	for material in clear_materials:
		material.roughness = settings["clear_roughness"]
		material.albedo_color.a = settings["clear_alpha"]
	for material in acrylic_materials:
		material.set_shader_parameter("opacity", settings["acrylic_opacity"])
		material.set_shader_parameter("surface_roughness", settings["acrylic_roughness"])
		material.set_shader_parameter("plate_color", settings["acrylic_color"])

func _sync_controls() -> void:
	syncing = true
	for key in inputs:
		var input: Control = inputs[key]
		if input is ColorWell: input.color = settings[key]
		elif input is CheckButton: input.set_pressed_no_signal(settings[key])
		elif input is SpinBox: input.set_value_no_signal(float(settings[key]))
		if sliders.has(key): sliders[key].set_value_no_signal(float(settings[key]))
	syncing = false

func _close_colors() -> void:
	rotating = false
	for input in inputs.values():
		if input is ColorWell: input.get_popup().hide()

func _fit_panel() -> void:
	if not panel.user_positioned: panel.position = Vector2(24, 24)
	panel.fit_to_window()

func _update_camera() -> void:
	var direction := Vector3(sin(orbit.x) * cos(orbit.y), sin(orbit.y), cos(orbit.x) * cos(orbit.y))
	camera.position = target + direction * distance
	camera.look_at(target)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		rotating = false
		return
	if is_instance_valid(panel.editor_modal):
		rotating = false
		return
	for input in inputs.values():
		if input is ColorWell and input.get_popup().visible:
			rotating = false
			return
	var hovered := get_viewport().gui_get_hovered_control()
	var on_ui := hovered != null and hovered != hud
	if event is InputEventMouseButton:
		if on_ui: return
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed: rotating = true
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			distance = clampf(distance * (0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.9), 4, 50)
			_update_camera()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and rotating:
		orbit.x -= event.relative.x * 0.006
		orbit.y = clampf(orbit.y + event.relative.y * 0.006, 0.08, 1.45)
		_update_camera()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT: rotating = false
