extends Node3D

const Ground = preload("res://scripts/ground_material.gd")
const Appearance = preload("res://scripts/token_appearance.gd")
const BlendSample = preload("res://dev/ground_blend_sample.gd")
const Grass = preload("res://scripts/grass_patch.gd")
const EnvironmentProfile = preload("res://scripts/environment_profile.gd")
const Style = preload("res://ui/components/page_style.gd")
const Layout = preload("res://ui/components/editor_layout.gd")
const ColorWell = preload("res://ui/components/color_well.gd")
const PanelScene = preload("res://ui/components/utility_panel.tscn")
const Controls = preload("res://dev/ground_controls.gd")
const PAGES := ["grass", "sand", "beach", "water", "blades", "blend"]
const TITLES := ["草地", "沙漠", "沙滩", "水面", "草片与风", "衔接涂绘"]
const Water = preload("res://scripts/water_material.gd")
const PRESETS := {
	"grass": {"明亮草地": Color("40b85a"), "嫩草": Color("8cbd62"), "干草": Color("b8a365"), "深草": Color("348665")},
	"beach": {"米白沙": Color("e4d3af"), "浅沙": Color("dfbe7b"), "灰沙": Color("aaa599")},
	"sand": {"浅沙": Color("dfbe7b"), "米白沙": Color("e4d3af"), "红沙": Color("c6845d"), "灰沙": Color("aaa599")}
}

var blend: Node3D
var blend_body: VBoxContainer
var painting := false
var paint_button: Button
var brush_mode: OptionButton
var undo_button: Button
var redo_button: Button
var brush_settings := {"size_feet": 12.0, "softness": 0.7, "strength": 0.5}
var brush_marker: MeshInstance3D
var water_values: Dictionary = Water.defaults()
var water_body: VBoxContainer
var shore_enabled: CheckButton
var water_wells: Array[ColorWell] = []
var water_sliders: Dictionary = {}
var water_numbers: Dictionary = {}
var sand_body: VBoxContainer
var materials: Dictionary = {}
var values: Dictionary = {}
var kind := "grass"
var syncing := false
var environment_root: Node3D
var camera: Camera3D
var orbit := Vector2(0.0, 0.85)
var distance := 64.0
var rotating := false
var target := Vector3(9,0,0)
var free_mode := false
var free_turning := false
var free_yaw := 0.0
var free_pitch := 0.0
var mouse_origin := Vector2.ZERO
var mode_button: Button
var camera_hint: Label
var hud: Control
var panel: PanelContainer
var color_input: ColorWell
var preset_input: OptionButton
var varied_input: CheckButton
var variant_input: OptionButton
var seed_input: SpinBox
var tabs: Array[Button] = []
var sliders: Dictionary = {}
var numbers: Dictionary = {}
var grass: Node3D
var grass_values: Dictionary = Grass.defaults()
var page := "grass"
var ground_body: VBoxContainer
var grass_body: VBoxContainer
var grass_color: ColorWell
var grass_enabled: CheckButton
var grass_seed: SpinBox
var grass_sliders: Dictionary = {}
var grass_numbers: Dictionary = {}
var reset_button: Button

