extends RefCounted
const PreviewImage = preload("res://scripts/library_preview_image.gd")
const StoragePaths = preload("res://scripts/storage_paths.gd")
const Platforms = preload("res://scripts/platform_library_store.gd")
const Data = preload("res://scripts/map_data.gd")
const Weather = preload("res://scripts/map_weather.gd")
static var DIRECTORY := StoragePaths.data_path("products/maps")
const Files = preload("res://scripts/product_files.gd")
const VERSION := 1
const MAX_BYTES := 128*1024*1024

static func _error(message: String) -> Dictionary:
	return {"ok":false,"message":message}

static func signature(data: Dictionary) -> String:
	return Data.signature(data)

static func _pack(data: Dictionary, id: String, thumbnail: Image) -> Dictionary:
	var layers: Array = []
	var images := {}
	for item: Dictionary in data["platforms"]:
		var packed := Platforms.pack(item["data"],item["id"])
		if not packed["ok"]: return packed
		var platform: Dictionary = packed["record"]
		images.merge(platform["images"],true)
		platform.erase("images")
		var at: Vector3 = item["offset_feet"]
		layers.append({"source_id":item["source_id"],"offset_feet":[at.x,at.y,at.z],"platform":platform})
	var record := {"format_version":VERSION,"id":id,"title":str(data["title"]).strip_edges(),"environment":data["environment"],"platforms":layers,"images":images}
	if thumbnail!=null and not thumbnail.is_empty():
		var small := PreviewImage.prepare(thumbnail)
		record["preview_png"] = Marshalls.raw_to_base64(small.save_png_to_buffer())
	return {"ok":true,"record":record}

static func save(data: Dictionary, id := "", thumbnail: Image = null) -> Dictionary:
	if not data.get("title") is String or data["title"].strip_edges().is_empty() or data["title"].length()>60:
		return _error("地图名称不能为空，最多60个字符。")
	if not data.get("platforms") is Array or data["platforms"].size()>256: return _error("地图最多包含256块地台。")
	if not id.is_empty():
		var existing := get_record(id)
		if not existing["ok"]: return _error("原地图无法读取，修改未保存："+existing["message"])
	else:
		id = Data.new_id()
		while FileAccess.file_exists(DIRECTORY.path_join(id+".json")): id = Data.new_id()
	var packed := _pack(data,id,thumbnail)
	if not packed["ok"]: return packed
	var record: Dictionary = packed["record"]
	var decoded := _decode(record,id+".json")
	if not decoded["ok"]: return decoded
	var bytes := JSON.stringify(record).to_utf8_buffer()
	if bytes.size()>MAX_BYTES: return _error("地图文件超过128 MiB保存上限。")
	var error := DirAccess.make_dir_recursive_absolute(DIRECTORY)
	if error!=OK: return _error("无法创建地图目录。")
	var path := DIRECTORY.path_join(id+".json")
	var temp := path+".tmp"
	var backup := path+".bak"
	var file := FileAccess.open(temp,FileAccess.WRITE)
	if file==null: return _error("无法写入地图，编辑内容已保留。")
	file.store_buffer(bytes)
	file.flush()
	error = file.get_error()
	file.close()
	if error!=OK:
		DirAccess.remove_absolute(temp)
		return _error("写入地图失败，编辑内容已保留。")
	var original := FileAccess.file_exists(path)
	if original:
		if FileAccess.file_exists(backup) and DirAccess.remove_absolute(backup)!=OK: return _error("无法更新地图备份，原文件未改动。")
		if DirAccess.rename_absolute(path,backup)!=OK: return _error("无法替换原地图，原文件未改动。")
	error = DirAccess.rename_absolute(temp,path)
	if error!=OK:
		var recovered := not original or DirAccess.rename_absolute(backup,path)==OK
		return _error("保存失败，编辑内容已保留。"+("原文件已恢复。" if recovered else "原文件保留在备份中。"))
	# Prefer the caller's raw capture over the decode compatibility classification.
	var catalog_record: Dictionary = decoded["record"]
	catalog_record["thumbnail"] = thumbnail
	ProductCatalog.record_saved("maps",id,catalog_record)
	return {"ok":true,"id":id}

