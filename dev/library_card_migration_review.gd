extends Control

# Static composition only: no game input, storage writes or thumbnail generation.
@export var mobile_preview := false

const Shell = preload("res://ui/components/page_shell.tscn")
const Card = preload("res://ui/components/cards/library_reference_card.gd")
const Typography = preload("res://ui/theme/typography.gd")
const Presentation = preload("res://ui/components/features/library/library_presentation.gd")

func _ready() -> void:
	BoardUiStyle.configure()
	get_window().content_scale_mode = Window.CONTENT_SCALE_MODE_DISABLED
	get_window().content_scale_factor = 1.0
	get_window().size = Vector2i(1440, 880)
	var shell := Shell.instantiate()
	add_child(shell)
	shell.configure_library("统一卡片 · 管理 / 选择", "tokens")
	var grid := GridContainer.new()
	grid.columns = 4
	grid.add_theme_constant_override("h_separation", 16)
	grid.add_theme_constant_override("v_separation", 16)
	shell.use_fullscreen_content(grid)
	grid.position = Vector2(24, 24)
	var cards: Array[Control] = []
	for selection in [false, true]:
		for kind in ["tokens", "platforms", "maps", "adventures"]:
			var card := Card.new()
			card.library_kind = kind
			card.record = {"id": "sample", "title": Presentation.noun(kind) + " · 中文长名称单行省略样例", "kind": "basic" if kind == "tokens" else kind, "tags": ["战士"], "summary": {"width_feet": 8, "length_feet": 12, "thickness_feet": 0.5, "platform_count": 12, "map_count": 4}}
			card.force_mobile = mobile_preview
			card.selection_only = selection
			card.primary_text = ("打开冒险" if kind == "adventures" else "添加") if selection else "编辑"
			card.page_shell = shell
			grid.add_child(card)
			cards.append(card)
	for frame in range(8): await get_tree().process_frame
	var expected: Dictionary = cards[0].layout_snapshot_for_showcase()
	for card in cards:
		var geometry: Dictionary = card.layout_snapshot_for_showcase()
		assert(card.size == cards[0].size)
		assert(geometry.title == expected.title and geometry.rail_y == expected.rail_y)
		print("LibraryCard migration ", card.library_kind, " select=", card.selection_only, " geometry=", geometry)
	await RenderingServer.frame_post_draw
	print("LibraryCard migration capture=", get_viewport().get_texture().get_image().save_png("res://logs/library-card-migration-mobile.png" if mobile_preview else "res://logs/library-card-migration.png"))
