extends HBoxContainer

func configure(focus_action: Callable, overview_action: Callable) -> void:
	add_theme_constant_override("separation",8)
	for action in [["聚焦选中",focus_action],["查看全景",overview_action]]:
		var button := Button.new()
		button.text = action[0]
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		preload("res://ui/components/page_style.gd").button(button,false,44)
		add_child(button)
		button.pressed.connect(action[1])
