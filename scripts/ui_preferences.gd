extends RefCounted
const StoragePaths = preload("res://scripts/storage_paths.gd")

signal changed
signal storage_status_changed(message: String, failed: bool)
static var SETTINGS_PATH := StoragePaths.data_path("ui_preferences.cfg")
static var _shared: RefCounted
var creation_rows := 1
var creation_mode := "pages"
const UI_SCALES := [0.75, 0.85, 1.0, 1.15, 1.25, 1.5]
const INFO_SCALES := [0.75, 1.0, 1.25, 1.5]
const TEXT_SCALES := [0.85, 1.0, 1.15, 1.25]
var ui_scale := 1.0
var info_scale := 1.0
var floating_text := 1.0
var motion := 0
var storage_message := "更改后自动保存在本机。"
var storage_failed := false

static func shared() -> RefCounted:
	if _shared == null:
		_shared = load("res://scripts/ui_preferences.gd").new()
		_shared.load_settings()
	return _shared

func load_settings() -> void:
	var config := ConfigFile.new()
	var error := config.load(SETTINGS_PATH)
	if error == ERR_FILE_NOT_FOUND:
		return
	if error != OK:
		_set_status("无法读取界面设置，暂用默认值（%s）。" % error_string(error), true)
		return
	var rows: Variant = config.get_value("creation_bar", "rows", 1)
	var mode: Variant = config.get_value("creation_bar", "mode", "pages")
	var invalid := false
	if typeof(rows) != TYPE_INT or int(rows) < 1 or int(rows) > 3 or typeof(mode) != TYPE_STRING or mode not in ["pages", "scroll"]:
		invalid = true
	else:
		creation_rows = int(rows)
		creation_mode = str(mode)
	for key in ["ui_scale", "info_scale", "floating_text"]:
		var value: Variant = config.get_value("interface", key, 1.0)
		var choices: Array = UI_SCALES if key == "ui_scale" else (INFO_SCALES if key == "info_scale" else TEXT_SCALES)
		if (typeof(value) == TYPE_FLOAT or typeof(value) == TYPE_INT) and choices.has(float(value)): set(key, float(value))
		else: invalid = true
	var saved_motion: Variant = config.get_value("interface", "motion", 0)
	if typeof(saved_motion) == TYPE_INT and saved_motion >= 0 and saved_motion <= 2: motion = saved_motion
	else: invalid = true
	_set_status("部分界面设置无效，相应项使用默认值。" if invalid else "已读取本机界面设置。", invalid)

func set_rows(rows: int) -> void:
	if rows < 1 or rows > 3:
		return
	creation_rows = rows
	_save()

func set_mode(mode: String) -> void:
	if mode not in ["pages", "scroll"]:
		return
	creation_mode = mode
	_save()

func _save() -> void:
	var config := ConfigFile.new()
	config.set_value("meta", "format_version", 2)
	config.set_value("creation_bar", "rows", creation_rows)
	config.set_value("creation_bar", "mode", creation_mode)
	for key in ["ui_scale", "info_scale", "floating_text", "motion"]: config.set_value("interface", key, get(key))
	var error := config.save(SETTINGS_PATH)
	_set_status("已保存到本机，重启后继续使用。" if error == OK else "当前设置已生效，但无法保存到本机（%s）。" % error_string(error), error != OK)
	changed.emit()

func _set_status(message: String, failed: bool) -> void:
	storage_message = message
	storage_failed = failed
	storage_status_changed.emit(message, failed)

func set_option(key: String, value: Variant) -> void:
	if key == "motion":
		if typeof(value) != TYPE_INT or value < 0 or value > 2: return
	elif key in ["ui_scale", "info_scale", "floating_text"]:
		var choices: Array = UI_SCALES if key == "ui_scale" else (INFO_SCALES if key == "info_scale" else TEXT_SCALES)
		if typeof(value) != TYPE_FLOAT or not choices.has(value): return
	else: return
	set(key, value)
	_save()

func reset_defaults() -> void:
	creation_rows = 1
	creation_mode = "pages"
	ui_scale = 1.0
	info_scale = 1.0
	floating_text = 1.0
	motion = 0
	_save()

func duration(seconds: float) -> float:
	return seconds * [1.0, 0.5, 0.0][motion]
