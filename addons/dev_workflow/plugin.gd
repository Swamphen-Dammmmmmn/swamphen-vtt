@tool
extends EditorPlugin

func _enter_tree() -> void:
	var settings := EditorInterface.get_editor_settings()
	settings.set_setting("text_editor/behavior/files/auto_reload_scripts_on_external_change", true)
	settings.set_project_metadata("debug_options", "run_live_debug", true)
	settings.set_project_metadata("debug_options", "run_reload_scripts", true)
