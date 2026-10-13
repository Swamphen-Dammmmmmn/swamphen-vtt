extends Button

const Thumbnail = preload("res://ui/components/token_thumbnail.gd")
var entry: Dictionary = {}
var slot_height := BoardUiStyle.CREATION_SLOT_HEIGHT
var thumbnail: Control

func _ready() -> void:
	custom_minimum_size = Vector2(BoardUiStyle.CREATION_SLOT_WIDTH, slot_height)
	focus_mode = Control.FOCUS_NONE
	clip_contents = true

func set_slot_height(value: float) -> void:
	slot_height = value
	custom_minimum_size.y = value
	if thumbnail != null:
		thumbnail.custom_minimum_size.y = maxf(24, value - 40)

func configure(data: Dictionary) -> void:
	thumbnail = null
	tooltip_text = ""
	entry = data.duplicate(true)
	disabled = entry.is_empty()
	BoardUiStyle.creation_slot(self, disabled)
	for child in get_children():
		remove_child(child)
		child.queue_free()
	if disabled:
		return
	tooltip_text = str(entry.get("tooltip", entry.get("title", "")))
	var margin := MarginContainer.new()
	margin.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	margin.mouse_filter = Control.MOUSE_FILTER_IGNORE
	for edge in ["left", "right", "top", "bottom"]:
		margin.add_theme_constant_override("margin_" + edge, 6)
	add_child(margin)
	var column := VBoxContainer.new()
	column.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_theme_constant_override("separation", 4)
	margin.add_child(column)
	var preview: Control
	if entry.has("thumbnail"):
		var picture := TextureRect.new()
		picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
		if entry["thumbnail"]!=null: picture.texture = ImageTexture.create_from_image(entry["thumbnail"])
		preview = picture
	else:
		preview = Thumbnail.new()
	thumbnail = preview
	preview.custom_minimum_size.y = maxf(24, slot_height - 40)
	preview.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(preview)
	if not entry.has("thumbnail"): preview.configure(entry.get("parameters", {}))
	var title := Label.new()
	title.text = str(entry.get("title", ""))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_size_override("font_size", 14)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)
