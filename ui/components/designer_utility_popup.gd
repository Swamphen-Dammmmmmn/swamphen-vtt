extends PanelContainer

signal dismissed

const Typography = preload("res://ui/theme/typography.gd")

const Style = preload("res://ui/components/page_style.gd")
const Layout = preload("res://ui/components/editor_layout.gd")
const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
const Icons = preload("res://ui/theme/icons/library_icons.gd")
const ButtonFocus = preload("res://ui/components/button_focus.gd")
var title := "显示设置"
# Set before entering the tree: Fluent face, fixed header/footer, only the body scrolls.
var fluent := false
var preferred_width := 320.0
var body: VBoxContainer
var scroll: ScrollContainer
var footer: VBoxContainer
var dragged := false
var last_available := Vector2.ZERO
var last_anchor := Vector2.ZERO
var fit_pending := false
var reveal_revision := 0
var _title_label: Label
var _frame: VBoxContainer
var _available_rect := Rect2()
var _has_available_rect := false

func _ready() -> void:
	hide()
	z_index = 7
	set_anchors_and_offsets_preset(Control.PRESET_TOP_LEFT)
	size_flags_horizontal = Control.SIZE_SHRINK_BEGIN
	size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	if fluent:
		set_meta("style_owned", true)
		theme = FluentTheme.shared()
		var face := FluentTheme.face(T.SURFACE, T.STROKE, T.RADIUS, 1)
		face.set_content_margin_all(16)
		add_theme_stylebox_override("panel", face)
	else: add_theme_stylebox_override("panel",BoardUiStyle.card_face(12))
	scroll = ScrollContainer.new()
	Layout.scroll(scroll)
	body = Style.column(12)
	body.size_flags_vertical = Control.SIZE_SHRINK_BEGIN
	scroll.add_child(body)
	var header := HBoxContainer.new()
	header.set_meta("mobile_drag","native")
	if fluent:
		_frame = Style.column(12)
		add_child(_frame)
		_frame.add_child(header)
		_frame.add_child(scroll)
		footer = Style.column(8)
		footer.visible = false
		_frame.add_child(footer)
		footer.child_entered_tree.connect(func(_node: Node): footer.visible = true)
		footer.minimum_size_changed.connect(_queue_fit)
		header.minimum_size_changed.connect(_queue_fit)
	else:
		add_child(scroll)
		body.add_child(header)
	body.minimum_size_changed.connect(_queue_fit)
	if Mobile.enabled: Mobile.changed.connect(_queue_fit)
	_title_label = Style.text(title,Typography.SECTION)
	_title_label.autowrap_mode = TextServer.AUTOWRAP_OFF
	_title_label.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	if fluent:
		_title_label.text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
		_title_label.add_theme_font_override("font", Typography.MEDIUM)
		_title_label.add_theme_color_override("font_color", T.FOREGROUND)
		_title_label.mouse_filter = Control.MOUSE_FILTER_PASS
	header.add_child(_title_label)
	var close := Button.new()
	close.tooltip_text = "关闭"
	if fluent:
		close.theme_type_variation = "FluentInputAction"
		close.icon = Icons.texture("res://ui/theme/icons/close_tintable.svg")
		close.expand_icon = true
		close.icon_alignment = HORIZONTAL_ALIGNMENT_CENTER
		close.add_theme_constant_override("icon_max_width", 20)
		close.custom_minimum_size = Vector2(44, 44)
		close.add_child(ButtonFocus.new())
	else:
		GoStyle.apply_icon(close,GoIconSet.CLOSE,18)
		Style.button(close)
		close.custom_minimum_size.x = 36
	close.pressed.connect(dismiss)
	header.add_child(close)
	header.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseMotion and (event.button_mask & MOUSE_BUTTON_MASK_LEFT)!=0:
			dragged = true
			var safe := _layout_rect(get_parent().size)
			position = (position+event.relative).clamp(safe.position,(safe.end-size).max(safe.position))
	)

func set_title(value: String) -> void:
	title = value
	if is_instance_valid(_title_label): _title_label.text = value

func content() -> VBoxContainer:
	return body

# The optional restriction is in the popup parent's coordinates.
func set_available_rect(area: Rect2) -> void:
	if _has_available_rect and _available_rect.is_equal_approx(area):
		return
	_available_rect = area
	_has_available_rect = true
	_queue_fit()

func _layout_rect(available: Vector2) -> Rect2:
	if not _has_available_rect:
		return Mobile.safe_rect(available)
	var safe := Mobile.local_safe_rect(get_parent()) if Mobile.enabled else Rect2(Vector2.ZERO, available)
	return safe.intersection(_available_rect)

func reveal_at(available: Vector2, anchor: Vector2) -> void:
	reveal_revision += 1
	var revision := reveal_revision
	fit_at(available,anchor)
	await get_tree().process_frame
	if not is_inside_tree() or revision!=reveal_revision: return
	fit_at(get_parent().size,anchor)
	show()
	Style.Motion.fade_in(self)

func fit_at(available: Vector2, anchor: Vector2) -> void:
	last_available = available
	last_anchor = anchor
	var chrome := get_theme_stylebox("panel").get_minimum_size()
	var safe := _layout_rect(available)
	custom_minimum_size.x = minf(preferred_width if fluent else 320.0,maxf(1,safe.size.x-48))
	size.x = custom_minimum_size.x
	scroll.size.x = maxf(1,size.x-chrome.x)
	var fixed := 0.0
	if fluent:
		# Header and footer stay visible; only the body shrinks and scrolls.
		var count := 0
		for child in _frame.get_children():
			if child is Control and child.visible:
				count += 1
				if child != scroll: fixed += child.get_combined_minimum_size().y
		fixed += maxi(0, count - 1) * _frame.get_theme_constant("separation")
	var height := minf(body.get_combined_minimum_size().y,maxf(1,safe.size.y-48-chrome.y-fixed))
	scroll.custom_minimum_size.y = height
	size = Vector2(custom_minimum_size.x,height+chrome.y+fixed)
	if not dragged: position = _anchored_position(anchor)
	position = position.clamp(safe.position,(safe.end-size).max(safe.position))

# Undragged placement for the current size; subclasses may place against their own anchor.
func _anchored_position(anchor: Vector2) -> Vector2:
	return Vector2(anchor.x,maxf(24,anchor.y-size.y-12))

func _queue_fit() -> void:
	if fit_pending: return
	fit_pending = true
	_refit.call_deferred()

func _refit() -> void:
	fit_pending = false
	if last_available != Vector2.ZERO:
		var available: Vector2 = get_parent().size if _has_available_rect else last_available
		fit_at(available, last_anchor)

func dismiss() -> void:
	reveal_revision += 1
	var was_visible := visible
	hide()
	if was_visible: dismissed.emit()
