extends "res://ui/components/utility_panel.gd"

const Typography = preload("res://ui/theme/typography.gd")

signal parameters_changed(parameters: Dictionary)
signal action_requested(action: String)

const ShapePlan = preload("res://scripts/shape_plan.gd")
var kind: OptionButton
var fields: Dictionary = {}
var rows: Dictionary = {}
var actions: Dictionary = {}
var status: Label
var instruction: Label
var updating := false
var rotation_slider: HSlider
var anchor: OptionButton
var dimensions: BoxContainer

func _ready() -> void:
	super._ready()
	configure_editor()
	kind = OptionButton.new()
	for title in ["圆形", "扇形", "矩形", "线形"]:
		kind.add_item(title)
	kind.custom_minimum_size.y = 44
	EditorLayout.field(content(), "形状").add_child(kind)
	kind.item_selected.connect(func(index: int):
		if updating:
			return
		if index == ShapePlan.Kind.LINE:
			fields["length"].set_value_no_signal(30)
			fields["width"].set_value_no_signal(5)
		_update_rows()
		_emit_parameters()
	)
	_add_field("radius", "半径（英尺）", 1, 300, 10)
	_add_field("length", "长度（英尺）", 1, 300, 15)
	_add_field("width", "宽度（英尺）", 1, 300, 15)
	var anchor_row := EditorLayout.field(content(), "定位方式")
	rows["anchor"] = anchor_row
	anchor = OptionButton.new()
	anchor.add_item("角点对齐")
	anchor.add_item("中心对齐")
	anchor.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	anchor_row.add_child(anchor)
	anchor.item_selected.connect(func(_index: int): _emit_parameters())
	_add_field("angle", "张角（度）", 1, 180, 90)
	_add_field("rotation", "方向（度）", 0, 359, 0)
	rotation_slider = HSlider.new()
	rotation_slider.min_value = 0
	rotation_slider.max_value = 359
	rotation_slider.step = 1
	rotation_slider.custom_minimum_size.y = 28
	rotation_slider.tooltip_text = "调整扇形朝向，张角保持不变"
	content().add_child(rotation_slider)
	rows["rotation_slider"] = rotation_slider
	rotation_slider.value_changed.connect(func(value: float):
		if not updating:
			fields["rotation"].value = value
	)
	var rotation_buttons := HBoxContainer.new()
	rotation_buttons.add_theme_constant_override("separation", 8)
	content().add_child(rotation_buttons)
	rows["rotation_buttons"] = rotation_buttons
	for offset in [-15, 15]:
		var amount: int = offset
		var button := GoStyle.button("%+d°" % amount, func(): fields["rotation"].value = fposmod(fields["rotation"].value + amount, 360.0), GoStyle.Tone.COMPACT)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		rotation_buttons.add_child(button)
	var sector_buttons := GridContainer.new()
	sector_buttons.columns = 2
	sector_buttons.add_theme_constant_override("h_separation", 8)
	sector_buttons.add_theme_constant_override("v_separation", 8)
	content().add_child(sector_buttons)
	rows["sector_buttons"] = sector_buttons
	for offset in [-45, 45, -60, 60]:
		var amount: int = offset
		var button := GoStyle.button("%+d°" % amount, func(): fields["rotation"].value = fposmod(fields["rotation"].value + amount, 360.0), GoStyle.Tone.COMPACT)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.tooltip_text = "相对当前朝向旋转 %+d°" % amount
		sector_buttons.add_child(button)
	status = editor_status
	instruction = EditorStyle.text("", Typography.CAPTION, true)
	content().add_child(instruction)
	instruction.hide()
	var buttons := VBoxContainer.new()
	buttons.add_theme_constant_override("separation", BoardUiStyle.CONTENT_GAP)
	editor_footer.add_child(buttons)
	for item in [["new", "创建"]]:
		var action: String = item[0]
		var button := GoStyle.button(item[1], func(): action_requested.emit(action), GoStyle.Tone.PRIMARY)
		button.custom_minimum_size.y = 44
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		buttons.add_child(button)
		actions[action] = button
	dimensions = EditorLayout.pair(content())
	content().move_child(dimensions, rows["length"].get_index())
	rows["length"].reparent(dimensions)
	rows["width"].reparent(dimensions)
	set_parameters(ShapePlan.defaults())

func _add_field(key: String, title: String, minimum: float, maximum: float, initial: float) -> void:
	var row := EditorLayout.field(content(), title)
	rows[key] = row
	var input := SpinBox.new()
	input.min_value = minimum
	input.max_value = maximum
	input.step = 1
	input.value = initial
	input.custom_minimum_size.y = 44
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(input)
	fields[key] = input
	input.value_changed.connect(func(_value: float): _emit_parameters())

func parameters() -> Dictionary:
	var values := {"kind": kind.selected, "anchor": anchor.selected}
	for key in fields:
		values[key] = fields[key].value
	return values

func set_parameters(data: Dictionary) -> void:
	updating = true
	kind.select(int(data["kind"]))
	anchor.select(int(data.get("anchor", 0)))
	for key in fields:
		fields[key].set_value_no_signal(float(data[key]))
	rotation_slider.set_value_no_signal(float(data["rotation"]))
	updating = false
	_update_rows()

func set_state(selected: bool, has_draft: bool, moving: bool, ready: bool, count: int, busy: bool) -> void:
	actions["new"].disabled = count >= ShapePlan.MAX_SHAPES or busy
	set_editor_status("%s · %d / %d 个形状" % ["移动中" if moving else ("修改中" if selected else ("创建中" if has_draft else "就绪")), count, ShapePlan.MAX_SHAPES])

func _emit_parameters() -> void:
	if not updating:
		rotation_slider.set_value_no_signal(float(fields["rotation"].value))
		parameters_changed.emit(parameters())

func _update_rows() -> void:
	dimensions.visible = kind.selected != ShapePlan.Kind.CIRCLE
	rows["radius"].visible = kind.selected == ShapePlan.Kind.CIRCLE
	rows["length"].visible = kind.selected != ShapePlan.Kind.CIRCLE
	rows["width"].visible = kind.selected in [ShapePlan.Kind.RECTANGLE, ShapePlan.Kind.LINE]
	rows["anchor"].visible = kind.selected == ShapePlan.Kind.RECTANGLE
	rows["angle"].visible = kind.selected == ShapePlan.Kind.CONE
	rows["rotation"].visible = kind.selected != ShapePlan.Kind.CIRCLE
	rows["rotation_buttons"].visible = kind.selected != ShapePlan.Kind.CIRCLE
	rows["rotation_slider"].visible = kind.selected == ShapePlan.Kind.CONE
	rows["sector_buttons"].visible = kind.selected == ShapePlan.Kind.CONE
	fit_to_window.call_deferred()

func popup_visible() -> bool:
	return (kind != null and kind.get_popup().visible) or (anchor != null and anchor.get_popup().visible)

func close() -> void:
	if kind != null: kind.get_popup().hide()
	if anchor != null: anchor.get_popup().hide()
	super.close()
