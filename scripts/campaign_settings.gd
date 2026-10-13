extends RefCounted
const StoragePaths = preload("res://scripts/storage_paths.gd")

signal distance_mode_changed(mode: int)
signal storage_status_changed(message: String, failed: bool)

static var SETTINGS_PATH := StoragePaths.data_path("campaign_settings.cfg")
var distance_mode := 0
var storage_message := "更改后自动保存在本机，重启后继续使用。"
var storage_failed := false
var persist_to_file := true

func load_settings() -> void:
	var config := ConfigFile.new()
	var error := config.load(SETTINGS_PATH)
	if error == ERR_FILE_NOT_FOUND:
		return
	if error != OK:
		_set_storage_status("无法读取团内设置，暂用默认计距方式（%s）。" % error_string(error), true)
		return
	var value: Variant = config.get_value("rules", "distance_mode", 0)
	if typeof(value) != TYPE_INT or int(value) < 0 or int(value) > 2:
		_set_storage_status("保存的计距方式无效，暂用默认值；重新选择后可保存。", true)
		return
	distance_mode = int(value)
	_set_storage_status("已读取本机保存的团内设置。", false)

func select_distance_mode(mode: int) -> void:
	if mode < 0 or mode > 2:
		return
	if distance_mode != mode:
		distance_mode = mode
		distance_mode_changed.emit(mode)
	if not persist_to_file:
		_set_storage_status("计距方式随当前冒险保存。",false)
		return
	var config := ConfigFile.new()
	config.set_value("meta", "format_version", 1)
	config.set_value("rules", "distance_mode", distance_mode)
	var error := config.save(SETTINGS_PATH)
	if error == OK:
		_set_storage_status("已保存到本机，重启后继续使用。", false)
	else:
		_set_storage_status("当前规则已生效，但无法保存到本机（%s）。" % error_string(error), true)

func _set_storage_status(message: String, failed: bool) -> void:
	storage_message = message
	storage_failed = failed
	storage_status_changed.emit(message, failed)
