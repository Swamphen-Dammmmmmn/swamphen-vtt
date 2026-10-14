extends Node3D

const Generator = preload("res://dev/rock_generator.gd")
const RockShader = preload("res://assets/scenery/rocks/rock_surface.gdshader")
const EnvironmentProfile = preload("res://scripts/environment_profile.gd")
const Appearance = preload("res://scripts/token_appearance.gd")
const FlyCamera = preload("res://dev/terrain_fly_camera.gd")
const UtilityPopup = preload("res://ui/components/designer_utility_popup.gd")
const Style = preload("res://ui/components/page_style.gd")
const ColorWell = preload("res://ui/components/color_well.gd")
const Catalog = preload("res://dev/rock_catalog.gd")
const Thumbnail = preload("res://dev/rock_thumbnail.gd")
const PAGE_SIZE := 6
const PRESETS := [
	{"title": "风化巨石", "width": 12.0, "depth": 9.0, "height": 7.0, "rounding": 0.85},
	{"title": "棱角岩块", "width": 10.0, "depth": 8.0, "height": 8.0, "rounding": 0.15},
	{"title": "扁平卧石", "width": 14.0, "depth": 10.0, "height": 4.0, "rounding": 0.55}
]

var values := {"shape": 0, "seed": 1, "width": 12.0, "depth": 9.0, "height": 7.0,
	"variation": 0.55, "rounding": 0.85, "burial": 0.10,
	"color": Color("858a86"), "color_variation": 0.12, "roughness": 0.88,
	"profile": 0}
var inputs: Dictionary = {}
var camera: Camera3D
var hud: Control
var panel: PanelContainer
var rock: MeshInstance3D
var stone_material: ShaderMaterial
var ground_material: ShaderMaterial
var stage_base: MeshInstance3D
var stage_surface: MeshInstance3D
var reference: Node3D
var reference_caption: Label3D
var status: Label
var shape_input: OptionButton
var color_input: ColorWell
var syncing := false
var rebuild_timer: Timer
var environment_root: Node3D
var assets: Array[Dictionary] = Catalog.entries()
var mesh_cache: Dictionary = {}
var generator_body: VBoxContainer
var assets_body: VBoxContainer
var asset_grid: GridContainer
var asset_info: Label
var asset_cards: Dictionary = {}
var page_buttons: Dictionary = {}
var selected_asset := 0
var asset_category := 0
var page := "assets"
var generator_draft: Dictionary = {}
var profile_input: OptionButton
var asset_page := 0
var page_label: Label
var previous_page: Button
var next_page: Button
var gallery_revision := 0

func _ready() -> void:
	BoardUiStyle.configure()
	DisplayServer.window_set_title("紫水鸡棋盘 · 石头生成测试")
	environment_root = EnvironmentProfile.create()
	add_child(environment_root)
	Graphics.changed.connect(_apply_environment)
	_apply_environment()
	_build_stage()
	stone_material = ShaderMaterial.new()
	stone_material.shader = RockShader
	rock = MeshInstance3D.new()
	rock.material_override = stone_material
	add_child(rock)
	camera = FlyCamera.new()
	camera.current = true
	camera.near = 0.015
	camera.far = 250.0
	camera.fov = 50.0
	camera.base_speed = 4.0
	add_child(camera)
	camera.set_enabled(true)
	rebuild_timer = Timer.new()
	rebuild_timer.one_shot = true
	rebuild_timer.wait_time = 0.18
	rebuild_timer.timeout.connect(_generate)
	add_child(rebuild_timer)
	generator_draft = values.duplicate(true)
	for argument in OS.get_cmdline_user_args():
		if argument.begins_with("--rock-category="):
			asset_category = clampi(argument.trim_prefix("--rock-category=").to_int(), 0, 2)
	selected_asset = asset_category * 25
	values = assets[selected_asset].parameters.duplicate(true)
	_build_ui()
	_generate()
	_reset_camera()
	get_viewport().size_changed.connect(_fit_panel)
	get_window().focus_exited.connect(camera.release_mouse)
	_open_panel.call_deferred()

func _apply_environment() -> void:
	EnvironmentProfile.apply(environment_root, EnvironmentProfile.defaults())
	var world: WorldEnvironment = environment_root.get_node("WorldEnvironment")
	Graphics.apply_environment(world.environment)

