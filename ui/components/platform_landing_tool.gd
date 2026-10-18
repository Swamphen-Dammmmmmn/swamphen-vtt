extends VBoxContainer

const Typography = preload("res://ui/theme/typography.gd")
const Style = preload("res://ui/components/page_style.gd")
const Layout = preload("res://ui/components/editor_layout.gd")
const Landing = preload("res://scripts/platform_landing.gd")
signal state_changed
signal cells_changed
var editor: Control
var page: Control
var preview: Control
var values: Dictionary
var status: Label
var add_button: Button
var remove_button: Button
var summary: Label
var draft := {}
var operation := "add"
var dragging := false
var anchor := Vector2i.ZERO
var active := false
var method := "brush"
var brush_size := 1
var last_cell = null
var brush_field: Control

func _ready() -> void:
	add_theme_constant_override("separation",12)
	var commands := Layout.pair(self)
	add_button = _button("允许摆放")
	remove_button = _button("禁止摆放")
	commands.add_child(add_button)
	commands.add_child(remove_button)
	add_button.pressed.connect(func(): _choose_operation("add"))
	remove_button.pressed.connect(func(): _choose_operation("remove"))
	var method_input := OptionButton.new()
	method_input.custom_minimum_size.y = 44
	method_input.add_item("画笔")
	method_input.add_item("矩形")
	Layout.field(self,"范围方式").add_child(method_input)
	method_input.item_selected.connect(func(index: int):
		pause_gesture()
		method = "brush" if index==0 else "rectangle"
		_refresh()
	)
	brush_field = Layout.field(self,"画笔边长 · 格")
	var size_input := SpinBox.new()
	size_input.min_value = 1
	size_input.max_value = 20
	size_input.step = 1
	size_input.value = brush_size
	size_input.custom_minimum_size.y = 44
	brush_field.add_child(size_input)
	size_input.value_changed.connect(func(value: float):
		pause_gesture()
		brush_size = roundi(value)
	)
	summary = Style.text("",Typography.CAPTION,true)
	add_child(summary)

func attach(data: Dictionary) -> void:
	values = data
	Landing.normalize(values)
	_update_summary()
	if active: _refresh()

func _button(title: String) -> Button:
	var button := Button.new()
	button.text = title
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Style.card_button(button)
	return button

func set_active(enabled: bool) -> void:
	if not enabled: pause_gesture()
	active = enabled
	visible = enabled
	if active: _refresh()

func _update_summary() -> void:
	summary.text = "可摆放：%d 格，共 %d 格" % [values.get("landing_cells",[]).size(),Landing.bounds(values).get_area()]

func _choose_operation(kind: String) -> void:
	pause_gesture()
	operation = kind
	_refresh()

func _refresh() -> void:
	if not active: return
	Style.button(add_button,operation=="add")
	Style.button(remove_button,operation=="remove")
	brush_field.visible = method=="brush"
	Layout.set_status(status, "")
	state_changed.emit()

func handle_pointer(event: InputEvent, over_ui: bool) -> bool:
	if not active: return false
	if method=="brush": return _handle_brush(event,over_ui)
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed and dragging:
		var cell = null if over_ui else _brush_point(event.position)
		if cell!=null:
			_drag_to(cell)
			if Landing.changed_count(values,draft,operation=="add")>0:
				Landing.apply_rectangle(values,draft,operation=="add")
				preview.show_landing_cells(values["landing_cells"])
				_update_summary()
				cells_changed.emit()
		pause_gesture()
		return true
	if event is InputEventMouseMotion and dragging:
		var point = null if over_ui else preview.top_point(event.position)
		if point!=null:
			_drag_to(_cell(point))
		else:
			preview.show_landing_draft({})
		return true
	if over_ui: return false
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		var cell = _brush_point(event.position)
		if cell==null: return false
		anchor = cell
		dragging = true
		_drag_to(cell)
		return true
	return false

func _drag_to(cell: Vector2i) -> void:
	# Limit the pointer relative to the anchor before building the rectangle in either direction.
	var end := Vector2i(clampi(cell.x,anchor.x-199,anchor.x+199),clampi(cell.y,anchor.y-199,anchor.y+199))
	var start := Vector2i(mini(anchor.x,end.x),mini(anchor.y,end.y))
	var finish := Vector2i(maxi(anchor.x,end.x)+1,maxi(anchor.y,end.y)+1)
	var rect := Rect2i(start,finish-start).intersection(Landing.bounds(values))
	draft = {"x":rect.position.x,"z":rect.position.y,"width":rect.size.x,"length":rect.size.y}
	preview.show_landing_draft(draft,false,false,operation=="remove")

func pause_gesture() -> void:
	dragging = false
	last_cell = null
	draft = {}
	preview.show_landing_brush(Rect2i())
	preview.show_landing_draft({})

func blocked() -> bool:
	return false

func _cell(point: Vector2) -> Vector2i:
	var local: Vector2 = (point-values["grid_origin_feet"])/5.0
	return Vector2i(floori(local.x),floori(local.y))

func _brush_rect(cell: Vector2i) -> Rect2i:
	var offset := floori((brush_size-1)/2.0)
	return Rect2i(cell-Vector2i(offset,offset),Vector2i(brush_size,brush_size)).intersection(Landing.bounds(values))

func _brush_point(screen: Vector2):
	var point = preview.top_point(screen)
	if point==null: return null
	var cell := _cell(point)
	return cell if Landing.bounds(values).has_point(cell) else null

func _stamp(cell: Vector2i) -> bool:
	var rect := _brush_rect(cell)
	var region := {"x":rect.position.x,"z":rect.position.y,"width":rect.size.x,"length":rect.size.y}
	if Landing.changed_count(values,region,operation=="add")==0: return false
	Landing.apply_rectangle(values,region,operation=="add")
	return true

func _paint_cells(cell: Vector2i) -> void:
	var changed := false
	if last_cell==null:
		changed = _stamp(cell)
	else:
		var from: Vector2i = last_cell
		var steps := maxi(absi(cell.x-from.x),absi(cell.y-from.y))
		for i in range(steps+1):
			var t := float(i)/maxi(1,steps)
			changed = _stamp(Vector2i(roundi(lerpf(from.x,cell.x,t)),roundi(lerpf(from.y,cell.y,t)))) or changed
	last_cell = cell
	if changed:
		preview.show_landing_cells(values["landing_cells"])
		_update_summary()
		cells_changed.emit()

func _handle_brush(event: InputEvent, over_ui: bool) -> bool:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed and dragging:
		pause_gesture()
		return true
	if event is InputEventMouseMotion and dragging:
		var cell = null if over_ui else _brush_point(event.position)
		if cell==null:
			last_cell = null
			preview.show_landing_brush(Rect2i())
		else:
			_paint_cells(cell)
		return true
	if over_ui: return false
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		var cell = _brush_point(event.position)
		if cell==null: return false
		dragging = true
		last_cell = null
		_paint_cells(cell)
		return true
	return false

func _process(_delta: float) -> void:
	if not active or method!="brush": return
	var point := get_global_mouse_position()
	if editor._camera_blocked() or editor.rotating or editor._over_ui(point):
		preview.show_landing_brush(Rect2i())
		return
	var cell = _brush_point(point)
	preview.show_landing_brush(Rect2i() if cell==null else _brush_rect(cell),operation=="remove")