func _ready() -> void:
	BoardUiStyle.configure()
	DisplayServer.window_set_title("紫水鸡棋盘 · 草地、沙漠、沙滩与水面小样")
	for name in ["grass", "sand", "beach"]: values[name] = Ground.defaults(name)
	environment_root = EnvironmentProfile.create()
	add_child(environment_root)
	Graphics.changed.connect(_apply_environment)
	_apply_environment()
	_build_ground()
	grass = Grass.new()
	grass.name = "GrassSample"
	grass.position.y = 0.002
	grass.area = Rect2(Vector2(-16, 0), Vector2(16, 16))
	grass.exclusion_center = Vector2(-8, 8)
	add_child(grass)
	grass.bind_ground(materials["grass"])
	grass.rebuilt.connect(func(_count: int): _update_status())
	blend = BlendSample.new()
	blend.name = "GroundBlendSample"
	add_child(blend)
	blend.changed.connect(_update_blend_controls)
	var blend_slab := BoxMesh.new()
	blend_slab.size = Vector3(16,0.6,16)
	var slab_color := StandardMaterial3D.new()
	slab_color.albedo_color = Color("8f998e")
	_mesh(blend_slab,Vector3(26,-0.3,0),slab_color)
	var reference := Appearance.build(1,Color("2e7ae0"),"circle")
	reference.position = Vector3(26,0.004,0)
	add_child(reference)
	_label("衔接涂绘 · 80×80 英尺",Vector3(26,0.01,6.6))
	brush_marker = MeshInstance3D.new()
	brush_marker.mesh = TorusMesh.new()
	var marker_color := StandardMaterial3D.new()
	marker_color.albedo_color = Color("e8faff")
	marker_color.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	brush_marker.material_override = marker_color
	brush_marker.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	brush_marker.visible = false
	add_child(brush_marker)
	camera = Camera3D.new()
	camera.current = true
	camera.fov = 45
	camera.near = 0.05
	camera.far = 300
	add_child(camera)
	_update_camera()
	_build_ui()
	_toggle_camera_mode()
	_sync_controls()
	get_viewport().size_changed.connect(_fit_panel)
	_fit_panel.call_deferred()

func _apply_environment() -> void:
	var world: WorldEnvironment = environment_root.get_node("WorldEnvironment")
	EnvironmentProfile.apply(environment_root, EnvironmentProfile.defaults())
	Graphics.apply_environment(world.environment)

func _build_ground() -> void:
	var slab_material := StandardMaterial3D.new()
	slab_material.albedo_color = Color("8f998e")
	slab_material.roughness = 0.95
	var slab := BoxMesh.new()
	slab.size = Vector3(32, 0.6, 32)
	_mesh(slab, Vector3(0, -0.3, 0), slab_material)
	for index in range(4):
		var name: String = PAGES[index]
		var offset := Vector2(-8 if index % 2 == 0 else 8, 8 if index < 2 else -8)
		var top := PlaneMesh.new()
		top.size = Vector2(16, 16)
		var material: ShaderMaterial
		if name == "water":
			material = Water.create()
		else:
			material = Ground.create(name, offset)
			if name != "grass":
				top.subdivide_width = 192
				top.subdivide_depth = 192
		materials[name] = material
		_mesh(top, Vector3(offset.x, 0.002, offset.y), material)
		var token := Appearance.build(1, Color("2e7ae0"), "circle")
		token.name = "%s_scale_reference" % name
		token.position = Vector3(offset.x, 0.004, offset.y)
		add_child(token)
		_label(TITLES[index] + " · 80×80 英尺", Vector3(offset.x, 0.01, offset.y+6.6))
	_apply_water()

func _apply_water() -> void:
	Water.apply(materials["water"], water_values)

func _mesh(mesh: Mesh, at: Vector3, material: Material) -> MeshInstance3D:
	var instance := MeshInstance3D.new()
	instance.mesh = mesh
	instance.position = at
	instance.material_override = material
	add_child(instance)
	return instance

