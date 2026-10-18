extends MenuButton
# Native MenuButton owns the popup and its press/focus lifecycle.
func _ready() -> void:
	theme = preload("res://ui/theme/themes/library_reference_theme.gd").shared()
	theme_type_variation = "LibraryIcon"
	icon = load("res://ui/theme/icons/library/more.svg")
	expand_icon = true
	icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_theme_constant_override("icon_max_width",20)
	tooltip_text = "更多操作"
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
