extends "res://ui/components/utility_panel.gd"

const Parameters = preload("res://scripts/token_parameters.gd")
const Appearance = preload("res://scripts/token_appearance.gd")
const PREVIEW_TURN_SECONDS := 30.0
signal placement_requested(parameters: Dictionary)
signal appearance_saved(token_id: int, parameters: Dictionary)

var editing_id := -1
var submit_button: Button
var note: Label
var creation_values: Dictionary = {}

var name_input: LineEdit
var size_input: OptionButton
var base_input: OptionButton
var color_input: ColorPickerButton
var hp_input: LineEdit
var maximum_input: LineEdit
var ac_input: LineEdit
var error_label: Label
var stats_fold: FoldableContainer
var stats_body: VBoxContainer
var preview_viewport: SubViewport
var preview_root: Node3D
var preview_camera: Camera3D
var preview_actor: Node3D
var preview_angle := 0.0

func _ready() -> void:
	super._ready()
	configure_editor()
	_build_preview()
	name_input = _field("名称", "棋子", 40)
	size_input = _choice("占地", ["1 × 1", "2 × 2", "3 × 3", "4 × 4", "5 × 5"])
	base_input = _choice("底座", ["正方形", "圆形", "六边形"])
	base_input.select(1)
	var row := _row("颜色")
	color_input = ColorPickerButton.new()
	color_input.color = Color("2e7ae0")
	color_input.edit_alpha = false
	color_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_input.custom_minimum_size.y = BoardUiStyle.CONTROL_HEIGHT
	row.add_child(color_input)
	_configure_color_popup()
	stats_fold = GoStyle.foldable("初始数值", true, null, false)
	EditorLayout.fold(stats_fold)
	content().add_child(stats_fold)
	stats_body = EditorStyle.column(12)
	stats_fold.add_child(stats_body)
	hp_input = _field("当前 HP", "", 6)
	maximum_input = _field("最大 HP", "", 6)
	ac_input = _field("AC", "", 6)
	for input in [hp_input, maximum_input, ac_input]: input.get_parent().reparent(stats_body)
	note = GoStyle.label("HP / AC 可留空；仅填一项 HP 时，当前与最大生命值相同。底座不改变正方形占地。")
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content().add_child(note)
	error_label = editor_status
	submit_button = GoStyle.button("放置", _begin_placement, GoStyle.Tone.PRIMARY)
	editor_footer.add_child(submit_button)
	size_input.item_selected.connect(func(_index: int): _refresh_preview())
	base_input.item_selected.connect(func(_index: int): _refresh_preview())
	color_input.color_changed.connect(func(_color: Color): _refresh_preview())
	for field in [name_input, hp_input, maximum_input, ac_input]:
		field.text_changed.connect(func(_text: String):
			for input in [name_input, hp_input, maximum_input, ac_input]: EditorLayout.field_error(input, "")
			set_editor_status("准备放置" if editing_id < 0 else "编辑外观"))
	_refresh_preview()
	_style_content.call_deferred()

func _parameters() -> Dictionary:
	return {"title": name_input.text, "size": size_input.selected, "base": base_input.selected, "color": color_input.color, "hp": hp_input.text, "max_hp": maximum_input.text, "ac": ac_input.text}

func open_creation() -> void:
	if editing_id >= 0 and not creation_values.is_empty():
		name_input.text = creation_values["title"]
		size_input.select(creation_values["size"])
		base_input.select(creation_values["base"])
		color_input.color = creation_values["color"]
		hp_input.text = creation_values["hp"]
		maximum_input.text = creation_values["max_hp"]
		ac_input.text = creation_values["ac"]
	editing_id = -1
	$Shell/Header/Row/Title.text = "创建基础棋子"
	size_input.disabled = false
	for field in [name_input, hp_input, maximum_input, ac_input]:
		field.get_parent().show()
	note.text = "HP / AC 可留空；仅填一项 HP 时，当前与最大生命值相同。底座不改变正方形占地。"
	submit_button.text = "放置"
	stats_fold.visible = true
	set_editor_status("准备放置")
	_refresh_preview()
	open()

func open_edit(data: Dictionary) -> void:
	if editing_id < 0:
		creation_values = _parameters()
	editing_id = int(data["id"])
	$Shell/Header/Row/Title.text = "编辑基础棋子 · " + str(data["title"])
	size_input.select(int(data["size"]) - 1)
	size_input.disabled = true
	base_input.select(Appearance.BASES.find(data["base"]))
	color_input.color = data["color"]
	for field in [name_input, hp_input, maximum_input, ac_input]:
		field.get_parent().hide()
	note.text = "占地为创建时确定的基础规格，不可修改。名称、生命值与 AC 通过棋子信息栏编辑。"
	submit_button.text = "保存外观"
	stats_fold.hide()
	set_editor_status("占地不可修改")
	_refresh_preview()
	open()

