extends RefCounted
const StoragePaths = preload("res://scripts/storage_paths.gd")
const Parameters = preload("res://scripts/platform_parameters.gd")
const Landing = preload("res://scripts/platform_landing.gd")
static var DIRECTORY := StoragePaths.data_path("products/platforms")
const Files = preload("res://scripts/product_files.gd")
const Instance = preload("res://scripts/token_instance.gd")
const Images = preload("res://scripts/token_image_store.gd")
const VERSION := 2
const MAX_BYTES := 32*1024*1024

static func _error(message: String) -> Dictionary:
	return {"ok":false,"message":message}

static func _id_valid(id: String) -> bool:
	if id.length()!=32: return false
	for c in id:
		if not c in "0123456789abcdef": return false
	return true

static func _number(value) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value))

static func _vector(value) -> bool:
	return value is Array and value.size()==2 and _number(value[0]) and _number(value[1])

static func _geometry(data: Dictionary) -> Dictionary:
	var result := {}
	for key in ["title","width_feet","length_feet","thickness_feet","top_feet","material"]: result[key] = data[key]
	for key in ["grid_origin_feet","bounds_origin_feet"]:
		var point: Vector2 = data.get(key,data["grid_origin_feet"])
		result[key] = [point.x,point.y]
	var cells: Array = []
	for cell: Vector2i in data.get("landing_cells",[]): cells.append([cell.x,cell.y])
	result["landing_cells"] = cells
	result["tokens"] = []
	for token: Dictionary in data.get("tokens",[]): result["tokens"].append(Instance.encode(token))
	return result

static func signature(data: Dictionary) -> String:
	var hash := HashingContext.new()
	hash.start(HashingContext.HASH_SHA256)
	hash.update(JSON.stringify(_geometry(data)).to_utf8_buffer())
	var image: Image = data.get("paint_overlay")
	if image!=null: hash.update(image.get_data())
	return hash.finish().hex_encode()

static func save(data: Dictionary, id := "", thumbnail: Image = null) -> Dictionary:
	var checked := Parameters.validate(data)
	if not checked["ok"]: return checked
	if not id.is_empty():
		var existing := get_record(id)
		if not existing["ok"]: return _error("原地台无法读取，修改未保存："+existing["message"])
	else:
		for attempt in range(6):
			id = Crypto.new().generate_random_bytes(16).hex_encode()
			if not FileAccess.file_exists(DIRECTORY.path_join(id+".json")): break
			id = ""
		if id.is_empty(): return _error("无法生成地台编号，请重试。")
	var packed := pack(data,id,thumbnail)
	if not packed["ok"]: return packed
	var record: Dictionary = packed["record"]
	var encoded := JSON.stringify(record).to_utf8_buffer()
	if encoded.size()>MAX_BYTES: return _error("地台文件超过32 MiB保存上限。")
	var error := DirAccess.make_dir_recursive_absolute(DIRECTORY)
	if error!=OK: return _error("无法创建地台目录："+error_string(error))
	var path := DIRECTORY.path_join(id+".json")
	var temp := path+".tmp"
	var backup := path+".bak"
	var file := FileAccess.open(temp,FileAccess.WRITE)
	if file==null: return _error("无法写入地台文件："+error_string(FileAccess.get_open_error()))
	file.store_buffer(encoded)
	file.flush()
	error = file.get_error()
	file.close()
	if error!=OK:
		DirAccess.remove_absolute(temp)
		return _error("写入失败，编辑内容已保留："+error_string(error))
	var had_original := FileAccess.file_exists(path)
	if had_original:
		if FileAccess.file_exists(backup):
			error = DirAccess.remove_absolute(backup)
			if error!=OK: return _error("无法更新地台备份，原存档未改动。")
		error = DirAccess.rename_absolute(path,backup)
		if error!=OK: return _error("无法替换原地台，原存档未改动。")
	error = DirAccess.rename_absolute(temp,path)
	if error!=OK:
		var recovery := OK
		if had_original: recovery = DirAccess.rename_absolute(backup,path)
		return _error("保存失败，编辑内容已保留。"+("原存档已恢复。" if recovery==OK else "原存档保留在备份文件中。"))
	ProductCatalog.record_saved("platforms",id,{"id":id,"title":str(data["title"]).strip_edges(),"parameters":data,"thumbnail":thumbnail})
	return {"ok":true,"id":id}

