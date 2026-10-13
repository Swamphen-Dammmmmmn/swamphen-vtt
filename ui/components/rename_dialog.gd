extends Control

signal name_saved(index: int, title: String)
var token_index := -1
var anchor_rect := Rect2()
var left_margin := 16.0

func _ready() -> void:
	theme = GoUi.theme()
	$Panel.set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	$Panel.custom_minimum_size.x = BoardUiStyle.EDIT_WIDTH
	$Panel.add_theme_stylebox_override("panel", BoardUiStyle.card_face(BoardUiStyle.PANEL_PADDING))
	$Panel/Content.add_theme_constant_override("separation", BoardUiStyle.CONTENT_GAP)
	$Panel/Content/Name.custom_minimum_size.x = 0
	BoardUiStyle.style_controls($Panel)
	GoStyle.apply_icon($Panel/Content/Header/Close, GoIconSet.CLOSE, 16)
	$Panel/Content/Header/Close.pressed.connect(hide)
	resized.connect(_position_panel)
	gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			hide()
	)
	$Panel/Content/Buttons/Cancel.pressed.connect(hide)
	$Panel/Content/Buttons/Save.pressed.connect(_save)
	$Panel/Content/Name.text_submitted.connect(func(_text: String): _save())
	$Panel/Content/Name.text_changed.connect(func(text: String): $Panel/Content/Buttons/Save.disabled = text.strip_edges().is_empty())

func open(index: int, title: String, at: Rect2, margin: float) -> void:
	token_index = index
	anchor_rect = at
	left_margin = margin
	$Panel/Content/Name.text = title
	$Panel/Content/Buttons/Save.disabled = false
	show()
	$Panel.modulate.a = 0.0
	create_tween().tween_property($Panel, "modulate:a", 1.0, preload("res://ui/components/page_motion.gd").duration(BoardUiStyle.FADE_TIME))
	_position_panel.call_deferred()
	$Panel/Content/Name.grab_focus()
	$Panel/Content/Name.select_all()

func _position_panel() -> void:
	BoardUiStyle.place_floating($Panel, anchor_rect, size, left_margin, BoardUiStyle.FloatingRole.EDIT)

func _save() -> void:
	var title: String = $Panel/Content/Name.text.strip_edges()
	if title.is_empty():
		return
	name_saved.emit(token_index, title)
	hide()

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide()
		get_viewport().set_input_as_handled()