func _configure_color_popup() -> void:
	BoardUiStyle.configure_color_picker(color_input)

func _process(delta: float) -> void:
	if not is_visible_in_tree() or preview_actor == null:
		return
	preview_angle = fposmod(preview_angle + TAU * delta / PREVIEW_TURN_SECONDS, TAU)
	preview_actor.rotation.y = preview_angle
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func _row(title: String) -> VBoxContainer:
	var row := EditorLayout.field(content(), title)
	return row

func _field(title: String, initial: String, max_length: int) -> LineEdit:
	var row := _row(title)
	var field := GoStyle.line_edit("未填写" if title != "名称" else "棋子名称")
	field.text = initial
	field.max_length = max_length
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(field)
	return field

func _choice(title: String, options: Array) -> OptionButton:
	var row := _row(title)
	var choice := OptionButton.new()
	choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for option in options:
		choice.add_item(option)
	row.add_child(choice)
	return choice

func _build_preview() -> void:
	var container := SubViewportContainer.new()
	container.custom_minimum_size = Vector2(0, 160)
	container.stretch = true
	container.mouse_filter = Control.MOUSE_FILTER_IGNORE
	content().add_child(container)
	preview_viewport = SubViewport.new()
	preview_viewport.size = Vector2i(320, 160)
	preview_viewport.own_world_3d = true
	preview_viewport.handle_input_locally = false
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	container.add_child(preview_viewport)
	preview_root = Node3D.new()
	preview_viewport.add_child(preview_root)
	var environment := WorldEnvironment.new()
	var settings := Environment.new()
	settings.background_mode = Environment.BG_COLOR
	settings.background_color = Color("edf2f8")
	settings.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	settings.ambient_light_color = Color.WHITE
	settings.ambient_light_energy = 0.6
	environment.environment = settings
	preview_root.add_child(environment)
	var light := DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-45, -35, 0)
	preview_root.add_child(light)
	preview_camera = Camera3D.new()
	preview_camera.current = true
	preview_camera.fov = 35
	preview_root.add_child(preview_camera)
	container.resized.connect(func(): preview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE)
	visibility_changed.connect(func():
		if is_visible_in_tree(): preview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE
	)

func _refresh_preview() -> void:
	if preview_actor != null:
		preview_root.remove_child(preview_actor)
		preview_actor.queue_free()
	var count := size_input.selected + 1
	preview_actor = Appearance.build(count, color_input.color, Appearance.BASES[base_input.selected])
	preview_actor.rotation.y = preview_angle
	preview_root.add_child(preview_actor)
	preview_camera.position = Vector3(1.8, 1.5, 2.6) * count
	preview_camera.look_at(Vector3(0, count * 0.4, 0))
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func popup_visible() -> bool:
	return (color_input != null and color_input.get_popup().visible) \
		or (size_input != null and size_input.get_popup().visible) \
		or (base_input != null and base_input.get_popup().visible)

func _fail(message: String) -> void:
	set_editor_status(message, true)

func _begin_placement() -> void:
	if editing_id >= 0:
		var edited_color := color_input.color
		edited_color.a = 1.0
		appearance_saved.emit(editing_id, {"base": Appearance.BASES[base_input.selected], "color": edited_color})
		close()
		return
	var result := Parameters.validate({"title": name_input.text, "size": size_input.selected + 1, "base": Appearance.BASES[base_input.selected], "color": color_input.color, "hp": hp_input.text, "max_hp": maximum_input.text, "ac": ac_input.text})
	if not result["ok"]:
		_fail(result["message"])
		var fields := {"title": name_input, "hp": hp_input, "max_hp": maximum_input, "ac": ac_input, "size": size_input}
		var field: Control = fields.get(result["field"], name_input)
		EditorLayout.field_error(field, result["message"])
		if field in [hp_input, maximum_input, ac_input]: stats_fold.folded = false
		$Shell/Body.ensure_control_visible(field)
		field.grab_focus()
		return
	close()
	placement_requested.emit(result["parameters"])

func close() -> void:
	if color_input != null: color_input.get_popup().hide()
	if size_input != null: size_input.get_popup().hide()
	if base_input != null: base_input.get_popup().hide()
	super.close()