func _build_stage() -> void:
	var shader := Shader.new()
	shader.code = """shader_type spatial;
uniform vec4 ground_color : source_color = vec4(0.57, 0.65, 0.49, 1.0);
uniform bool show_grid = true;
varying vec2 ground_position;
void vertex() { ground_position = VERTEX.xz; }
void fragment() {
	vec2 cell = abs(fract(ground_position - 0.5) - 0.5);
	vec2 width = max(fwidth(ground_position), vec2(0.0001));
	float line = 1.0 - clamp(min(cell.x / width.x, cell.y / width.y), 0.0, 1.0);
	ALBEDO = mix(ground_color.rgb, ground_color.rgb * 0.8, show_grid ? line * 0.65 : 0.0);
	ROUGHNESS = 0.95;
}"""
	ground_material = ShaderMaterial.new()
	ground_material.shader = shader
	var slab := BoxMesh.new()
	slab.size = Vector3(12, 0.3, 12)
	var slab_material := StandardMaterial3D.new()
	slab_material.albedo_color = Color("91958a")
	slab_material.roughness = 0.95
	stage_base = MeshInstance3D.new()
	stage_base.mesh = slab
	stage_base.material_override = slab_material
	stage_base.position.y = -0.16
	add_child(stage_base)
	stage_surface = MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2(12, 12)
	stage_surface.mesh = plane
	stage_surface.material_override = ground_material
	add_child(stage_surface)
	reference = Appearance.build(1, Color("2e7ae0"), "circle")
	reference.position = Vector3(-3.0, 0.004, 0.0)
	add_child(reference)
	reference_caption = Label3D.new()
	reference_caption.text = "1×1 棋子 · 5 英尺"
	reference_caption.position = Vector3(-3, 0.015, 1.15)
	reference_caption.rotation_degrees.x = -90
	reference_caption.font_size = 48
	reference_caption.pixel_size = 0.002
	reference_caption.modulate = Color("334155")
	reference_caption.outline_size = 0
	reference_caption.no_depth_test = false
	add_child(reference_caption)

func _build_ui() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	hud = Control.new()
	hud.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	hud.mouse_filter = Control.MOUSE_FILTER_IGNORE
	hud.theme = GoUi.config.theme
	layer.add_child(hud)
	panel = UtilityPopup.new()
	panel.title = "石头测试"
	hud.add_child(panel)
	var tabs := HBoxContainer.new()
	tabs.add_theme_constant_override("separation", 8)
	panel.body.add_child(tabs)
	page_buttons.assets = _button(tabs, "资产预览", func(): _set_page("assets"), true)
	page_buttons.generator = _button(tabs, "生成器", func(): _set_page("generator"))
	for button: Button in page_buttons.values(): button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	assets_body = Style.column(12)
	panel.body.add_child(assets_body)
	_build_assets()
	generator_body = Style.column(12)
	panel.body.add_child(generator_body)
	generator_body.hide()
	var body := generator_body
	shape_input = OptionButton.new()
	for preset in PRESETS: shape_input.add_item(preset.title)
	BoardUiStyle.style_controls(shape_input)
	body.add_child(shape_input)
	shape_input.item_selected.connect(_set_shape)
	body.add_child(Style.text("主体结构", 14, true))
	profile_input = OptionButton.new()
	for title in Catalog.PROFILES: profile_input.add_item(title)
	BoardUiStyle.style_controls(profile_input)
	body.add_child(profile_input)
	profile_input.item_selected.connect(func(index: int):
		values.profile = index
		rebuild_timer.start())
	var dimensions := HBoxContainer.new()
	dimensions.add_theme_constant_override("separation", 8)
	body.add_child(dimensions)
	for field in [["width", "宽 · 英尺"], ["depth", "长 · 英尺"], ["height", "高 · 英尺"]]:
		var column := Style.column(6)
		dimensions.add_child(column)
		column.add_child(Style.text(field[1], 14, true))
		var number := _number(field[0], 1.0, 50.0, 0.5)
		column.add_child(number)
	_add_range(body, "variation", "轮廓变化", 0.0, 1.0, 0.01)
	_add_range(body, "rounding", "棱角磨圆", 0.0, 1.0, 0.01)
	_add_range(body, "burial", "埋入地面 · %", 0.0, 0.4, 0.01, 100.0)
	var separator := HSeparator.new()
	body.add_child(separator)
	color_input = ColorWell.new()
	color_input.color = values.color
	color_input.popup_host = hud
	Style.button(color_input)
	body.add_child(color_input)
	color_input.color_changed.connect(func(color: Color):
		values.color = color
		_apply_material())
	_add_range(body, "color_variation", "色斑强度", 0.0, 0.5, 0.01)
	_add_range(body, "roughness", "表面粗糙度", 0.3, 1.0, 0.01)
	body.add_child(HSeparator.new())
	var seed_row := HBoxContainer.new()
	seed_row.add_theme_constant_override("separation", 8)
	body.add_child(seed_row)
	seed_row.add_child(Style.text("造型编号", 16))
	var seed_input := _number("seed", 1, 999999, 1)
	seed_row.add_child(seed_input)
	_button(body, "换一个造型", _randomize_shape, true)
	_button(body, "恢复候选参数", _restore_asset)
	status = Style.text("", 14, true)
	panel.body.add_child(status)
	var grid := CheckButton.new()
	grid.text = "五英尺参考网格"
	grid.button_pressed = true
	BoardUiStyle.style_controls(grid)
	panel.body.add_child(grid)
	grid.toggled.connect(func(enabled: bool): ground_material.set_shader_parameter("show_grid", enabled))
	var top := HBoxContainer.new()
	top.set_anchors_and_offsets_preset(Control.PRESET_TOP_RIGHT)
	top.grow_horizontal = Control.GROW_DIRECTION_BEGIN
	top.position = Vector2(-310, 20)
	top.add_theme_constant_override("separation", 10)
	hud.add_child(top)
	_button(top, "镜头复位", _reset_camera)
	_button(top, "生成参数", _open_panel)
	_sync_inputs()

