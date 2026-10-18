extends Control

const PreviewImage = preload("res://scripts/library_preview_image.gd")
const Shell = preload("res://ui/components/page_shell.tscn")
const Card = preload("res://ui/components/cards/library_reference_card.gd")

func _ready() -> void:
	BoardUiStyle.configure()
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().content_scale_factor = 1.0
	get_window().size = Vector2i(1400, 780)
	var shell := Shell.instantiate()
	add_child(shell)
	shell.configure_library("预览图片与容器", "adventures")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	shell.use_fullscreen_content(grid)
	var blue := Color8(63, 126, 235, 255)
	for extent in [Vector2i(640,360), Vector2i(400,400), Vector2i(200,400)]:
		var source := Image.create(extent.x, extent.y, false, Image.FORMAT_RGBA8)
		source.fill(blue)
		var result := PreviewImage.prepare(source)
		assert(result.get_pixel(0,0) == blue)
		assert(result.get_width() <= 320 and result.get_height() <= 200)
		assert(absi(result.get_width() * extent.y - result.get_height() * extent.x) <= maxi(extent.x,extent.y))
		assert(PreviewImage.decode(result.save_png_to_buffer(), false) != null)
		print("Preview raw dimensions ", extent, " -> ", result.get_size(), "; corner preserved")
		_add_card(grid, shell, "%d × %d 等比图片" % [extent.x,extent.y], result)
	var alpha := Image.create(12,12,false,Image.FORMAT_RGBA8)
	alpha.fill(Color.TRANSPARENT)
	assert(PreviewImage.prepare(alpha).get_pixel(0,0).a == 0)
	assert(PreviewImage.prepare(alpha).get_size() == Vector2i(12,12))
	var oversize := Image.create(321,200,false,Image.FORMAT_RGBA8)
	assert(PreviewImage.decode(oversize.save_png_to_buffer()) == null)
	var catalog := ProductCatalog.read_list("adventures")
	for entry: Dictionary in catalog.entries:
		if int(entry.get("preview_version",0)) != PreviewImage.VERSION: continue
		var path := ProductCatalog._image("adventures", entry.id, entry.preview_revision)
		var real := ProductCatalog._read_image(path)
		if real != null:
			_add_card(grid, shell, "真实冒险缩略图", real)
			print("Real adventure image dimensions: ", real.get_size())
			break
	for frame in range(8): await get_tree().process_frame
	await RenderingServer.frame_post_draw
	print("Preview sample capture=",get_viewport().get_texture().get_image().save_png("res://logs/library-preview-content-review.png"))

func _add_card(grid: GridContainer, shell: Control, title: String, image: Image) -> void:
	var card := Card.new()
	card.record = {"id":"preview_sample","title":title,"summary":{"map_count":1},"preview_texture":ImageTexture.create_from_image(image)}
	card.library_kind = "adventures"
	card.selection_only = true
	card.primary_text = "打开冒险"
	card.page_shell = shell
	grid.add_child(card)
