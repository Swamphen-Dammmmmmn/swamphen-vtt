extends "res://ui/components/utility_panel.gd"

signal parameters_changed(parameters: Dictionary)
signal action_requested(action: String)

const ShapePlan = preload("res://scripts/shape_plan.gd")
const OptionField = preload("res://ui/components/forms/editor_option_field.gd")
const SpinField = preload("res://ui/components/forms/editor_spin_field.gd")
const SliderField = preload("res://ui/components/forms/editor_slider_field.gd")
const FluentButton = preload("res://ui/components/controls/fluent_button.gd")

const KIND_TITLES := ["圆形", "扇形", "矩形", "线形"]
const ANCHOR_TITLES := ["角点对齐", "中心对齐"]

var _kind_field: OptionField
var _anchor_field: OptionField
var _rotation_slider_field: SliderField
var fields: Dictionary = {}
var rows: Dictionary = {}
var actions: Dictionary = {}
var status: Label
var instruction: Label
var updating := false
var dimensions: BoxContainer

func _init() -> void:
	fluent = true
	layout_key = "adventure.shape"
	host_controls_close = true
	panel_title = "形状参数"
	preferred_width = 340.0

func _ready() -> void:
	super._ready()
	configure_editor()

	_kind_field = OptionField.new()
	_kind_field.setup("形状", KIND_TITLES, 0)
	content().add_child(_kind_field)
	_kind_field.option_selected.connect(func(index: int, _val: String):
		if updating:
			return
		if index == ShapePlan.Kind.LINE:
			fields["length"].set_value(30.0, false)
			fields["width"].set_value(5.0, false)
		_update_rows()
		_emit_parameters()
	)

	_add_field("radius", "半径（英尺）", 1, 300, 10)
	_add_field("length", "长度（英尺）", 1, 300, 15)
	_add_field("width", "宽度（英尺）", 1, 300, 15)

	_anchor_field = OptionField.new()
	_anchor_field.setup("定位方式", ANCHOR_TITLES, 0)
	content().add_child(_anchor_field)
	rows["anchor"] = _anchor_field
	_anchor_field.option_selected.connect(func(_index: int, _val: String):
		if not updating:
			_emit_parameters()
	)

	_add_field("angle", "张角（度）", 1, 180, 90)
	_add_field("rotation", "方向（度）", 0, 359, 0)

	_rotation_slider_field = SliderField.new()
	_rotation_slider_field.set_slider_variation(&"FluentSlider")
	_rotation_slider_field.setup("扇形朝向", 0.0, 359.0, 0.0, "°", "%.0f")
	_rotation_slider_field.tooltip_text = "调整扇形朝向，张角保持不变"
	content().add_child(_rotation_slider_field)
	rows["rotation_slider"] = _rotation_slider_field
	_rotation_slider_field.value_changed.connect(func(value: float):
		if not updating:
			fields["rotation"].set_value(value, true)
	)

	var rotation_buttons := HBoxContainer.new()
	rotation_buttons.add_theme_constant_override("separation", 8)
	content().add_child(rotation_buttons)
	rows["rotation_buttons"] = rotation_buttons
	for offset in [-15, 15]:
		var amount: int = offset
		var button := FluentButton.new()
		button.text = "%+d°" % amount
		button.variant = "FluentCompact"
		button.minimum_height = 36.0
		button.tooltip_text = "相对当前朝向旋转 %+d°" % amount
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func(): fields["rotation"].set_value(fposmod(fields["rotation"].get_value() + amount, 360.0), true))
		rotation_buttons.add_child(button)

	var sector_buttons := GridContainer.new()
	sector_buttons.columns = 2
	sector_buttons.add_theme_constant_override("h_separation", 8)
	sector_buttons.add_theme_constant_override("v_separation", 8)
	content().add_child(sector_buttons)
	rows["sector_buttons"] = sector_buttons
	for offset in [-45, 45, -60, 60]:
		var amount: int = offset
		var button := FluentButton.new()
		button.text = "%+d°" % amount
		button.variant = "FluentCompact"
		button.minimum_height = 36.0
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = "相对当前朝向旋转 %+d°" % amount
		button.pressed.connect(func(): fields["rotation"].set_value(fposmod(fields["rotation"].get_value() + amount, 360.0), true))
		sector_buttons.add_child(button)

	status = editor_status
	instruction = Label.new()
	instruction.theme_type_variation = &"FluentSecondary"
	instruction.add_theme_font_size_override("font_size", Typography.CAPTION)
	instruction.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content().add_child(instruction)
	instruction.hide()

	panel_action_requested.connect(func(action: String): action_requested.emit(action))

	dimensions = EditorLayout.pair(content())
	content().move_child(dimensions, rows["length"].get_index())
	rows["length"].reparent(dimensions)
	rows["width"].reparent(dimensions)
	set_parameters(ShapePlan.defaults())

func _add_field(key: String, title: String, minimum: float, maximum: float, initial: float) -> void:
	var field := SpinField.new()
	field.set_spin_variation(&"FluentSpinBox")
	field.setup(title, minimum, maximum, 1.0, initial)
	content().add_child(field)
	rows[key] = field
	fields[key] = field
	field.value_changed.connect(func(_value: float): _emit_parameters())

