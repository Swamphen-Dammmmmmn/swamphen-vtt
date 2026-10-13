extends RefCounted
const StoragePaths = preload("res://scripts/storage_paths.gd")
const Platforms = preload("res://scripts/platform_library_store.gd")
const Data = preload("res://scripts/adventure_data.gd")
const MapStore = preload("res://scripts/map_library_store.gd")
const Runtime = preload("res://scripts/adventure_runtime.gd")
const Policy = preload("res://scripts/network_policy.gd")
const Members = preload("res://scripts/adventure_members.gd")
const Trays = preload("res://scripts/adventure_trays.gd")
static var DIRECTORY := StoragePaths.data_path("products/adventures")
const Files = preload("res://scripts/product_files.gd")
const VERSION := 1
const MAX_BYTES := 512*1024*1024

static func _error(message: String) -> Dictionary:
	return {"ok":false,"message":message}

static func signature(data: Dictionary) -> String:
	return Data.signature(data)

static func _pack(data: Dictionary, id: String, _thumbnail: Image) -> Dictionary:
	var maps: Array = []
	for item: Dictionary in data["maps"]:
		var packed := MapStore._pack(item["data"],item["id"],item.get("thumbnail"))
		if not packed["ok"]: return packed
		maps.append({"source_id":item["source_id"],"map":packed["record"]})
	var trays := Trays.pack(data.get("trays",Trays.defaults()))
	if not trays["ok"]: return trays
	return {"ok":true,"record":{"format_version":VERSION,"id":id,"title":str(data["title"]).strip_edges(),"maps":maps,"runtime":Runtime.pruned(data),"trays":trays["data"],"tray_images":trays["images"],"party":Members.normalized(data),"network":Policy.normalize(data)}}

static func save(data: Dictionary, id := "", thumbnail: Image = null) -> Dictionary:
	if not data.get("title") is String or data["title"].strip_edges().is_empty() or data["title"].length()>60:
		return _error("冒险名称不能为空，最多60个字符。")
	if not data.get("maps") is Array or data["maps"].size()>64: return _error("冒险最多包含64张地图。")
	if not id.is_empty():
		var existing := get_record(id)
		if not existing["ok"]: return _error("原冒险无法读取，修改未保存："+existing["message"])
	else:
		id = MapStore.Data.new_id()
		while FileAccess.file_exists(DIRECTORY.path_join(id+".json")): id = MapStore.Data.new_id()
	var packed := _pack(data,id,thumbnail)
	if not packed["ok"]: return packed
	var record: Dictionary = packed["record"]
	var decoded := _decode(record,id+".json")
	if not decoded["ok"]: return decoded
	var bytes := JSON.stringify(record).to_utf8_buffer()
	if bytes.size()>MAX_BYTES: return _error("冒险文件超过512 MiB保存上限。")
	var error := DirAccess.make_dir_recursive_absolute(DIRECTORY)
	if error!=OK: return _error("无法创建冒险目录。")
	var path := DIRECTORY.path_join(id+".json")
	var temp := path+".tmp"
	var backup := path+".bak"
	var file := FileAccess.open(temp,FileAccess.WRITE)
	if file==null: return _error("无法写入冒险，编辑内容已保留。")
	file.store_buffer(bytes)
	file.flush()
	error = file.get_error()
	file.close()
	if error!=OK:
		DirAccess.remove_absolute(temp)
		return _error("写入冒险失败，编辑内容已保留。")
	var original := FileAccess.file_exists(path)
	if original:
		if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup)!=OK: return _error("无法更新冒险备份，原文件未改动。")
		if DirAccess.rename_absolute(path,backup)!=OK: return _error("无法替换原冒险，原文件未改动。")
	error = DirAccess.rename_absolute(temp,path)
	if error!=OK:
		var recovered := not original or DirAccess.rename_absolute(backup,path)==OK
		return _error("保存失败，编辑内容已保留。"+("原文件已恢复。" if recovered else "原文件保留在备份中。"))
	return {"ok":true,"id":id}

