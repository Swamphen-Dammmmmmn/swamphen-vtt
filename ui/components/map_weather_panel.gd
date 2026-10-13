extends VBoxContainer

const Style = preload("res://ui/components/page_style.gd")
const Layout = preload("res://ui/components/editor_layout.gd")
const Weather = preload("res://scripts/map_weather.gd")
const ColorWell = preload("res://ui/components/color_well.gd")
const DirectionPreview = preload("res://ui/components/light_direction_preview.gd")
const PresetPreview = preload("res://ui/components/weather_preset_preview.gd")
signal changed
var popup_host: Control
var data: Dictionary
var angle_inputs: Dictionary = {}
var adjustment_inputs: Dictionary = {}
var wells: Array = []
var tool := ""
var direction_preview: SubViewportContainer
var preset_buttons: Array = []
var time_label: Label
var weather_label: Label
var page_cache: Dictionary = {}
var field_inputs: Array = []
var color_inputs: Array = []
var shadow_toggle: CheckButton

func show_tool(key: String, values: Dictionary) -> void:
	hide_popups()
	cancel_interaction()
	if page_cache.has(tool):
		for entry in page_cache[tool]["children"]:
			entry[1] = entry[0].visible
			entry[0].hide()
	data = values
	tool = key
	if page_cache.has(key):
		_restore_page(page_cache[key])
		return
	var previous_children := get_children()
	wells = []
	angle_inputs = {}
	adjustment_inputs = {}
	preset_buttons = []
	field_inputs = []
	color_inputs = []
	shadow_toggle = null
	direction_preview = null
	time_label = null
	weather_label = null
	add_theme_constant_override("separation",12)
	match key:
		"weather_atmosphere":
			time_label = Style.text("时间氛围",18)
			add_child(time_label)
			_presets("time_preset",["morning","noon","evening"])
			weather_label = Style.text("天气氛围",18)
			add_child(weather_label)
			_presets("weather_preset",["clear","cloudy","overcast"])
			_adjustment(self,"明暗","brightness",0.01)
			_adjustment(self,"冷暖","warmth",0.01)
			_adjustment(self,"天气强度","weather_strength",0.01)
			_sync_presets()
		"weather_sky":
			_color(self,"天空顶部","sky","top_color")
			_color(self,"地平线","sky","bottom_color")
			var detail := _details("详细调整")
			_number(detail,"基础天空亮度","sky","brightness",0.01)
			_number(detail,"晴天基础云量","sky","clouds",0.01)
			_number(detail,"晴天高层云量","sky","high_clouds",0.01)
		"weather_light":
			direction_preview = DirectionPreview.new()
			add_child(direction_preview)
			direction_preview.sync(data["light"]["azimuth"],data["light"]["altitude"])
			direction_preview.direction_changed.connect(func(azimuth: float, altitude: float):
				data["light"]["azimuth"] = azimuth
				data["light"]["altitude"] = altitude
				_base_changed()
				sync_angles()
			)
			var pair := Layout.pair(self)
			_number(pair,"朝向 · °","light","azimuth",0.1)
			_number(pair,"高度 · °","light","altitude",0.1)
			_color(self,"基础光照颜色","light","color")
			_number(self,"基础光照强度","light","energy",0.01)
			var detail := _details("详细调整")
			_color(detail,"基础补光颜色","light","ambient_color")
			_number(detail,"基础补光强度","light","ambient_energy",0.01)
			var toggle := CheckButton.new()
			shadow_toggle = toggle
			toggle.text = "显示阴影"
			toggle.button_pressed = data["light"]["shadows"]
			detail.add_child(toggle)
			toggle.toggled.connect(func(on: bool): data["light"]["shadows"] = on; _base_changed())
		"weather_wind":
			for item in [["风向 · °","wind_direction",1.0],["基础风强","wind_strength",0.01],["阵风强度","gust_strength",0.01]]:
				_number(self,item[0],"wind",item[1],item[2])
			var detail := _details("详细调整")
			for item in [["阵风频率 · 次/秒","gust_frequency",0.01],["风波宽度 · 英尺","wave_width_feet",1.0],["传播速度 · 英尺/秒","wave_speed_feet",0.1],["摆动周期 · 秒","sway_period",0.1],["摆动幅度","sway_amplitude",0.01]]:
				_number(detail,item[0],"wind",item[1],item[2])
	var children: Array = []
	for child in get_children():
		if not previous_children.has(child): children.append([child,child.visible])
	page_cache[key] = {"children":children,"wells":wells,"angles":angle_inputs,"adjustments":adjustment_inputs,"presets":preset_buttons,"direction":direction_preview,"time_label":time_label,"weather_label":weather_label,"fields":field_inputs,"colors":color_inputs,"shadows":shadow_toggle}

func _restore_page(state: Dictionary) -> void:
	wells = state["wells"]
	angle_inputs = state["angles"]
	adjustment_inputs = state["adjustments"]
	preset_buttons = state["presets"]
	direction_preview = state["direction"]
	time_label = state["time_label"]
	weather_label = state["weather_label"]
	field_inputs = state["fields"]
	color_inputs = state["colors"]
	shadow_toggle = state["shadows"]
	for item in field_inputs: item["input"].set_value_no_signal(data[item["group"]][item["key"]])
	for item in color_inputs: item["well"].color = Color(data[item["group"]][item["key"]])
	if is_instance_valid(shadow_toggle): shadow_toggle.set_pressed_no_signal(data["light"]["shadows"])
	for entry in state["children"]: entry[0].visible = entry[1]
	sync_angles()
	_sync_presets()

