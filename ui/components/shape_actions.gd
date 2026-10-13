extends PanelContainer

signal action_requested(action: String)
var mode := ""
var motion: Tween

func _ready() -> void:
	hide()
	theme = GoUi.theme()
	add_theme_stylebox_override("panel", BoardUiStyle.card_face(BoardUiStyle.ACTION_PADDING))

func set_mode(value: String) -> void:
	if mode == value:
		return
	mode = value
	for child in $Actions.get_children():
		$Actions.remove_child(child)
		child.queue_free()
	var items: Array = [["move", "移动"], ["delete", "删除"], ["more", "⋯"]]
	if value == "confirm":
		items = [["confirm", "确认"], ["cancel", "取消"]]
	elif value == "cancel_preview":
		items = [["cancel", "取消"]]
	elif value == "measure_wait":
		items = [["cancel_creation", "取消创建"]]
	elif value == "measure_move_cancel":
		items = [["cancel_node", "取消本点修改"]]
	elif value == "undo":
		items = [["undo_delete", "已删除 · 撤销"]]
	elif value == "measure_line":
		items = [["continue", "继续绘制"], ["delete_measure", "删除整条"], ["more", "⋯"]]
	elif value == "measure_node":
		items = [["move_node", "移动"], ["delete_node", "删除节点"], ["more", "⋯"]]
	elif value == "measure_confirm":
		items = [["confirm_node", "确认"], ["cancel_node", "取消"]]
	elif value == "measure_undo":
		items = [["undo_measure", "已删除 · 撤销"]]
	for item in items:
		var action: String = item[0]
		var button := GoStyle.button(item[1], func(): action_requested.emit(action), GoStyle.Tone.PRIMARY if action in ["confirm", "confirm_node"] else GoStyle.Tone.COMPACT)
		BoardUiStyle.action_button(button, BoardUiStyle.ACTION_HEIGHT, action in ["confirm", "confirm_node"], action in ["delete", "delete_node", "delete_measure"])
		if action in ["move", "move_node"]:
			GoStyle.apply_icon(button, GoIconSet.FORWARD, 16)
		elif action in ["delete", "delete_node", "delete_measure"]:
			GoStyle.apply_icon(button, GoIconSet.TRASH, 16)
		elif action == "more":
			button.text = ""
			GoStyle.apply_icon(button, GoIconSet.MORE, 16)
		button.focus_mode = Control.FOCUS_NONE
		$Actions.add_child(button)
	reset_size()

func reveal() -> void:
	if visible:
		return
	show()
	if motion:
		motion.kill()
	modulate.a = 0.0
	motion = create_tween()
	motion.tween_property(self, "modulate:a", 1.0, preload("res://ui/components/page_motion.gd").duration(BoardUiStyle.FADE_TIME))

func place_above(at: Vector2, left_margin: float) -> void:
	var role := BoardUiStyle.FloatingRole.CONFIRM if mode in ["confirm", "measure_confirm"] else BoardUiStyle.FloatingRole.ACTION
	BoardUiStyle.place_floating(self, Rect2(at, Vector2.ZERO), get_parent().size, left_margin, role)

func pointer_near() -> bool:
	if not is_visible_in_tree() or not get_global_rect().has_point(get_global_mouse_position()):
		return false
	var hovered := get_viewport().gui_get_hovered_control()
	return hovered != null and (hovered == self or is_ancestor_of(hovered))