func _label(title: String, at: Vector3) -> void:
	var mesh := TextMesh.new()
	mesh.text = title
	mesh.font = GoUi.theme().default_font
	mesh.font_size = 64
	mesh.pixel_size = 0.007
	mesh.depth = 0
	var material := StandardMaterial3D.new()
	material.albedo_color = Color("263b33")
	material.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	var instance := _mesh(mesh, at, material)
	instance.rotation.x = -PI / 2
	instance.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

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
	panel.panel_closed.connect(_close_color)
	var body: VBoxContainer = panel.content()
	for group in [[0,1,2], [3,4,5]]:
		var tab_row := HBoxContainer.new()
		tab_row.add_theme_constant_override("separation", 0)
		body.add_child(tab_row)
		var group_buttons: Array[Button] = []
		for index: int in group:
			var button := Button.new()
			button.text = TITLES[index]
			button.toggle_mode = true
			button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
			Style.card_button(button)
			tab_row.add_child(button)
			tabs.append(button)
			group_buttons.append(button)
			var chosen: String = PAGES[index]
			button.pressed.connect(func():
				_close_color()
				painting = false
				page = chosen
				if chosen in ["grass", "sand", "beach"]: kind = chosen
				_sync_controls()
			)
		Layout.tabs(group_buttons)
	ground_body = Style.column()
	body.add_child(ground_body)
	body = ground_body
	preset_input = OptionButton.new()
	Layout.field(body, "配色预设").add_child(preset_input)
	preset_input.item_selected.connect(func(index: int):
		var palette: Dictionary = PRESETS[kind]
		_change("color", palette.values()[index])
		_sync_controls()
	)
	color_input = ColorWell.new()
	color_input.popup_host = hud
	Layout.field(body, "主颜色").add_child(color_input)
	Style.card_button(color_input)
	color_input.color_changed.connect(func(color: Color): _change("color", color))
	_knob(body, "色差强度", "contrast", 0, 1, 0.01)
	_knob(body, "纹理尺度 · 英尺", "texture_feet", 2, 30, 0.5)
	var row := HBoxContainer.new()
	var title := Style.text("多变体混合")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(title)
	varied_input = CheckButton.new()
	row.add_child(varied_input)
	body.add_child(row)
	varied_input.toggled.connect(func(active: bool): _change("varied", active))
	variant_input = OptionButton.new()
	for index in range(4): variant_input.add_item("纹理 %d" % (index + 1))
	Layout.field(body, "单纹理对照").add_child(variant_input)
	variant_input.item_selected.connect(func(index: int): _change("variant", index))
	seed_input = SpinBox.new()
	seed_input.min_value = 0
	seed_input.max_value = 1000000
	seed_input.step = 1
	Layout.field(body, "分布种子").add_child(seed_input)
	seed_input.value_changed.connect(func(seed_value: float): _change("seed", int(seed_value)))
	var next_pattern := Button.new()
	next_pattern.text = "换一种分布"
	Style.card_button(next_pattern)
	body.add_child(next_pattern)
	next_pattern.pressed.connect(func():
		_change("seed", (int(values[kind]["seed"]) + 1) % 1000001)
		_sync_controls()
	)
	sand_body = Style.column()
	ground_body.add_child(sand_body)
	_knob(sand_body, "起伏高度 · 英尺", "relief_feet", 0, 0.4, 0.005)
	_knob(sand_body, "风纹强度", "ripple_strength", 0, 0.4, 0.005)
	_knob(sand_body,"固定色斑强度","patch_strength",0,0.8,0.01)
	_knob(sand_body,"砂粒颜色强度","grain_color",0,1,0.01)
	_knob(sand_body,"颗粒纹理范围 · 英尺","grain_feet",0.5,10,0.1)
	_knob(sand_body,"颗粒受光强度","grain_normal",0,0.4,0.01)
	_knob(sand_body,"砂粒反光强度","glint_strength",0,1,0.01)
	_knob(sand_body,"反光颗粒密度","glint_density",0,0.5,0.01)
	water_body = Style.column()
	panel.content().add_child(water_body)
	for index in range(2):
		var key: String = ["edge_color", "center_color"][index]
		var well := ColorWell.new()
		well.popup_host = hud
		Style.card_button(well)
		Layout.field(water_body, ["边缘浅水颜色", "中央深水颜色"][index]).add_child(well)
		water_wells.append(well)
		well.color_changed.connect(func(value: Color):
			if syncing: return
			water_values[key] = value
			_apply_water()
		)
	_water_knob("深浅过渡范围", "gradient_range", 0.1, 1.0, 0.05)
	water_body.add_child(Style.text("水面细节", 18))
	_water_knob("波纹强度", "wave_strength", 0.0, 0.3, 0.005)
	_water_knob("波纹尺度 · 英尺", "wave_feet", 2.0, 20.0, 0.5)
	_water_knob("流动速度", "flow_speed", 0.0, 2.0, 0.05)
	_water_knob("柔和亮纹强度", "highlight_strength", 0.0, 0.4, 0.01)
	_water_knob("表面光泽", "gloss", 0.0, 1.0, 0.05)
	water_body.add_child(Style.text("水岸浪",18))
	shore_enabled = CheckButton.new()
	shore_enabled.text = "显示水岸浪"
	water_body.add_child(shore_enabled)
	shore_enabled.toggled.connect(func(active: bool):
		if syncing: return
		water_values["shore_enabled"] = active
		_apply_water()
	)
	_water_knob("岸浪强度", "shore_strength", 0.0, 1.0, 0.05)
	_water_knob("岸浪覆盖宽度 · 英尺", "shore_width_feet", 1.0, 15.0, 0.5)
	_water_knob("岸浪平均间隔 · 秒", "shore_period", 1.0, 10.0, 0.1)
	grass_body = Style.column()
	panel.content().add_child(grass_body)
	_build_grass_controls()
	_build_blend_controls()
	var reset := Button.new()
	reset_button = reset
	reset.text = "恢复当前地面默认值"
	Style.card_button(reset)
	panel.editor_footer.add_child(reset)
	reset.pressed.connect(func():
		_close_color()
		if page == "blades":
			grass_values = Grass.defaults()
			grass.apply(grass_values)
			blend.apply_grass(grass_values)
		elif page == "blend":
			painting = false
			blend.reset_example()
		elif page == "water":
			water_values = Water.defaults()
			_apply_water()
		else:
			values[kind] = Ground.defaults(kind)
			Ground.apply(materials[kind], values[kind])
			blend.apply_sand_settings(values["sand"])
			blend.set_colors(values["grass"]["color"],values["sand"]["color"])
		_sync_controls()
	)
	var reopen := Button.new()
	reopen.text = "材质参数"
	Style.card_button(reopen)
	hud.add_child(reopen)
	reopen.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	reopen.offset_left = -164
	reopen.offset_right = -24
	reopen.offset_top = 24
	reopen.offset_bottom = 68
	reopen.pressed.connect(func(): panel.open())
	mode_button = Button.new()
	mode_button.text = "自由相机"
	Style.card_button(mode_button)
	hud.add_child(mode_button)
	mode_button.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	mode_button.offset_left = -316
	mode_button.offset_right = -176
	mode_button.offset_top = 24
	mode_button.offset_bottom = 68
	mode_button.pressed.connect(_toggle_camera_mode)
	camera_hint = Style.text("", 14)
	hud.add_child(camera_hint)
	camera_hint.set_anchors_and_offsets_preset(Control.PRESET_BOTTOM_WIDE)
	camera_hint.offset_left = 24
	camera_hint.offset_right = -24
	camera_hint.offset_top = -44
	camera_hint.offset_bottom = -16
	camera_hint.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	camera_hint.add_theme_color_override("font_color", Color.WHITE)
	camera_hint.add_theme_color_override("font_shadow_color", Color("334155"))
	camera_hint.add_theme_constant_override("shadow_offset_x", 1)
	camera_hint.add_theme_constant_override("shadow_offset_y", 1)
	panel.open()
	panel._style_content.call_deferred()