func parameters() -> Dictionary:
	if not is_node_ready():
		return ShapePlan.defaults()
	var values := {
		"kind": _kind_field.get_selected_index(),
		"anchor": _anchor_field.get_selected_index(),
	}
	for key in fields:
		values[key] = fields[key].get_value()
	return values

func summary_text() -> String:
	var p := parameters()
	var k := clampi(int(p.get("kind", 0)), 0, KIND_TITLES.size() - 1)
	var title: String = KIND_TITLES[k]
	match k:
		ShapePlan.Kind.CIRCLE:
			return "%s · 半径 %d 尺" % [title, roundi(float(p.get("radius", 10.0)))]
		ShapePlan.Kind.CONE:
			return "%s · 长度 %d 尺 · 张角 %d° · 方向 %d°" % [title, roundi(float(p.get("length", 15.0))), roundi(float(p.get("angle", 90.0))), roundi(float(p.get("rotation", 0.0)))]
		ShapePlan.Kind.RECTANGLE:
			var anc: String = ANCHOR_TITLES[clampi(int(p.get("anchor", 0)), 0, ANCHOR_TITLES.size() - 1)]
			return "%s · %d × %d 尺 · %s · 方向 %d°" % [title, roundi(float(p.get("length", 15.0))), roundi(float(p.get("width", 15.0))), anc, roundi(float(p.get("rotation", 0.0)))]
		ShapePlan.Kind.LINE:
			return "%s · %d × %d 尺 · 方向 %d°" % [title, roundi(float(p.get("length", 30.0))), roundi(float(p.get("width", 5.0))), roundi(float(p.get("rotation", 0.0)))]
	return title

func set_parameters(data: Dictionary) -> void:
	if not is_node_ready():
		return
	updating = true
	_kind_field.set_selected_index(clampi(int(data.get("kind", 0)), 0, KIND_TITLES.size() - 1), false)
	_anchor_field.set_selected_index(clampi(int(data.get("anchor", 0)), 0, ANCHOR_TITLES.size() - 1), false)
	for key in fields:
		if data.has(key):
			fields[key].set_value(float(data[key]), false)
	_rotation_slider_field.set_value(float(data.get("rotation", 0.0)), false)
	updating = false
	_update_rows()

func set_state(selected: bool, has_draft: bool, moving: bool, _ready: bool, count: int, busy: bool) -> void:
	set_editor_status("%s · %d / %d 个形状" % ["移动中" if moving else ("修改中" if selected else ("创建中" if has_draft else "就绪")), count, ShapePlan.MAX_SHAPES])
	set_panel_actions([
		{"id": "new", "title": "新建形状", "visible": not busy, "enabled": count < ShapePlan.MAX_SHAPES, "primary": true},
		{"id": "confirm", "title": "确认", "visible": busy, "enabled": _ready and not moving, "primary": true},
		{"id": "cancel", "title": "取消本次", "visible": busy},
	])

func set_delete_undo_available(available: bool) -> void:
	# Keep undo in a stable footer slot, separate from the creation/edit action set.
	if not actions.has("undo_delete"):
		var button := FluentButton.new()
		button.text = "撤销删除"
		button.pressed.connect(func(): action_requested.emit("undo_delete"))
		editor_footer.add_child(button)
		actions["undo_delete"] = button
	actions["undo_delete"].visible = available

func _emit_parameters() -> void:
	if not updating:
		_rotation_slider_field.set_value(float(fields["rotation"].get_value()), false)
		parameters_changed.emit(parameters())

func _update_rows() -> void:
	var k := _kind_field.get_selected_index()
	dimensions.visible = k != ShapePlan.Kind.CIRCLE
	rows["radius"].visible = k == ShapePlan.Kind.CIRCLE
	rows["length"].visible = k != ShapePlan.Kind.CIRCLE
	rows["width"].visible = k in [ShapePlan.Kind.RECTANGLE, ShapePlan.Kind.LINE]
	rows["anchor"].visible = k == ShapePlan.Kind.RECTANGLE
	rows["angle"].visible = k == ShapePlan.Kind.CONE
	rows["rotation"].visible = k != ShapePlan.Kind.CIRCLE
	rows["rotation_buttons"].visible = k != ShapePlan.Kind.CIRCLE
	rows["rotation_slider"].visible = k == ShapePlan.Kind.CONE
	rows["sector_buttons"].visible = k == ShapePlan.Kind.CONE
	fit_to_window.call_deferred()

func popup_visible() -> bool:
	return (is_instance_valid(_kind_field) and _kind_field.is_popup_open()) or (is_instance_valid(_anchor_field) and _anchor_field.is_popup_open())

func close_popups() -> bool:
	var closed := false
	if is_instance_valid(_kind_field) and _kind_field.is_popup_open():
		_kind_field.close_popup()
		closed = true
	if is_instance_valid(_anchor_field) and _anchor_field.is_popup_open():
		_anchor_field.close_popup()
		closed = true
	return closed

func close() -> void:
	close_popups()
	super.close()
