extends "res://ui/components/utility_panel.gd"

signal values_changed(values: Array)
signal reset_requested
signal interval_changed(value: float)
const Style = preload("res://ui/components/page_style.gd")
var mode := ""
var inputs: Array[LineEdit] = []
var labels: Array[Label] = []
var rows: Array[VBoxContainer] = []
var syncing := false
var reset_button: Button
var interval_input: LineEdit
var interval_label: Label
var intervals := {"position": "0.1", "rotation": "5", "scale": "0.1"}
var round_base := false

func _ready() -> void:
	preferred_width = 320
	super._ready()
	configure_editor()
	for index in range(3):
		var row := VBoxContainer.new()
		row.add_theme_constant_override("separation", EditorLayout.LABEL_GAP)
		content().add_child(row)
		var label := Style.text("", 14, true)
		row.add_child(label)
		var input := LineEdit.new()
		input.max_length = 32
		input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
		input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		row.add_child(input)
		inputs.append(input)
		labels.append(label)
		rows.append(row)
		input.text_changed.connect(func(_text: String):
			if not syncing:
				if mode == "scale" and round_base and index in [0, 2]:
					syncing = true
					inputs[2 if index == 0 else 0].text = inputs[index].text
					syncing = false
				var values: Array = []
				for field in inputs: values.append(field.text)
				values_changed.emit(values)
				_publish_value_status()
		)
	var interval_row := VBoxContainer.new()
	interval_row.add_theme_constant_override("separation", EditorLayout.LABEL_GAP)
	content().add_child(interval_row)
	interval_label = Style.text("拖动间隔", 14, true)
	interval_row.add_child(interval_label)
	interval_input = LineEdit.new()
	interval_input.max_length = 32
	interval_input.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	interval_input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	interval_row.add_child(interval_input)
	interval_input.text_changed.connect(func(value: String):
		if not syncing:
			intervals[mode] = value
			_publish_interval()
	)
	reset_button = Button.new()
	Style.card_button(reset_button)
	reset_button.pressed.connect(func(): reset_requested.emit())
	editor_footer.add_child(reset_button)
	_style_content.call_deferred()

func open_transform(next_mode: String, values: Array, at: Vector2, circle := false) -> void:
	mode = next_mode
	round_base = circle
	$Shell/Header/Row/Title.text = {"position": "调整位置", "rotation": "调整旋转", "scale": "调整尺寸"}[mode]
	reset_button.text = {"position": "重置位置", "rotation": "重置旋转", "scale": "恢复本次尺寸"}[mode]
	var titles: Array = ["X · 左右 英尺", "Y · 上下 英尺", "Z · 前后 英尺"]
	if mode == "rotation": titles = ["X · 前后倾斜 °", "Y · 转向 °", "Z · 左右倾斜 °"]
	elif mode == "scale": titles = ["直径 · 英尺" if circle else "宽 · 英尺", "厚度 · 英尺", "长 · 英尺"]
	for index in range(3):
		rows[index].visible = not (mode == "scale" and circle and index == 2)
		labels[index].text = titles[index]
	interval_label.text = "拖动间隔 · °" if mode == "rotation" else "拖动间隔 · 英尺"
	syncing = true
	interval_input.text = intervals[mode]
	syncing = false
	_publish_interval()
	sync_values(values)
	place_initial(at)
	open()
	Style.Motion.fade_in(self)

func _publish_interval() -> void:
	var raw := interval_input.text.strip_edges()
	var value := raw.to_float() if raw.is_valid_float() else 0.0
	var valid := is_finite(value) and value > 0
	interval_input.add_theme_color_override("font_color", Color("334155") if valid else Color("b33c3c"))
	interval_input.tooltip_text = "" if valid else "拖动间隔须为有限正数，修正后可拖动操作柄。"
	_publish_value_status()
	interval_changed.emit(value if valid else 0.0)

func sync_values(values: Array) -> void:
	syncing = true
	for index in range(values.size()): inputs[index].text = str(values[index])
	syncing = false
	_publish_value_status()

func _publish_value_status() -> void:
	var message := ""
	for index in range(inputs.size()):
		if not rows[index].visible: continue
		var raw := inputs[index].text.strip_edges()
		var valid := raw.is_valid_float() and is_finite(raw.to_float()) and (mode != "scale" or raw.to_float() > 0)
		var error := "" if valid else labels[index].text + ("须为有限正数" if mode == "scale" else "须为有限数值")
		EditorLayout.field_error(inputs[index], error)
		if message.is_empty(): message = error
	var interval := interval_input.text.strip_edges()
	if message.is_empty() and (not interval.is_valid_float() or not is_finite(interval.to_float()) or interval.to_float() <= 0): message = "拖动间隔须为有限正数"
	set_editor_status("数值与操作柄同步" if message.is_empty() else message, not message.is_empty())
