extends RefCounted
const StoragePaths = preload("res://scripts/storage_paths.gd")

static var PATH := StoragePaths.data_path("identity.json")

static func validate(data: Dictionary) -> String:
	if typeof(data.get("nickname")) != TYPE_STRING or data["nickname"].strip_edges().is_empty() or data["nickname"].length() > 40:
		return "昵称不能为空，最多40个字符。"
	if typeof(data.get("code")) != TYPE_STRING: return "身份码无效。"
	var code: String = data["code"]
	if code.length() < 32 or code.length() > 128: return "身份码须为32～128位。"
	for character in code:
		if not character in "abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ0123456789_-":
			return "身份码只允许英文字母、数字、下划线和连字符。"
	return ""

static func read() -> Dictionary:
	if not FileAccess.file_exists(PATH):
		if FileAccess.file_exists(PATH+".bak") or FileAccess.file_exists(PATH+".tmp"):
			return _error("身份文件缺失，发现备份或未完成的保存文件。未生成新身份，原文件已保留。")
		var code := Crypto.new().generate_random_bytes(16).hex_encode()
		if code.length() != 32: return _error("无法生成本机身份码。")
		return save({"nickname":"玩家", "code":code}, {})
	return _read_file()

static func _read_file() -> Dictionary:
	var file := FileAccess.open(PATH,FileAccess.READ)
	if file == null: return _error("无法读取本机身份（%s）。" % error_string(FileAccess.get_open_error()))
	if file.get_length() > 4096: return _error("本机身份文件格式无效，原文件已保留。")
	var parsed: Variant = JSON.parse_string(file.get_as_text())
	if not parsed is Dictionary or parsed.get("version") != 1: return _error("本机身份文件损坏或版本不支持，原文件已保留。")
	var message := validate(parsed)
	if not message.is_empty(): return _error(message+"原文件已保留。")
	return {"ok":true,"data":{"nickname":parsed["nickname"],"code":parsed["code"]}}

static func save(data: Dictionary, expected: Dictionary) -> Dictionary:
	var message := validate(data)
	if not message.is_empty(): return _error(message)
	if FileAccess.file_exists(PATH):
		var current := _read_file()
		if not current["ok"]: return current
		if current["data"] != expected: return _error("本机身份已在其他窗口修改，请重新进入身份页面。")
	elif not expected.is_empty():
		return _error("本机身份文件已丢失，未覆盖备份。")
	var saved := {"nickname":str(data["nickname"]).strip_edges(),"code":data["code"]}
	var record := saved.duplicate()
	record["version"] = 1
	var temporary := PATH+".tmp"
	var file := FileAccess.open(temporary,FileAccess.WRITE)
	if file == null: return _error("无法保存本机身份（%s）。" % error_string(FileAccess.get_open_error()))
	file.store_string(JSON.stringify(record,"\t"))
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK: return _error("本机身份写入失败，修改未生效。")
	var original := FileAccess.file_exists(PATH)
	var backup := PATH+".bak"
	if original:
		if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup) != OK: return _error("无法更新身份备份，原身份未改动。")
		if DirAccess.rename_absolute(PATH,backup) != OK: return _error("无法替换身份文件，原身份未改动。")
	if DirAccess.rename_absolute(temporary,PATH) != OK:
		var recovered := not original or DirAccess.rename_absolute(backup,PATH) == OK
		return _error("身份保存失败。"+("原身份未改动。" if recovered else "原身份保留在备份中。"))
	return {"ok":true,"data":saved}

static func _error(message: String) -> Dictionary:
	return {"ok":false,"message":message}