func _build_assets() -> void:
	var categories := OptionButton.new()
	for title in Catalog.CATEGORIES: categories.add_item(title + " · 25个")
	categories.select(asset_category)
	BoardUiStyle.style_controls(categories)
	assets_body.add_child(categories)
	categories.item_selected.connect(func(index: int):
		asset_category = index
		asset_page = 0
		for i in range(assets.size()):
			if int(assets[i].parameters.shape) == index:
				selected_asset = i
				break
		_build_asset_cards()
		_select_asset(selected_asset)
		panel.scroll.scroll_vertical = 0)
	asset_info = Style.text("", 14, true)
	assets_body.add_child(asset_info)
	var pager := HBoxContainer.new()
	pager.add_theme_constant_override("separation", 8)
	assets_body.add_child(pager)
	previous_page = _page_button(pager, GoIconSet.CHEVRON_LEFT, "上一页", -1)
	page_label = Style.text("", 14, true)
	page_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	page_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	page_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pager.add_child(page_label)
	next_page = _page_button(pager, GoIconSet.CHEVRON_RIGHT, "下一页", 1)
	asset_grid = GridContainer.new()
	asset_grid.columns = 2
	asset_grid.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	asset_grid.add_theme_constant_override("h_separation", 8)
	asset_grid.add_theme_constant_override("v_separation", 8)
	assets_body.add_child(asset_grid)
	_button(assets_body, "载入生成器", _load_asset, true)
	_build_asset_cards()

func _asset_mesh(index: int) -> ArrayMesh:
	var id: String = assets[index].id
	if not mesh_cache.has(id):
		var path := "res://assets/scenery/rocks/" + id + ".res"
		var fixed: ArrayMesh = load(path) as ArrayMesh if FileAccess.file_exists(path) else null
		mesh_cache[id] = fixed if fixed != null else Generator.build(assets[index].parameters)
	return mesh_cache[id]

func _page_button(parent: Container, icon: StringName, title: String, direction: int) -> Button:
	var button := Button.new()
	GoStyle.apply_icon(button, icon, 18)
	Style.button(button)
	button.tooltip_text = title
	button.custom_minimum_size.x = 44
	button.pressed.connect(func():
		asset_page = clampi(asset_page + direction, 0, 4)
		_build_asset_cards()
		panel.scroll.scroll_vertical = 0)
	parent.add_child(button)
	return button

func _material(data: Dictionary) -> ShaderMaterial:
	var material := ShaderMaterial.new()
	material.shader = RockShader
	material.set_shader_parameter("stone_color", data.color)
	material.set_shader_parameter("variation", data.color_variation)
	material.set_shader_parameter("surface_roughness", data.roughness)
	material.set_shader_parameter("seed", float(data.seed))
	return material