static func _decode(record: Dictionary, filename: String) -> Dictionary:
	if not Platforms._number(record.get("format_version")) or float(record["format_version"])!=VERSION: return _error("不支持此地图文件版本。")
	var id = record.get("id")
	if not id is String or not Platforms._id_valid(id) or filename!=id+".json": return _error("地图编号无效。")
	var title = record.get("title")
	if not title is String or title.strip_edges().is_empty() or title.length()>60: return _error("地图名称无效。")
	var environment = record.get("environment")
	var weather := Weather.decode(environment)
	if not weather["ok"]: return weather
	environment = weather["data"]
	var layers = record.get("platforms")
	if not layers is Array or layers.size()>256: return _error("地图地台列表无效。")
	var images = record.get("images")
	if not images is Dictionary: return _error("地图图片依赖无效。")
	# Also validate dependencies for an empty map before passing them to platform readers.
	for image_id in images:
		if not Platforms.Images.valid_id(image_id) or not images[image_id] is String or images[image_id].length()>3333400: return _error("地图图片依赖无效。")
		var bytes := Marshalls.base64_to_raw(images[image_id])
		if Platforms.Images.content_id(bytes)!=image_id: return _error("地图图片内容校验失败。")
		var checked := Platforms.Images._decode(bytes)
		if not checked["ok"]: return checked
	var data := {"title":title.strip_edges(),"environment":environment.duplicate(true),"platforms":[]}
	var ids := {}
	var token_ids := {}
	for layer in layers:
		if not layer is Dictionary or not layer.get("platform") is Dictionary: return _error("地图地台内容无效。")
		if not layer.get("source_id") is String or not Platforms._id_valid(layer["source_id"]): return _error("地台来源编号无效。")
		var offset = layer.get("offset_feet")
		if not offset is Array or offset.size()!=3: return _error("地台位置无效。")
		for value in offset:
			if not Platforms._number(value) or absf(float(value))>1000000 or float(value)!=floorf(float(value)): return _error("地台位置须为有效的整数英尺。")
		if not is_zero_approx(fmod(float(offset[0]),5)) or not is_zero_approx(fmod(float(offset[2]),5)): return _error("地台水平位置须对齐5英尺网格。")
		var platform: Dictionary = layer["platform"].duplicate(true)
		var platform_id = platform.get("id")
		if not platform_id is String or ids.has(platform_id): return _error("地台实例编号重复或无效。")
		platform["images"] = images
		var loaded := Platforms._decode(platform,platform_id+".json")
		if not loaded["ok"]: return _error("地图中的地台无法读取："+loaded["message"])
		for token: Dictionary in loaded["record"]["parameters"].get("tokens",[]):
			if token_ids.has(token["id"]): return _error("地图中的棋子实例编号重复。")
			token_ids[token["id"]] = true
		ids[platform_id] = true
		var item := {"id":platform_id,"source_id":layer["source_id"],"offset_feet":Vector3(offset[0],offset[1],offset[2]),"data":loaded["record"]["parameters"]}
		if Data.conflicts(item,item["offset_feet"],data["platforms"]): return _error("地图中存在实体相交的地台。")
		data["platforms"].append(item)
	var thumbnail: Image
	if record.get("preview_png") is String and record["preview_png"].length()<1024*1024:
		thumbnail = PreviewImage.decode(Marshalls.base64_to_raw(record["preview_png"]))
	return {"ok":true,"record":{"id":id,"title":data["title"],"parameters":data,"thumbnail":thumbnail}}

static func get_record(id: String) -> Dictionary:
	if not Platforms._id_valid(id): return _error("地图编号无效。")
	return _read(DIRECTORY.path_join(id+".json"),id+".json")

static func _read(path: String, filename: String) -> Dictionary:
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null: return _error("无法打开地图文件。")
	if file.get_length()>MAX_BYTES:
		file.close()
		return _error("地图文件超过大小上限。")
	var text := file.get_as_text()
	var error := file.get_error()
	file.close()
	if error!=OK and error!=ERR_FILE_EOF: return _error("地图读取失败。")
	var raw: Variant = JSON.parse_string(text)
	if not raw is Dictionary: return _error("地图文件格式无效。")
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
	for item: Dictionary in data["platforms"]:
		item["id"] = Data.new_id()
		for token: Dictionary in item["data"].get("tokens",[]): token["id"] = Data.new_id()
	return save(data,"",loaded["record"]["thumbnail"])

static func delete(id: String) -> Dictionary:
	var loaded := get_record(id)
	if not loaded["ok"]: return loaded
	var path := DIRECTORY.path_join(id+".json")
	if DirAccess.remove_absolute(path)!=OK: return _error("删除地图失败，原文件已保留。")
	for suffix in [".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	ProductCatalog.removed("maps",id)
	return {"ok":true}

static func read_catalog() -> Dictionary:
	return ProductCatalog.read_list("maps")
