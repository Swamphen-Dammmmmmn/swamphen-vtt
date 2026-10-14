extends RefCounted
const StoragePaths = preload("res://scripts/storage_paths.gd")

const Sticker = preload("res://scripts/token_sticker.gd")
const Images = preload("res://scripts/token_image_store.gd")
const Parameters = preload("res://scripts/token_parameters.gd")
const AdvancedParameters = preload("res://scripts/advanced_token_parameters.gd")
const Upgrade = preload("res://scripts/token_upgrade.gd")
const Appearance = preload("res://scripts/token_appearance.gd")
static var DIRECTORY := StoragePaths.data_path("products/tokens")
const VERSION := 1
const MAX_FILE_BYTES := 65536
const BUILTIN_DIRECTORY := "res://assets/builtin_tokens"
const BUILTIN_ID := "14169e80e22da50316d06c9b22230ada"
static var BUILTIN_MARKER := StoragePaths.data_path("products/.builtin_tokens_v1")
const Files = preload("res://scripts/product_files.gd")

static func _ensure_builtin_example() -> Dictionary:
	if FileAccess.file_exists(BUILTIN_MARKER): return {"ok": true}
	var source_path := BUILTIN_DIRECTORY.path_join(BUILTIN_ID + ".json")
	var raw: Variant = JSON.parse_string(FileAccess.get_file_as_string(source_path))
	if not raw is Dictionary or raw.get("id") != BUILTIN_ID:
		return _invalid("内置棋子范例数据无效。")
	var specification: Dictionary = raw.get("parameters", {}).get("components", {}).get("standee", {}).get("sticker", {})
	for image_id in Sticker.resource_ids(specification):
		if Images.load_image(image_id)["ok"]: continue
		var bytes := FileAccess.get_file_as_bytes(BUILTIN_DIRECTORY.path_join(image_id + ".img"))
		if Images.content_id(bytes) != image_id: return _invalid("内置棋子范例图片缺失或损坏。")
		var imported := Images.save_image(bytes)
		if not imported["ok"]: return imported
	var checked := _read_record(source_path, BUILTIN_ID + ".json")
	if not checked["ok"]: return checked
	var error := DirAccess.make_dir_recursive_absolute(DIRECTORY)
	if error != OK: return _invalid("无法创建棋子保存目录。")
	var destination := DIRECTORY.path_join(BUILTIN_ID + ".json")
	# 已有同编号的用户产物优先，初始化不覆盖内容或恢复已删除的范例。
	if not FileAccess.file_exists(destination):
		var saved := _write_record(raw, destination)
		if not saved["ok"]: return saved
	var marker := FileAccess.open(BUILTIN_MARKER, FileAccess.WRITE)
	if marker == null: return _invalid("无法记录内置棋子范例的初始化状态。")
	marker.store_string(BUILTIN_ID)
	marker.flush()
	error = marker.get_error()
	marker.close()
	if error != OK:
		DirAccess.remove_absolute(BUILTIN_MARKER)
		return _invalid("无法记录内置棋子范例的初始化状态。")
	return {"ok": true}

static func create(raw: Dictionary) -> Dictionary:
	return _create(raw, [])

static func copy(id: String) -> Dictionary:
	var existing := get_record(id)
	if not existing["ok"]: return _invalid("无法复制棋子：" + existing["message"])
	var record: Dictionary = existing["record"]
	var raw: Dictionary = record["parameters"].duplicate(true)
	raw["kind"] = record["kind"]
	raw["title"] = str(record["title"]).left(35) + " · 副本"
	for key in ["hp", "max_hp", "ac"]:
		raw[key] = "" if int(raw[key]) < 0 else str(int(raw[key]))
	return _create(raw, record["tags"].duplicate())

static func upgrade(id: String, replace_original := false) -> Dictionary:
	var existing := get_record(id)
	if not existing["ok"]: return _invalid("无法升级棋子：" + existing["message"])
	var source: Dictionary = existing["record"]
	if source["kind"] != "basic": return _invalid("只有基础棋子可以升级。")
	var raw := Upgrade.from_basic(source)
	if not replace_original: return _create(raw, source["tags"].duplicate())
	var checked := validate(raw)
	if not checked["ok"]: return checked
	var params: Dictionary = checked["parameters"].duplicate(true)
	var title: String = params["title"]
	params.erase("title")
	params["color"] = params["color"].to_html(false)
	var record := {"format_version": 2, "id": id, "kind": "advanced", "title": title, "tags": source["tags"].duplicate(), "parameters": params}
	return _write_record(record, DIRECTORY.path_join(id + ".json"))

