extends RefCounted
# Local presentation preference only; never part of adventures or network snapshots.
const StoragePaths = preload("res://scripts/storage_paths.gd")
static var PATH := StoragePaths.data_path("floating_panels.cfg")
static var _loaded := false
static var _positions: Dictionary = {}
static var _reported := false

static func _load_once() -> void:
	if _loaded: return
	_loaded = true
	var config := ConfigFile.new()
	var error := config.load(PATH)
	if error == ERR_FILE_NOT_FOUND: return
	if error != OK or config.get_value("layout", "version", 0) != 1:
		_report("无法读取浮窗位置，暂用默认位置。")
		return
	for key in config.get_section_keys("positions") if config.has_section("positions") else PackedStringArray():
		var value: Variant = config.get_value("positions", key)
		if value is Vector2 and value.is_finite() and value.x >= 0 and value.x <= 1 and value.y >= 0 and value.y <= 1:
			_positions[key] = value
		else:
			_report("部分浮窗位置无效，相应窗口使用默认位置。")

static func position_for(key: String) -> Variant:
	_load_once()
	return _positions.get(key)

static func save_position(key: String, value: Vector2) -> Error:
	_load_once()
	if key.is_empty() or not value.is_finite(): return ERR_INVALID_PARAMETER
	_positions[key] = value.clamp(Vector2.ZERO, Vector2.ONE)
	var config := ConfigFile.new()
	config.set_value("layout", "version", 1)
	for id in _positions: config.set_value("positions", id, _positions[id])
	var error := config.save(PATH)
	if error != OK: _report("浮窗位置本次已保留，但未能保存到本机：" + error_string(error))
	return error

static func _report(message: String) -> void:
	if _reported: return
	_reported = true
	push_warning(message)
