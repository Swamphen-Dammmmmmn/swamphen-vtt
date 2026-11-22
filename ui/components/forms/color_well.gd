# Shared color entry: Fluent button with a drawn swatch that opens the shared picker popup.
# Assigning color is silent; color_changed fires only for picks made in the popup. Alpha stays 1.
extends Button

signal color_changed(value: Color)

const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
const Motion = preload("res://ui/components/page_motion.gd")
const ButtonFocus = preload("res://ui/components/button_focus.gd")
const PickerPopup = preload("res://ui/components/overlays/color_picker_popup.gd")

# Control that holds the popup, outside any clipped panel; set before the first open.
# Without it the topmost Control ancestor is used.
var popup_host: Control
var popup_title := "选择颜色"
var color := Color("2e7ae0"):
	set(value):
		color = Color(value.r, value.g, value.b, 1.0)
		queue_redraw()
		if not _picking and is_instance_valid(_popup): _popup.set_color_silent(color)
var _popup: PickerPopup
var _picking := false
var _swatch := StyleBoxFlat.new()

func _init() -> void:
	text = "选择颜色"
	# BoardUiStyle.style_controls and legacy panel button passes leave this component alone.
	set_meta("style_owned", true)
	set_process(false)

func _ready() -> void:
	theme = FluentTheme.shared()
	theme_type_variation = "FluentColorWell"
	alignment = HORIZONTAL_ALIGNMENT_LEFT
	text_overrun_behavior = TextServer.OVERRUN_TRIM_ELLIPSIS
	custom_minimum_size.y = maxf(custom_minimum_size.y, T.BUTTON_HEIGHT)
	mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_swatch.set_corner_radius_all(T.COLOR_SWATCH_RADIUS)
	_swatch.set_border_width_all(1)
	Motion.prepare_button(self)
	add_child(ButtonFocus.new())
	pressed.connect(open_popup)

func _draw() -> void:
	var side := T.COLOR_SWATCH_SIZE
	var left := get_theme_stylebox("normal").get_margin(SIDE_LEFT) - T.COLOR_SWATCH_GAP - side
	_swatch.bg_color = color.lerp(T.SURFACE, 0.6) if disabled else color
	_swatch.border_color = T.DISABLED if disabled else T.STROKE
	draw_style_box(_swatch, Rect2(Vector2(left, (size.y - side) * 0.5), Vector2(side, side)))

# BaseButton has no disabled-changed signal. Watch only during an open (including its
# deferred layout), rather than changing popup state from the drawing callback.
func _process(_delta: float) -> void:
	if not is_instance_valid(_popup) or disabled or not is_visible_in_tree(): close_popup()

func open_popup() -> void:
	if disabled or not is_visible_in_tree(): return
	if not is_instance_valid(_popup):
		_popup = PickerPopup.new()
		_popup.title = popup_title
		_host().add_child(_popup)
		_popup.color_changed.connect(_on_picked)
		_popup.dismissed.connect(_on_dismissed)
	else: _popup.set_title(popup_title)
	set_process(true)
	_popup.open_color(color, _rect_in_host())

func is_popup_open() -> bool:
	return is_instance_valid(_popup) and _popup.visible

# Closes the popup (and cancels an open still waiting for layout); does not change the color.
func close_popup() -> void:
	set_process(false)
	if is_instance_valid(_popup): _popup.dismiss()

# Canvas rectangle of the open popup, empty when closed; for hosts that route pointer input.
func get_popup_rect() -> Rect2:
	return _popup.get_global_transform_with_canvas() * Rect2(Vector2.ZERO, _popup.size) if is_popup_open() else Rect2()

func _on_picked(value: Color) -> void:
	if disabled or not is_visible_in_tree() or not is_popup_open(): return
	_picking = true
	color = value
	_picking = false
	color_changed.emit(color)

func _on_dismissed() -> void:
	set_process(false)
	if not is_inside_tree() or is_queued_for_deletion(): return
	# Return focus only when it was inside the popup; a close caused by focusing elsewhere keeps it there.
	var focused := get_viewport().gui_get_focus_owner()
	if is_visible_in_tree() and not disabled and (focused == null or focused == _popup or _popup.is_ancestor_of(focused)):
		grab_focus()

func _rect_in_host() -> Rect2:
	var host := _popup.get_parent() as Control
	return host.get_global_transform_with_canvas().affine_inverse() * get_global_transform_with_canvas() * Rect2(Vector2.ZERO, size)

func _host() -> Control:
	if is_instance_valid(popup_host): return popup_host
	var top: Control = self
	var node := get_parent()
	while node != null and not node is Window:
		if node is Control: top = node
		node = node.get_parent()
	return top

func _notification(what: int) -> void:
	if what == NOTIFICATION_VISIBILITY_CHANGED and not is_visible_in_tree():
		close_popup()
	elif what == NOTIFICATION_EXIT_TREE and is_instance_valid(_popup):
		close_popup()
		_popup.queue_free()
		_popup = null
