extends VBoxContainer
const Style = preload("res://ui/components/page_style.gd")
const Layout = preload("res://ui/components/editor_layout.gd")
signal state_changed
var editor: Control
var preview: Control
var status: Label
var active := false
var dragging := false
var target := 1
var diameter := 12.0
var strength := 0.5
var softness := 0.7
var method := "brush"
var method_selector: OptionButton
var brush_settings: VBoxContainer
var anchor := Vector2.ZERO
var rectangle := Rect2()
var selector: OptionButton
var undo_button: Button
var redo_button: Button

func _ready() -> void:
	add_theme_constant_override("separation",12)
	selector = OptionButton.new()
	selector.custom_minimum_size.y = 44
	for title in ["草地","沙漠","沙滩","水面","恢复默认地面"]: selector.add_item(title)
	selector.select(target)
	Layout.field(self,"地面类型").add_child(selector)
	selector.item_selected.connect(func(index: int):
		pause_gesture()
		target = index if index<4 else -1
	)
	method_selector = OptionButton.new()
	method_selector.custom_minimum_size.y = 44
	for title in ["画笔","矩形","整片填充","吸取"]: method_selector.add_item(title)
	Layout.field(self,"绘制工具").add_child(method_selector)
	method_selector.item_selected.connect(func(index: int): _set_method(["brush","rectangle","fill","sample"][index]))
	brush_settings = Style.column(12)
	add_child(brush_settings)
	_number("画笔大小 · 英尺",2,100,1,diameter,func(value: float): diameter = value,brush_settings)
	var pair := Layout.pair(brush_settings)
	_number("涂抹力度",0,1,0.05,strength,func(value: float): strength = value,pair)
	_number("边缘过渡",0,1,0.05,softness,func(value: float): softness = value,pair)
	var history := Layout.pair(self)
	undo_button = _button("撤销",false)
	redo_button = _button("重做",false)
	history.add_child(undo_button)
	history.add_child(redo_button)
	undo_button.pressed.connect(func():
		pause_gesture()
		preview.paint.undo()
	)
	redo_button.pressed.connect(func():
		pause_gesture()
		preview.paint.redo()
	)
	preview.paint.changed.connect(_refresh)
	_refresh()

func _number(title: String, low: float, high: float, step: float, initial: float, callback: Callable, parent: Control = null) -> void:
	var input := SpinBox.new()
	input.min_value = low
	input.max_value = high
	input.step = step
	input.value = initial
	input.custom_minimum_size.y = 44
	input.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Layout.field(self if parent==null else parent,title).add_child(input)
	input.value_changed.connect(func(value: float):
		pause_gesture()
		callback.call(value)
	)

func _button(title: String, primary: bool) -> Button:
	var button := Button.new()
	button.text = title
	button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	Style.card_button(button)
	if primary: Style.button(button,true)
	return button

func set_active(enabled: bool) -> void:
	active = enabled
	if not enabled:
		pause_gesture()
		preview.show_brush(null,diameter,softness)
	visible = enabled
	_refresh()

func _refresh() -> void:
	if not is_instance_valid(undo_button): return
	undo_button.disabled = preview.paint.undo_stack.is_empty() or dragging
	redo_button.disabled = preview.paint.redo_stack.is_empty() or dragging
	if active and is_instance_valid(status):
		Layout.set_status(status, "")
	brush_settings.visible = method=="brush"
	state_changed.emit()

func _point(screen: Vector2):
	var point = preview.top_point(screen)
	if point==null or not preview.paint.area.has_point(point/5.0): return null
	return point

func handle_pointer(event: InputEvent, over_ui: bool) -> bool:
	if not active: return false
	if method!="brush": return _handle_other(event,over_ui)
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed and dragging:
		pause_gesture()
		return true
	if event is InputEventMouseMotion and dragging:
		var point = null if over_ui else _point(event.position)
		if point==null:
			preview.paint.break_segment()
			preview.show_brush(null,diameter,softness)
		else:
			preview.paint.paint(point,target,diameter,softness,strength)
			preview.show_brush(point,diameter,softness)
		return true
	if over_ui: return false
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		var point = _point(event.position)
		if point==null: return false
		preview.paint.begin_stroke()
		dragging = true
		preview.paint.paint(point,target,diameter,softness,strength)
		_refresh()
		return true
	return false

func pause_gesture() -> void:
	if not dragging:
		preview.show_brush(null,diameter,softness)
		preview.show_paint_rectangle(Rect2())
		return
	if method=="brush": preview.paint.finish_stroke()
	dragging = false
	rectangle = Rect2()
	preview.show_brush(null,diameter,softness)
	preview.show_paint_rectangle(Rect2())
	_refresh()

func _process(_delta: float) -> void:
	if not active: return
	if editor._camera_blocked() or editor.rotating or editor._over_ui(get_global_mouse_position()):
		preview.show_brush(null,diameter,softness)
		preview.show_paint_rectangle(Rect2())
		return
	if method=="brush": preview.show_brush(_point(get_global_mouse_position()),diameter,softness)
	elif method=="fill":
		preview.show_paint_rectangle(Rect2(preview.paint.origin_feet,Vector2(preview.paint.coverage.get_size())) if _point(get_global_mouse_position())!=null else Rect2())
	elif method=="rectangle" and dragging:
		var point = _point(get_global_mouse_position())
		if point!=null: _update_rectangle(point)
		else: preview.show_paint_rectangle(Rect2())

func _set_method(next: String) -> void:
	pause_gesture()
	method = next
	_refresh()

func _update_rectangle(point: Vector2) -> void:
	var origin: Vector2 = preview.paint.origin_feet
	var end := origin+(point-origin).floor()
	var low := Vector2(minf(anchor.x,end.x),minf(anchor.y,end.y))
	var high := Vector2(maxf(anchor.x,end.x)+1,maxf(anchor.y,end.y)+1)
	rectangle = Rect2(low,high-low).intersection(Rect2(origin,Vector2(preview.paint.coverage.get_size())))
	preview.show_paint_rectangle(rectangle)

func _handle_other(event: InputEvent, over_ui: bool) -> bool:
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and not event.pressed and dragging:
		var point = null if over_ui else _point(event.position)
		if point!=null:
			_update_rectangle(point)
			preview.paint.fill_rectangle(rectangle,target)
		pause_gesture()
		return true
	if event is InputEventMouseMotion and dragging:
		var point = null if over_ui else _point(event.position)
		if point!=null: _update_rectangle(point)
		else: preview.show_paint_rectangle(Rect2())
		return true
	if over_ui: return false
	if event is InputEventMouseButton and event.button_index==MOUSE_BUTTON_LEFT and event.pressed:
		var point = _point(event.position)
		if point==null: return false
		if method=="rectangle":
			anchor = preview.paint.origin_feet+(point-preview.paint.origin_feet).floor()
			dragging = true
			_update_rectangle(point)
			_refresh()
		elif method=="fill": preview.paint.fill_all(target)
		elif method=="sample":
			var picked: int = preview.paint.sample_kind(point)
			if picked>=0:
				target = picked
				selector.select(picked)
				_set_method("brush")
				method_selector.select(0)
		return true
	return false
