extends VBoxContainer
const Style = preload("res://ui/components/page_style.gd")
var side: OptionButton
var slider: HSlider
var amount: SpinBox
var note: Label
func _ready() -> void:
	add_theme_constant_override("separation",8)
	add_child(Style.text("前摄位置",14,true))
	side = OptionButton.new()
	for title in ["自动识别","左侧","右侧"]: side.add_item(title)
	Style.button(side)
	add_child(side)
	add_child(Style.text("前摄侧缩进 · dp",14,true))
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",12)
	add_child(row)
	slider = HSlider.new()
	slider.min_value = 0
	slider.max_value = 96
	slider.step = 1
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	slider.custom_minimum_size.y = 48
	row.add_child(slider)
	amount = SpinBox.new()
	amount.min_value = 0
	amount.max_value = 96
	amount.step = 1
	amount.custom_minimum_size = Vector2(100,48)
	row.add_child(amount)
	var reset := Button.new()
	reset.text = "恢复自动"
	Style.card_button(reset)
	add_child(reset)
	note = Style.text("",14,true)
	add_child(note)
	side.item_selected.connect(func(index: int): Mobile.preferences.change(["auto","left","right"][index],Mobile.preferences.inset_dp,int(Mobile.native_info.get("rotation",0))))
	slider.value_changed.connect(_change)
	amount.value_changed.connect(_change)
	reset.pressed.connect(func(): Mobile.preferences.change("auto",-1,int(Mobile.native_info.get("rotation",0))))
	Mobile.changed.connect(_sync)
	_sync()
func _change(value: float) -> void:
	Mobile.preferences.change("auto" if Mobile.preferences.side=="auto" else Mobile.camera_side,value,int(Mobile.native_info.get("rotation",0)))
func _sync() -> void:
	side.select(["auto","left","right"].find("auto" if Mobile.preferences.side=="auto" else Mobile.camera_side))
	var value: float = Mobile.auto_camera_dp if Mobile.preferences.inset_dp<0 else Mobile.preferences.inset_dp
	slider.set_value_no_signal(value)
	if not amount.get_line_edit().has_focus(): amount.set_value_no_signal(value)
	note.text = Mobile.preferences.error
	note.visible = not note.text.is_empty()
