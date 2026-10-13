extends "res://ui/components/utility_panel.gd"

signal color_changed(value: Color)
var picker: ColorPicker

func _ready() -> void:
	panel_title = "选择颜色"
	preferred_width = 440
	super._ready()
	picker = ColorPicker.new()
	picker.edit_alpha = false
	picker.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	content().add_child(picker)
	picker.color_changed.connect(func(value: Color): color_changed.emit(value))
	_style_content.call_deferred()

func open_color(value: Color, anchor: Rect2) -> void:
	picker.color = value
	place_initial(Vector2(anchor.end.x + 16, anchor.position.y))
	open()
