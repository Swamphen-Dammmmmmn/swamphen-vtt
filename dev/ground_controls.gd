extends "res://ui/components/utility_panel.gd"

func _ready() -> void:
	panel_title = "地面材质小样"
	preferred_width = 380
	super._ready()
	configure_editor()