func _knob(parent: Control, title: String, key: String, minimum: float, maximum: float, step: float, for_grass := false) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	Layout.field(parent, title).add_child(row)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var number := SpinBox.new()
	number.min_value = minimum
	number.max_value = maximum
	number.step = step
	number.custom_minimum_size = Vector2(96, 44)
	row.add_child(number)
	if for_grass:
		grass_sliders[key] = slider
		grass_numbers[key] = number
	else:
		sliders[key] = slider
		numbers[key] = number
	slider.value_changed.connect(func(value: float):
		number.set_value_no_signal(value)
		if for_grass: _grass_change(key, value)
		else: _change(key, value)
	)
	number.value_changed.connect(func(value: float):
		slider.set_value_no_signal(value)
		if for_grass: _grass_change(key, value)
		else: _change(key, value)
	)

func _build_blend_controls() -> void:
	blend_body = Style.column()
	panel.content().add_child(blend_body)
	brush_mode = OptionButton.new()
	for title in ["沙漠", "草地", "沙滩", "水域", "恢复底色（草地）"]: brush_mode.add_item(title)
	Layout.field(blend_body,"涂绘材质").add_child(brush_mode)
	for key in brush_settings:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation",8)
		var titles := {"size_feet":"画笔直径 · 英尺", "softness":"边缘柔软度", "strength":"涂绘强度"}
		Layout.field(blend_body,titles[key]).add_child(row)
		var slider := HSlider.new()
		slider.min_value = 1.0 if key == "size_feet" else 0.0
		slider.max_value = 30.0 if key == "size_feet" else 1.0
		slider.step = 0.5 if key == "size_feet" else 0.05
		slider.value = brush_settings[key]
		slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		row.add_child(slider)
		var number := SpinBox.new()
		number.min_value = slider.min_value
		number.max_value = slider.max_value
		number.step = slider.step
		number.value = slider.value
		number.custom_minimum_size = Vector2(96,44)
		row.add_child(number)
		slider.value_changed.connect(func(value: float):
			number.set_value_no_signal(value)
			brush_settings[key] = value
		)
		number.value_changed.connect(func(value: float):
			slider.set_value_no_signal(value)
			brush_settings[key] = value
		)
	paint_button = Button.new()
	Style.card_button(paint_button)
	blend_body.add_child(paint_button)
	paint_button.pressed.connect(func():
		_close_color()
		painting = not painting
		_update_blend_controls()
		_update_status()
	)
	var row := HBoxContainer.new()
	blend_body.add_child(row)
	undo_button = Button.new()
	redo_button = Button.new()
	undo_button.text = "撤销"
	redo_button.text = "重做"
	for button in [undo_button,redo_button]:
		Style.card_button(button)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(button)
	undo_button.pressed.connect(func(): blend.undo())
	redo_button.pressed.connect(func(): blend.redo())

