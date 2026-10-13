extends PanelContainer

signal action_requested(action: String)
var expanded := false
var motion: Tween

func _ready() -> void:
	theme = GoUi.theme()
	add_theme_stylebox_override("panel", BoardUiStyle.card_face(BoardUiStyle.ACTION_PADDING))
	var move := GoStyle.button("移动", func(): action_requested.emit("move"), GoStyle.Tone.COMPACT)
	var turn := GoStyle.button("转向",func(): action_requested.emit("turn"),GoStyle.Tone.COMPACT)
	var more := GoStyle.button("", func(): action_requested.emit("more"), GoStyle.Tone.COMPACT)
	for button in [move, turn, more]:
		BoardUiStyle.action_button(button)
		button.autowrap_mode = TextServer.AUTOWRAP_OFF
		button.focus_mode = Control.FOCUS_NONE
		$Actions.add_child(button)
	GoStyle.apply_icon(move, GoIconSet.FORWARD, 16)
	GoStyle.apply_icon(more, GoIconSet.MORE, 16)
	more.tooltip_text = "更多操作"
	modulate.a = 0.0

func set_expanded(value: bool) -> void:
	if expanded == value:
		return
	expanded = value
	if motion:
		motion.kill()
	if value:
		show()
	for button in $Actions.get_children():
		button.disabled = not value
	mouse_filter = Control.MOUSE_FILTER_STOP if value else Control.MOUSE_FILTER_IGNORE
	motion = create_tween()
	motion.tween_property(self, "modulate:a", 1.0 if value else 0.0, preload("res://ui/components/page_motion.gd").duration(BoardUiStyle.FADE_TIME))
	if not value:
		motion.chain().tween_callback(hide)

func place_below(card: Control, bounds: Vector2, left_margin: float) -> void:
	BoardUiStyle.place_floating(self, card.get_global_rect(), bounds, left_margin, BoardUiStyle.FloatingRole.ACTION, true)