func _presets(group: String, keys: Array) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	add_child(row)
	var choices := ButtonGroup.new()
	for key: String in keys:
		var button := Button.new()
		Style.card_button(button,106)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.toggle_mode = true
		button.button_group = choices
		row.add_child(button)
		var margin := MarginContainer.new()
		margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
		button.add_child(margin)
		margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
		for edge in ["left","right","top","bottom"]: margin.add_theme_constant_override("margin_"+edge,6)
		var body := Style.column(6)
		body.mouse_filter = Control.MOUSE_FILTER_IGNORE
		margin.add_child(body)
		var preview := PresetPreview.new()
		preview.data = _preset_data(group,key)
		body.add_child(preview)
		var label := Style.text(Weather.TIMES[key] if group=="time_preset" else Weather.CONDITIONS[key],14)
		label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		label.autowrap_mode = TextServer.AUTOWRAP_OFF
		body.add_child(label)
		preset_buttons.append({"button":button,"preview":preview,"group":group,"key":key})
		button.pressed.connect(func():
			if group=="time_preset": Weather.select_time(data,key)
			else: data["weather_preset"] = key
			changed.emit()
			_sync_presets()
		)

func _preset_data(group: String, key: String) -> Dictionary:
	var result := data.duplicate(true)
	if group=="time_preset":
		Weather.select_time(result,key)
		result["weather_preset"] = "clear"
	else: result["weather_preset"] = key
	return result

func _sync_presets() -> void:
	for key in adjustment_inputs:
		adjustment_inputs[key]["input"].set_value_no_signal(data[key])
		adjustment_inputs[key]["slider"].set_value_no_signal(data[key])
	if is_instance_valid(time_label): time_label.text = "时间氛围 · "+Weather.TIMES[data["time_preset"]]
	if is_instance_valid(weather_label): weather_label.text = "天气氛围 · "+Weather.CONDITIONS[data["weather_preset"]]
	for item in preset_buttons:
		item["button"].set_pressed_no_signal(data[item["group"]]==item["key"])
		item["preview"].configure(_preset_data(item["group"],item["key"]))

func _details(title: String) -> VBoxContainer:
	var fold := Button.new()
	fold.text = "›  "+title
	fold.alignment = HORIZONTAL_ALIGNMENT_LEFT
	fold.toggle_mode = true
	Style.button(fold)
	add_child(fold)
	var body := Style.column(12)
	add_child(body)
	body.hide()
	fold.toggled.connect(func(on: bool):
		fold.text = ("⌄  " if on else "›  ")+title
		body.visible = on
		if on: Style.Motion.fade_in(body)
	)
	return body

func _number(parent: Control, title: String, group: String, key: String, interval: float) -> void:
	var field := Layout.field(parent,title)
	field.get_child(0).autowrap_mode = TextServer.AUTOWRAP_OFF
	var input := SpinBox.new()
	input.min_value = Weather.LIMITS[group][key][0]
	input.max_value = Weather.LIMITS[group][key][1]
	input.step = interval
	input.value = data[group][key]
	input.custom_minimum_size.y = 44
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.add_child(input)
	field_inputs.append({"group":group,"key":key,"input":input})
	if key in ["azimuth","altitude"]: angle_inputs[key] = input
	input.value_changed.connect(func(value: float):
		data[group][key] = value
		if group=="wind": changed.emit()
		else:
			_base_changed()
			sync_angles()
	)

func _adjustment(parent: Control, title: String, key: String, interval: float) -> void:
	var field := Layout.field(parent,title)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation",8)
	field.add_child(row)
	var slider := HSlider.new()
	slider.min_value = Weather.ADJUSTMENTS[key][0]
	slider.max_value = Weather.ADJUSTMENTS[key][1]
	slider.step = interval
	slider.value = data[key]
	slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(slider)
	var input := SpinBox.new()
	input.min_value = Weather.ADJUSTMENTS[key][0]
	input.max_value = Weather.ADJUSTMENTS[key][1]
	input.step = interval
	input.value = data[key]
	adjustment_inputs[key] = {"input":input,"slider":slider}
	input.custom_minimum_size = Vector2(88,44)
	row.add_child(input)
	slider.value_changed.connect(func(value: float): input.value = value)
	input.value_changed.connect(func(value: float):
		data[key] = value
		if key!="weather_strength": data["time_preset"] = "custom"
		changed.emit()
		_sync_presets()
	)

func _color(parent: Control, title: String, group: String, key: String) -> void:
	var button := ColorWell.new()
	button.popup_host = popup_host
	button.color = Color(data[group][key])
	Style.button(button)
	Layout.field(parent,title).add_child(button)
	wells.append(button)
	color_inputs.append({"group":group,"key":key,"well":button})
	button.color_changed.connect(func(value: Color): data[group][key] = value.to_html(false); _base_changed())

func _base_changed() -> void:
	data["time_preset"] = "custom"
	changed.emit()

func sync_angles() -> void:
	for key in angle_inputs: angle_inputs[key].set_value_no_signal(data["light"][key])
	if is_instance_valid(direction_preview): direction_preview.sync(data["light"]["azimuth"],data["light"]["altitude"])

func cancel_interaction() -> void:
	if is_instance_valid(direction_preview): direction_preview.cancel()

func blocked() -> bool:
	return color_open() or (is_instance_valid(direction_preview) and direction_preview.interacting())

func color_open() -> bool:
	for well in wells:
		if is_instance_valid(well.panel) and well.panel.visible: return true
	return false

func hide_popups() -> void:
	for well in wells:
		if is_instance_valid(well.panel) and well.panel.visible: well.panel.close()
