extends "res://ui/components/build_toolbar.gd"

func _init() -> void:
	categories = ["地图","天气"]
	defaults = ["map_select","weather_atmosphere"]

func _build_body() -> void:
	for child in body.get_children():
		body.remove_child(child)
		child.queue_free()
	buttons.clear()
	var group := ButtonGroup.new()
	var items: Array = [["map_select","选择地台",GoIconSet.TARGET],["map_properties","地图属性",GoIconSet.EDIT],["add_platform","添加地台",GoIconSet.PLUS],["platforms","地台列表",GoIconSet.MAP]] if category_index==0 else [["weather_atmosphere","氛围",GoIconSet.GRID],["weather_light","光照",GoIconSet.SUN],["weather_sky","天空",GoIconSet.MAP],["weather_wind","风",GoIconSet.SETTINGS]]
	if Mobile.enabled: items.append(["mobile_camera","镜头",GoIconSet.TARGET])
	for item in items:
		var button := _button(item[1],item[2],body)
		button.toggle_mode = true
		button.button_group = group
		button.button_pressed = item[0]==defaults[category_index]
		buttons[item[0]] = button
		button.pressed.connect(func(): tool_selected.emit(item[0]))
