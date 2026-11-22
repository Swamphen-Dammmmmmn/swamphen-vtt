extends Control

const Typography = preload("res://ui/theme/typography.gd")
const FluentTheme = preload("res://ui/theme/themes/fluent_theme.gd")
const T = preload("res://ui/theme/tokens/fluent_tokens.gd")
const FluentButton = preload("res://ui/components/controls/fluent_button.gd")

signal deletion_confirmed(token_id: int)

var target_id := -1
var panel: PanelContainer
var message: Label
var cancel_button: Button
var shade: ColorRect

func _ready() -> void:
	set_meta("style_owned", true)
	set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	theme = FluentTheme.shared()

	shade = ColorRect.new()
	shade.color = Color(0, 0, 0, 0.28)
	shade.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	add_child(shade)
	shade.gui_input.connect(func(event: InputEvent):
		if event is InputEventMouseButton and event.pressed and event.button_index == MOUSE_BUTTON_LEFT:
			hide()
	)

	panel = PanelContainer.new()
	var face := FluentTheme.face(T.SURFACE, T.STROKE, T.RADIUS, 1)
	face.set_content_margin_all(T.FORM_PADDING)
	panel.add_theme_stylebox_override("panel", face)
	add_child(panel)

	var column := VBoxContainer.new()
	column.add_theme_constant_override("separation", T.GAP)
	panel.add_child(column)

	var title := Label.new()
	title.text = "删除棋子"
	title.add_theme_font_override("font", Typography.MEDIUM)
	title.add_theme_font_size_override("font_size", Typography.SECTION)
	column.add_child(title)

	message = Label.new()
	message.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	column.add_child(message)

	var buttons := HBoxContainer.new()
	buttons.add_theme_constant_override("separation", 8)
	buttons.alignment = BoxContainer.ALIGNMENT_END
	column.add_child(buttons)

	cancel_button = FluentButton.new()
	cancel_button.text = "取消"
	cancel_button.pressed.connect(hide)
	buttons.add_child(cancel_button)

	var confirm_button := FluentButton.new()
	confirm_button.text = "删除"
	confirm_button.variant = "FluentDangerOutline"
	confirm_button.pressed.connect(_confirm)
	buttons.add_child(confirm_button)

	resized.connect(_position_panel)
	hide()

func open(data: Dictionary, measurement_count: int) -> void:
	target_id = int(data["id"])
	message.text = "删除“%s”？" % data["title"]
	if measurement_count > 0:
		message.text += "\n同时删除与它绑定的 %d 条测距。" % measurement_count
	message.text += "\n删除后无法撤销。"
	show()
	panel.modulate.a = 0.0
	create_tween().tween_property(panel, "modulate:a", 1.0, preload("res://ui/components/page_motion.gd").duration(BoardUiStyle.FADE_TIME))
	get_parent().move_child(self, get_parent().get_child_count() - 1)
	_position_panel.call_deferred()
	cancel_button.grab_focus()

func _confirm() -> void:
	var id := target_id
	hide()
	deletion_confirmed.emit(id)

func _position_panel() -> void:
	if not is_instance_valid(panel):
		return
	var safe := Mobile.local_safe_rect(self) if Mobile.enabled else Rect2(Vector2.ZERO, size)
	var target_w := minf(400.0, maxf(1.0, safe.size.x - 32.0))
	panel.custom_minimum_size.x = target_w
	panel.reset_size()
	panel.size.x = target_w
	panel.size.y = panel.get_combined_minimum_size().y
	panel.position = safe.position + (safe.size - panel.size) / 2.0

func _input(event: InputEvent) -> void:
	if visible and event is InputEventKey and event.pressed and event.keycode == KEY_ESCAPE:
		hide()
		get_viewport().set_input_as_handled()
