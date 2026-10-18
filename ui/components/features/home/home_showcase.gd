extends PanelContainer

# TEMPORARY PLACEHOLDER: replace with a curated small-platform scene preview
# when the project can author a sufficiently polished scene. Not a live 3D view yet.
const IS_PLACEHOLDER := true
const PLACEHOLDER_TEXTURE = preload("res://ui/theme/illustrations/home_tabletop.tres")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	size_flags_vertical = Control.SIZE_FILL
	clip_children = CanvasItem.CLIP_CHILDREN_AND_DRAW
	var face := FluentTheme.face(Color("f3f7fc"), Color.TRANSPARENT, T.HOME_ILLUSTRATION_RADIUS, 0)
	for edge in ["left", "right", "top", "bottom"]: face.set("content_margin_"+edge, 0)
	add_theme_stylebox_override("panel", face)
	var art := TextureRect.new()
	art.texture = PLACEHOLDER_TEXTURE
	art.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	art.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	art.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(art)