static func _decode(record: Dictionary, filename: String) -> Dictionary:
	if not Platforms._number(record.get("format_version")) or float(record["format_version"])!=VERSION: return _error("不支持此冒险文件版本。")
	var id = record.get("id")
	if not id is String or not Platforms._id_valid(id) or filename!=id+".json": return _error("冒险编号无效。")
	var title = record.get("title")
	if not title is String or title.strip_edges().is_empty() or title.length()>60: return _error("冒险名称无效。")
	var maps = record.get("maps")
	if not maps is Array or maps.size()>64: return _error("冒险地图列表无效。")
	var data := {"title":title.strip_edges(),"maps":[]}
	var ids := {}
	var platform_ids := {}
	var token_ids := {}
	var preview: Image
	for item in maps:
		if not item is Dictionary or not item.get("map") is Dictionary: return _error("冒险地图内容无效。")
		if not item.get("source_id") is String or not Platforms._id_valid(item["source_id"]): return _error("地图来源编号无效。")
		var map_id = item["map"].get("id")
		if not map_id is String or ids.has(map_id): return _error("地图编号重复或无效。")
		var loaded := MapStore._decode(item["map"],map_id+".json")
		if not loaded["ok"]: return loaded
		ids[map_id] = true
		var map: Dictionary = loaded["record"]
		for platform: Dictionary in map["parameters"]["platforms"]:
			if platform_ids.has(platform["id"]): return _error("冒险内地台编号重复。")
			platform_ids[platform["id"]] = true
			for token: Dictionary in platform["data"].get("tokens",[]):
				if token_ids.has(token["id"]): return _error("冒险内棋子编号重复。")
				token_ids[token["id"]] = true
		data["maps"].append({"id":map_id,"source_id":item["source_id"],"data":map["parameters"],"thumbnail":map["thumbnail"]})
		if preview==null: preview = map["thumbnail"]
	var trays := Trays.decode(record.get("trays",Trays.defaults()),record.get("tray_images",{}),token_ids)
	if not trays["ok"]: return trays
	data["trays"] = trays["data"]
	var party := Members.decode(record.get("party",Members.defaults()),data)
	if not party["ok"]: return party
	data["party"] = party["data"]
	for member in data["party"]["members"]:
		var key := Members.tray_key(member)
		if not data["trays"].has(key): data["trays"][key] = []
	var runtime := Runtime.decode(record.get("runtime",Runtime.defaults()),data["maps"])
	if not runtime["ok"]: return runtime
	data["runtime"] = runtime["data"]
	var policy := Policy.decode(record.get("network",Policy.defaults()),data)
	if not policy["ok"]: return policy
	data["network"] = policy["data"]
	return {"ok":true,"record":{"id":id,"title":data["title"],"parameters":data,"thumbnail":preview}}

static func get_record(id: String) -> Dictionary:
	if not Platforms._id_valid(id): return _error("冒险编号无效。")
	return _read(DIRECTORY.path_join(id+".json"),id+".json")

static func _read(path: String, filename: String) -> Dictionary:
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null: return _error("无法打开冒险文件。")
	if file.get_length()>MAX_BYTES:
		file.close()
		return _error("冒险文件超过大小上限。")
	var text := file.get_as_text()
	var error := file.get_error()
	file.close()
	if error!=OK and error!=ERR_FILE_EOF: return _error("冒险读取失败。")
	var raw: Variant = JSON.parse_string(text)
	if not raw is Dictionary: return _error("冒险文件格式无效。")
	return _decode(raw,filename)

static func read_all() -> Dictionary:
	var result := {"entries":[],"warnings":[],"error":""}
	var listed := Files.list_json(DIRECTORY)
	result["error"] = listed["error"]
	for filename in listed["files"]:
		if not filename.ends_with(".json"): continue
		var loaded := _read(DIRECTORY.path_join(filename),filename)
		if loaded["ok"]: result["entries"].append(loaded["record"])
		else: result["warnings"].append(filename+"："+loaded["message"])
	result["entries"].sort_custom(func(a: Dictionary,b: Dictionary): return str(a["title"]).naturalnocasecmp_to(str(b["title"]))<0)
	return result

static func rename(id: String, title: String) -> Dictionary:
	var loaded := get_record(id)
	if not loaded["ok"]: return loaded
	loaded["record"]["parameters"]["title"] = title
	return save(loaded["record"]["parameters"],id,loaded["record"]["thumbnail"])

static func copy(id: String) -> Dictionary:
	var loaded := get_record(id)
	if not loaded["ok"]: return loaded
	var data: Dictionary = loaded["record"]["parameters"]
	data["title"] = str(data["title"]).left(54)+" · 副本"
	var remapping := {}
	for item: Dictionary in data["maps"]:
		var next_id := MapStore.Data.new_id()
		remapping[item["id"]] = next_id
		item["id"] = next_id
		for platform: Dictionary in item["data"]["platforms"]:
			next_id = MapStore.Data.new_id()
			remapping[platform["id"]] = next_id
			platform["id"] = next_id
			for token: Dictionary in platform["data"].get("tokens",[]):
				next_id = MapStore.Data.new_id()
				remapping[token["id"]] = next_id
				token["id"] = next_id
	for key in data["trays"]:
		for token: Dictionary in data["trays"][key]:
			var next_id := MapStore.Data.new_id()
			remapping[token["id"]] = next_id
			token["id"] = next_id
	var owners := {}
	for old_id in data["party"]["owners"]:
		if remapping.has(old_id): owners[remapping[old_id]] = data["party"]["owners"][old_id]
	data["party"]["owners"] = owners
	for member in data["party"]["positions"]:
		data["party"]["positions"][member] = remapping.get(data["party"]["positions"][member],"")
	data["runtime"] = Runtime.remap(data["runtime"],remapping)
	for key in ["visible_maps","locked_maps"]:
		data["network"][key] = data["network"][key].map(func(old_id: String): return remapping.get(old_id,old_id))
	var tools := {}
	for key in data["network"]["tool_owners"]:
		var parts: PackedStringArray = str(key).split(":")
		if parts.size()==3: tools[str(remapping.get(parts[0],parts[0]))+":"+parts[1]+":"+parts[2]] = data["network"]["tool_owners"][key]
	data["network"]["tool_owners"] = tools
	return save(data,"",loaded["record"]["thumbnail"])

static func delete(id: String) -> Dictionary:
	var loaded := get_record(id)
	if not loaded["ok"]: return loaded
	var path := DIRECTORY.path_join(id+".json")
	if DirAccess.remove_absolute(path)!=OK: return _error("删除冒险失败，原文件已保留。")
	for suffix in [".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	return {"ok":true}