func _update_blend_controls() -> void:
	if not is_instance_valid(paint_button): return
	paint_button.text = "结束涂绘" if painting else "开始涂绘"
	undo_button.disabled = blend.undo_stack.is_empty()
	redo_button.disabled = blend.redo_stack.is_empty()

func _paint_at(point: Vector2) -> void:
	var target_value: int = [1,0,2,3,0][brush_mode.selected]
	blend.paint(point,target_value,brush_settings["size_feet"],brush_settings["softness"],brush_settings["strength"])

func _update_brush_marker() -> void:
	if not is_instance_valid(brush_marker): return
	brush_marker.visible = false
	if not painting or page != "blend" or free_turning: return
	if _color_popup_visible() or is_instance_valid(panel.editor_modal): return
	var hovered := get_viewport().gui_get_hovered_control()
	if hovered != null and hovered != hud: return
	var point: Variant = blend.hit(camera,get_viewport().get_mouse_position())
	if point == null: return
	var radius := float(brush_settings["size_feet"])/10.0
	var ring: TorusMesh = brush_marker.mesh
	ring.inner_radius = maxf(radius-0.012,0.01)
	ring.outer_radius = radius+0.012
	brush_marker.position = Vector3(point.x,0.025,point.y)
	brush_marker.visible = true

func _water_knob(title: String, key: String, minimum: float, maximum: float, step: float) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	Layout.field(water_body, title).add_child(row)
	var slider := HSlider.new()
	slider.min_value = minimum
	slider.max_value = maximum
	slider.step = step
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var number := SpinBox.new()
	number.min_value = minimum
	number.max_value = maximum
	number.step = step
	number.custom_minimum_size = Vector2(96, 44)
	row.add_child(number)
	water_sliders[key] = slider
	water_numbers[key] = number
	slider.value_changed.connect(func(value: float):
		number.set_value_no_signal(value)
		if syncing: return
		water_values[key] = value
		_apply_water()
	)
	number.value_changed.connect(func(value: float):
		slider.set_value_no_signal(value)
		if syncing: return
		water_values[key] = value
		_apply_water()
	)

