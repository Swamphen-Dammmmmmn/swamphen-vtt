extends PanelContainer

const FluentButton = preload("res://ui/components/controls/fluent_button.gd")
const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
var application: Node
var button: Button
var dismissed := ""
var _home := false
var _row: HBoxContainer
var _message: Label

func _ready() -> void:
	_build(false)
	Updates.changed.connect(_refresh)
	hide()

func _build(home: bool) -> void:
	_home = home
	if is_instance_valid(_row):
		_row.hide()
		_row.queue_free()
	var face := FluentTheme.face(T.NOTICE_BACKGROUND,T.NOTICE_STROKE,T.RADIUS) if home else BoardUiStyle.card_face(3)
	face.set_border_width_all(1)
	if not home:
		face.border_color = Color("5d8ccd")
		face.bg_color = Color("eef5ff")
	for edge in ["top","bottom"]: face.set("content_margin_"+edge,4)
	add_theme_stylebox_override("panel",face)
	_row = HBoxContainer.new()
	_row.add_theme_constant_override("separation",8)
	add_child(_row)
	_message = null
	if home:
		theme = FluentTheme.shared()
		_message = Label.new()
		_message.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_message.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_message.custom_minimum_size.x = 80
		_message.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_row.add_child(_message)
		button = FluentButton.new()
	else:
		button = Button.new()
		BoardUiStyle.action_button(button,28)
	GoStyle.apply_icon(button,GoIconSet.DOWNLOAD,16)
	button.focus_mode = Control.FOCUS_ALL if home else Control.FOCUS_NONE
	_row.add_child(button)
	button.pressed.connect(func(): Updates.page_requested.emit())
	var close: Button = FluentButton.new() if home else Button.new()
	if not home: BoardUiStyle.action_button(close,28)
	GoStyle.apply_icon(close,GoIconSet.CLOSE,14)
	close.tooltip_text = "本次运行不再提示"
	close.focus_mode = Control.FOCUS_ALL if home else Control.FOCUS_NONE
	_row.add_child(close)
	close.pressed.connect(func(): dismissed = Updates.latest; hide())
	_refresh()

func _refresh() -> void:
	var message := ("更新就绪 · " if Updates.state=="staged" else "新版本 · ")+Updates.latest
	if _home:
		_message.text = message
		_message.tooltip_text = message
		button.text = "查看更新"
	else: button.text = message
	reset_size()

func _process(_delta: float) -> void:
	var route: String = application.current_route
	var home_mode := route=="home"
	if home_mode != _home: _build(home_mode)
	var shown: bool = Updates.available and Updates.state in ["available","staged"] and dismissed!=Updates.latest
	shown = shown and not OS.has_feature("android") and route in ["home","board","session_menu"] and not is_instance_valid(application.session_modal) and not is_instance_valid(application.token_edit_layer)
	if route=="board" and application.board!=null:
		shown = shown and application.board.tool==0 and not application.board.ui.rename_open() and not application.board.turn_control.panel.visible
		position = Vector2(217,20)
	elif home_mode and application.current_page!=null:
		var area: Rect2 = application.current_page.notification_area()
		position = area.position
		size = area.size
	else:
		position = Vector2(20,18)
	visible = shown
