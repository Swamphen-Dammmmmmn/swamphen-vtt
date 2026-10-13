extends Control

signal stats_saved(index: int, hp: int, maximum: int, ac: int)
var token_index := -1
var history_id := -1
var current_hp := -1
var maximum_hp := -1
var current_ac := -1
var mode := "hp"
var fields: Dictionary = {}
var heading: Label
var summary: Label
var error_label: Label
var hp_group: VBoxContainer
var ac_group: VBoxContainer
var settings: FoldableContainer
var apply_buttons: Array[Button] = []
var panel: PanelContainer
var anchor_rect := Rect2()
var undo_button: Button
var history: Dictionary = {}
var left_margin := 204.0
var body_scroll: ScrollContainer

func _ready() -> void:
	theme = GoUi.theme()
	panel = GoStyle.card()
	panel.add_theme_stylebox_override("panel", BoardUiStyle.card_face(BoardUiStyle.PANEL_PADDING))
	panel.custom_minimum_size.x = BoardUiStyle.WIDE_WIDTH
	add_child(panel)
	body_scroll = ScrollContainer.new()
	body_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	panel.add_child(body_scroll)
	var content := GoStyle.column(BoardUiStyle.CONTENT_GAP)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body_scroll.add_child(content)
	var header := GoStyle.row(8)
	content.add_child(header)
	heading = GoStyle.label("生命值")
	heading.add_theme_font_size_override("font_size", 20)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(heading)
	var close := GoStyle.button("", hide, GoStyle.Tone.COMPACT)
	GoStyle.apply_icon(close, GoIconSet.CLOSE, 18)
	close.tooltip_text = "关闭 · Esc"
	header.add_child(close)
	summary = GoStyle.label("")
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(summary)
	hp_group = GoStyle.column(BoardUiStyle.CONTENT_GAP)
	content.add_child(hp_group)
	_add_adjustment("decrease", "扣去", -1)
	_add_adjustment("increase", "增加", 1)
	undo_button = GoStyle.button("撤销最近一次生命值操作", _undo_hp, GoStyle.Tone.COMPACT)
	hp_group.add_child(undo_button)
	settings = GoStyle.foldable("修改当前值与最大值", true, null, false)
	hp_group.add_child(settings)
	var settings_body := GoStyle.column(8)
	settings.add_child(settings_body)
	_add_field(settings_body, "current", "当前 HP")
	_add_field(settings_body, "maximum", "最大 HP")
	settings_body.add_child(GoStyle.button("保存生命值设置", _save_settings, GoStyle.Tone.PRIMARY))
	ac_group = GoStyle.column(8)
	content.add_child(ac_group)
	_add_field(ac_group, "ac", "AC")
	ac_group.add_child(GoStyle.button("保存 AC", _save_ac, GoStyle.Tone.PRIMARY))
	error_label = GoStyle.label("")
	error_label.add_theme_color_override("font_color", Color("b33c3c"))
	error_label.custom_minimum_size.x = 0
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(error_label)
	BoardUiStyle.style_controls(panel)
	content.minimum_size_changed.connect(func(): _position_panel.call_deferred())
	gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			hide()
	)
	resized.connect(_position_panel)
	panel.minimum_size_changed.connect(func(): _position_panel.call_deferred())

func _position_panel() -> void:
	var available := maxf(0, size.y - 118)
	var natural_height: float = body_scroll.get_child(0).get_combined_minimum_size().y + BoardUiStyle.PANEL_PADDING * 2
	panel.size = Vector2(BoardUiStyle.WIDE_WIDTH, minf(natural_height, available))
	panel.position = BoardUiStyle.floating_position(panel.size, anchor_rect, size, left_margin, BoardUiStyle.FloatingRole.EDIT)

func _add_adjustment(key: String, text: String, direction: int) -> void:
	var row := GoStyle.row(8)
	hp_group.add_child(row)
	row.add_child(GoStyle.label(text))
	var field := GoStyle.line_edit("数量")
	field.custom_minimum_size.x = 70
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.max_length = 6
	field.text_submitted.connect(func(_text: String): _adjust_hp(key, direction))
	fields[key] = field
	row.add_child(field)
	row.add_child(GoStyle.label("生命"))
	var button := GoStyle.button("应用", func(): _adjust_hp(key, direction))
	row.add_child(button)
	apply_buttons.append(button)

func _add_field(parent: Control, key: String, title: String) -> void:
	var row := GoStyle.row(8)
	parent.add_child(row)
	var label := GoStyle.label(title)
	label.custom_minimum_size.x = 90
	row.add_child(label)
	var field := GoStyle.line_edit("未填写")
	field.custom_minimum_size.x = 80
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.max_length = 6
	field.text_submitted.connect(func(_text: String):
		if key == "ac": _save_ac()
		else: _save_settings()
	)
	row.add_child(field)
	fields[key] = field

