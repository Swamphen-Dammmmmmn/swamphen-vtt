extends PanelContainer

var application: Node
var button: Button
var dismissed := ""

func _ready() -> void:
	var face := BoardUiStyle.card_face(3)
	face.set_border_width_all(1)
	face.border_color = Color("5d8ccd")
	face.bg_color = Color("eef5ff")
	add_theme_stylebox_override("panel",face)
	var row := HBoxContainer.new()
	add_child(row)
	button = Button.new()
	BoardUiStyle.action_button(button,28)
	GoStyle.apply_icon(button,GoIconSet.DOWNLOAD,16)
	button.focus_mode = Control.FOCUS_NONE
	row.add_child(button)
	button.pressed.connect(func(): Updates.page_requested.emit())
	var close := Button.new()
	BoardUiStyle.action_button(close,28)
	GoStyle.apply_icon(close,GoIconSet.CLOSE,14)
	close.tooltip_text = "本次运行不再提示"
	close.focus_mode = Control.FOCUS_NONE
	row.add_child(close)
	close.pressed.connect(func(): dismissed = Updates.latest; hide())
	Updates.changed.connect(_refresh)
	hide()

func _refresh() -> void:
	button.text = ("更新就绪 · " if Updates.state=="staged" else "新版本 · ")+Updates.latest
	reset_size()

func _process(_delta: float) -> void:
	var route: String = application.current_route
	var shown: bool = Updates.available and Updates.state in ["available","staged"] and dismissed!=Updates.latest
	shown = shown and route in ["home","board","session_menu"] and not is_instance_valid(application.session_modal) and not is_instance_valid(application.token_edit_layer)
	if route=="board" and application.board!=null:
		shown = shown and application.board.tool==0 and not application.board.ui.rename_open() and not application.board.turn_control.panel.visible
		position = Vector2(217,20)
	else:
		position = Vector2(20,18)
		if route=="home" and application.current_page!=null:
			var header: Control = application.current_page.get_node("Layout/Header")
			if get_global_rect().intersects(header.get_global_rect()): position.y = header.get_global_rect().end.y+8
	visible = shown
