extends Button

const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
const Motion = preload("res://ui/components/page_motion.gd")
const ButtonFocus = preload("res://ui/components/button_focus.gd")
const Icons = preload("res://ui/theme/icons/library_icons.gd")

var variant := "FluentButton"
var icon_name: StringName = &""
var icon_path := ""
var minimum_height := 0.0

func _ready() -> void:
	set_meta("style_owned", true)
	theme = FluentTheme.shared()
	theme_type_variation = variant
	var default_height: float = T.ENTRY_HEIGHT if variant.ends_with("Entry") else (32 if variant=="FluentCompact" else T.BUTTON_HEIGHT)
	if variant.begins_with("FluentToolbar"):
		default_height = T.TOUCH_BUTTON_HEIGHT if Mobile.enabled else T.TOOLBAR_BUTTON_HEIGHT
	custom_minimum_size.y = maxf(minimum_height, default_height)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	var icon_px := 24 if variant.ends_with("Entry") else (16 if variant=="FluentCompact" else 20)
	if variant.begins_with("FluentToolbar"): icon_px = T.TOOLBAR_ICON_SIZE
	if not icon_path.is_empty():
		icon = Icons.texture(icon_path)
		# Native Button must count the icon in its minimum width; expansion omits it.
		expand_icon = icon != null and icon_px > icon.get_width()
		add_theme_constant_override("icon_max_width", icon_px)
		if text.is_empty():
			icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	elif not icon_name.is_empty():
		GoStyle.apply_icon(self, icon_name, icon_px)
	if variant not in ["FluentFilter", "FluentChoice", "FluentChoiceSelected"] and not variant.begins_with("FluentToolbar"): Motion.prepare_button(self)
	add_child(ButtonFocus.new())

func set_variant(next_variant: String) -> void:
	variant = next_variant
	if is_inside_tree():
		theme_type_variation = variant
