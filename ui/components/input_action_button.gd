extends Button

# An action inside an input shares the input's boundary and height.
func _init() -> void:
	set_meta("embedded_input_action",true)
	flat = true
	expand_icon = true
	add_theme_constant_override("icon_max_width",20)
	for state in ["normal","hover","pressed","hover_pressed","disabled"]:
		add_theme_stylebox_override(state,StyleBoxEmpty.new())
		add_theme_color_override("icon_"+state+"_color",Color("94a3b8") if state=="disabled" else (Color("2563a6") if state in ["hover","pressed","hover_pressed"] else Color("64748b")))
	var focus := StyleBoxFlat.new()
	focus.bg_color = Color.TRANSPARENT
	focus.set_border_width_all(2)
	focus.border_color = Color("60a5fa")
	focus.set_corner_radius_all(4)
	add_theme_stylebox_override("focus",focus)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	add_child(preload("res://ui/components/button_focus.gd").new())

func fit_input(parent_input: LineEdit) -> void:
	var width := 48.0 if Mobile.enabled else 40.0
	custom_minimum_size = Vector2(width,0)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	anchor_left = 1.0
	offset_left = -width-2
	offset_right = -2
	offset_top = 0
	offset_bottom = 0
	for state in ["normal","read_only","focus"]:
		var face := parent_input.get_theme_stylebox(state).duplicate()
		face.content_margin_right = width+8
		parent_input.add_theme_stylebox_override(state,face)
