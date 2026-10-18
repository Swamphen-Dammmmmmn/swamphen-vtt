extends Control

const Typography = preload("res://ui/theme/typography.gd")

signal navigation_requested(destination: String, detail: String)
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const FluentButton = preload("res://ui/components/controls/fluent_button.gd")
const Entry = preload("res://ui/components/navigation/fluent_navigation_entry.gd")
const BOARD = preload("res://ui/theme/icons/home_board.svg")
const JOIN = preload("res://ui/theme/icons/home_join.svg")
const BOOK = preload("res://ui/theme/icons/home_book.svg")
const Brand = preload("res://ui/components/features/home/home_brand.gd")
const Showcase = preload("res://ui/components/features/home/home_showcase.gd")
const Footer = preload("res://ui/components/features/home/home_footer.gd")
var _brand: Brand
var _identity: Button
var _scroll: ScrollContainer
var _body: VBoxContainer
var _top: HBoxContainer
var _session: VBoxContainer
var _tools: VBoxContainer
var _tool_grid: GridContainer
var _hero: Showcase
var _footer: Footer
var _title: Label
var _tool_entries: Array[Button] = []
var _notice_area := Rect2()
var _focus_order: Array[Control] = []

func _ready() -> void:
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = FluentTheme.shared()
	var background := ColorRect.new()
	background.color = T.BACKGROUND
	background.mouse_filter = Control.MOUSE_FILTER_IGNORE
	background.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(background)
	_brand = Brand.new()
	add_child(_brand)
	_identity = _button("身份", "identity", GoIconSet.USER)
	add_child(_identity)
	_scroll = ScrollContainer.new()
	_scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	add_child(_scroll)
	_body = VBoxContainer.new()
	_body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_body.add_theme_constant_override("separation", 36)
	_scroll.add_child(_body)
	_top = HBoxContainer.new()
	_top.add_theme_constant_override("separation", 40)
	_body.add_child(_top)
	_session = VBoxContainer.new()
	_session.add_theme_constant_override("separation", 16)
	_session.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_top.add_child(_session)
	var heading := VBoxContainer.new()
	heading.add_theme_constant_override("separation", 8)
	_session.add_child(heading)
	heading.add_child(_label("三维虚拟桌面", Typography.BODY, true))
	_title = _label("开始冒险", Typography.HERO)
	heading.add_child(_title)
	var heading_gap := Control.new()
	heading_gap.custom_minimum_size.y = 8
	heading_gap.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_session.add_child(heading_gap)
	var host := _entry("开团", "主持冒险 · DM", "adventures", BOARD, true)
	var join := _entry("加团", "加入房间 · PL", "join", JOIN)
	_session.add_child(host)
	_session.add_child(join)
	_focus_order.assign([host,join,_identity])
	_hero = Showcase.new()
	_top.add_child(_hero)
	_tools = VBoxContainer.new()
	_tools.add_theme_constant_override("separation", 16)
	_body.add_child(_tools)
	_tools.add_child(_label("创作与工具", Typography.SUBTITLE, true))
	_tool_grid = GridContainer.new()
	_tool_grid.columns = 3
	_tool_grid.add_theme_constant_override("h_separation", 16)
	_tool_grid.add_theme_constant_override("v_separation", 12)
	_tools.add_child(_tool_grid)
	_tool_entries.append(_entry("定制", "", "customize", GoUi.icons().texture(GoIconSet.EDIT)))
	_tool_entries.append(_entry("软件设置", "", "settings", GoUi.icons().texture(GoIconSet.SETTINGS)))
	_tool_entries.append(_entry("教程", "", "tutorials", BOOK))
	for entry in _tool_entries:
		_tool_grid.add_child(entry)
		_focus_order.append(entry)
	_footer = Footer.new()
	_footer.version = str(ProjectSettings.get_setting("application/config/version", ""))
	_footer.exit_requested.connect(func(): navigation_requested.emit("quit", ""))
	add_child(_footer)
	_focus_order.append_array(_footer.focus_targets())
	resized.connect(_fit)
	if Mobile.enabled: Mobile.changed.connect(_fit)
	_fit()
	_update_focus_order()

