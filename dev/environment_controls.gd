extends "res://ui/components/utility_panel.gd"

func _ready() -> void:
	panel_title = "开发环境沙盒"
	preferred_width = 360
	super._ready()
	configure_editor()