func _build_grass_controls() -> void:
	var row := HBoxContainer.new()
	grass_body.add_child(row)
	var title := Style.text("显示草片")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(title)
	grass_enabled = CheckButton.new()
	row.add_child(grass_enabled)
	grass_enabled.toggled.connect(func(active: bool): _grass_change("enabled", active))
	grass_color = ColorWell.new()
	grass_color.popup_host = hud
	Layout.field(grass_body, "草片颜色").add_child(grass_color)
	Style.card_button(grass_color)
	grass_color.color_changed.connect(func(value: Color): _grass_change("color", value))
	var appearance := _grass_section("长短与分布", false)
	_knob(appearance, "最低高度 · 英尺", "min_height", 0.1, 3.0, 0.05, true)
	_knob(appearance, "最高高度 · 英尺", "max_height", 0.1, 3.0, 0.05, true)
	_knob(appearance, "宽度 · 英尺", "width", 0.04, 0.4, 0.01, true)
	_knob(appearance, "密度 · 每平方英尺上限", "density", 0.0, 4.0, 0.1, true)
	grass_seed = SpinBox.new()
	grass_seed.min_value = 0
	grass_seed.max_value = 1000000
	grass_seed.step = 1
	Layout.field(appearance, "草片分布种子").add_child(grass_seed)
	grass_seed.value_changed.connect(func(value: float): _grass_change("seed", int(value)))
	var wind := _grass_section("临时风参数", false)
	_knob(wind, "柔软程度", "softness", 0.0, 2.0, 0.05, true)
	_knob(wind, "日常摆动周期 · 秒", "sway_period", 1.0, 5.0, 0.1, true)
	_knob(wind, "日常摆动幅度", "sway_amplitude", 0.0, 0.7, 0.01, true)
	_knob(wind, "风向 · °", "wind_direction", 0, 360, 1, true)
	_knob(wind, "基础风强", "wind_strength", 0, 1.5, 0.05, true)
	_knob(wind, "阵风强度", "gust_strength", 0, 2, 0.05, true)
	_knob(wind, "阵风频率 · 次/秒", "gust_frequency", 0.03, 0.6, 0.01, true)
	_knob(wind, "风波宽度 · 英尺", "wave_width_feet", 2, 60, 1, true)
	_knob(wind, "传播速度 · 英尺/秒", "wave_speed_feet", 1, 40, 1, true)
	var visibility_body := _grass_section("高处显示", false)
	_knob(visibility_body, "远距宽度倍率", "distant_width", 1.0, 1.5, 0.05, true)
	_knob(visibility_body, "地面风波强度", "ground_wave_strength", 0.0, 0.12, 0.005, true)

func _grass_section(title: String, folded: bool) -> VBoxContainer:
	var section := FoldableContainer.new()
	section.title = title
	section.folded = folded
	grass_body.add_child(section)
	Layout.fold(section)
	var body := Style.column()
	section.add_child(body)
	return body

func _grass_change(key: String, value: Variant) -> void:
	if syncing: return
	grass_values[key] = value
	if key == "min_height" and float(value) > float(grass_values["max_height"]): grass_values["max_height"] = value
	if key == "max_height" and float(value) < float(grass_values["min_height"]): grass_values["min_height"] = value
	grass.apply(grass_values)
	blend.apply_grass(grass_values)
	_sync_grass_controls()
	_update_status()

func _sync_grass_controls() -> void:
	var was_syncing := syncing
	syncing = true
	grass_enabled.set_pressed_no_signal(grass_values["enabled"])
	grass_color.color = grass_values["color"]
	grass_seed.set_value_no_signal(int(grass_values["seed"]))
	for key in grass_sliders:
		grass_sliders[key].set_value_no_signal(float(grass_values[key]))
		grass_numbers[key].set_value_no_signal(float(grass_values[key]))
	syncing = was_syncing

func _change(key: String, value: Variant) -> void:
	if syncing: return
	values[kind][key] = value
	Ground.apply(materials[kind], values[kind])
	blend.apply_sand_settings(values["sand"])
	variant_input.disabled = bool(values[kind]["varied"])
	if key == "color":
		_sync_palette()
		blend.set_colors(values["grass"]["color"],values["sand"]["color"])
	_update_status()

func _sync_palette() -> void:
	preset_input.select(-1)
	var palette: Dictionary = PRESETS[kind]
	for index in range(palette.size()):
		if values[kind]["color"].is_equal_approx(palette.values()[index]): preset_input.select(index)

