extends Control

var hp := -1
var maximum := -1
var temporary := 0
var ratios := Vector2.ZERO
var initialized := false
var motion: Tween

func set_values(current: int, total: int, extra: int) -> void:
	if hp==current and maximum==total and temporary==extra: return
	hp = current
	maximum = total
	temporary = extra
	var target := Vector2(float(maxi(current,0)),float(extra))/float(total+extra) if total>0 else Vector2.ZERO
	if motion: motion.kill()
	if not initialized:
		_set_ratios(target)
		initialized = true
	else:
		motion = create_tween()
		motion.tween_method(_set_ratios,ratios,target,preload("res://ui/components/page_motion.gd").duration(0.2))

func _set_ratios(value: Vector2) -> void:
	ratios = value
	queue_redraw()

func _draw() -> void:
	var track := Rect2(Vector2.ZERO,size)
	draw_style_box(_style(Color("e2e7ed")),track)
	var regular := size.x*ratios.x
	var extra := size.x*ratios.y
	if regular>0: draw_style_box(_style(Color("429d86")),Rect2(0,0,regular,size.y))
	if extra>0: draw_style_box(_style(Color("2998e6")),Rect2(regular,0,extra,size.y))

func _style(color: Color) -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = color
	style.set_corner_radius_all(2)
	return style
