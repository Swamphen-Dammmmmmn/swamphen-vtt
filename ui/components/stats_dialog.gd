extends Control

const Typography = preload("res://ui/theme/typography.gd")
const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
const FluentButton = preload("res://ui/components/controls/fluent_button.gd")
const EditorFoldableGroup = preload("res://ui/components/layout/editor_foldable_group.gd")
const EditorLayout = preload("res://ui/components/editor_layout.gd")
const Icons = preload("res://ui/theme/icons/library_icons.gd")
const ButtonFocus = preload("res://ui/components/button_focus.gd")

signal stats_saved(index: int, hp: int, maximum: int, ac: int, temporary: int)

var token_index := -1
var history_id := -1
var current_hp := -1
var maximum_hp := -1
var current_ac := -1
var temporary_hp := 0
var consume_temporary: CheckBox
var mode := "hp"
var fields: Dictionary = {}
var heading: Label
var summary: Label
var error_label: Label
var hp_group: VBoxContainer
var ac_group: VBoxContainer
var settings: EditorFoldableGroup
var apply_buttons: Array[Button] = []
var panel: PanelContainer
var anchor_rect := Rect2()
var undo_button: Button
var history: Dictionary = {}
var left_margin := 16.0
var top_margin := 64.0
var body_scroll: ScrollContainer
var _frame: VBoxContainer
var _body_inset: MarginContainer

func _ready() -> void:
	set_meta("style_owned", true)
	theme = FluentTheme.shared()

	panel = PanelContainer.new()
	var face := FluentTheme.face(T.SURFACE, T.STROKE, T.RADIUS, 1)
	face.set_content_margin_all(16)
	panel.add_theme_stylebox_override("panel", face)
	panel.custom_minimum_size.x = BoardUiStyle.WIDE_WIDTH
	add_child(panel)

	_frame = VBoxContainer.new()
	_frame.add_theme_constant_override("separation", 12)
	panel.add_child(_frame)

	var header := HBoxContainer.new()
	header.add_theme_constant_override("separation", 8)
	_frame.add_child(header)

	heading = Label.new()
	heading.text = "生命值"
	heading.add_theme_font_override("font", Typography.MEDIUM)
	heading.add_theme_font_size_override("font_size", Typography.SECTION)
	heading.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	heading.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	header.add_child(heading)

	var close := Button.new()
	close.theme_type_variation = &"FluentInputAction"
	close.icon = Icons.texture("res://ui/theme/icons/close_tintable.svg")
	close.expand_icon = true
	close.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	close.add_theme_constant_override("icon_max_width", 20)
	close.custom_minimum_size = Vector2(40, 40)
	close.tooltip_text = "关闭 · Esc"
	close.add_child(ButtonFocus.new())
	close.pressed.connect(hide)
	header.add_child(close)

	body_scroll = ScrollContainer.new()
	EditorLayout.scroll(body_scroll)
	body_scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	_frame.add_child(body_scroll)

	_body_inset = MarginContainer.new()
	_body_inset.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for edge in ["left", "right", "top", "bottom"]:
		_body_inset.add_theme_constant_override("margin_" + edge, T.MODAL_BODY_DRAW_INSET)
	body_scroll.add_child(_body_inset)

	var content := VBoxContainer.new()
	content.add_theme_constant_override("separation", 10)
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body_inset.add_child(content)

	summary = Label.new()
	summary.theme_type_variation = &"FluentSecondary"
	summary.add_theme_font_size_override("font_size", Typography.CAPTION)
	summary.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(summary)

	hp_group = VBoxContainer.new()
	hp_group.add_theme_constant_override("separation", 10)
	content.add_child(hp_group)
	_add_adjustment("decrease", "扣去", -1)
	_add_adjustment("increase", "增加", 1)

	consume_temporary = CheckBox.new()
	consume_temporary.theme_type_variation = &"FluentCheckBox"
	consume_temporary.text = "先扣临时生命值"
	consume_temporary.button_pressed = true
	consume_temporary.custom_minimum_size.y = 36
	hp_group.add_child(consume_temporary)

	_add_field(hp_group, "temporary", "临时生命值")
	var temp_actions := HBoxContainer.new()
	temp_actions.add_theme_constant_override("separation", 8)
	hp_group.add_child(temp_actions)

	var set_temp_btn := FluentButton.new()
	set_temp_btn.text = "设置临时生命值"
	set_temp_btn.variant = "FluentCompact"
	set_temp_btn.minimum_height = 36.0
	set_temp_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	set_temp_btn.pressed.connect(_save_temporary)
	temp_actions.add_child(set_temp_btn)

	var clear_temp_btn := FluentButton.new()
	clear_temp_btn.text = "清零"
	clear_temp_btn.variant = "FluentCompact"
	clear_temp_btn.minimum_height = 36.0
	clear_temp_btn.pressed.connect(func():
		fields["temporary"].text = "0"
		_save_temporary()
	)
	temp_actions.add_child(clear_temp_btn)

	undo_button = FluentButton.new()
	undo_button.text = "撤销最近一次生命值操作"
	undo_button.variant = "FluentCompact"
	undo_button.minimum_height = 36.0
	undo_button.pressed.connect(_undo_hp)
	hp_group.add_child(undo_button)

	settings = EditorFoldableGroup.new()
	settings.set_group_title("修改当前值与最大值")
	settings.folded = true
	hp_group.add_child(settings)
	var settings_body: VBoxContainer = settings.content()
	_add_field(settings_body, "current", "当前 HP")
	_add_field(settings_body, "maximum", "最大 HP")
	var save_hp_btn := FluentButton.new()
	save_hp_btn.text = "保存生命值设置"
	save_hp_btn.variant = "FluentPrimary"
	save_hp_btn.minimum_height = 40.0
	save_hp_btn.pressed.connect(_save_settings)
	settings_body.add_child(save_hp_btn)

	ac_group = VBoxContainer.new()
	ac_group.add_theme_constant_override("separation", 10)
	content.add_child(ac_group)
	_add_field(ac_group, "ac", "AC")
	var save_ac_btn := FluentButton.new()
	save_ac_btn.text = "保存 AC"
	save_ac_btn.variant = "FluentPrimary"
	save_ac_btn.minimum_height = 40.0
	save_ac_btn.pressed.connect(_save_ac)
	ac_group.add_child(save_ac_btn)

	error_label = Label.new()
	error_label.visible = false
	error_label.add_theme_font_size_override("font_size", Typography.CAPTION)
	error_label.add_theme_color_override("font_color", T.DANGER)
	error_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content.add_child(error_label)

	content.minimum_size_changed.connect(func(): _position_panel.call_deferred())
	settings.folding_changed.connect(func(_folded: bool): _position_panel.call_deferred())
	gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			hide()
	)
	resized.connect(_position_panel)
	panel.minimum_size_changed.connect(func(): _position_panel.call_deferred())