func open(index: int, data: Dictionary, edit_mode: String, at: Rect2) -> void:
	anchor_rect = at
	token_index = index
	history_id = int(data["id"])
	current_hp = data["hp"]
	maximum_hp = data["max_hp"]
	current_ac = data["ac"]
	mode = edit_mode
	heading.text = "%s · %s" % [data["title"], "生命值" if mode == "hp" else "护甲等级"]
	hp_group.visible = mode == "hp"
	ac_group.visible = mode == "ac"
	fields["ac"].text = str(current_ac) if current_ac >= 0 else ""
	fields["increase"].text = ""
	fields["decrease"].text = ""
	error_label.text = ""
	error_label.add_theme_color_override("font_color", Color("b33c3c"))
	_refresh_hp()
	settings.folded = true
	show()
	panel.modulate.a = 0.0
	create_tween().tween_property(panel, "modulate:a", 1.0, preload("res://ui/components/page_motion.gd").duration(BoardUiStyle.FADE_TIME))
	_position_panel.call_deferred()
	var first: LineEdit = fields["ac" if mode == "ac" else "decrease"]
	first.grab_focus()
	first.select_all()

func _refresh_hp() -> void:
	summary.text = "当前生命值：%d / %d" % [current_hp, maximum_hp] if maximum_hp > 0 else "生命值未填写，请先设置当前值与最大值。"
	summary.visible = mode == "hp"
	fields["current"].text = str(current_hp) if current_hp >= 0 else ""
	fields["maximum"].text = str(maximum_hp) if maximum_hp > 0 else ""
	for button in apply_buttons:
		button.disabled = maximum_hp <= 0
	undo_button.disabled = not history.has(history_id)

func _adjust_hp(key: String, direction: int) -> void:
	error_label.add_theme_color_override("font_color", Color("b33c3c"))
	if maximum_hp <= 0:
		error_label.text = "请先设置当前生命值与最大值。"
		return
	var amount: String = fields[key].text.strip_edges()
	if not amount.is_valid_int() or int(amount) <= 0:
		error_label.text = "本次数量请填写正整数。"
		return
	var before := current_hp
	current_hp = clampi(current_hp + direction * int(amount), 0, maximum_hp)
	if current_hp != before:
		history[history_id] = before
	stats_saved.emit(token_index, current_hp, maximum_hp, current_ac)
	_refresh_hp()
	error_label.add_theme_color_override("font_color", Color("28785e"))
	error_label.text = ("已增加 %d 生命" % (current_hp - before) if direction > 0 else "已扣去 %d 生命" % (before - current_hp)) + "，剩余 %d / %d。" % [current_hp, maximum_hp]
	fields[key].text = ""
	fields[key].grab_focus()

func _save_settings() -> void:
	error_label.add_theme_color_override("font_color", Color("b33c3c"))
	var hp_text: String = fields["current"].text.strip_edges()
	var max_text: String = fields["maximum"].text.strip_edges()
	if hp_text.is_empty() and max_text.is_empty():
		current_hp = -1
		maximum_hp = -1
	elif not hp_text.is_valid_int() or not max_text.is_valid_int() or int(max_text) <= 0 or int(hp_text) < 0 or int(hp_text) > int(max_text):
		error_label.text = "最大 HP 必须大于 0，当前 HP 在 0 到最大值之间。"
		return
	else:
		current_hp = int(hp_text)
		maximum_hp = int(max_text)
	history.erase(history_id)
	stats_saved.emit(token_index, current_hp, maximum_hp, current_ac)
	_refresh_hp()
	settings.folded = true
	error_label.text = "生命值设置已保存。"
	_position_panel.call_deferred()

func _undo_hp() -> void:
	if not history.has(history_id):
		return
	current_hp = int(history[history_id])
	history.erase(history_id)
	stats_saved.emit(token_index, current_hp, maximum_hp, current_ac)
	_refresh_hp()
	error_label.add_theme_color_override("font_color", Color("28785e"))
	error_label.text = "已撤销最近一次操作，剩余 %d / %d。" % [current_hp, maximum_hp]

func _save_ac() -> void:
	error_label.add_theme_color_override("font_color", Color("b33c3c"))
	var text: String = fields["ac"].text.strip_edges()
	if not text.is_empty() and (not text.is_valid_int() or int(text) < 0):
		error_label.text = "AC 请填写非负整数，留空表示未填写。"
		return
	current_ac = -1 if text.is_empty() else int(text)
	stats_saved.emit(token_index, current_hp, maximum_hp, current_ac)
	hide()

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide()
		get_viewport().set_input_as_handled()
