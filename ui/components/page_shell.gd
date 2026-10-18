extends MarginContainer

const Typography = preload("res://ui/theme/typography.gd")

const Style = preload("res://ui/components/page_style.gd")
const LibraryPresentation = preload("res://ui/components/features/library/library_presentation.gd")
const LibTokens = preload("res://ui/theme/tokens/library_tokens.gd")
signal back_requested
signal navigation_requested(page: String, detail: String)
var fullscreen_content := false
var overlay_layer: CanvasLayer
var _sensitive_fields: Array[LineEdit] = []
var notification_area_provider: Callable
var _library_mode := false
var _fluent_mode := false
var _library_nav: Control

@onready var content: VBoxContainer = $Layout/Scroll/Content
@onready var _header: HBoxContainer = $Layout/Header
@onready var _back: Button = $Layout/Header/Back
@onready var _title: Label = $Layout/Header/Titles/Title
@onready var _subtitle: Label = $Layout/Header/Titles/Subtitle

func _ready() -> void:
	theme = GoUi.theme()
	$Layout.add_theme_constant_override("separation", Style.SECTION_GAP)
	content.add_theme_constant_override("separation", Style.SECTION_GAP)
	Style.button(_back)
	GoStyle.apply_icon(_back, GoIconSet.BACK, 20)
	_back.pressed.connect(func(): back_requested.emit())
	resized.connect(_fit)
	if Mobile.enabled: Mobile.changed.connect(_fit)
	_fit()

func configure(title: String, subtitle := "", allow_back := true) -> void:
	_back.visible = allow_back
	_title.text = title
	_subtitle.text = subtitle
	_subtitle.visible = not subtitle.is_empty()
	_title.add_theme_font_size_override("font_size", Typography.COMPACT_PAGE_TITLE if Mobile.enabled else Style.TITLE_SIZE)
	_subtitle.add_theme_font_size_override("font_size", Style.BODY_SIZE)
	_subtitle.add_theme_color_override("font_color", Color("64748b"))

func configure_fluent(title: String, subtitle := "", allow_back := true) -> void:
	_fluent_mode = true
	# Apply Fluent theme without library mode
	theme = preload("res://ui/theme/themes/fluent_theme.gd").shared()
	var fluent_tokens = preload("res://ui/theme/tokens/fluent_tokens.gd")

	# Replace back button with Fluent variant
	if not _back.has_meta("fluent_configured"):
		var back := preload("res://ui/components/controls/fluent_button.gd").new()
		back.text = "返回"
		back.icon_name = GoIconSet.BACK
		back.minimum_height = 48
		var previous := _back
		_header.remove_child(previous)
		previous.queue_free()
		back.name = "Back"
		_header.add_child(back)
		_header.move_child(back, 0)
		_back = back
		back.pressed.connect(func(): back_requested.emit())
		_back.set_meta("fluent_configured", true)

	_back.visible = allow_back
	_title.text = title
	_title.theme_type_variation = "FluentStrong"
	_title.add_theme_font_size_override("font_size", Typography.COMPACT_PAGE_TITLE if Mobile.enabled else Typography.PAGE_TITLE)
	_subtitle.text = subtitle
	_subtitle.visible = not subtitle.is_empty()
	_subtitle.add_theme_font_size_override("font_size", fluent_tokens.BODY_SIZE)
	_subtitle.add_theme_color_override("font_color", fluent_tokens.SECONDARY)

	# Apply Fluent background
	queue_redraw()

func configure_library(title: String, kind: String, mode: int = LibraryPresentation.Mode.MANAGE) -> void:
	assert(LibraryPresentation.KINDS.has(kind))
	assert(mode in [LibraryPresentation.Mode.MANAGE, LibraryPresentation.Mode.SELECT])
	if not _library_mode:
		_library_mode = true
		$Layout.add_theme_constant_override("separation", LibTokens.SHELL_GAP)
		theme = preload("res://ui/theme/themes/fluent_theme.gd").shared()
		var back := preload("res://ui/components/controls/fluent_button.gd").new()
		back.text = "返回"
		back.icon_name = GoIconSet.BACK
		back.minimum_height = 48
		var previous := _back
		_header.remove_child(previous)
		previous.queue_free()
		back.name = "Back"
		_header.add_child(back)
		_header.move_child(back,0)
		_back = back
		back.pressed.connect(func(): back_requested.emit())
		_title.theme_type_variation = "FluentStrong"
		_inset_library_row(_header)
	configure(title)
	if _library_nav==null:
		_library_nav = preload("res://ui/components/navigation/library_navigation.gd").new()
		_library_nav.current = kind
		_library_nav.mode = mode
		$Layout.add_child(_library_nav)
		$Layout.move_child(_inset_library_row(_library_nav),0)
		_library_nav.back_requested.connect(func(): back_requested.emit())
		_library_nav.destination_requested.connect(func(route: String): navigation_requested.emit(route,""))
		_back.hide()
	_fit()
	queue_redraw()

