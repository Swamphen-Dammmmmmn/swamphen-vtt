extends RefCounted
const StoragePaths = preload("res://scripts/storage_paths.gd")

signal changed
static var PATH := StoragePaths.data_path("camera_preferences.cfg")
const SPEEDS := [0.5, 0.75, 1.0, 1.25, 1.5, 2.0]
static var _shared: RefCounted
var values := {"pan": 1.0, "rotation": 1.0, "zoom": 1.0, "reverse_zoom": false, "smooth": false, "strength": 1}
var status := "更改后自动保存在本机。"
var failed := false

static func shared() -> RefCounted:
	if _shared == null:
		_shared = load("res://scripts/camera_preferences.gd").new()
		_shared.read_settings()
	return _shared

func valid(key: String, value: Variant) -> bool:
	if key in ["pan", "rotation", "zoom"]:
		return typeof(value) in [TYPE_FLOAT, TYPE_INT] and SPEEDS.has(float(value))
	if key in ["reverse_zoom", "smooth"]: return typeof(value) == TYPE_BOOL
	if key == "strength": return typeof(value) == TYPE_INT and value >= 0 and value <= 2
	return false

func read_settings() -> void:
	var config := ConfigFile.new()
	var error := config.load(PATH)
	if error == ERR_FILE_NOT_FOUND: return
	if error != OK:
		status = "无法读取镜头设置，暂用默认值（%s）。" % error_string(error)
		failed = true
		return
	for key in values:
		var value: Variant = config.get_value("camera", key, values[key])
		if valid(key, value): values[key] = value
		else: failed = true
	status = "部分镜头设置无效，相应项使用默认值。" if failed else "已读取本机镜头设置。"

func set_value(key: String, value: Variant) -> void:
	if not valid(key, value): return
	values[key] = value
	_save()

func reset_defaults() -> void:
	values = {"pan": 1.0, "rotation": 1.0, "zoom": 1.0, "reverse_zoom": false, "smooth": false, "strength": 1}
	_save()

func _save() -> void:
	var config := ConfigFile.new()
	for key in values: config.set_value("camera", key, values[key])
	var error := config.save(PATH)
	failed = error != OK
	status = "已保存到本机，重启后继续使用。" if not failed else "镜头设置已生效，但无法保存（%s）。" % error_string(error)
	changed.emit()