func _build_asset_cards() -> void:
	gallery_revision += 1
	var revision := gallery_revision
	for child in asset_grid.get_children():
		asset_grid.remove_child(child)
		child.queue_free()
	asset_cards.clear()
	page_label.text = "%d / 5" % [asset_page + 1]
	previous_page.disabled = asset_page == 0
	next_page.disabled = asset_page == 4
	_refresh_asset_selection()
	var start := asset_category * 25 + asset_page * PAGE_SIZE
	var end := mini(start + PAGE_SIZE, (asset_category + 1) * 25)
	for i in range(start, end):
		if not is_inside_tree() or revision != gallery_revision: return
		var entry := assets[i]
		var data: Dictionary = entry.parameters
		if int(data.shape) != asset_category: continue
		var card := Button.new()
		card.custom_minimum_size = Vector2(130, 184)
		card.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		card.focus_mode = Control.FOCUS_NONE
		card.tooltip_text = "%s · 宽%s、长%s、高%s英尺" % [entry.title, String.num(data.width, 1), String.num(data.depth, 1), String.num(data.height, 1)]
		Style.card_button(card, 184)
		asset_grid.add_child(card)
		var margin := MarginContainer.new()
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		for side in ["left", "right", "top", "bottom"]:
			margin.add_theme_constant_override("margin_" + side, 8)
		card.add_child(margin)
		var content := Style.column(4)
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_child(content)
		var thumbnail := Thumbnail.new()
		thumbnail.custom_minimum_size.y = 94
		thumbnail.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		content.add_child(thumbnail)
		thumbnail.configure(_asset_mesh(i), _material(data))
		var title := Style.text(entry.title, 15)
		title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(title)
		var size_label := Style.text("%s × %s × %s 英尺" % [String.num(data.width, 1), String.num(data.depth, 1), String.num(data.height, 1)], 12, true)
		size_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(size_label)
		var structure: String = entry.structure
		var structure_label := Style.text(structure, 12, true)
		structure_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(structure_label)
		card.pressed.connect(_select_asset.bind(i))
		asset_cards[i] = card
		_refresh_asset_selection()
		await get_tree().process_frame

func _refresh_asset_selection() -> void:
	for index in asset_cards:
		var card: Button = asset_cards[index]
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			var face := card.get_theme_stylebox(state).duplicate() as StyleBoxFlat
			face.bg_color = Color("e1edfc") if index == selected_asset else Color("f0f4f9")
			face.border_color = Color("2e7ae0") if index == selected_asset else BoardUiStyle.BORDER_COLOR
			card.add_theme_stylebox_override(state, face)
	var data: Dictionary = assets[selected_asset].parameters
	asset_info.text = "%s · %s\n宽%s / 长%s / 高%s英尺" % [assets[selected_asset].title, assets[selected_asset].structure, String.num(data.width, 1), String.num(data.depth, 1), String.num(data.height, 1)]

func _select_asset(index: int) -> void:
	selected_asset = index
	values = assets[index].parameters.duplicate(true)
	rebuild_timer.stop()
	_generate()
	_refresh_asset_selection()
	_reset_camera()

func _set_page(next_page: String) -> void:
	if page == next_page: return
	if page == "generator": generator_draft = values.duplicate(true)
	page = next_page
	generator_body.visible = page == "generator"
	assets_body.visible = page == "assets"
	values = (generator_draft if page == "generator" else assets[selected_asset].parameters).duplicate(true)
	_sync_inputs()
	for key in page_buttons: Style.button(page_buttons[key], key == page)
	rebuild_timer.stop()
	_generate()
	_reset_camera()
	panel.scroll.scroll_vertical = 0

func _load_asset() -> void:
	generator_draft = assets[selected_asset].parameters.duplicate(true)
	_set_page("generator")

func _restore_asset() -> void:
	values = assets[selected_asset].parameters.duplicate(true)
	_sync_inputs()
	rebuild_timer.stop()
	_generate()

func _sync_inputs() -> void:
	syncing = true
	shape_input.select(int(values.shape))
	profile_input.select(int(values.get("profile", 0)))
	for key in ["width", "depth", "height", "variation", "rounding", "burial", "color_variation", "roughness", "seed"]:
		var amount := float(values[key]) * (100.0 if key == "burial" else 1.0)
		inputs[key].set_value_no_signal(amount)
		if inputs.has(key + "_slider"): inputs[key + "_slider"].set_value_no_signal(amount)
	color_input.color = values.color
	syncing = false

