extends Button

const Typography = preload("res://ui/theme/typography.gd")

const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const CHEVRON = preload("res://ui/theme/icons/home_chevron.svg")
const Motion = preload("res://ui/components/page_motion.gd")
const ButtonFocus = preload("res://ui/components/button_focus.gd")
var title := ""
var preview_texture: Texture2D

func _ready() -> void:
	theme = FluentTheme.shared()
	theme_type_variation = "FluentEntry"
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_default_cursor_shape = Control.CURSOR_ARROW if disabled else Control.CURSOR_POINTING_HAND
	accessibility_name = title + ("，未开放" if disabled else "")
	var column := VBoxContainer.new()
	column.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	column.add_theme_constant_override("separation", 0)
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(column)
	var preview := TextureRect.new()
	preview.texture = preview_texture # Deliberately blank until category artwork is selected.
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(preview)
	var footer := MarginContainer.new()
	footer.custom_minimum_size.y = T.CATEGORY_FOOTER_HEIGHT
	footer.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for edge in ["left", "right"]: footer.add_theme_constant_override("margin_"+edge, 20)
	column.add_child(footer)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 12)
	row.mouse_filter = Control.MOUSE_FILTER_IGNORE
	footer.add_child(row)
	var labels := VBoxContainer.new()
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	labels.add_theme_constant_override("separation", 4)
	labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(labels)
	var name_label := Label.new()
	name_label.text = title
	name_label.theme_type_variation = "FluentStrong"
	name_label.add_theme_font_override("font", Typography.MEDIUM)
	name_label.add_theme_font_size_override("font_size", Typography.SECTION)
	name_label.add_theme_color_override("font_color", T.SECONDARY if disabled else T.FOREGROUND)
	name_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	labels.add_child(name_label)
	# Keep an equal status row in every card so one unavailable category cannot lift its title.
	var status := Label.new()
	status.text = "未开放" if disabled else ""
	status.custom_minimum_size.y = T.CATEGORY_STATUS_HEIGHT
	status.add_theme_font_size_override("font_size", T.CAPTION_SIZE)
	status.add_theme_color_override("font_color", T.SECONDARY)
	status.mouse_filter = Control.MOUSE_FILTER_IGNORE
	labels.add_child(status)
	if not disabled:
		var arrow := TextureRect.new()
		arrow.texture = CHEVRON
		arrow.modulate = T.SECONDARY
		arrow.custom_minimum_size = Vector2(20,20)
		arrow.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		arrow.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		arrow.size_flags_vertical = Control.SIZE_SHRINK_CENTER
		arrow.mouse_filter = Control.MOUSE_FILTER_IGNORE
		row.add_child(arrow)
	Motion.prepare_button(self)
	add_child(ButtonFocus.new())

func set_extent(width: float, compact: bool) -> void:
	var ratio: float = T.CATEGORY_COMPACT_PREVIEW_RATIO if compact else T.CATEGORY_PREVIEW_RATIO
	custom_minimum_size = Vector2(width, roundf(width*ratio)+T.CATEGORY_FOOTER_HEIGHT)
