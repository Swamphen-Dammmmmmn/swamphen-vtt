extends PanelContainer

const Style = preload("res://ui/components/page_style.gd")
var message_label: Label

func _init() -> void:
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	add_theme_stylebox_override("panel", BoardUiStyle.card_face(20))
	message_label = Style.text("", 16, true)
	add_child(message_label)
	hide()

func show_message(message: String, is_error := false) -> void:
	var was_visible := visible
	message_label.text = message
	message_label.add_theme_color_override("font_color", Color("b33c3c") if is_error else Color("64748b"))
	show()
	if not was_visible:
		Style.Motion.fade_in(self, Style.Motion.NOTICE_FADE)