func _number(key: String, minimum: float, maximum: float, step: float, multiplier := 1.0) -> SpinBox:
	var input := SpinBox.new()
	input.min_value = minimum * multiplier
	input.max_value = maximum * multiplier
	input.step = step * multiplier
	input.value = float(values[key]) * multiplier
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	input.custom_minimum_size.x = 64
	input.custom_minimum_size.y = 44
	BoardUiStyle.style_controls(input)
	inputs[key] = input
	input.value_changed.connect(func(value: float):
		if syncing: return
		values[key] = value / multiplier
		_changed(key))
	return input

func _add_range(parent: VBoxContainer, key: String, title: String, minimum: float, maximum: float, step: float, multiplier := 1.0) -> void:
	parent.add_child(Style.text(title, 14, true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 10)
	parent.add_child(row)
	var slider := HSlider.new()
	slider.min_value = minimum * multiplier
	slider.max_value = maximum * multiplier
	slider.step = step * multiplier
	slider.value = float(values[key]) * multiplier
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var number := _number(key, minimum, maximum, step, multiplier)
	number.custom_minimum_size.x = 84
	number.size_flags_horizontal = Control.SIZE_FILL
	row.add_child(number)
	slider.value_changed.connect(func(value: float): number.value = value)
	number.value_changed.connect(func(value: float): slider.set_value_no_signal(value))
	inputs[key + "_slider"] = slider

func _button(parent: Container, title: String, action: Callable, primary := false) -> Button:
	var button := Button.new()
	button.text = title
	Style.button(button, primary)
	button.pressed.connect(action)
	parent.add_child(button)
	return button

func _set_shape(index: int) -> void:
	values.shape = index
	for key in ["width", "depth", "height", "rounding"]:
		values[key] = PRESETS[index][key]
	values.profile = 0
	_sync_inputs()
	rebuild_timer.start()

func _changed(key: String) -> void:
	if key in ["color_variation", "roughness"]:
		_apply_material()
	else:
		rebuild_timer.start()

func _randomize_shape() -> void:
	values.seed = int(values.seed) % 999999 + 1
	inputs.seed.set_value_no_signal(values.seed)
	rebuild_timer.stop()
	_generate()

func _generate() -> void:
	rock.mesh = _asset_mesh(selected_asset) if page == "assets" else Generator.build(values)
	# Keep the scale reference outside even the widest generated rock.
	var width := float(values.width) * Generator.FEET
	var depth := float(values.depth) * Generator.FEET
	reference.position.x = -maxf(3.0, width * 0.5 + 1.25)
	reference_caption.position.x = reference.position.x
	var extent := Vector2(maxf(12.0, width + 8.0), maxf(12.0, depth + 6.0))
	(stage_surface.mesh as PlaneMesh).size = extent
	(stage_base.mesh as BoxMesh).size = Vector3(extent.x, 0.3, extent.y)
	_apply_material()
	var triangles: int = int(rock.mesh.surface_get_array_len(0) / 3)
	var title: String = assets[selected_asset].title if page == "assets" else PRESETS[int(values.shape)].title
	status.text = "%s · %d 个三角面" % [title, triangles]

func _apply_material() -> void:
	stone_material.set_shader_parameter("stone_color", values.color)
	stone_material.set_shader_parameter("variation", values.color_variation)
	stone_material.set_shader_parameter("surface_roughness", values.roughness)
	stone_material.set_shader_parameter("seed", float(values.seed))

func _reset_camera() -> void:
	var dimensions := Vector3(float(values.width), float(values.height), float(values.depth)) * Generator.FEET
	var radius := maxf(3.5, dimensions.length() * 0.85)
	var target := Vector3(-0.8, dimensions.y * 0.3, 0)
	camera.position = target + Vector3(1, 0.62, 1.2) * radius
	camera.look_at(target)
	camera.yaw = camera.rotation.y
	camera.pitch = camera.rotation.x
	camera.release_mouse()
	if get_viewport().gui_get_focus_owner() != null:
		get_viewport().gui_get_focus_owner().release_focus()

func _open_panel() -> void:
	panel.reveal_at(hud.size, Vector2(20, hud.size.y - 20))

func _fit_panel() -> void:
	if panel.visible: panel.fit_at(hud.size, Vector2(20, hud.size.y - 20))

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and not event.pressed:
		camera.release_mouse()
	if event is InputEventMouseMotion and camera.turning:
		camera.turn(event.relative)
		get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_RIGHT and event.pressed:
		camera.begin_turn()
		get_viewport().set_input_as_handled()
