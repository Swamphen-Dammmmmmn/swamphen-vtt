extends Control

signal deletion_confirmed(token_id: int)
var target_id := -1
var panel: PanelContainer
var message: Label
var cancel_button: Button

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = GoUi.theme()
	panel = GoStyle.card()
	panel.add_theme_stylebox_override("panel", BoardUiStyle.card_face(BoardUiStyle.PANEL_PADDING))
	add_child(panel)
	var column := GoStyle.column(BoardUiStyle.CONTENT_GAP)
	panel.add_child(column)
	var title := GoStyle.label("删除棋子")
	title.add_theme_font_size_override("font_size", 20)
	column.add_child(title)
	message = GoStyle.label("")
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(message)
	var buttons := GoStyle.row(8)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(buttons)
	cancel_button = GoStyle.button("取消", hide)
	buttons.add_child(cancel_button)
	buttons.add_child(GoStyle.button("删除", _confirm, GoStyle.Tone.DANGER))
	BoardUiStyle.style_controls(panel)
	resized.connect(_position_panel)
	gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			hide()
	)
	hide()

func open(data: Dictionary, measurement_count: int) -> void:
	target_id = int(data["id"])
	message.text = "删除“%s”？" % data["title"]
	if measurement_count > 0:
		message.text += "\n同时删除与它绑定的 %d 条测距。" % measurement_count
	message.text += "\n删除后无法撤销。"
	show()
	panel.modulate.a = 0.0
	create_tween().tween_property(panel, "modulate:a", 1.0, preload("res://ui/components/page_motion.gd").duration(BoardUiStyle.FADE_TIME))
	get_parent().move_child(self, get_parent().get_child_count() - 1)
	_position_panel.call_deferred()
	cancel_button.grab_focus()

func _confirm() -> void:
	var id := target_id
	hide()
	deletion_confirmed.emit(id)

func _position_panel() -> void:
	panel.size = Vector2(minf(BoardUiStyle.EDIT_WIDTH, maxf(0, size.x - 32)), 0)
	panel.position = (size - panel.size) / 2.0

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide()
		get_viewport().set_input_as_handled()
