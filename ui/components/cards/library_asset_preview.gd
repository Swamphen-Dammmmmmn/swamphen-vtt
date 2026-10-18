extends PanelContainer

const Typography = preload("res://ui/theme/typography.gd")
# Static catalog preview. No product parsing or 3D world is created here.
var record: Dictionary
var _image: TextureRect
var _placeholder: VBoxContainer
func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var face := preload("res://ui/theme/themes/fluent_theme.gd").face(Color("edf3f8"),Color.TRANSPARENT,8,0)
	face.set_content_margin_all(0)
	add_theme_stylebox_override("panel",face)
	_image = TextureRect.new()
	_image.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	_image.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_image.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_image)
	_placeholder = VBoxContainer.new()
	_placeholder.alignment = BoxContainer.ALIGNMENT_CENTER
	_placeholder.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_placeholder.add_theme_constant_override("separation",8)
	add_child(_placeholder)
	var symbol := TextureRect.new()
	symbol.texture = load("res://ui/theme/icons/library/image.svg")
	symbol.custom_minimum_size = Vector2(24,24)
	symbol.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	symbol.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	symbol.size_flags_horizontal = Control.SIZE_SHRINK_CENTER
	symbol.modulate = Color("a0a0a0")
	symbol.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_placeholder.add_child(symbol)
	var caption := Label.new()
	caption.text = "暂无缩略图"
	caption.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	caption.add_theme_font_size_override("font_size",Typography.TAG)
	caption.add_theme_color_override("font_color",Color("616161"))
	caption.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_placeholder.add_child(caption)
	ProductCatalog.request_preview(record,_image)
	_process(0)
func _process(_delta: float) -> void:
	if _image==null: return
	_placeholder.visible = _image.texture==null
	if _image.texture!=null: set_process(false)
