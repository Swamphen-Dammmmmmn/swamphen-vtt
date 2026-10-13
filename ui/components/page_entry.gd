extends Button

const Style = preload("res://ui/components/page_style.gd")

func setup(title: String, description: String, icon_name: StringName, status := "") -> void:
	Style.button(self)
	custom_minimum_size.y = 148
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for state in ["normal", "hover", "pressed", "disabled", "focus"]:
		var face := BoardUiStyle.card_face(20)
		face.bg_color = Color("e1edfc") if state == "pressed" else (Color("f0f4f9") if state == "hover" else Color.WHITE)
		if state == "focus":
			face.bg_color = Color.TRANSPARENT
			face.border_color = Color("60a5fa")
		add_theme_stylebox_override(state, face)
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 20)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(margin)
	var box := Style.column()
	box.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.add_child(box)
	var row := HBoxContainer.new()
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_theme_constant_override("separation", 12)
	box.add_child(row)
	var icon := GoUi.icons().node(icon_name, 24, Color("2563a6"))
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(icon)
	var name_label := Style.text(title, 20)
	name_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row.add_child(name_label)
	if not status.is_empty():
		row.add_child(Style.text(status, 14, true))
	box.add_child(Style.text(description, 16, true))
	tooltip_text = title + "：" + description
	# Button does not derive minimum size from children; account for wrapped text.
	box.minimum_size_changed.connect(func(): custom_minimum_size.y = maxf(148, box.get_combined_minimum_size().y + 40))