func _sync_controls() -> void:
	syncing = true
	for index in range(6): tabs[index].set_pressed_no_signal(page == PAGES[index])
	ground_body.visible = page in ["grass", "sand", "beach"]
	sand_body.visible = page in ["sand", "beach"]
	water_body.visible = page == "water"
	shore_enabled.set_pressed_no_signal(water_values["shore_enabled"])
	water_wells[0].color = water_values["edge_color"]
	water_wells[1].color = water_values["center_color"]
	for key in water_numbers:
		water_numbers[key].set_value_no_signal(water_values[key])
		water_sliders[key].set_value_no_signal(water_values[key])
	blend_body.visible = page == "blend"
	_update_blend_controls()
	grass_body.visible = page == "blades"
	reset_button.text = "恢复草片与风默认值" if page == "blades" else ("恢复水面默认值" if page == "water" else ("恢复衔接示例" if page == "blend" else "恢复当前地面默认值"))
	_sync_grass_controls()
	var data: Dictionary = values[kind]
	color_input.color = data["color"]
	preset_input.clear()
	for title in PRESETS[kind]: preset_input.add_item(title)
	_sync_palette()
	for key in sliders:
		sliders[key].set_value_no_signal(float(data[key]))
		numbers[key].set_value_no_signal(float(data[key]))
	varied_input.set_pressed_no_signal(data["varied"])
	variant_input.select(int(data["variant"]))
	variant_input.disabled = bool(data["varied"])
	seed_input.set_value_no_signal(int(data["seed"]))
	syncing = false
	_update_status()

func _update_status() -> void:
	if not is_instance_valid(panel): return
	if page == "blades":
		panel.set_editor_status("草片 %d 片 · 临时风 · 本次运行有效" % grass.blade_count)
	elif page == "blend":
		panel.set_editor_status("草地底色 · 左键涂绘" if painting else "衔接样地 · 本次运行有效")
	elif page == "water":
		panel.set_editor_status("不透明水面 · 圆润深浅过渡与细波 · 本次运行有效")
	else:
		panel.set_editor_status(TITLES[PAGES.find(kind)] + " · " + ("四种纹理混合" if values[kind]["varied"] else "单纹理对照") + " · 本次运行有效")
	if is_instance_valid(camera_hint):
		camera_hint.text = ("左键涂绘衔接样地 · " if painting else "") + ("WASD 移动 · Q/E 升降 · 右键转向 · Shift 加速 · Ctrl 减速" if free_mode else "空白处按住左键旋转 · 滚轮缩放")

func _fit_panel() -> void:
	if not panel.user_positioned: panel.position = Vector2(24, 24)
	panel.fit_to_window()

func _close_color() -> void:
	if is_instance_valid(blend): blend.finish_stroke()
	rotating = false
	_release_free_mouse()
	if is_instance_valid(color_input): color_input.get_popup().close()
	if is_instance_valid(grass_color): grass_color.get_popup().close()
	for well in water_wells: well.get_popup().close()

func _color_popup_visible() -> bool:
	for well in water_wells:
		if well.get_popup().visible: return true
	return color_input.get_popup().visible or grass_color.get_popup().visible

func _update_camera() -> void:
	var direction := Vector3(sin(orbit.x) * cos(orbit.y), sin(orbit.y), cos(orbit.x) * cos(orbit.y))
	camera.position = target + direction * distance
	camera.look_at(target)

func _toggle_camera_mode() -> void:
	rotating = false
	_release_free_mouse()
	free_mode = not free_mode
	if free_mode:
		free_yaw = camera.rotation.y
		free_pitch = camera.rotation.x
	else:
		# Reconstruct an orbit in front of the current view without jumping position.
		target = camera.position - camera.basis.z * distance
		var direction := camera.basis.z.normalized()
		orbit = Vector2(atan2(direction.x, direction.z), asin(clampf(direction.y, -1, 1)))
	mode_button.text = "环绕相机" if free_mode else "自由相机"
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null: focused.release_focus()
	_update_status()

func _release_free_mouse() -> void:
	if not free_turning: return
	free_turning = false
	Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
	if DisplayServer.window_is_focused(): get_viewport().warp_mouse(mouse_origin)

