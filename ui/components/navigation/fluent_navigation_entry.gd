extends Button

const Typography = preload("res://ui/theme/typography.gd")

const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const Motion = preload("res://ui/components/page_motion.gd")
const ButtonFocus = preload("res://ui/components/button_focus.gd")
const ARROW = preload("res://ui/theme/icons/home_arrow.svg")
const CHEVRON = preload("res://ui/theme/icons/home_chevron.svg")

var title := ""
var description := ""
var entry_icon: Texture2D
var primary := false
var minimum_height := float(T.ENTRY_HEIGHT)
var _content: HBoxContainer

func _ready() -> void:
	theme = FluentTheme.shared()
	theme_type_variation = "FluentPrimaryEntry" if primary else "FluentEntry"
	custom_minimum_size.y = minimum_height
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	accessibility_name = title + ("，"+description if not description.is_empty() else "")
	var face := FluentTheme.entry_face(primary)
	add_theme_stylebox_override("normal", face)
	var margin := MarginContainer.new()
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	for edge in ["left", "right"]: margin.add_theme_constant_override("margin_"+edge, 24)
	for edge in ["top", "bottom"]: margin.add_theme_constant_override("margin_"+edge, 16)
	add_child(margin)
	_content = HBoxContainer.new()
	_content.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_content.add_theme_constant_override("separation", 20)
	margin.add_child(_content)
	if entry_icon != null: _content.add_child(_icon(entry_icon, 28))
	var labels := VBoxContainer.new()
	labels.mouse_filter = Control.MOUSE_FILTER_IGNORE
	labels.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	labels.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	labels.add_theme_constant_override("separation", 4)
	_content.add_child(labels)
	labels.add_child(_label(title, Typography.EMPHASIS))
	if not description.is_empty(): labels.add_child(_label(description, Typography.BODY))
	_content.add_child(_icon(ARROW if not description.is_empty() else CHEVRON, 22))
	Motion.prepare_button(self)
	add_child(ButtonFocus.new())
	_update_ink()
	theme_changed.connect(_update_ink)
	set_process(true)

func _process(_delta: float) -> void:
	# Match child content to native disabled state without inventing a second input path.
	_update_ink()

func _update_ink() -> void:
	if _content == null: return
	_content.modulate = T.DISABLED if disabled else (Color.WHITE if primary else T.FOREGROUND)

func set_entry_height(value: float) -> void:
	minimum_height = value
	custom_minimum_size.y = value

func _label(value: String, font_size: int) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_color_override("font_color", Color.WHITE)
	label.add_theme_font_size_override("font_size", font_size)
	if font_size >= Typography.SECTION: label.theme_type_variation = "FluentStrong"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _icon(texture: Texture2D, dimension: int) -> TextureRect:
	var image := TextureRect.new()
	image.texture = texture
	image.custom_minimum_size = Vector2(dimension, dimension)
	image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	image.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return image