static func _create(raw: Dictionary, tags: Array) -> Dictionary:
	var checked := validate(raw)
	if not checked["ok"]: return checked
	var error := DirAccess.make_dir_recursive_absolute(DIRECTORY)
	if error != OK:
		return {"ok": false, "message": "无法创建棋子保存目录（%s），填写内容已保留。" % error_string(error)}
	var id := ""
	var final_path := ""
	for attempt in range(6):
		id = Crypto.new().generate_random_bytes(16).hex_encode()
		final_path = DIRECTORY.path_join(id + ".json")
		if not FileAccess.file_exists(final_path): break
		id = ""
	if id.is_empty():
		return {"ok": false, "message": "无法生成独立棋子编号，请重试。"}
	var params: Dictionary = checked["parameters"].duplicate(true)
	var title: String = params["title"]
	params.erase("title")
	params["color"] = params["color"].to_html(false)
	var record := {"format_version": 2 if raw.get("kind", "basic") == "advanced" else VERSION, "id": id, "kind": raw.get("kind", "basic"), "title": title, "tags": tags, "parameters": params}
	return _write_record(record, final_path)

static func get_record(id: String) -> Dictionary:
	if not _matches(id, "^[0-9a-f]{32}$"): return _invalid("棋子编号无效")
	return _read_record(DIRECTORY.path_join(id + ".json"), id + ".json")

static func update(id: String, raw: Dictionary) -> Dictionary:
	var existing := get_record(id)
	if not existing["ok"]: return _invalid("无法加载原棋子，修改未保存：" + existing["message"])
	var input := raw.duplicate(true)
	input["kind"] = existing["record"]["kind"]
	var checked := validate(input)
	if not checked["ok"]: return checked
	var params: Dictionary = checked["parameters"].duplicate(true)
	var title: String = params["title"]
	params.erase("title")
	params["color"] = params["color"].to_html(false)
	var record := {"format_version": 2 if existing["record"]["kind"] == "advanced" else VERSION, "id": id, "kind": existing["record"]["kind"], "title": title, "tags": existing["record"]["tags"], "parameters": params}
	return _write_record(record, DIRECTORY.path_join(id + ".json"))

static func rename(id: String, title: String) -> Dictionary:
	var loaded := get_record(id)
	if not loaded["ok"]: return loaded
	var raw: Dictionary = loaded["record"]["parameters"].duplicate(true)
	raw["title"] = title
	raw["kind"] = loaded["record"]["kind"]
	for key in ["hp","max_hp","ac"]:
		raw[key] = "" if int(raw[key])<0 else str(int(raw[key]))
	return update(id,raw)

static func delete(id: String) -> Dictionary:
	var existing := get_record(id)
	if not existing["ok"]: return _invalid("无法删除棋子：" + existing["message"])
	var error := DirAccess.remove_absolute(DIRECTORY.path_join(id + ".json"))
	if error != OK: return _invalid("删除失败（%s），请重试。" % error_string(error))
	for suffix in [".bak",".tmp"]:
		var path: String = DIRECTORY.path_join(id+".json")+suffix
		if FileAccess.file_exists(path): DirAccess.remove_absolute(path)
	return {"ok": true}

static func _write_record(record: Dictionary, final_path: String) -> Dictionary:
	var dependency := _check_image(record)
	if not dependency["ok"]: return dependency
	var encoded := JSON.stringify(record, "\t")
	if encoded.to_utf8_buffer().size() > MAX_FILE_BYTES: return _invalid("棋子数据超过64 KB保存预算，请减少轮廓复杂度。")
	var temporary := final_path + ".tmp"
	var file := FileAccess.open(temporary, FileAccess.WRITE)
	if file == null:
		return {"ok": false, "message": "无法写入棋子文件（%s），填写内容已保留。" % error_string(FileAccess.get_open_error())}
	file.store_string(encoded)
	file.flush()
	var error := file.get_error()
	file.close()
	if error != OK:
		DirAccess.remove_absolute(temporary)
		return {"ok": false, "message": "保存棋子失败（%s），填写内容已保留。" % error_string(error)}
	var backup := final_path+".bak"
	var original := FileAccess.file_exists(final_path)
	if original:
		if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup)!=OK: return _invalid("无法更新棋子备份，原文件未改动。")
		if DirAccess.rename_absolute(final_path,backup)!=OK: return _invalid("无法替换原棋子，原文件未改动。")
	error = DirAccess.rename_absolute(temporary,final_path)
	if error!=OK:
		var recovered := not original or DirAccess.rename_absolute(backup,final_path)==OK
		return _invalid("保存棋子失败，修改已保留。"+("原文件已恢复。" if recovered else "原文件保留在备份中。"))
	TokenPreviews.refresh_saved.call_deferred(str(record["id"]))
	return {"ok": true, "id": record["id"]}

static func read_all() -> Dictionary:
	var result := {"entries": [], "error": "", "warnings": []}
	var builtin := _ensure_builtin_example()
	if not builtin["ok"]:
		result["warnings"].append("内置高级棋子范例：" + builtin["message"])
	var listed := Files.list_json(DIRECTORY)
	result["error"] = listed["error"]
	for filename in listed["files"]:
		if not filename.ends_with(".json"): continue
		var loaded := _read_record(DIRECTORY.path_join(filename), filename)
		if loaded["ok"]:
			result["entries"].append(loaded["record"])
		else:
			result["warnings"].append(filename + "：" + loaded["message"])
			push_warning("棋子库读取失败：" + filename + "：" + loaded["message"])
	return result