func _process(delta: float) -> void:
	_update_brush_marker()
	if is_instance_valid(grass):
		materials["water"].set_shader_parameter("water_time", grass.wind_elapsed)
		blend.apply_water(water_values,grass.wind_elapsed)
		blend.set_beach_color(values["beach"]["color"])
	if not free_mode or not DisplayServer.window_is_focused(): return
	if blend.stroke_before != null: return
	if _color_popup_visible() or is_instance_valid(panel.editor_modal):
		_release_free_mouse()
		return
	var focused := get_viewport().gui_get_focus_owner()
	if focused is LineEdit or focused is TextEdit or focused is SpinBox: return
	var hovered := get_viewport().gui_get_hovered_control()
	if not free_turning and hovered != null and hovered != hud: return
	var direction := Vector3.ZERO
	if Input.is_physical_key_pressed(KEY_W): direction -= camera.basis.z
	if Input.is_physical_key_pressed(KEY_S): direction += camera.basis.z
	if Input.is_physical_key_pressed(KEY_A): direction -= camera.basis.x
	if Input.is_physical_key_pressed(KEY_D): direction += camera.basis.x
	if Input.is_physical_key_pressed(KEY_E): direction += Vector3.UP
	if Input.is_physical_key_pressed(KEY_Q): direction -= Vector3.UP
	var speed := 4.0
	if Input.is_physical_key_pressed(KEY_SHIFT): speed *= 4.0
	if Input.is_physical_key_pressed(KEY_CTRL): speed *= 0.25
	camera.position += direction.normalized() * speed * minf(delta, 0.1)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		_release_free_mouse()
		return
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and not event.pressed:
		rotating = false
		if is_instance_valid(blend): blend.finish_stroke()
		return
	if not is_instance_valid(color_input): return
	if _color_popup_visible() or is_instance_valid(panel.editor_modal):
		blend.finish_stroke()
		rotating = false
		_release_free_mouse()
		return
	var hovered := get_viewport().gui_get_hovered_control()
	var on_ui := hovered != null and hovered != hud
	if painting and page == "blend" and not free_turning:
		if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT and event.pressed and not on_ui:
			var point: Variant = blend.hit(camera,event.position)
			if point != null:
				var focused := get_viewport().gui_get_focus_owner()
				if focused != null: focused.release_focus()
				blend.begin_stroke()
				_paint_at(point)
			get_viewport().set_input_as_handled()
			return
		if event is InputEventMouseMotion and blend.stroke_before != null:
			var point: Variant = null if on_ui else blend.hit(camera,event.position)
			if point == null: blend.break_segment()
			else: _paint_at(point)
			get_viewport().set_input_as_handled()
			return
	if free_mode:
		if event is InputEventMouseButton:
			if on_ui: return
			if event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
				blend.finish_stroke()
				var focused := get_viewport().gui_get_focus_owner()
				if focused != null: focused.release_focus()
				mouse_origin = get_viewport().get_mouse_position()
				free_turning = true
				Input.mouse_mode = Input.MOUSE_MODE_CAPTURED
				get_viewport().set_input_as_handled()
		elif event is InputEventMouseMotion and free_turning:
			free_yaw -= event.relative.x * 0.003
			free_pitch = clampf(free_pitch - event.relative.y * 0.003, -1.5, 1.5)
			camera.rotation = Vector3(free_pitch, free_yaw, 0)
			get_viewport().set_input_as_handled()
		return
	if event is InputEventMouseButton:
		if on_ui: return
		if event.button_index == MOUSE_BUTTON_LEFT and event.pressed:
			rotating = true
			var focused := get_viewport().gui_get_focus_owner()
			if focused != null: focused.release_focus()
		elif event.pressed and event.button_index in [MOUSE_BUTTON_WHEEL_UP, MOUSE_BUTTON_WHEEL_DOWN]:
			distance = clampf(distance * (0.9 if event.button_index == MOUSE_BUTTON_WHEEL_UP else 1.0 / 0.9), 3, 110)
			_update_camera()
			get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and rotating:
		if on_ui:
			rotating = false
			return
		orbit.x -= event.relative.x * 0.006
		orbit.y = clampf(orbit.y + event.relative.y * 0.006, -1.45, 1.45)
		_update_camera()
		get_viewport().set_input_as_handled()

func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if is_instance_valid(blend): blend.finish_stroke()
		rotating = false
		_release_free_mouse()

func _exit_tree() -> void:
	if free_turning: Input.mouse_mode = Input.MOUSE_MODE_VISIBLE
