extends Control

const Typography = preload("res://ui/theme/typography.gd")

func _ready() -> void:
	BoardUiStyle.configure()
	get_tree().root.content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_tree().root.content_scale_factor = 1.0
	get_tree().root.size = Vector2i(1100, 650)
	var surface := ColorRect.new()
	surface.color = Color("fafafa")
	surface.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(surface)
	var column := VBoxContainer.new()
	column.position = Vector2(30, 25)
	column.add_theme_constant_override("separation", 12)
	add_child(column)
	for font in [Typography.REGULAR, Typography.MEDIUM, Typography.BOLD]:
		assert(font is FontFile and font.get("multichannel_signed_distance_field") == false)
		print("Typography font=", font.get_font_name(), " / ", font.get_font_style_name(), "; MSDF=", font.get("multichannel_signed_distance_field"))
		var sample := Label.new()
		sample.text = "鸿蒙字体 · 紫水鸡棋盘 · " + font.get_font_style_name() + " · ABC 012345"
		sample.add_theme_font_override("font", font)
		sample.add_theme_font_size_override("font_size", Typography.DIALOG_TITLE)
		sample.add_theme_color_override("font_color", Color("242424"))
		column.add_child(sample)
	assert(Typography.WORLD_REGULAR.get("multichannel_signed_distance_field") == true)
	assert(Typography.WORLD_REGULAR != Typography.REGULAR)
	assert(Typography.REGULAR.get("multichannel_signed_distance_field") == false)
	assert(preload("res://ui/theme/preview_size_font.tres").base_font == Typography.WORLD_REGULAR)
	print("Typography world MSDF=", Typography.WORLD_REGULAR.get("multichannel_signed_distance_field"))
	for text_size in [Typography.TAG, Typography.STATUS, Typography.CAPTION, Typography.BODY, Typography.SUBTITLE, Typography.SECTION, Typography.PAGE_TITLE]:
		var sample := Label.new()
		sample.text = "%d px · 高级棋子 · 创建棋子 · 标签与菜单 · ABC 012345" % text_size
		sample.add_theme_font_override("font", Typography.REGULAR)
		sample.add_theme_font_size_override("font_size", text_size)
		sample.add_theme_color_override("font_color", Color("242424"))
		column.add_child(sample)
	# Loading checks only: do not instantiate scenes or automate game input.
	for directory in ["res://ui", "res://scripts"]:
		_load_scripts(directory)
	for frame in range(8): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	var result := get_viewport().get_texture().get_image().save_png("res://logs/typography-review.png")
	print("Typography review capture=", result)

func _load_scripts(directory: String) -> void:
	for child in DirAccess.get_directories_at(directory):
		_load_scripts(directory.path_join(child))
	for file in DirAccess.get_files_at(directory):
		if file.ends_with(".gd"):
			assert(load(directory.path_join(file)) != null, directory.path_join(file))
