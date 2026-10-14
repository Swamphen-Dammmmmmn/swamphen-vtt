extends VBoxContainer

const Store = preload("res://scripts/local_identity.gd")
const Style = preload("res://ui/components/page_style.gd")
const Field = preload("res://ui/components/page_field.gd")
const Modal = preload("res://ui/components/page_modal.gd")
var page: Control
var data: Dictionary = {}
var nickname: Field
var code: LineEdit
var save_button: Button
var feedback: Label
var feedback_revision := 0
var dialog: Control

func _ready() -> void:
	page.configure("身份")
	var center := CenterContainer.new()
	add_child(center)
	var card := Style.card()
	center.add_child(card)
	var fit := func(): card.custom_minimum_size.x = minf(560,center.size.x)
	center.resized.connect(fit)
	fit.call_deferred()
	var form := Style.column(16)
	card.add_child(form)
	nickname = Field.new()
	form.add_child(nickname)
	nickname.setup("昵称", "")
	nickname.input.max_length = 40
	form.add_child(Style.text("身份码",16))
	code = LineEdit.new()
	code.editable = false
	code.custom_minimum_size.y = Style.BUTTON_HEIGHT
	form.add_child(code)
	form.add_child(Style.text("在其他设备使用相同身份码，可在同一个团中沿用原成员身份、棋子和个人托盘权限。\n请妥善保存身份码，避免泄露；持有该码的人可能获得同样的权限。",14,true))
	var actions := HBoxContainer.new()
	actions.add_theme_constant_override("separation",8)
	form.add_child(actions)
	var copy := _button("复制身份码",func():
		DisplayServer.clipboard_set(data["code"])
		_notify("已复制")
	)
	actions.add_child(copy)
	var modify := _button("修改身份码",_modify)
	actions.add_child(modify)
	var footer := HBoxContainer.new()
	footer.add_theme_constant_override("separation",8)
	form.add_child(footer)
	feedback = Style.text("",14,true)
	feedback.autowrap_mode = TextServer.AUTOWRAP_OFF
	feedback.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	feedback.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	feedback.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	footer.add_child(feedback)
	save_button = _button("保存",_save,true)
	footer.add_child(save_button)
	var loaded := Store.read()
	if not loaded["ok"]:
		nickname.input.editable = false
		for button in [copy,modify,save_button]: button.disabled = true
		var error := Style.text(loaded["message"],14)
		error.add_theme_color_override("font_color",Color("b33c3c"))
		form.add_child(error)
		return
	data = loaded["data"]
	nickname.input.text = data["nickname"]
	code.text = data["code"]
	nickname.input.text_changed.connect(func(_text: String): save_button.disabled = not _dirty())
	nickname.input.text_submitted.connect(func(_text: String): _save())
	save_button.disabled = true

func _button(title: String, callback: Callable, primary := false) -> Button:
	var button := Button.new()
	button.text = title
	Style.button(button,primary)
	button.pressed.connect(callback)
	return button

func _dirty() -> bool:
	return not data.is_empty() and nickname.input.text != data["nickname"]

func _save() -> bool:
	if data.is_empty(): return false
	var edited := data.duplicate()
	edited["nickname"] = nickname.input.text.strip_edges()
	var result := Store.save(edited,data)
	if not result["ok"]:
		_notify(result["message"],true)
		return false
	data = result["data"]
	nickname.input.text = data["nickname"]
	save_button.disabled = true
	_notify("已保存")
	return true

func _modify() -> void:
	if is_instance_valid(dialog): return
	dialog = Modal.new()
	page.add_overlay(dialog)
	dialog.configure("修改身份码", "身份码用于识别你在团内的身份。修改后再次加入原有团，将无法控制原身份所属的棋子或使用原个人托盘。\n恢复原身份码可重新匹配原成员；修改昵称不会影响权限。")
	var field := Field.new()
	dialog.content.add_child(field)
	field.setup("身份码", "")
	field.input.max_length = 128
	field.input.text = data["code"]
	dialog.add_action("取消",dialog.dismiss)
	dialog.add_action("确认修改",func():
		var edited := data.duplicate()
		edited["code"] = field.input.text
		var result := Store.save(edited,data)
		if not result["ok"]:
			field.set_error(result["message"])
			return
		data = result["data"]
		code.text = data["code"]
		dialog.dismiss()
		_notify("身份码已修改")
	,true)

func has_unsaved_changes() -> bool:
	return _dirty()

func guard_leave(action: Callable) -> bool:
	if is_instance_valid(dialog): return true
	if not _dirty(): return false
	dialog = Modal.new()
	page.add_overlay(dialog)
	dialog.configure("昵称尚未保存", "离开前是否保存？")
	var error := Style.text("",14)
	error.add_theme_color_override("font_color",Color("b33c3c"))
	error.hide()
	dialog.content.add_child(error)
	dialog.add_action("保存并返回",func():
		if _save():
			dialog.dismiss()
			dialog = null
			action.call()
		else:
			error.text = feedback.text
			error.show()
	,true)
	dialog.add_action("放弃修改",func():
		nickname.input.text = data["nickname"]
		dialog.dismiss()
		dialog = null
		action.call()
	)
	dialog.add_action("继续编辑",dialog.dismiss)
	return true

func _notify(message: String, failed := false) -> void:
	feedback_revision += 1
	var revision := feedback_revision
	feedback.text = message
	feedback.tooltip_text = message
	feedback.add_theme_color_override("font_color",Color("b33c3c") if failed else Color("64748b"))
	if failed: return
	get_tree().create_timer(2.5).timeout.connect(func():
		if is_instance_valid(feedback) and revision == feedback_revision: feedback.text = ""
	)
