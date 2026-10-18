extends Control
# 初始已展开的静态展示；不模拟点击或游戏输入。
const Menu = preload("res://ui/components/overlays/vertical_command_menu.gd")
var menu: Menu
func _ready() -> void:
	$DemoAnchor.text = ""
	$DemoAnchor.icon = load("res://ui/theme/icons/library/more.svg")
	$DemoAnchor.expand_icon = true
	$DemoAnchor.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
	$DemoAnchor.add_theme_constant_override("icon_max_width",20)
	var layer := CanvasLayer.new()
	layer.layer = 101
	add_child(layer)
	menu = Menu.new()
	layer.add_child(menu)
	var actions: Array[Dictionary] = [
		{"title":"重命名","id":"rename","icon":"res://ui/theme/icons/library/edit.svg"},
		{"title":"复制","id":"copy","icon":"res://ui/theme/icons/library/copy.svg"},
		{"title":"删除…","id":"delete","danger":true,"separator_before":true}
	]
	menu.open($DemoAnchor, actions)
	await get_tree().process_frame
	await get_tree().process_frame
	print("VERTICAL_MENU_STATIC ",menu.layout_snapshot())
	await RenderingServer.frame_post_draw
	var target := "res://logs/vertical-menu-root-preview-20261017.png"
	print("VERTICAL_MENU_CAPTURE ",get_viewport().get_texture().get_image().save_png(target))
