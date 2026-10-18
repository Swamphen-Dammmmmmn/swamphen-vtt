extends HFlowContainer
signal destination_requested(route: String)
signal back_requested
const Presentation = preload("res://ui/components/features/library/library_presentation.gd")
const Action = preload("res://ui/components/controls/library_reference_button.gd")
const LibTokens = preload("res://ui/theme/tokens/library_tokens.gd")
var current := "tokens"
var mode := Presentation.Mode.MANAGE
var _active: Button
var _back_button: Button
var _tabs_group: HBoxContainer

func _ready() -> void:
	custom_minimum_size.y = LibTokens.NAVIGATION_HEIGHT
	add_theme_constant_override("h_separation", 16)
	add_theme_constant_override("v_separation", 8)
	_back_button = Action.new()
	_back_button.text = "返回" if mode == Presentation.Mode.SELECT else "定制"
	_back_button.icon_name = "back"
	_back_button.custom_minimum_size = Vector2(LibTokens.NAVIGATION_BACK_WIDTH, 48)
	add_child(_back_button)
	_back_button.pressed.connect(func(): back_requested.emit())
	if mode == Presentation.Mode.SELECT: return
	_tabs_group = HBoxContainer.new()
	_tabs_group.add_theme_constant_override("separation", LibTokens.NAVIGATION_TAB_GAP)
	add_child(_tabs_group)
	for kind: String in Presentation.KINDS:
		var button := Action.new()
		button.text = Presentation.noun(kind)
		button.custom_minimum_size = Vector2(LibTokens.NAVIGATION_TAB_WIDTH, 48)
		button.presentation = "LibraryTab"
		_tabs_group.add_child(button)
		if kind==current:
			_active = button
			button.add_theme_color_override("font_color", Color("0f6cbd"))
		button.pressed.connect(func():
			if kind!=current: destination_requested.emit(str(Presentation.KINDS[kind].route))
		)
	resized.connect(queue_redraw)
	sort_children.connect(queue_redraw)
	_tabs_group.sort_children.connect(queue_redraw)

func _draw() -> void:
	if is_instance_valid(_active):
		var global_rect := _active.get_global_rect()
		var nav_global_rect := get_global_rect()
		var local_x := global_rect.position.x - nav_global_rect.position.x
		var local_y := global_rect.end.y - nav_global_rect.position.y - 3
		draw_style_box(preload("res://ui/theme/themes/fluent_theme.gd").face(Color("0f6cbd"),Color.TRANSPARENT,2,0),Rect2(local_x+16,local_y,_active.size.x-32,3))
