extends Control

# Settings page: coordinates settings shell and category content

signal back_requested()

const SettingsShell = preload("res://ui/components/features/settings/settings_shell.gd")
const GraphicsPanel = preload("res://ui/components/graphics_settings_panel.gd")
const InterfaceSettings = preload("res://ui/components/features/settings/interface_settings.gd")
const CameraSettings = preload("res://ui/components/features/settings/camera_settings.gd")
const PlaceholderCategory = preload("res://ui/components/features/settings/placeholder_category.gd")
const ConnectionSettingsForm = preload("res://ui/components/features/network/connection_settings_form.gd")
const SoftwareUpdatePanel = preload("res://ui/components/software_update_panel.gd")
const AboutSettings = preload("res://ui/components/features/settings/about_settings.gd")
const Preferences = preload("res://scripts/ui_preferences.gd")
const CameraPreferences = preload("res://scripts/camera_preferences.gd")
const NetworkSettings = preload("res://scripts/network_settings.gd")

var _shell: SettingsShell
var _current_category := ""
var _current_content: Node
var _preferences: RefCounted
var _camera_preferences: RefCounted

func _ready() -> void:
	# Create settings shell
	_shell = SettingsShell.new()
	_shell.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_shell.size_flags_vertical = Control.SIZE_EXPAND_FILL
	add_child(_shell)
	_shell.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)

	_shell.back_requested.connect(func(): back_requested.emit())
	_shell.category_selected.connect(_on_category_selected)

	# Load preferences
	_preferences = Preferences.shared()
	_camera_preferences = CameraPreferences.shared()

	# Select initial category
	var initial := "video"
	for arg in OS.get_cmdline_user_args():
		if arg.begins_with("--settings-tab="):
			initial = arg.trim_prefix("--settings-tab=")
			break
	_shell.select_category(initial)

func _on_category_selected(key: String) -> void:
	if key == _current_category:
		return

	# Cancel pending display changes
	Graphics.cancel_display()

	_current_category = key
	_shell.clear_content()

	# Clean up old content
	if _current_content != null:
		_disconnect_category_signals()
		_current_content = null

	var content_area := _shell.get_content_area()

	# Create content based on category
	if key == "video":
		var panel := GraphicsPanel.new()
		panel.set_meta("fluent_variant", true)
		content_area.add_child(panel)
		_current_content = panel
		Graphics.changed.connect(_on_graphics_changed)
		_on_graphics_changed()

	elif key == "interface":
		var settings := InterfaceSettings.new()
		content_area.add_child(settings)
		_current_content = settings
		settings.value_changed.connect(_on_interface_value_changed)
		settings.reset_requested.connect(_preferences.reset_defaults)
		_preferences.changed.connect(_on_preferences_changed)
		_preferences.storage_status_changed.connect(_on_interface_status)
		settings.sync_preferences(_preferences)
		_on_interface_status(_preferences.storage_message, _preferences.storage_failed)

	elif key == "camera":
		var settings := CameraSettings.new()
		content_area.add_child(settings)
		_current_content = settings
		settings.value_changed.connect(_on_camera_value_changed)
		settings.reset_requested.connect(_camera_preferences.reset_defaults)
		_camera_preferences.changed.connect(_on_camera_preferences_changed)
		settings.sync_preferences(_camera_preferences)
		_on_camera_status()

	elif key == "network":
		var form := ConnectionSettingsForm.new()
		content_area.add_child(form)
		_current_content = form

		var options := NetworkSettings.read()
		form.load_settings(options["address"], options["certificate"])

		form.save_requested.connect(func(address: String, certificate_path: String):
			var error := NetworkSettings.save(address, certificate_path)
			if error == OK:
				form.set_result(true, "已保存，下次连接生效")
			else:
				form.set_result(false, "无法保存，请检查地址和公开证书。")
		)
		_shell.set_status("")

	elif key == "updates":
		var about := AboutSettings.new()
		content_area.add_child(about)
		_current_content = about
		_shell.set_status("")

	else:
		# Placeholder for tutorial/audio
		var placeholder := PlaceholderCategory.new()
		var title_map := {"tutorial": "教程与提示", "audio": "音效"}
		placeholder.set_meta("category_title", title_map.get(key, ""))
		content_area.add_child(placeholder)
		_current_content = placeholder
		_shell.set_status("")

func _disconnect_category_signals() -> void:
	if Graphics.changed.is_connected(_on_graphics_changed):
		Graphics.changed.disconnect(_on_graphics_changed)
	if _preferences != null:
		if _preferences.changed.is_connected(_on_preferences_changed):
			_preferences.changed.disconnect(_on_preferences_changed)
		if _preferences.storage_status_changed.is_connected(_on_interface_status):
			_preferences.storage_status_changed.disconnect(_on_interface_status)
	if _camera_preferences != null and _camera_preferences.changed.is_connected(_on_camera_preferences_changed):
		_camera_preferences.changed.disconnect(_on_camera_preferences_changed)

func _on_graphics_changed() -> void:
	if _current_category == "video":
		_shell.set_status(Graphics.status)

func _on_interface_value_changed(key: String, value: Variant) -> void:
	if key == "creation_rows":
		_preferences.set_rows(int(value) + 1)
	elif key == "creation_mode":
		_preferences.set_mode("pages" if int(value) == 0 else "scroll")
	elif key == "motion":
		_preferences.set_option("motion", int(value))
	else:
		_preferences.set_option(key, value)

func _on_preferences_changed() -> void:
	if _current_category == "interface" and _current_content is InterfaceSettings:
		_current_content.sync_preferences(_preferences)

func _on_interface_status(message: String, failed: bool) -> void:
	if _current_category == "interface":
		_shell.set_status(message, failed)

func _on_camera_value_changed(key: String, value: Variant) -> void:
	_camera_preferences.set_value(key, value)

func _on_camera_preferences_changed() -> void:
	if _current_category == "camera" and _current_content is CameraSettings:
		_current_content.sync_preferences(_camera_preferences)
	_on_camera_status()

func _on_camera_status() -> void:
	if _current_category == "camera":
		_shell.set_status(_camera_preferences.status, _camera_preferences.failed)

func _exit_tree() -> void:
	_disconnect_category_signals()
