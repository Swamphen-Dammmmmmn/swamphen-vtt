extends "res://ui/components/utility_panel.gd"

signal mode_requested(mode: int)

func _ready() -> void:
	super._ready()
	content().get_node("Algorithm").item_selected.connect(func(index: int): mode_requested.emit(index))

func open() -> void:
	super.open()
	content().get_node("Algorithm").grab_focus()

func close() -> void:
	content().get_node("Algorithm").get_popup().hide()
	super.close()

func set_mode(mode: int) -> void:
	content().get_node("Algorithm").select(mode)

func set_storage_status(message: String, failed: bool) -> void:
	var label := content().get_node("Storage") as Label
	label.text = message
	label.add_theme_color_override("font_color", Color("b33c3c") if failed else Color("64748b"))
	fit_to_window.call_deferred()

func popup_visible() -> bool:
	return content().get_node("Algorithm").get_popup().visible
