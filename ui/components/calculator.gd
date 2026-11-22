extends "res://ui/components/utility_panel.gd"

const CalculatorEngine = preload("res://scripts/calculator_engine.gd")
const FluentButton = preload("res://ui/components/controls/fluent_button.gd")

var engine := CalculatorEngine.new()
var entry: LineEdit
var answer: Label
var feedback: Label
var copy_button: Button
var history_list: VBoxContainer
var history: Array[Dictionary] = []
var last_result := ""

func _init() -> void:
	fluent = true
	layout_key = "adventure.calculator"
	panel_title = "计算器"
	preferred_width = 360.0

func _ready() -> void:
	super._ready()
	entry = LineEdit.new()
	entry.placeholder_text = "例如 (18 + 7) / 2"
	entry.max_length = 256
	entry.custom_minimum_size.y = T.BUTTON_HEIGHT
	content().add_child(entry)
	entry.text_submitted.connect(func(_text: String): calculate())

	var result_row := HBoxContainer.new()
	result_row.add_theme_constant_override("separation", 8)
	content().add_child(result_row)

	answer = Label.new()
	answer.text = "结果：—"
	answer.add_theme_font_override("font", Typography.MEDIUM)
	answer.add_theme_font_size_override("font_size", Typography.EMPHASIS)
	answer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	answer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	result_row.add_child(answer)

	copy_button = FluentButton.new()
	copy_button.text = "复制结果"
	copy_button.variant = "FluentCompact"
	copy_button.minimum_height = 36.0
	copy_button.disabled = true
	copy_button.pressed.connect(func(): DisplayServer.clipboard_set(last_result))
	result_row.add_child(copy_button)

	feedback = Label.new()
	feedback.visible = false
	feedback.add_theme_font_size_override("font_size", Typography.CAPTION)
	feedback.add_theme_color_override("font_color", T.DANGER)
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content().add_child(feedback)

	var keys := GridContainer.new()
	keys.columns = 4
	keys.add_theme_constant_override("h_separation", 6)
	keys.add_theme_constant_override("v_separation", 6)
	content().add_child(keys)
	for symbol in ["(", ")", "退格", "清空", "7", "8", "9", "÷", "4", "5", "6", "×", "1", "2", "3", "−", "0", ".", "计算", "+"]:
		var key: String = symbol
		var button := FluentButton.new()
		button.text = key
		button.variant = "FluentPrimary" if key == "计算" else "FluentCompact"
		button.minimum_height = 38.0
		button.custom_minimum_size.x = 60.0
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		button.pressed.connect(func(): _key(key))
		keys.add_child(button)

	var sep := HSeparator.new()
	sep.theme_type_variation = &"FluentSeparator"
	content().add_child(sep)

	var history_header := HBoxContainer.new()
	history_header.add_theme_constant_override("separation", 8)
	content().add_child(history_header)

	var history_title := Label.new()
	history_title.text = "历史记录 · 最近 50 条"
	history_title.theme_type_variation = &"FluentSecondary"
	history_title.add_theme_font_size_override("font_size", Typography.CAPTION)
	history_title.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	history_title.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	history_header.add_child(history_title)

	var clear_history := FluentButton.new()
	clear_history.text = "清空历史"
	clear_history.variant = "FluentCompact"
	clear_history.minimum_height = 34.0
	clear_history.pressed.connect(func():
		history.clear()
		_rebuild_history()
	)
	history_header.add_child(clear_history)

	history_list = VBoxContainer.new()
	history_list.add_theme_constant_override("separation", 6)
	content().add_child(history_list)
	_rebuild_history()

func open() -> void:
	super.open()
	entry.grab_focus()

func calculate() -> void:
	var result := engine.evaluate(entry.text)
	if not result["ok"]:
		feedback.text = result["error"]
		feedback.visible = true
		entry.grab_focus()
		fit_to_window.call_deferred()
		return
	feedback.text = ""
	feedback.visible = false
	last_result = result["display"]
	answer.text = "结果：" + last_result
	copy_button.disabled = false
	history.push_front({"expression": entry.text, "value": result["value"], "display": last_result})
	if history.size() > 50:
		history.pop_back()
	_rebuild_history()
	entry.grab_focus()

func _key(key: String) -> void:
	if key == "计算":
		calculate()
		return
	entry.grab_focus()
	if key == "清空":
		entry.clear()
		feedback.text = ""
		feedback.visible = false
		answer.text = "结果：—"
		last_result = ""
		copy_button.disabled = true
		fit_to_window.call_deferred()
	elif key == "退格":
		if entry.has_selection():
			_delete_selection()
		elif entry.caret_column > 0:
			var caret := entry.caret_column
			entry.delete_text(caret - 1, caret)
			entry.caret_column = caret - 1
	else:
		if entry.has_selection():
			_delete_selection()
		entry.insert_text_at_caret(key)

func _delete_selection() -> void:
	var start := entry.get_selection_from_column()
	entry.delete_text(start, entry.get_selection_to_column())
	entry.deselect()
	entry.caret_column = start

func _rebuild_history() -> void:
	for child in history_list.get_children():
		history_list.remove_child(child)
		child.queue_free()
	if history.is_empty():
		var empty := Label.new()
		empty.text = "暂无记录"
		empty.theme_type_variation = &"FluentSecondary"
		empty.add_theme_font_size_override("font_size", Typography.CAPTION)
		history_list.add_child(empty)
	for record in history:
		var row := HBoxContainer.new()
		row.add_theme_constant_override("separation", 6)
		history_list.add_child(row)
		var data: Dictionary = record
		var restore := FluentButton.new()
		restore.text = "%s = %s" % [data["expression"], data["display"]]
		restore.variant = "FluentCompact"
		restore.minimum_height = 36.0
		restore.alignment = HORIZONTAL_ALIGNMENT_LEFT
		restore.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		restore.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		restore.pressed.connect(func():
			entry.text = data["expression"]
			entry.grab_focus()
			entry.caret_column = entry.text.length()
		)
		row.add_child(restore)
		var copy := FluentButton.new()
		copy.text = "复制"
		copy.variant = "FluentCompact"
		copy.minimum_height = 36.0
		copy.pressed.connect(func(): DisplayServer.clipboard_set(data["display"]))
		row.add_child(copy)
	fit_to_window.call_deferred()
