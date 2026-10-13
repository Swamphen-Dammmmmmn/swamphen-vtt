extends Button

const PanelScene = preload("res://ui/components/utility_panel.tscn")
const PanelScript = preload("res://ui/components/color_picker_panel.gd")
signal color_changed(value: Color)
var popup_host: Control
var panel: PanelContainer
var swatch: ColorRect
var color := Color("2e7ae0"):
	set(value):
		color = Color(value.r, value.g, value.b, 1.0)
		if swatch != null: swatch.color = color

func _ready() -> void:
	text = "选择颜色"
	swatch = ColorRect.new()
	swatch.mouse_filter = Control.MOUSE_FILTER_IGNORE
	swatch.anchor_top = 0.5
	swatch.anchor_bottom = 0.5
	swatch.offset_left = 12
	swatch.offset_right = 30
	swatch.offset_top = -9
	swatch.offset_bottom = 9
	swatch.color = color
	add_child(swatch)
	panel = PanelScene.instantiate()
	panel.set_script(PanelScript)
	panel.z_index = 20
	popup_host.add_child(panel)
	panel.color_changed.connect(func(value: Color):
		color = value
		color_changed.emit(color)
	)
	panel.panel_closed.connect(func():
		if is_visible_in_tree(): grab_focus()
	)
	pressed.connect(func(): panel.open_color(color, get_global_rect()))

func get_popup() -> PanelContainer:
	return panel

func _exit_tree() -> void:
	if is_instance_valid(panel) and not panel.is_queued_for_deletion(): panel.queue_free()
