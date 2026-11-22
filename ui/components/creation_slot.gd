extends Button

const Typography = preload("res://ui/theme/typography.gd")
const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
const ButtonFocus = preload("res://ui/components/button_focus.gd")

var entry: Dictionary = {}
var slot_height := BoardUiStyle.CREATION_SLOT_HEIGHT
var thumbnail: Control
var _title_label: Label
var fluent := false
var _selected := false

func _ready() -> void:
	custom_minimum_size = Vector2(BoardUiStyle.CREATION_SLOT_WIDTH, slot_height)
	clip_contents = true
	if fluent:
		set_meta("style_owned", true)
		theme = FluentTheme.shared()
		focus_mode = Control.FOCUS_ALL
		mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
		add_child(ButtonFocus.new())
		_sync_fluent_variation()
	else:
		focus_mode = Control.FOCUS_NONE

func set_slot_height(value: float) -> void:
	slot_height = value
	custom_minimum_size.y = value
	if thumbnail != null:
		thumbnail.custom_minimum_size.y = maxf(24, value - 40)

func set_selected_state(selected_flag: bool) -> void:
	_selected = selected_flag
	if fluent:
		_sync_fluent_variation()
	else:
		set_pressed_no_signal(selected_flag)

func _sync_fluent_variation() -> void:
	theme_type_variation = &"FluentAssetSlotSelected" if (_selected and not disabled) else &"FluentAssetSlot"
	if is_instance_valid(_title_label):
		_title_label.add_theme_color_override("font_color", T.BRAND if (_selected and not disabled) else T.FOREGROUND)

func configure(data: Dictionary) -> void:
	thumbnail = null
	_title_label = null
	tooltip_text = ""
	entry = data.duplicate(true)
	disabled = entry.is_empty()
	if fluent:
		_sync_fluent_variation()
	else:
		BoardUiStyle.creation_slot(self, disabled)
	for child in get_children():
		if child is ButtonFocus:
			continue
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
	var picture := TextureRect.new()
	picture.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	picture.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	picture.mouse_filter = Control.MOUSE_FILTER_IGNORE
	thumbnail = picture
	picture.custom_minimum_size.y = maxf(24, slot_height - 40)
	picture.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_child(picture)
	if entry.has("catalog_kind"): ProductCatalog.request_preview(entry, picture)
	elif entry.get("thumbnail") != null: picture.texture = ImageTexture.create_from_image(entry.thumbnail)
	else: TokenPreviews.request(entry.get("parameters", {}), picture)
	var title := Label.new()
	_title_label = title
	title.text = str(entry.get("title", ""))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.add_theme_font_size_override("font_size", Typography.CAPTION)
	if fluent:
		title.add_theme_color_override("font_color", T.BRAND if _selected else T.FOREGROUND)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	column.add_child(title)
