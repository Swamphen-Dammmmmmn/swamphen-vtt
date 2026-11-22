extends "res://ui/components/utility_panel.gd"

const Parameters = preload("res://scripts/token_parameters.gd")
const Appearance = preload("res://scripts/token_appearance.gd")
const ColorWell = preload("res://ui/components/forms/color_well.gd")
const TextField = preload("res://ui/components/forms/editor_text_field.gd")
const OptionField = preload("res://ui/components/forms/editor_option_field.gd")
const EditorFoldableGroup = preload("res://ui/components/layout/editor_foldable_group.gd")
const FluentButton = preload("res://ui/components/controls/fluent_button.gd")
const PREVIEW_TURN_SECONDS := 30.0

signal placement_requested(parameters: Dictionary)
signal appearance_saved(token_id: int, parameters: Dictionary)

var editing_id := -1
var submit_button: Button
var note: Label
var creation_values: Dictionary = {}

var _name_field: TextField
var _size_field: OptionField
var _base_field: OptionField
var color_input: ColorWell
var _hp_field: TextField
var _maximum_field: TextField
var _ac_field: TextField
var stats_fold: EditorFoldableGroup
var preview_viewport: SubViewport
var preview_root: Node3D
var preview_camera: Camera3D
var preview_actor: Node3D
var preview_angle := 0.0

func _init() -> void:
	fluent = true
	panel_title = "创建基础棋子"
	preferred_width = 360.0

func _ready() -> void:
	super._ready()
	configure_editor()
	_build_preview()

	_name_field = TextField.new()
	_name_field.setup("名称", "棋子名称", "棋子")
	_name_field.configure_input(40)
	content().add_child(_name_field)

	_size_field = OptionField.new()
	_size_field.setup("占地", ["1 × 1", "2 × 2", "3 × 3", "4 × 4", "5 × 5"], 0)
	content().add_child(_size_field)

	_base_field = OptionField.new()
	_base_field.setup("底座", ["正方形", "圆形", "六边形"], 1)
	content().add_child(_base_field)

	var color_row := VBoxContainer.new()
	color_row.add_theme_constant_override("separation", 6)
	content().add_child(color_row)
	var color_label := Label.new()
	color_label.text = "颜色"
	color_label.theme_type_variation = &"FluentSecondary"
	color_label.add_theme_font_size_override("font_size", Typography.CAPTION)
	color_row.add_child(color_label)
	color_input = ColorWell.new()
	color_input.popup_host = get_parent()
	color_input.popup_title = "棋子颜色"
	color_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	color_row.add_child(color_input)

	stats_fold = EditorFoldableGroup.new()
	stats_fold.set_group_title("初始数值")
	stats_fold.folded = true
	content().add_child(stats_fold)

	_hp_field = TextField.new()
	_hp_field.setup("当前 HP", "未填写", "")
	_hp_field.configure_input(6, LineEdit.KEYBOARD_TYPE_NUMBER)
	stats_fold.content().add_child(_hp_field)

	_maximum_field = TextField.new()
	_maximum_field.setup("最大 HP", "未填写", "")
	_maximum_field.configure_input(6, LineEdit.KEYBOARD_TYPE_NUMBER)
	stats_fold.content().add_child(_maximum_field)

	_ac_field = TextField.new()
	_ac_field.setup("AC", "未填写", "")
	_ac_field.configure_input(6, LineEdit.KEYBOARD_TYPE_NUMBER)
	stats_fold.content().add_child(_ac_field)

	note = Label.new()
	note.text = "HP / AC 可留空；仅填一项 HP 时，当前与最大生命值相同。底座不改变正方形占地。"
	note.theme_type_variation = &"FluentSecondary"
	note.add_theme_font_size_override("font_size", Typography.CAPTION)
	note.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content().add_child(note)

	submit_button = FluentButton.new()
	submit_button.text = "放置"
	submit_button.variant = "FluentPrimary"
	submit_button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	submit_button.pressed.connect(_begin_placement)
	editor_footer.add_child(submit_button)

	_size_field.option_selected.connect(func(_index: int, _val: String): _refresh_preview())
	_base_field.option_selected.connect(func(_index: int, _val: String): _refresh_preview())
	color_input.color_changed.connect(func(_color: Color): _refresh_preview())
	for field in [_name_field, _hp_field, _maximum_field, _ac_field]:
		field.text_changed.connect(func(_text: String):
			_clear_all_errors()
			set_editor_status("准备放置" if editing_id < 0 else "编辑外观")
		)
	_refresh_preview()

func is_editing_instance() -> bool:
	return visible and editing_id >= 0

func _clear_all_errors() -> void:
	for field in [_name_field, _hp_field, _maximum_field, _ac_field]:
		field.set_error("")
	_size_field.set_error("")