func mount_library_controls(controls: Control) -> void:
	controls.reparent($Layout)
	var row: Control = _inset_library_row(controls) if _library_mode else controls
	$Layout.move_child(row,2 if _library_nav!=null else 1)

func _inset_library_row(row: Control) -> MarginContainer:
	var inset := MarginContainer.new()
	for edge in ["left", "right"]:
		inset.add_theme_constant_override("margin_" + edge, LibTokens.CONTENT_INSET)
	var index := row.get_index()
	$Layout.add_child(inset)
	$Layout.move_child(inset, index)
	row.reparent(inset)
	return inset

func _draw() -> void:
	if _library_mode or theme == preload("res://ui/theme/themes/fluent_theme.gd").shared():
		draw_rect(Rect2(Vector2.ZERO, size), preload("res://ui/theme/tokens/fluent_tokens.gd").BACKGROUND)

func reveal() -> void:
	Style.Motion.fade_in(self)

func register_sensitive_field(input: LineEdit) -> void:
	_sensitive_fields.append(input)

func clear_sensitive_fields() -> void:
	for input in _sensitive_fields:
		if is_instance_valid(input): input.clear()
	# Older pages register one input as metadata; keep cleanup compatible during migration.
	if has_meta("password_input"):
		var legacy_input := get_meta("password_input") as LineEdit
		if is_instance_valid(legacy_input): legacy_input.clear()

func navigation_header_rect() -> Rect2:
	return _header.get_global_rect() if not fullscreen_content else Rect2()

func notification_area() -> Rect2:
	return notification_area_provider.call() if notification_area_provider.is_valid() else Rect2()

func add_overlay(control: Control) -> void:
	if not is_instance_valid(overlay_layer):
		overlay_layer = CanvasLayer.new()
		var page_layer := get_canvas_layer_node()
		overlay_layer.layer = page_layer.layer + 1 if page_layer != null else 1
		add_child(overlay_layer)
	control.theme = theme
	overlay_layer.add_child(control)

func _fit() -> void:
	if fullscreen_content: return
	if _fluent_mode and not _library_mode:
		_title.add_theme_font_size_override("font_size", Typography.COMPACT_PAGE_TITLE if Mobile.enabled else Typography.PAGE_TITLE)
	if _library_mode:
		queue_redraw()
		_title.add_theme_font_size_override("font_size", LibTokens.TITLE_SIZE_MOBILE if Mobile.enabled else LibTokens.TITLE_SIZE_DESKTOP)
	var safe := Mobile.safe_rect(size)
	var content_width: float = preload("res://ui/theme/tokens/fluent_tokens.gd").CONTENT_WIDTH if _library_mode else Style.MAX_WIDTH
	var margin := maxi(16 if Mobile.enabled else Style.PAGE_MARGIN, int((safe.size.x - content_width) / 2.0))
	add_theme_constant_override("margin_left", margin+roundi(safe.position.x))
	add_theme_constant_override("margin_right", margin+roundi(size.x-safe.end.x))
	add_theme_constant_override("margin_top", roundi(safe.position.y)+(16 if Mobile.enabled else Style.PAGE_MARGIN))
	add_theme_constant_override("margin_bottom", roundi(size.y-safe.end.y)+(16 if Mobile.enabled else Style.PAGE_MARGIN))

func use_fullscreen_content(control: Control) -> void:
	fullscreen_content = true
	$Layout.hide()
	for edge in ["left", "right", "top", "bottom"]:
		add_theme_constant_override("margin_" + edge, 0)
	if resized.is_connected(_fit): resized.disconnect(_fit)
	add_child(control)
