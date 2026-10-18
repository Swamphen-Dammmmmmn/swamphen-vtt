extends MarginContainer

# Settings shell component: navigation + content area + status bar
# Handles category switching, content mounting, unified status display

const Typography = preload("res://ui/theme/typography.gd")
const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const FluentTokens = preload("res://ui/theme/tokens/fluent_tokens.gd")
const Header = preload("res://ui/components/layout/fluent_page_header.gd")
const FluentButton = preload("res://ui/components/controls/fluent_button.gd")

signal back_requested()
signal category_selected(key: String)

const CATEGORIES := [
	["video", "视频"],
	["audio", "音效"],
	["interface", "界面"],
	["camera", "镜头"],
	["network", "联机"],
	["tutorial", "教程与提示"],
	["updates", "关于与更新"]
]

var _navigation_buttons: Dictionary = {}
var _content_area: VBoxContainer
var _status_label: Label
var _current_category := ""
var _layout: VBoxContainer
var _navigation: ScrollContainer
var _separator: VSeparator
var _picker: OptionButton
var _content_scroll: ScrollContainer

func _ready() -> void:
	theme = FluentTheme.shared()
	_layout = VBoxContainer.new()
	_layout.add_theme_constant_override("separation", FluentTokens.GAP)
	add_child(_layout)

	# Header with back button and title
	var header := _create_header()
	_layout.add_child(header)
	_picker = OptionButton.new()
	_picker.custom_minimum_size.y = FluentTokens.BUTTON_HEIGHT
	for entry in CATEGORIES:
		_picker.add_item("关于" if entry[0] == "updates" and Mobile.enabled else entry[1])
	_picker.item_selected.connect(func(index: int): _on_category_pressed(CATEGORIES[index][0]))
	_layout.add_child(_picker)

	# Main surface with navigation and content
	var surface := _create_surface()
	_layout.add_child(surface)
	resized.connect(_fit)
	if Mobile.enabled: Mobile.changed.connect(_fit)
	_fit()

func _create_header() -> HBoxContainer:
	var header := Header.new()
	header.title = "软件设置"
	header.back_requested.connect(func(): back_requested.emit())
	return header

func _create_surface() -> PanelContainer:
	var surface := PanelContainer.new()
	surface.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var bg := StyleBoxFlat.new()
	bg.bg_color = FluentTokens.SURFACE
	bg.border_color = FluentTokens.STROKE
	bg.set_border_width_all(1)
	bg.set_corner_radius_all(FluentTokens.RADIUS)
	surface.add_theme_stylebox_override("panel", bg)

	var columns := HBoxContainer.new()
	columns.add_theme_constant_override("separation", 0)
	surface.add_child(columns)

	# Navigation
	var nav_container := _create_navigation()
	_navigation = nav_container
	columns.add_child(nav_container)

	# Separator
	var sep := VSeparator.new()
	_separator = sep
	sep.add_theme_constant_override("separation", 1)
	sep.add_theme_stylebox_override("separator", _create_separator_style())
	columns.add_child(sep)

	# Content area
	var content_column := _create_content_area()
	columns.add_child(content_column)

	return surface

func _create_navigation() -> ScrollContainer:
	var nav := ScrollContainer.new()
	nav.custom_minimum_size.x = 180
	nav.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	nav.size_flags_vertical = Control.SIZE_EXPAND_FILL

	var list := VBoxContainer.new()
	list.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	list.add_theme_constant_override("separation", 4)
	nav.add_child(list)

	# Add margin
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_top", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_bottom", 12)
	list.add_child(margin)

	var buttons_container := VBoxContainer.new()
	buttons_container.add_theme_constant_override("separation", 4)
	margin.add_child(buttons_container)

	for entry in CATEGORIES:
		var button := FluentButton.new()
		button.text = "关于" if entry[0] == "updates" and Mobile.enabled else entry[1]
		button.toggle_mode = true
		button.set_meta("page_motion_prepared", true)
		button.alignment = HORIZONTAL_ALIGNMENT_LEFT
		button.custom_minimum_size.y = 40
		button.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		_apply_nav_button_style(button)
		buttons_container.add_child(button)
		_navigation_buttons[entry[0]] = button
		button.pressed.connect(_on_category_pressed.bind(entry[0]))

	return nav