func _parameters() -> Dictionary:
	return {
		"title": _name_field.get_value(),
		"size": _size_field.get_selected_index(),
		"base": _base_field.get_selected_index(),
		"color": color_input.color,
		"hp": _hp_field.get_value(),
		"max_hp": _maximum_field.get_value(),
		"ac": _ac_field.get_value(),
	}

func open_creation() -> void:
	if editing_id >= 0 and not creation_values.is_empty():
		_name_field.set_value(str(creation_values["title"]))
		_size_field.set_selected_index(int(creation_values["size"]))
		_base_field.set_selected_index(int(creation_values["base"]))
		color_input.color = creation_values["color"]
		_hp_field.set_value(str(creation_values["hp"]))
		_maximum_field.set_value(str(creation_values["max_hp"]))
		_ac_field.set_value(str(creation_values["ac"]))
	editing_id = -1
	set_panel_title("创建基础棋子")
	_size_field.set_disabled(false)
	_name_field.show()
	stats_fold.show()
	_clear_all_errors()
	note.text = "HP / AC 可留空；仅填一项 HP 时，当前与最大生命值相同。底座不改变正方形占地。"
	submit_button.text = "放置"
	set_editor_status("准备放置")
	_refresh_preview()
	open()

func open_edit(data: Dictionary) -> void:
	if editing_id < 0:
		creation_values = _parameters()
	editing_id = int(data["id"])
	set_panel_title("编辑基础棋子 · " + str(data["title"]))
	_size_field.set_selected_index(clampi(int(data["size"]) - 1, 0, 4))
	_size_field.set_disabled(true)
	_base_field.set_selected_index(maxi(0, Appearance.BASES.find(data["base"])))
	color_input.color = data["color"]
	_name_field.hide()
	stats_fold.hide()
	_clear_all_errors()
	note.text = "占地为创建时确定的基础规格，不可修改。名称、生命值与 AC 通过棋子信息栏编辑。"
	submit_button.text = "保存外观"
	set_editor_status("占地不可修改")
	_refresh_preview()
	open()

func _process(delta: float) -> void:
	if not is_visible_in_tree() or preview_actor == null:
		return
	preview_angle = fposmod(preview_angle + TAU * delta / PREVIEW_TURN_SECONDS, TAU)
	preview_actor.rotation.y = preview_angle
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

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
	var count := _size_field.get_selected_index() + 1
	var base_idx := clampi(_base_field.get_selected_index(), 0, Appearance.BASES.size() - 1)
	preview_actor = Appearance.build(count, color_input.color, Appearance.BASES[base_idx])
	preview_actor.rotation.y = preview_angle
	preview_root.add_child(preview_actor)
	preview_camera.position = Vector3(1.8, 1.5, 2.6) * count
	preview_camera.look_at(Vector3(0, count * 0.4, 0))
	preview_viewport.render_target_update_mode = SubViewport.UPDATE_ONCE

func popup_visible() -> bool:
	return (color_input != null and color_input.is_popup_open()) \
		or (is_instance_valid(_size_field) and _size_field.is_popup_open()) \
		or (is_instance_valid(_base_field) and _base_field.is_popup_open())

func close_popups() -> bool:
	var closed := false
	if color_input != null and color_input.is_popup_open():
		color_input.close_popup()
		closed = true
	if is_instance_valid(_size_field) and _size_field.is_popup_open():
		_size_field.close_popup()
		closed = true
	if is_instance_valid(_base_field) and _base_field.is_popup_open():
		_base_field.close_popup()
		closed = true
	return closed

func _fail(message: String) -> void:
	set_editor_status(message, true)

func _begin_placement() -> void:
	if editing_id >= 0:
		var edited_color := color_input.color
		edited_color.a = 1.0
		var base_idx := clampi(_base_field.get_selected_index(), 0, Appearance.BASES.size() - 1)
		appearance_saved.emit(editing_id, {"base": Appearance.BASES[base_idx], "color": edited_color})
		close()
		return
	var base_idx := clampi(_base_field.get_selected_index(), 0, Appearance.BASES.size() - 1)
	var result := Parameters.validate({
		"title": _name_field.get_value(),
		"size": _size_field.get_selected_index() + 1,
		"base": Appearance.BASES[base_idx],
		"color": color_input.color,
		"hp": _hp_field.get_value(),
		"max_hp": _maximum_field.get_value(),
		"ac": _ac_field.get_value(),
	})
	if not result["ok"]:
		_fail(result["message"])
		var field_map := {
			"title": _name_field,
			"hp": _hp_field,
			"max_hp": _maximum_field,
			"ac": _ac_field,
			"size": _size_field,
		}
		var target := field_map.get(result["field"], _name_field) as Control
		if target.has_method("set_error"):
			target.call("set_error", result["message"])
		if target in [_hp_field, _maximum_field, _ac_field]:
			stats_fold.folded = false
		ensure_control_visible(target)
		if target.has_method("focus_input"):
			target.call("focus_input")
		return
	close()
	placement_requested.emit(result["parameters"])

func close() -> void:
	close_popups()
	super.close()
