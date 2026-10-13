extends RefCounted

# Keep directory enumeration errors distinct from a genuinely empty library.
static func list_json(directory_path: String) -> Dictionary:
	var path := ProjectSettings.globalize_path(directory_path)
	var result := {"files":PackedStringArray(),"error":""}
	if not DirAccess.dir_exists_absolute(path): return result
	var directory := DirAccess.open(path)
	if directory == null:
		result["error"] = "无法打开存档目录（%s）。" % error_string(DirAccess.get_open_error())
		return result
	directory.include_hidden = true
	print("目录请求：%s；实际打开：%s" % [path,directory.get_current_dir()])
	var error := directory.list_dir_begin()
	if error != OK:
		result["error"] = "无法列出存档文件（%s）。" % error_string(error)
		push_warning("%s：%s" % [path,result["error"]])
		return result
	var filename := directory.get_next()
	while not filename.is_empty():
		if not directory.current_is_dir() and filename.ends_with(".json"):
			result["files"].append(filename)
		filename = directory.get_next()
	directory.list_dir_end()
	result["files"].sort()
	print("存档目录枚举：%s；文件：%s" % [path,result["files"]])
	return result