func _position_panel() -> void:
	if not is_instance_valid(panel) or not is_instance_valid(_body_inset):
		return
	var safe := Mobile.local_safe_rect(self) if Mobile.enabled else Rect2(Vector2.ZERO, size)
	var available := maxf(1.0, safe.size.y - top_margin - 54.0)
	var chrome := panel.get_theme_stylebox("panel").get_minimum_size().y
	var header_h := (_frame.get_child(0) as Control).get_combined_minimum_size().y + _frame.get_theme_constant("separation")
	var body_natural := _body_inset.get_combined_minimum_size().y
	var body_height := minf(body_natural, maxf(1.0, available - chrome - header_h))
	body_scroll.custom_minimum_size.y = body_height
	panel.size = Vector2(minf(BoardUiStyle.WIDE_WIDTH, maxf(1.0, safe.size.x - 32.0)), chrome + header_h + body_height)
	panel.position = BoardUiStyle.floating_position(panel.size, anchor_rect, size, left_margin, BoardUiStyle.FloatingRole.EDIT, false, top_margin)
	if Mobile.enabled:
		panel.position = panel.position.clamp(safe.position, (safe.end - panel.size).max(safe.position))

func _add_adjustment(key: String, text: String, direction: int) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	hp_group.add_child(row)
	var prefix := Label.new()
	prefix.text = text
	prefix.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(prefix)
	var field := LineEdit.new()
	field.placeholder_text = "数量"
	field.custom_minimum_size = Vector2(72, 38)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.max_length = 6
	field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	field.text_submitted.connect(func(_text: String): _adjust_hp(key, direction))
	fields[key] = field
	row.add_child(field)
	var suffix := Label.new()
	suffix.text = "生命"
	suffix.theme_type_variation = &"FluentSecondary"
	suffix.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(suffix)
	var button := FluentButton.new()
	button.text = "应用"
	button.variant = "FluentCompact"
	button.minimum_height = 38.0
	button.pressed.connect(func(): _adjust_hp(key, direction))
	row.add_child(button)
	apply_buttons.append(button)

func _add_field(parent: Control, key: String, title: String) -> void:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 8)
	parent.add_child(row)
	var label := Label.new()
	label.text = title
	label.theme_type_variation = &"FluentSecondary"
	label.custom_minimum_size.x = 92
	label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(label)
	var field := LineEdit.new()
	field.placeholder_text = "未填写"
	field.custom_minimum_size = Vector2(80, 38)
	field.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	field.max_length = 6
	field.virtual_keyboard_type = LineEdit.KEYBOARD_TYPE_NUMBER
	field.text_submitted.connect(func(_text: String):
		if key == "temporary": _save_temporary()
		elif key == "ac": _save_ac()
		else: _save_settings()
	)
	row.add_child(field)
	fields[key] = field

func _set_feedback(text: String, is_error: bool) -> void:
	error_label.text = text
	error_label.visible = not text.is_empty()
	error_label.add_theme_color_override("font_color", T.DANGER if is_error else T.SUCCESS)
	_position_panel.call_deferred()