func _apply_nav_button_style(button: Button) -> void:
	# Normal state - transparent
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color.TRANSPARENT
	normal.set_corner_radius_all(6)
	button.add_theme_stylebox_override("normal", normal)

	# Hover state
	var hover := StyleBoxFlat.new()
	hover.bg_color = FluentTokens.HOVER
	hover.set_corner_radius_all(6)
	button.add_theme_stylebox_override("hover", hover)

	# Pressed (selected) state
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = FluentTokens.NOTICE_BACKGROUND
	pressed.set_corner_radius_all(6)
	button.add_theme_stylebox_override("pressed", pressed)
	button.add_theme_stylebox_override("hover_pressed", pressed)

	button.add_theme_color_override("font_color", FluentTokens.FOREGROUND)
	button.add_theme_color_override("font_hover_color", FluentTokens.FOREGROUND)
	button.add_theme_color_override("font_pressed_color", FluentTokens.BRAND)

func _create_content_area() -> VBoxContainer:
	var column := VBoxContainer.new()
	column.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	column.size_flags_vertical = Control.SIZE_EXPAND_FILL
	column.add_theme_constant_override("separation", 0)

	var scroll := ScrollContainer.new()
	_content_scroll = scroll
	scroll.size_flags_vertical = Control.SIZE_EXPAND_FILL
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	column.add_child(scroll)

	var margin := MarginContainer.new()
	margin.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_top", 20)
	margin.add_theme_constant_override("margin_right", 20)
	margin.add_theme_constant_override("margin_bottom", 20)
	scroll.add_child(margin)

	_content_area = VBoxContainer.new()
	_content_area.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_content_area.add_theme_constant_override("separation", 16)
	margin.add_child(_content_area)

	# Status bar
	var status_container := MarginContainer.new()
	status_container.add_theme_constant_override("margin_left", 20)
	status_container.add_theme_constant_override("margin_right", 20)
	status_container.add_theme_constant_override("margin_bottom", 12)
	column.add_child(status_container)

	_status_label = Label.new()
	_status_label.add_theme_font_size_override("font_size", Typography.CAPTION)
	_status_label.add_theme_color_override("font_color", FluentTokens.SECONDARY)
	_status_label.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	_status_label.hide()
	status_container.add_child(_status_label)

	return column

func _create_separator_style() -> StyleBoxFlat:
	var style := StyleBoxFlat.new()
	style.bg_color = FluentTokens.STROKE
	return style

func _on_category_pressed(key: String) -> void:
	if not _navigation_buttons.has(key): key = "video"
	if _current_category == key:
		_navigation_buttons[key].set_pressed_no_signal(true)
		return

	_current_category = key
	for name in _navigation_buttons:
		_navigation_buttons[name].set_pressed_no_signal(name == key)
	for i in range(CATEGORIES.size()):
		if CATEGORIES[i][0] == key: _picker.select(i)

	category_selected.emit(key)

func select_category(key: String) -> void:
	_on_category_pressed(key)

func get_content_area() -> VBoxContainer:
	return _content_area

func set_status(message: String, is_error: bool = false) -> void:
	if message.is_empty():
		_status_label.hide()
	else:
		_status_label.text = message
		_status_label.add_theme_color_override("font_color", FluentTokens.DANGER if is_error else FluentTokens.SECONDARY)
		_status_label.show()

func clear_content() -> void:
	_content_scroll.scroll_vertical = 0
	for child in _content_area.get_children():
		_content_area.remove_child(child)
		child.queue_free()

func _fit() -> void:
	var safe := Mobile.safe_rect(size)
	var padding := FluentTokens.FORM_PADDING
	add_theme_constant_override("margin_left", roundi(safe.position.x) + padding)
	add_theme_constant_override("margin_right", roundi(size.x - safe.end.x) + padding)
	add_theme_constant_override("margin_top", roundi(safe.position.y) + padding)
	add_theme_constant_override("margin_bottom", roundi(size.y - safe.end.y) + padding)
	var compact := safe.size.x < FluentTokens.SETTINGS_COMPACT_WIDTH
	_navigation.visible = not compact
	_separator.visible = not compact
	_picker.visible = compact

func _draw() -> void:
	draw_rect(Rect2(Vector2.ZERO, size), FluentTokens.BACKGROUND)
