extends Button
var presentation := "LibraryAction"
var icon_name := ""
func _ready() -> void:
	theme = preload("res://ui/theme/themes/library_reference_theme.gd").shared()
	theme_type_variation = presentation
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if not icon_name.is_empty():
		icon = load("res://ui/theme/icons/library/"+icon_name+".svg")
		expand_icon = true
		if text.is_empty(): icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		add_theme_constant_override("icon_max_width",14 if presentation=="LibraryTag" else 20)

func content_width() -> float:
	# clip_text deliberately removes text from native minimum width.
	# Measure the complete label before the card constrains the available width.
	var width := get_theme_font("font").get_string_size(text,HORIZONTAL_ALIGNMENT_LEFT,-1,get_theme_font_size("font_size")).x
	var face := get_theme_stylebox("normal")
	width += face.content_margin_left+face.content_margin_right
	if icon!=null: width += get_theme_constant("icon_max_width")+get_theme_constant("h_separation")
	return ceilf(width)
