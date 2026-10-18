extends HBoxContainer

const Typography = preload("res://ui/theme/typography.gd")

const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const BOARD = preload("res://ui/theme/icons/home_board.svg")
var product_name := "紫水鸡棋盘"
var _compact := false
var _name_label: Label
var _mark: TextureRect

func _ready() -> void:
	theme = FluentTheme.shared()
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_theme_constant_override("separation", 14)
	_mark = TextureRect.new()
	_mark.texture = BOARD
	_mark.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_mark.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_mark.modulate = T.BRAND
	_mark.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_mark)
	_name_label = Label.new()
	_name_label.text = product_name
	_name_label.theme_type_variation = "FluentStrong"
	_name_label.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	_name_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_name_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_name_label)
	set_compact(_compact)

func set_compact(value: bool) -> void:
	_compact = value
	if not is_instance_valid(_name_label): return
	_name_label.add_theme_font_size_override("font_size",Typography.SECTION if value else Typography.COMPACT_PAGE_TITLE)
	_mark.custom_minimum_size = Vector2(32,32) if value else Vector2(40,40)