func _update_focus_order() -> void:
	for index in range(_focus_order.size()):
		_focus_order[index].focus_next = _focus_order[(index+1)%_focus_order.size()].get_path()
		_focus_order[index].focus_previous = _focus_order[posmod(index-1,_focus_order.size())].get_path()

func notification_area() -> Rect2:
	return Rect2(global_position+_notice_area.position, _notice_area.size)

func _button(title: String, destination: String, icon: StringName) -> Button:
	var button := FluentButton.new()
	button.text = title
	button.icon_name = icon
	button.minimum_height = 48
	button.custom_minimum_size.x = 128
	button.pressed.connect(func(): navigation_requested.emit(destination, ""))
	return button

func _entry(title: String, description: String, destination: String, icon: Texture2D, primary := false) -> Button:
	var entry := Entry.new()
	entry.title = title
	entry.description = description
	entry.entry_icon = icon
	entry.primary = primary
	entry.tooltip_text = title
	entry.minimum_height = T.ENTRY_HEIGHT if not description.is_empty() else T.HOME_TOOL_HEIGHT
	entry.pressed.connect(func(): navigation_requested.emit(destination, ""))
	return entry

func _label(value: String, font_size: int, secondary := false) -> Label:
	var label := Label.new()
	label.text = value
	label.add_theme_font_size_override("font_size", font_size)
	label.add_theme_color_override("font_color", T.SECONDARY if secondary else T.FOREGROUND)
	if font_size >= Typography.SUBTITLE: label.theme_type_variation = "FluentStrong"
	label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	return label

func _fit() -> void:
	var safe := Mobile.safe_rect(size)
	var padding := 32 if safe.size.x < 1200 or safe.size.y < 760 else 64
	var side := maxf(padding, (safe.size.x-T.CONTENT_WIDTH)*0.5)
	var left := safe.position.x+side
	var right := safe.end.x-side
	var width := maxf(0,right-left)
	var compact := width < 1120 or safe.size.y < 760
	var narrow := width < 840
	_brand.set_compact(width < 600)
	_brand.position = Vector2(left, safe.position.y+24)
	_brand.size = Vector2(maxf(0,width-144),48)
	_identity.position = Vector2(right-128,safe.position.y+24)
	_identity.size = Vector2(128,48)
	var notice_height := 0 if Mobile.enabled else 56
	_notice_area = Rect2(right-minf(500,width),safe.position.y+84,minf(500,width),48)
	var body_top := safe.position.y+96+notice_height
	_scroll.position = Vector2(left,body_top)
	_scroll.size = Vector2(width,maxf(0,safe.end.y-body_top-T.HOME_FOOTER_HEIGHT-24))
	_footer.position = Vector2(left,safe.end.y-T.HOME_FOOTER_HEIGHT-16)
	_footer.size = Vector2(width,65)
	_title.add_theme_font_size_override("font_size",Typography.PAGE_TITLE if compact else Typography.HERO)
	_hero.visible = not compact
	_tool_grid.columns = 1 if compact else 3
	_session.custom_minimum_size.x = 0 if narrow else width*(0.55 if not compact else 0.56)-24
	_tools.custom_minimum_size.x = 0 if not compact or narrow else width*0.40-24
	_tools.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var tools_parent: Node = _body if not compact or narrow else _top
	if _tools.get_parent() != tools_parent: _tools.reparent(tools_parent)
	if narrow:
		# The session stays in the first row and tools become a second full-width row.
		_session.custom_minimum_size.x = 0
	for entry in _tool_entries: entry.set_entry_height(T.HOME_COMPACT_TOOL_HEIGHT if compact else T.HOME_TOOL_HEIGHT)
	if not _focus_order.is_empty(): _update_focus_order()