func clear_token_history(token_id: int) -> void:
	history.erase(token_id)

func clear_all_history() -> void:
	history.clear()

func close_if_editing_token(index: int) -> void:
	if visible and token_index == index:
		hide()

func open(index: int, data: Dictionary, edit_mode: String, at: Rect2) -> void:
	anchor_rect = at
	token_index = index
	history_id = int(data["id"])
	current_hp = data["hp"]
	maximum_hp = data["max_hp"]
	current_ac = data["ac"]
	temporary_hp = int(data.get("temp_hp", 0))
	if history.has(history_id) and history[history_id]["after"] != [current_hp, maximum_hp, temporary_hp]:
		history.erase(history_id)
	mode = edit_mode
	heading.text = "%s · %s" % [data["title"], "生命值" if mode == "hp" else "护甲等级"]
	hp_group.visible = mode == "hp"
	ac_group.visible = mode == "ac"
	fields["ac"].text = str(current_ac) if current_ac >= 0 else ""
	fields["increase"].text = ""
	fields["decrease"].text = ""
	_set_feedback("", false)
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
	fields["temporary"].text = str(temporary_hp)
	fields["current"].text = str(current_hp) if current_hp >= 0 else ""
	fields["maximum"].text = str(maximum_hp) if maximum_hp > 0 else ""
	for button in apply_buttons:
		button.disabled = maximum_hp <= 0
	undo_button.disabled = not history.has(history_id)

func _adjust_hp(key: String, direction: int) -> void:
	if maximum_hp <= 0:
		_set_feedback("请先设置当前生命值与最大值。", true)
		return
	var amount: String = fields[key].text.strip_edges()
	if not amount.is_valid_int() or int(amount) <= 0:
		_set_feedback("本次数量请填写正整数。", true)
		return
	var before := current_hp
	var previous_temporary := temporary_hp
	var remaining := int(amount)
	if direction < 0 and consume_temporary.button_pressed:
		var absorbed := mini(temporary_hp, remaining)
		temporary_hp -= absorbed
		remaining -= absorbed
	current_hp = clampi(current_hp + direction * remaining, 0, maximum_hp)
	if current_hp != before or temporary_hp != previous_temporary:
		history[history_id] = {"before": [before, previous_temporary], "after": [current_hp, maximum_hp, temporary_hp]}
	stats_saved.emit(token_index, current_hp, maximum_hp, current_ac, temporary_hp)
	_refresh_hp()
	_set_feedback(("已增加 %d 生命" % (current_hp - before) if direction > 0 else "已扣去 %d 生命" % (before - current_hp + previous_temporary - temporary_hp)) + "，剩余 %d / %d。" % [current_hp, maximum_hp], false)
	fields[key].text = ""
	fields[key].grab_focus()

func _save_settings() -> void:
	var hp_text: String = fields["current"].text.strip_edges()
	var max_text: String = fields["maximum"].text.strip_edges()
	if hp_text.is_empty() and max_text.is_empty():
		current_hp = -1
		maximum_hp = -1
	elif not hp_text.is_valid_int() or not max_text.is_valid_int() or int(max_text) <= 0 or int(hp_text) < 0 or int(hp_text) > int(max_text):
		_set_feedback("最大 HP 必须大于 0，当前 HP 在 0 到最大值之间。", true)
		return
	else:
		current_hp = int(hp_text)
		maximum_hp = int(max_text)
	history.erase(history_id)
	stats_saved.emit(token_index, current_hp, maximum_hp, current_ac, temporary_hp)
	_refresh_hp()
	settings.folded = true
	_set_feedback("生命值设置已保存。", false)

func _undo_hp() -> void:
	if not history.has(history_id):
		return
	current_hp = int(history[history_id]["before"][0])
	temporary_hp = int(history[history_id]["before"][1])
	history.erase(history_id)
	stats_saved.emit(token_index, current_hp, maximum_hp, current_ac, temporary_hp)
	_refresh_hp()
	_set_feedback("已撤销最近一次操作，剩余 %d / %d。" % [current_hp, maximum_hp], false)

func _save_ac() -> void:
	var text: String = fields["ac"].text.strip_edges()
	if not text.is_empty() and (not text.is_valid_int() or int(text) < 0):
		_set_feedback("AC 请填写非负整数，留空表示未填写。", true)
		return
	current_ac = -1 if text.is_empty() else int(text)
	stats_saved.emit(token_index, current_hp, maximum_hp, current_ac, temporary_hp)
	hide()

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide()
		get_viewport().set_input_as_handled()

func _save_temporary() -> void:
	var text: String = fields["temporary"].text.strip_edges()
	if not text.is_valid_int() or int(text) < 0 or int(text) > 999999:
		_set_feedback("临时生命值请填写不超过六位的非负整数。", true)
		return
	temporary_hp = int(text)
	history.erase(history_id)
	stats_saved.emit(token_index, current_hp, maximum_hp, current_ac, temporary_hp)
	_refresh_hp()
	_set_feedback("", false)