static func _read_record(path: String, filename: String) -> Dictionary:
	var file := FileAccess.open(path, FileAccess.READ)
	if file == null: return _invalid("无法打开文件")
	if file.get_length() > MAX_FILE_BYTES:
		file.close()
		return _invalid("超过棋子文件大小限制")
	var text := file.get_as_text()
	var error := file.get_error()
	file.close()
	if error != OK and error != ERR_FILE_EOF: return _invalid("读取失败")
	var json := JSON.new()
	if json.parse(text) != OK or not json.data is Dictionary: return _invalid("文件格式无效")
	var record: Dictionary = json.data
	if not _integer(record.get("format_version")) or int(record["format_version"]) not in [1, 2]:
		return _invalid("不支持的文件版本")
	var id = record.get("id")
	if not id is String or not _matches(id, "^[0-9a-f]{32}$") or filename != id + ".json":
		return _invalid("棋子编号无效")
	if record.get("kind") not in ["basic", "advanced"]: return _invalid("尚不支持此棋子类型")
	if record["kind"] == "advanced" and int(record["format_version"]) != 2: return _invalid("高级棋子版本无效")
	var title = record.get("title")
	var params = record.get("parameters")
	var tags = record.get("tags")
	if not title is String or not params is Dictionary or not tags is Array: return _invalid("缺少有效的棋子字段")
	if tags.size() > 32: return _invalid("分类标签数量过多")
	for tag in tags:
		if not tag is String or tag.strip_edges().is_empty() or tag.length() > 40:
			return _invalid("分类标签无效")
	var raw: Dictionary
	if record["kind"] == "basic":
		if not _integer(params.get("size")) or int(params["size"]) < 1 or int(params["size"]) > 5: return _invalid("占地无效")
		if params.get("base") not in Appearance.BASES: return _invalid("底座无效")
		var color = params.get("color")
		if not color is String or not _matches(color, "^[0-9a-fA-F]{6}$"): return _invalid("颜色无效")
		raw = {"title": title, "size": int(params["size"]), "base": params["base"], "color": Color.from_string(color, Color.WHITE)}
		if params.has("materials"): raw["materials"] = params["materials"]
	else:
		if not _integer(params.get("component_version")) or int(params["component_version"]) not in [1, 2]: return _invalid("不支持的组件版本")
		if not params.get("components") is Dictionary: return _invalid("组件无效")
		for component in ["base", "standee"]:
			var data = params["components"].get(component)
			if not data is Dictionary or not data.get("offset_ft") is Array: return _invalid("位置数据无效")
			if data["offset_ft"].size() != (2 if int(params["component_version"]) == 1 else 3): return _invalid("位置数据与组件版本不匹配")
		raw = {"title": title, "kind": "advanced", "width": params.get("width"), "length": params.get("length"), "components": params.get("components")}
	for key in ["hp", "max_hp", "ac"]:
		if not _integer(params.get(key)) or int(params[key]) < -1 or int(params[key]) > 999999:
			return _invalid("基础数值无效")
		raw[key] = "" if int(params[key]) == -1 else str(int(params[key]))
	var checked := validate(raw)
	if not checked["ok"]: return _invalid(checked["message"])
	var normalized: Dictionary = checked["parameters"]
	if int(params["hp"]) != normalized["hp"] or int(params["max_hp"]) != normalized["max_hp"]:
		return _invalid("生命值字段不一致")
	normalized.erase("title")
	return {"ok": true, "record": {"id": id, "kind": record["kind"], "title": title.strip_edges(), "tags": tags.duplicate(), "parameters": normalized}}

static func _integer(value: Variant) -> bool:
	return (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value)) and float(value) == floor(float(value))

static func _matches(value: String, pattern: String) -> bool:
	var regex := RegEx.new()
	regex.compile(pattern)
	return regex.search(value) != null

static func _invalid(message: String) -> Dictionary:
	return {"ok": false, "message": message}

static func validate(raw: Dictionary) -> Dictionary:
	var kind := str(raw.get("kind", "basic"))
	if kind not in ["basic", "advanced"]: return _invalid("棋子类型无效。")
	return AdvancedParameters.validate(raw) if kind == "advanced" else Parameters.validate(raw)

static func _check_image(record: Dictionary) -> Dictionary:
	if record["kind"] != "advanced": return {"ok": true}
	var specification: Dictionary = record["parameters"]["components"]["standee"].get("sticker", Sticker.defaults())
	for id in Sticker.resource_ids(specification):
		var loaded := Images.load_image(id)
		if not loaded["ok"]: return _invalid(loaded["message"])
	return {"ok": true}
