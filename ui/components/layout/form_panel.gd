extends MarginContainer

# The outer container provides flexible margins; the surface itself stays bounded.
const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")

@export var max_width: float = T.FORM_WIDTH
@export var enable_responsive := true
var content_area := VBoxContainer.new()

func _init() -> void:
	var surface := PanelContainer.new()
	surface.theme = FluentTheme.shared()
	surface.add_theme_stylebox_override("panel", FluentTheme.face(T.SURFACE, T.STROKE, T.ENTRY_RADIUS))
	add_child(surface)
	var padding := MarginContainer.new()
	# Theme face already contributes 16 horizontal and 8 vertical units.
	for edge in ["left", "right"]:
		padding.add_theme_constant_override("margin_" + edge, T.FORM_PADDING - 16)
	for edge in ["top", "bottom"]:
		padding.add_theme_constant_override("margin_" + edge, T.FORM_PADDING - 8)
	surface.add_child(padding)
	content_area.add_theme_constant_override("separation", T.GAP)
	padding.add_child(content_area)

func _ready() -> void:
	resized.connect(_fit)
	_fit()

func _fit() -> void:
	var inset := maxi(0, floori((size.x - max_width) / 2.0)) if enable_responsive else 0
	add_theme_constant_override("margin_left", inset)
	add_theme_constant_override("margin_right", inset)