static func pack(data: Dictionary, id: String, thumbnail: Image = null) -> Dictionary:
	var checked := Parameters.validate(data)
	if not checked["ok"]: return checked
	var dimensions := Vector2i(int(data["width_feet"]),int(data["length_feet"]))
	var image: Image = data.get("paint_overlay")
	if image==null:
		image = Image.create(dimensions.x,dimensions.y,false,Image.FORMAT_RGBA8)
		image.fill(Color(0,0,0,0))
	if image.get_size()!=dimensions or image.get_format()!=Image.FORMAT_RGBA8: return _error("地面绘制数据与地台尺寸不一致。")
	var payload := _geometry(checked["data"])
	payload["paint_png"] = Marshalls.raw_to_base64(image.save_png_to_buffer())
	var dependencies := {}
	for token: Dictionary in data.get("tokens",[]):
		for image_id: String in Instance.images(token):
			if dependencies.has(image_id): continue
			var loaded := Images.load_image(image_id)
			if not loaded["ok"]: return _error(loaded["message"])
			dependencies[image_id] = Marshalls.raw_to_base64(loaded["data"])
	var record := {"format_version":VERSION,"id":id,"parameters":payload,"images":dependencies}
	if thumbnail!=null and not thumbnail.is_empty():
		var small: Image = thumbnail.duplicate()
		var scale := minf(320.0/small.get_width(),200.0/small.get_height())
		small.resize(maxi(1,roundi(small.get_width()*scale)),maxi(1,roundi(small.get_height()*scale)),Image.INTERPOLATE_LANCZOS)
		small.convert(Image.FORMAT_RGBA8)
		var framed := Image.create(320,200,false,Image.FORMAT_RGBA8)
		framed.fill(Color("e5e7eb"))
		framed.blit_rect(small,Rect2i(Vector2i.ZERO,small.get_size()),(Vector2i(320,200)-small.get_size())/2)
		record["preview_png"] = Marshalls.raw_to_base64(framed.save_png_to_buffer())
	# Validate the same representation that readers will receive before replacing a file.
	var normalized := _decode(record,id+".json")
	if not normalized["ok"]: return normalized
	return {"ok":true,"record":record}

static func get_record(id: String) -> Dictionary:
	if not _id_valid(id): return _error("地台编号无效。")
	return _read(DIRECTORY.path_join(id+".json"),id+".json")

static func _read(path: String, filename: String) -> Dictionary:
	var file := FileAccess.open(path,FileAccess.READ)
	if file==null: return _error("无法打开地台文件。")
	if file.get_length()>MAX_BYTES:
		file.close()
		return _error("地台文件超过读取上限。")
	var text := file.get_as_text()
	var error := file.get_error()
	file.close()
	if error!=OK and error!=ERR_FILE_EOF: return _error("地台文件读取失败。")
	var json := JSON.new()
	if json.parse(text)!=OK or not json.data is Dictionary: return _error("地台文件格式无效。")
	return _decode(json.data,filename)

static func _png(bytes: PackedByteArray, expected: Vector2i) -> Image:
	# Check dimensions before allowing the image decoder to allocate memory.
	if bytes.size()<24 or bytes.slice(0,8)!=PackedByteArray([137,80,78,71,13,10,26,10]): return null
	var w := 0
	var h := 0
	for i in range(4):
		w = (w<<8)|bytes[16+i]
		h = (h<<8)|bytes[20+i]
	if Vector2i(w,h)!=expected: return null
	var image := Image.new()
	if image.load_png_from_buffer(bytes)!=OK: return null
	image.convert(Image.FORMAT_RGBA8)
	return image

