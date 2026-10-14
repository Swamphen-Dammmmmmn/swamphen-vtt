extends PanelContainer

const Style = preload("res://ui/components/page_style.gd")
const Thumbnail = preload("res://ui/components/token_thumbnail.gd")
const CardMenu = preload("res://ui/components/card_menu.gd")
signal edit_requested(id: String)
signal delete_requested(data: Dictionary)
signal copy_requested(id: String)
signal rename_requested(id: String)
signal tags_requested(id: String)
signal upgrade_requested(id: String)
var selection_only := false

func configure(data: Dictionary) -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_stylebox_override("panel", BoardUiStyle.card_face(12))
	var column := Style.column(10)
	add_child(column)
	var preview := TextureRect.new()
	preview.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	preview.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	preview.mouse_filter = Control.MOUSE_FILTER_IGNORE
	preview.custom_minimum_size.y = Style.LIBRARY_PREVIEW_HEIGHT
	column.add_child(preview)
	TokenPreviews.request(data["parameters"],preview)
	var title := Style.text(data["title"], 20)
	title.autowrap_mode = TextServer.AUTOWRAP_OFF
	title.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	title.tooltip_text = data["title"]
	column.add_child(title)
	var type_name := "基础棋子" if data["kind"] == "basic" else "高级棋子"
	var tag_row := HBoxContainer.new()
	tag_row.add_theme_constant_override("separation", 8)
	column.add_child(tag_row)
	var type_tag := Button.new()
	type_tag.text = type_name
	Style.card_button(type_tag, 32)
	type_tag.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	type_tag.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	type_tag.alignment = HORIZONTAL_ALIGNMENT_LEFT
	type_tag.add_theme_font_size_override("font_size", 14)
	type_tag.tooltip_text = "查看棋子类型与分类标签"
	type_tag.pressed.connect(func(): tags_requested.emit(data["id"]))
	tag_row.add_child(type_tag)
	var edit := Button.new()
	edit.text = "添加到托盘" if selection_only else "编辑"
	Style.card_button(edit)
	edit.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	edit.pressed.connect(func(): edit_requested.emit(data["id"]))
	column.add_child(edit)
	var more := Button.new()
	Style.card_button(more)
	more.custom_minimum_size.x = Style.BUTTON_HEIGHT
	more.tooltip_text = "更多棋子操作"
	GoStyle.apply_icon(more, GoIconSet.MORE, 20)
	tag_row.add_child(more)
	if selection_only:
		more.hide()
		type_tag.disabled = true
		Style.Motion.fade_in(self, Style.Motion.NOTICE_FADE)
		return
	more.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	var glyph := more.get_node_or_null("IconGlyph") as Control
	if glyph != null:
		glyph.mouse_filter = Control.MOUSE_FILTER_IGNORE
		glyph.set_anchors_and_offsets_preset(Control.PRESET_CENTER, Control.PRESET_MODE_MINSIZE)
	var menu := CardMenu.new()
	add_child(menu)
	menu.add_action("重命名", 3)
	menu.add_action("复制", 0)
	if data["kind"] == "basic":
		menu.add_action("升级为高级棋子…", 1)
	menu.add_action("删除…", 2, false, true)
	more.pressed.connect(func(): menu.toggle_for(more))
	menu.action_requested.connect(func(id: int):
		match id:
			3: rename_requested.emit(data["id"])
			0: copy_requested.emit(data["id"])
			1: upgrade_requested.emit(data["id"])
			2: delete_requested.emit(data)
	)
	Style.Motion.fade_in(self, Style.Motion.NOTICE_FADE)
