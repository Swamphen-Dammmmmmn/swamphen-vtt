extends RefCounted

const Typography = preload("res://ui/theme/typography.gd")

const Style = preload("res://ui/components/page_style.gd")
const Layout = preload("res://ui/components/editor_layout.gd")

static func populate(body: VBoxContainer, preview: Control, map_mode: bool, normal: float, fast: float, speed_changed: Callable, fit: Callable) -> void:
	body.add_child(Style.text("网格与区域",Typography.BODY))
	if map_mode:
		_toggle(body,"地图参考网格",preview.map_grid.visible,preview.set_map_grid)
	_toggle(body,"地台参考网格",preview.grid_shown,preview.set_grid_visible)
	_toggle(body,"可摆放区域高亮",preview.landing_highlight,preview.set_landing_highlight)
	var fold := Button.new()
	fold.text = "镜头速度"
	GoStyle.apply_icon(fold,GoIconSet.CHEVRON_RIGHT,18)
	fold.alignment = HORIZONTAL_ALIGNMENT_LEFT
	fold.toggle_mode = true
	Style.button(fold)
	body.add_child(fold)
	var section := Style.column(12)
	body.add_child(section)
	for accelerated in [false,true]:
		var input := SpinBox.new()
		input.min_value = 1
		input.max_value = 5000
		input.step = 1
		input.value = fast if accelerated else normal
		input.custom_minimum_size.y = 44
		input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var field := Layout.field(section,("加速速度 · 英尺/秒" if Mobile.enabled else "Shift 加速速度 · 英尺/秒") if accelerated else "正常速度 · 英尺/秒")
		field.get_child(0).autowrap_mode = TextServer.AUTOWRAP_OFF
		field.add_child(input)
		input.value_changed.connect(func(value: float): speed_changed.call(accelerated,value))
	section.hide()
	fold.toggled.connect(func(open: bool):
		GoStyle.apply_icon(fold,GoIconSet.CHEVRON_DOWN if open else GoIconSet.CHEVRON_RIGHT,18)
		section.visible = open
		if open: Style.Motion.fade_in(section)
		fit.call_deferred()
	)

static func _toggle(body: VBoxContainer, title: String, shown: bool, changed: Callable) -> void:
	var row := HBoxContainer.new()
	body.add_child(row)
	var label := Style.text(title)
	label.autowrap_mode = TextServer.AUTOWRAP_OFF
	label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(label)
	var toggle := CheckButton.new()
	toggle.button_pressed = shown
	toggle.custom_minimum_size.y = 44
	toggle.tooltip_text = title
	row.add_child(toggle)
	toggle.toggled.connect(changed)
