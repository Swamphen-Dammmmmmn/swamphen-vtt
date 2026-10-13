extends "res://ui/components/page_modal.gd"
const Field = preload("res://ui/components/page_field.gd")
signal name_saved
var name_field: Control
var confirm: Button
var working := false

func configure_product(title: String, max_length: int, save_name: Callable) -> void:
	content.add_child(Style.text("重命名", 24))
	name_field = Field.new()
	content.add_child(name_field)
	name_field.setup("名称", "填写名称")
	name_field.input.max_length = max_length
	name_field.input.text = title
	add_action("取消",dismiss)
	confirm = add_action("保存",func():
		if working: return
		var value: String = name_field.input.text.strip_edges()
		if value.is_empty():
			name_field.set_error("名称不能为空。")
			name_field.input.grab_focus()
			return
		working = true
		confirm.disabled = true
		var result: Dictionary = save_name.call(value)
		if not result["ok"]:
			name_field.set_error(result["message"])
			working = false
			confirm.disabled = false
			return
		name_saved.emit()
		dismiss()
	,true)
	name_field.input.grab_focus()
	name_field.input.select_all()
