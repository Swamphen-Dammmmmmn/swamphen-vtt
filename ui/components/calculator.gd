extends "res://ui/components/utility_panel.gd"

const Typography = preload("res://ui/theme/typography.gd")

const CalculatorEngine = preload("res://scripts/calculator_engine.gd")
var engine := CalculatorEngine.new()
var entry: LineEdit
var answer: Label
var feedback: Label
var copy_button: Button
var history_list: VBoxContainer
var history: Array[Dictionary] = []
var last_result := ""

func _ready() -> void:
	super._ready()
	entry = LineEdit.new()
	entry.placeholder_text = "例如 (18 + 7) / 2"
	entry.max_length = 256
	entry.custom_minimum_size.y = 40
	content().add_child(entry)
	entry.text_submitted.connect(func(_text: String): calculate())
	answer = GoStyle.label("结果：—")
	answer.add_theme_font_size_override("font_size", Typography.EMPHASIS)
	answer.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content().add_child(answer)
	feedback = GoStyle.label("")
	feedback.add_theme_color_override("font_color", Color("b33c3c"))
	feedback.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	content().add_child(feedback)
	var keys := GridContainer.new()
	keys.columns = 4
	keys.add_theme_constant_override("h_separation", 6)
	keys.add_theme_constant_override("v_separation", 6)
	content().add_child(keys)
	for symbol in ["(", ")", "退格", "清空", "7", "8", "9", "÷", "4", "5", "6", "×", "1", "2", "3", "−", "0", ".", "计算", "+"]:
		var key: String = symbol
		var button := GoStyle.button(key, func(): _key(key), GoStyle.Tone.COMPACT)
		button.focus_mode = Control.FOCUS_NONE
		button.custom_minimum_size = Vector2(60, 38)
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		keys.add_child(button)
	copy_button = GoStyle.button("复制结果", func(): DisplayServer.clipboard_set(last_result), GoStyle.Tone.COMPACT)
	copy_button.disabled = true
	copy_button.focus_mode = Control.FOCUS_NONE
	content().add_child(copy_button)
	content().add_child(GoStyle.label("历史记录 · 最近 50 条"))
	var clear_history := GoStyle.button("清空历史", func():
		history.clear()
		_rebuild_history()
	, GoStyle.Tone.COMPACT)
	clear_history.focus_mode = Control.FOCUS_NONE
	content().add_child(clear_history)
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
		entry.grab_focus()
		return
	feedback.text = ""
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
		answer.text = "结果：—"
		last_result = ""
		copy_button.disabled = true
	elif key == "退格":
		if entry.has_selection():
			_delete_selection()
		elif entry.caret_column > 0:
			var position := entry.caret_column
			entry.delete_text(position - 1, position)
			entry.caret_column = position - 1
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
		history_list.add_child(GoStyle.label("暂无记录"))
	for record in history:
		var row := HBoxContainer.new()
		history_list.add_child(row)
		var data: Dictionary = record
		var restore := GoStyle.button("%s = %s" % [data["expression"], data["display"]], func():
			entry.text = data["expression"]
			entry.grab_focus()
			entry.caret_column = entry.text.length()
		, GoStyle.Tone.COMPACT)
		restore.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		restore.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		restore.focus_mode = Control.FOCUS_NONE
		row.add_child(restore)
		var copy := GoStyle.button("复制", func(): DisplayServer.clipboard_set(data["display"]), GoStyle.Tone.COMPACT)
		copy.focus_mode = Control.FOCUS_NONE
		row.add_child(copy)
	BoardUiStyle.style_controls(history_list)
	fit_to_window.call_deferred()
