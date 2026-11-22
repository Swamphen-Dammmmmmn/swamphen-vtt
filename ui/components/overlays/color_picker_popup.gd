# Shared color picker popup: designer_utility_popup Fluent face (title, close, drag, scrolling body,
# natural height, safe-area bounds) holding the native ColorPicker with all its features except alpha.
# Created and owned by forms/color_well.gd; other code uses the color well's public methods.
extends "res://ui/components/designer_utility_popup.gd"

signal color_changed(value: Color)

const PickerTheme = preload("res://ui/theme/themes/color_picker_theme.gd")

var picker: ColorPicker
var _anchor_rect := Rect2()

func _init() -> void:
	fluent = true
	title = "选择颜色"
	preferred_width = T.COLOR_POPUP_WIDTH

func _ready() -> void:
	super._ready()
	z_index = 20
	focus_mode = Control.FOCUS_ALL
	var inset := MarginContainer.new()
	for side in ["left", "top", "right", "bottom"]:
		inset.add_theme_constant_override("margin_" + side, T.COLOR_PICKER_DRAW_INSET)
	body.add_child(inset)
	picker = ColorPicker.new()
	picker.edit_alpha = false
	picker.theme = PickerTheme.shared(Mobile.enabled)
	picker.set_translation_domain(PickerTheme.translation_domain())
	picker.set_meta("mobile_drag", "native")
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	inset.add_child(picker)
	picker.color_changed.connect(func(value: Color): color_changed.emit(Color(value.r, value.g, value.b, 1.0)))
	gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed: move_to_front())
	get_parent().resized.connect(func(): if visible: fit_at(get_parent().size, last_anchor))

func open_color(value: Color, anchor: Rect2) -> void:
	_anchor_rect = anchor
	set_color_silent(value)
	move_to_front()
	var revision := reveal_revision + 1
	await reveal_at(get_parent().size, anchor.position)
	if revision == reveal_revision and visible: grab_focus()

# Programmatic sync while open; emits nothing.
func set_color_silent(value: Color) -> void:
	if is_instance_valid(picker): picker.color = Color(value.r, value.g, value.b, 1.0)

func dismiss() -> void:
	# Native picker menus are child Windows. Hiding their Control ancestor alone
	# does not define their visibility, so close them together with the owner.
	_hide_child_windows(self)
	super.dismiss()

func _hide_child_windows(node: Node) -> void:
	for child in node.get_children(true):
		_hide_child_windows(child)
		if child is Window and child.visible: child.hide()

func fit_at(available: Vector2, anchor: Vector2) -> void:
	_fit_picker(available)
	super.fit_at(available, anchor)

# The square follows the space left by the popup width and the window height, between the token limits.
# It depends only on the available size, so resizing the square cannot toggle the scrollbar back and forth.
func _fit_picker(available: Vector2) -> void:
	if not is_instance_valid(picker): return
	var safe := Mobile.safe_rect(available)
	var chrome := get_theme_stylebox("panel").get_minimum_size()
	var header := (_frame.get_child(0) as Control).get_combined_minimum_size().y + _frame.get_theme_constant("separation")
	var current := float(picker.get_theme_constant("sv_height"))
	var rest := picker.get_combined_minimum_size().y - current + T.COLOR_PICKER_DRAW_INSET * 2
	var by_height := safe.size.y - 48 - chrome.y - header - rest
	var inner := minf(preferred_width, maxf(1, safe.size.x - 48)) - chrome.x - T.COLOR_PICKER_DRAW_INSET * 2
	if by_height < T.COLOR_SV_MIN:
		inner -= scroll.get_v_scroll_bar().get_combined_minimum_size().x + scroll.get_theme_constant("scrollbar_h_separation")
	var by_width := inner - T.COLOR_HUE_WIDTH - T.COLOR_ROW_GAP
	var side := int(clampf(minf(by_width, by_height), T.COLOR_SV_MIN, T.COLOR_SV_SIZE))
	if int(current) != side:
		picker.add_theme_constant_override("sv_width", side)
		picker.add_theme_constant_override("sv_height", side)

# Beside the entry (right, else left), top-aligned; the base clamps it into the safe area.
func _anchored_position(_anchor: Vector2) -> Vector2:
	var safe := Mobile.safe_rect(get_parent().size)
	var x := _anchor_rect.end.x + T.COLOR_POPUP_GAP
	if x + size.x > safe.end.x: x = _anchor_rect.position.x - T.COLOR_POPUP_GAP - size.x
	# Keep the same 24 edge room the base keeps above; it still clamps when the window is shorter.
	var y := minf(_anchor_rect.position.y, safe.end.y - size.y - 24)
	return Vector2(x, maxf(safe.position.y + 24, y))

func _input(event: InputEvent) -> void:
	if not visible or not (event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE): return
	var focused := get_viewport().gui_get_focus_owner()
	if focused != null and (focused == self or is_ancestor_of(focused)):
		dismiss()
		get_viewport().set_input_as_handled()
