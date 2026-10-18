extends Button

const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
const Motion = preload("res://ui/components/page_motion.gd")
const ButtonFocus = preload("res://ui/components/button_focus.gd")

var variant := "FluentButton"
var icon_name: StringName = &""
var minimum_height := 0.0

func _ready() -> void:
	theme = FluentTheme.shared()
	theme_type_variation = variant
	var default_height: float = T.ENTRY_HEIGHT if variant.ends_with("Entry") else (32 if variant=="FluentCompact" else T.BUTTON_HEIGHT)
	custom_minimum_size.y = maxf(minimum_height, default_height)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	if not icon_name.is_empty(): GoStyle.apply_icon(self, icon_name, 24 if variant.ends_with("Entry") else 20)
	if variant!="FluentFilter": Motion.prepare_button(self)
	add_child(ButtonFocus.new())
