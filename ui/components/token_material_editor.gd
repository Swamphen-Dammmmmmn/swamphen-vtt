extends VBoxContainer

const Surface = preload("res://scripts/token_surface.gd")
const Style = preload("res://ui/components/page_style.gd")
const ColorWell = preload("res://ui/components/color_well.gd")
signal changed
var value: Dictionary = Surface.defaults()
var default_value: Dictionary = Surface.defaults()
var popup_host: Control
var color_input: ColorWell
var numbers: Dictionary = {}
var sliders: Dictionary = {}
var cards: Dictionary = {}
var preset_status: Label
var board_row: HBoxContainer
var board_input: CheckButton
var syncing := false

func _ready() -> void:
	add_theme_constant_override("separation", 12)
	var heading := HBoxContainer.new()
	add_child(heading)
	var heading_label := Style.text("材质预设", 14, true)
	heading_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.add_child(heading_label)
	preset_status = Style.text("", 14)
	preset_status.autowrap_mode = TextServer.AUTOWRAP_OFF
	preset_status.custom_minimum_size.x = 72
	preset_status.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	heading.add_child(preset_status)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 8)
	grid.add_theme_constant_override("v_separation", 8)
	add_child(grid)
	for i in range(Surface.KINDS.size()):
		var kind: String = Surface.KINDS[i]
		var button := Button.new()
		button.custom_minimum_size = Vector2(88, 104)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		Style.card_button(button, 104)
		grid.add_child(button)
		button.clip_contents = true
		var inset := MarginContainer.new()
		inset.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(inset)
		inset.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for side in ["left", "right", "top", "bottom"]:
			inset.add_theme_constant_override("margin_" + side, 8)
		var content := VBoxContainer.new()
		content.mouse_filter = Control.MOUSE_FILTER_IGNORE
		content.add_theme_constant_override("separation", 4)
		inset.add_child(content)
		var preview := _preview(Surface.defaults(kind, "7ba5cc"))
		content.add_child(preview)
		var label := Style.text(Surface.TITLES[i], 13)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		content.add_child(label)
		button.pressed.connect(func():
			color_input.get_popup().hide()
			var board_visible: bool = value.board_visible
			value = Surface.defaults(kind, str(value.color))
			value.board_visible = board_visible
			_sync()
			changed.emit())
		cards[kind] = button
	color_input = ColorWell.new()
	color_input.popup_host = popup_host
	Style.card_button(color_input)
	add_child(Style.text("颜色", 14, true))
	add_child(color_input)
	color_input.color_changed.connect(func(color: Color):
		if syncing: return
		value.color = color.to_html(false)
		changed.emit())
	_knob("opacity", "不透明度 · %")
	_knob("roughness", "表面粗糙度 · %")
	_knob("metallic", "金属程度 · %")
	_knob("grain", "磨砂颗粒强度 · %")
	_knob("edge", "亚克力边缘效果 · %")
	board_row = HBoxContainer.new()
	add_child(board_row)
	var title := Style.text("显示承载板")
	title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	title.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	board_row.add_child(title)
	board_input = CheckButton.new()
	BoardUiStyle.style_controls(board_input)
	board_row.add_child(board_input)
	board_input.toggled.connect(func(enabled: bool):
		if syncing: return
		value.board_visible = enabled
		changed.emit())
	var reset := Button.new()
	reset.text = "恢复默认材质"
	Style.button(reset)
	add_child(reset)
	reset.pressed.connect(func():
		color_input.get_popup().hide()
		value = default_value.duplicate(true)
		_sync()
		changed.emit())
	_sync()

func configure(settings: Dictionary, defaults: Dictionary, image_mode := false) -> void:
	value = Surface.normalize(settings)
	default_value = Surface.normalize(defaults)
	board_row.visible = image_mode
	_sync()

func _sync() -> void:
	syncing = true
	color_input.color = Color(value.color)
	for key in numbers:
		numbers[key].set_value_no_signal(float(value[key]) * 100.0)
		sliders[key].set_value_no_signal(float(value[key]) * 100.0)
	board_input.set_pressed_no_signal(value.board_visible)
	_update_preset()
	syncing = false

func _update_preset() -> void:
	var selected := Surface.matching_preset(value)
	var index := Surface.KINDS.find(selected)
	preset_status.text = "自定义" if index < 0 else Surface.TITLES[index]
	for kind in cards:
		var button: Button = cards[kind]
		for state in ["normal", "hover", "pressed", "hover_pressed"]:
			var face := button.get_theme_stylebox(state).duplicate() as StyleBoxFlat
			face.bg_color = Color("e1edfc") if selected == kind else Color("f0f4f9")
			face.border_color = Color("2e7ae0") if selected == kind else BoardUiStyle.BORDER_COLOR
			button.add_theme_stylebox_override(state, face)

func _knob(key: String, title: String) -> VBoxContainer:
	var group := Style.column(6)
	add_child(group)
	group.add_child(Style.text(title, 14, true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	group.add_child(row)
	var slider := HSlider.new()
	slider.max_value = 100
	slider.step = 1
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	row.add_child(slider)
	var number := SpinBox.new()
	number.max_value = 100
	number.step = 1
	number.custom_minimum_size = Vector2(88, 44)
	BoardUiStyle.style_controls(number)
	row.add_child(number)
	sliders[key] = slider
	numbers[key] = number
	var update := func(amount: float):
		if syncing: return
		value[key] = amount / 100.0
		number.set_value_no_signal(amount)
		slider.set_value_no_signal(amount)
		_update_preset()
		changed.emit()
	slider.value_changed.connect(update)
	number.value_changed.connect(update)
	return group

func _preview(settings: Dictionary) -> SubViewportContainer:
	var host := SubViewportContainer.new()
	host.stretch = true
	host.mouse_filter = Control.MOUSE_FILTER_IGNORE
	host.custom_minimum_size.y = 56
	var viewport := SubViewport.new()
	viewport.size = Vector2i(48, 56)
	viewport.own_world_3d = true
	viewport.gui_disable_input = true
	viewport.handle_input_locally = false
	viewport.render_target_update_mode = SubViewport.UPDATE_DISABLED
	host.add_child(viewport)
	var world := WorldEnvironment.new()
	var environment := Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color("e9eef4")
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color.WHITE
	environment.ambient_light_energy = 0.5
	Surface.preview_reflection(environment)
	world.environment = environment
	viewport.add_child(world)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-35,-35,0)
	viewport.add_child(light)
	var sphere := MeshInstance3D.new()
	sphere.mesh = SphereMesh.new()
	sphere.material_override = Surface.material(settings)
	viewport.add_child(sphere)
	var camera := Camera3D.new()
	camera.position = Vector3(1.5,1.0,2.5)
	viewport.add_child(camera)
	camera.look_at.call_deferred(Vector3.ZERO)
	camera.fov = 38
	camera.current = true
	var refresh := func(): viewport.render_target_update_mode = SubViewport.UPDATE_ONCE if host.is_visible_in_tree() else SubViewport.UPDATE_DISABLED
	host.visibility_changed.connect(refresh)
	host.resized.connect(refresh)
	refresh.call_deferred()
	return host