static func _decode(record: Dictionary, filename: String) -> Dictionary:
	var version = record.get("format_version")
	if not _number(version) or float(version)!=floorf(float(version)) or int(version) not in [1,2]:
		return _error("不支持此地台文件版本。")
	var id = record.get("id")
	if not id is String or not _id_valid(id) or filename!=id+".json": return _error("地台编号与文件不一致。")
	var raw = record.get("parameters")
	if not raw is Dictionary: return _error("缺少地台内容。")
	if not raw.get("title") is String or raw["title"].length()>60: return _error("地台名称无效。")
	for key in ["width_feet","length_feet","thickness_feet","top_feet"]:
		if not _number(raw.get(key)): return _error("地台尺寸或高度无效。")
	if absf(float(raw["top_feet"]))>1000000: return _error("地台高度超出支持范围。")
	var data: Dictionary = raw.duplicate(true)
	for key in ["grid_origin_feet","bounds_origin_feet"]:
		if not _vector(raw.get(key)): return _error("地台网格坐标无效。")
		for value in raw[key]:
			if absf(float(value))>1000000 or not is_zero_approx(fmod(float(value),5)): return _error("地台坐标须对齐5英尺。")
		data[key] = Vector2(raw[key][0],raw[key][1])
	var checked := Parameters.validate(data)
	if not checked["ok"]: return checked
	data = checked["data"]
	var dimensions := Vector2i(int(data["width_feet"]),int(data["length_feet"]))
	var cells = raw.get("landing_cells")
	if not cells is Array or cells.size()>dimensions.x*dimensions.y/25: return _error("棋子摆放区域数据无效。")
	var seen := {}
	var normalized: Array[Vector2i] = []
	for cell in cells:
		if not _vector(cell) or float(cell[0])!=floorf(float(cell[0])) or float(cell[1])!=floorf(float(cell[1])): return _error("棋子摆放格子无效。")
		if absf(float(cell[0]))>1000000 or absf(float(cell[1]))>1000000: return _error("棋子摆放格子坐标无效。")
		var point := Vector2i(cell[0],cell[1])
		if not Landing.bounds(data).has_point(point) or seen.has(point): return _error("棋子摆放格子越界或重复。")
		seen[point] = true
		normalized.append(point)
	data["landing_cells"] = normalized
	var encoded = raw.get("paint_png")
	if not encoded is String: return _error("缺少地面绘制数据。")
	var mask := _png(Marshalls.base64_to_raw(encoded),dimensions)
	if mask==null: return _error("地面绘制图片损坏或尺寸不符。")
	data.erase("paint_png")
	data["paint_overlay"] = mask
	data["paint_origin_feet"] = data["bounds_origin_feet"]
	var dependencies = record.get("images",{})
	if not dependencies is Dictionary: return _error("棋子图片依赖无效。")
	# Validate all embedded bytes before installing any dependency.
	for image_id in dependencies:
		if not Images.valid_id(image_id) or not dependencies[image_id] is String or dependencies[image_id].length()>3333400: return _error("棋子图片依赖无效。")
		var bytes := Marshalls.base64_to_raw(dependencies[image_id])
		if Images.content_id(bytes)!=image_id: return _error("棋子图片内容校验失败。")
		var decoded := Images._decode(bytes)
		if not decoded["ok"]: return _error(decoded["message"])
	var raw_tokens = raw.get("tokens",[])
	if not raw_tokens is Array or raw_tokens.size()>4096: return _error("地台棋子列表无效。")
	var tokens: Array = []
	var ids := {}
	for item in raw_tokens:
		if not item is Dictionary or not item.get("id") is String or not _id_valid(item["id"]) or ids.has(item["id"]): return _error("地台棋子编号无效或重复。")
		if not _vector(item.get("cell")) or float(item["cell"][0])!=floorf(float(item["cell"][0])) or float(item["cell"][1])!=floorf(float(item["cell"][1])): return _error("棋子位置无效。")
		if absf(float(item["cell"][0]))>1000000 or absf(float(item["cell"][1]))>1000000: return _error("棋子位置超出支持范围。")
		var decoded := Instance.decode(item)
		if not decoded["ok"]: return _error(decoded["message"])
		var token: Dictionary = decoded["parameters"]
		token["id"] = item["id"]
		token["cell"] = Vector2i(item["cell"][0],item["cell"][1])
		var extent := Vector2i(int(token.get("width",token["size"])),int(token.get("length",token["size"])))
		if not Landing.bounds(data).encloses(Rect2i(token["cell"],extent)): return _error("棋子超出地台边界。")
		for image_id in Instance.images(token):
			if not dependencies.has(image_id): return _error("缺少棋子图片依赖。")
		ids[token["id"]] = true
		tokens.append(token)
	for image_id in dependencies:
		var installed := Images.save_image(Marshalls.base64_to_raw(dependencies[image_id]))
		if not installed["ok"]: return _error(installed["message"])
	data["tokens"] = tokens
	var thumbnail: Image
	if record.get("preview_png") is String and record["preview_png"].length()<1024*1024:
		thumbnail = _png(Marshalls.base64_to_raw(record["preview_png"]),Vector2i(320,200))
	return {"ok":true,"record":{"id":id,"title":data["title"],"parameters":data,"thumbnail":thumbnail}}

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

static func copy(id: String) -> Dictionary:
	var loaded := get_record(id)
	if not loaded["ok"]: return loaded
	var data: Dictionary = loaded["record"]["parameters"]
	data["title"] = str(data["title"]).left(54)+" · 副本"
	for token: Dictionary in data.get("tokens",[]): token["id"] = Crypto.new().generate_random_bytes(16).hex_encode()
	return save(data,"",loaded["record"]["thumbnail"])

static func rename(id: String, title: String) -> Dictionary:
	var loaded := get_record(id)
	if not loaded["ok"]: return loaded
	var data: Dictionary = loaded["record"]["parameters"].duplicate(true)
	data["title"] = title
	return save(data,id,loaded["record"]["thumbnail"])

static func delete(id: String) -> Dictionary:
	var loaded := get_record(id)
	if not loaded["ok"]: return loaded
	var path := DIRECTORY.path_join(id+".json")
	var error := DirAccess.remove_absolute(path)
	if error!=OK: return _error("删除失败："+error_string(error))
	for suffix in [".bak",".tmp"]:
		if FileAccess.file_exists(path+suffix): DirAccess.remove_absolute(path+suffix)
	ProductCatalog.removed("platforms",id)
	return {"ok":true}

static func preview_missing(image: Image) -> bool:
	if image==null or image.is_empty(): return true
	var first := image.get_pixel(0,0)
	for y in range(image.get_height()):
		for x in range(image.get_width()):
			if not image.get_pixel(x,y).is_equal_approx(first): return false
	return true

static func read_catalog() -> Dictionary:
	return ProductCatalog.read_list("platforms")
