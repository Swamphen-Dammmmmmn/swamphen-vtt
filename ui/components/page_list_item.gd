extends PanelContainer

const Style = preload("res://ui/components/page_style.gd")
signal opened

func setup(title: String, description: String, action_text: String, tag := "") -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_stylebox_override("panel", BoardUiStyle.card_face(20))
	var box := Style.column()
	add_child(box)
	box.add_child(Style.text(title, 20))
	if not tag.is_empty():
		box.add_child(Style.text(tag, 14, true))
	box.add_child(Style.text(description, 16, true))
	var actions := HBoxContainer.new()
	box.add_child(actions)
	var button := Button.new()
	button.text = action_text
	Style.button(button, true)
	GoStyle.apply_icon(button, GoIconSet.FORWARD, 18)
	actions.add_child(button)
	button.pressed.connect(func(): opened.emit())
