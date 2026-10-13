extends MarginContainer

const Style = preload("res://ui/components/page_style.gd")
signal back_requested
signal navigation_requested(page: String, detail: String)
var overlay_layer: CanvasLayer

@onready var content: VBoxContainer = $Layout/Scroll/Content

func _ready() -> void:
	theme = GoUi.theme()
	$Layout.add_theme_constant_override("separation", Style.SECTION_GAP)
	content.add_theme_constant_override("separation", Style.SECTION_GAP)
	Style.button($Layout/Header/Back)
	GoStyle.apply_icon($Layout/Header/Back, GoIconSet.BACK, 20)
	$Layout/Header/Back.pressed.connect(func(): back_requested.emit())
	resized.connect(_fit)
	_fit()

func configure(title: String, subtitle := "", allow_back := true) -> void:
	$Layout/Header/Back.visible = allow_back
	$Layout/Header/Titles/Title.text = title
	$Layout/Header/Titles/Subtitle.text = subtitle
	$Layout/Header/Titles/Subtitle.visible = not subtitle.is_empty()
	$Layout/Header/Titles/Title.add_theme_font_size_override("font_size", Style.TITLE_SIZE)
	$Layout/Header/Titles/Subtitle.add_theme_font_size_override("font_size", Style.BODY_SIZE)
	$Layout/Header/Titles/Subtitle.add_theme_color_override("font_color", Color("64748b"))

func reveal() -> void:
	Style.Motion.fade_in(self)

func add_overlay(control: Control) -> void:
	if not is_instance_valid(overlay_layer):
		overlay_layer = CanvasLayer.new()
		var page_layer := get_canvas_layer_node()
		overlay_layer.layer = page_layer.layer + 1 if page_layer != null else 1
		add_child(overlay_layer)
	control.theme = theme
	overlay_layer.add_child(control)

func _fit() -> void:
	var margin := maxi(Style.PAGE_MARGIN, int((size.x - Style.MAX_WIDTH) / 2.0))
	add_theme_constant_override("margin_left", margin)
	add_theme_constant_override("margin_right", margin)
	add_theme_constant_override("margin_top", Style.PAGE_MARGIN)
	add_theme_constant_override("margin_bottom", Style.PAGE_MARGIN)

func use_fullscreen_content(control: Control) -> void:
	$Layout.hide()
	for edge in ["left", "right", "top", "bottom"]:
		add_theme_constant_override("margin_" + edge, 0)
	if resized.is_connected(_fit): resized.disconnect(_fit)
	add_child(control)
