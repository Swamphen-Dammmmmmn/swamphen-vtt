extends Control

# 团员卡 normal/hover 静态对比：组合真实 party_member_card，经公开 set_hover_state_for_showcase 设初态。
# 不模拟鼠标、点击、键盘或触摸，不执行删除、联机或存档写入。
const Card = preload("res://ui/components/cards/party_member_card.gd")
const P = preload("res://ui/theme/tokens/party_tokens.gd")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
const DIR := "res://artifacts/cc-party-card-hover-2026-10-20/"
const RECORDS := [
	{"id": "dm", "nickname": "紫水鸡DM", "display_name": "紫水鸡DM", "role_text": "DM · 本人", "status": "未联机", "online": false, "can_remove": false},
	{"id": "pl1", "nickname": "长昵称的紫水鸡观察员与湿地调查记录员", "display_name": "长昵称的紫水鸡观察员与湿地调查记录员", "role_text": "PL", "status": "在线", "online": true, "can_remove": true},
	{"id": "pl2", "nickname": "观察员", "display_name": "观察员 · 3F2A", "role_text": "PL", "status": "离线", "online": false, "can_remove": true},
]

func _ready() -> void:
	var directory_error := DirAccess.make_dir_recursive_absolute(DIR)
	if directory_error != OK:
		push_error("无法创建团员卡静态展示输出目录：%s" % directory_error)
		return
	get_window().size = Vector2i(1920, 1080)
	var bg := ColorRect.new()
	bg.color = T.BACKGROUND
	bg.set_anchors_preset(Control.PRESET_FULL_RECT)
	add_child(bg)
	var grid := GridContainer.new()
	grid.columns = 2
	grid.position = Vector2(40, 40)
	grid.add_theme_constant_override("h_separation", 40)
	grid.add_theme_constant_override("v_separation", P.LIST_GAP)
	add_child(grid)
	var cards: Array = []
	for record in RECORDS:
		for hovered in [false, true]:
			var card := Card.new()
			card.custom_minimum_size.x = P.WIDTH
			card.set_member(record)
			grid.add_child(card)
			card.set_hover_state_for_showcase(hovered)
			cards.append({"card": card, "id": record.id, "hover": hovered})
	await get_tree().create_timer(1.0).timeout
	await RenderingServer.frame_post_draw
	var image := get_viewport().get_texture().get_image()
	var scale := float(image.get_width()) / float(get_viewport_rect().size.x)
	var crop := image.get_region(Rect2i(Vector2i(0, 0), Vector2i(int(600 * scale), int(290 * scale))))
	crop.resize(crop.get_width() * 2, crop.get_height() * 2, Image.INTERPOLATE_NEAREST)
	var result := crop.save_png(DIR + "hover_compare.png")
	var geometry: Array = []
	for item in cards:
		var rect: Rect2 = item.card.get_global_rect()
		geometry.append({"id": item.id, "hover": item.hover, "rect": [rect.position.x, rect.position.y, rect.size.x, rect.size.y], "min": [item.card.get_combined_minimum_size().x, item.card.get_combined_minimum_size().y]})
	var file := FileAccess.open(DIR + "hover_compare.json", FileAccess.WRITE)
	file.store_string(JSON.stringify(geometry, "\t"))
	print("PARTY_CARD_HOVER_STATIC capture=", result)
