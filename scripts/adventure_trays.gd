extends RefCounted
const Instance = preload("res://scripts/token_instance.gd")
const Store = preload("res://scripts/platform_library_store.gd")
const Images = preload("res://scripts/token_image_store.gd")
const Data = preload("res://scripts/map_data.gd")
const KEYS := ["dm","public"]
const LIMIT := 4096

static func defaults() -> Dictionary:
	return {"dm":[],"public":[]}

static func token(data: Dictionary) -> Dictionary:
	var result := data.duplicate(true)
	for key in ["node","platform_id","persistent_id","cell"]: result.erase(key)
	if result.get("kind","basic")=="basic":
		result["width"] = result["size"]
		result["length"] = result["size"]
	return Instance.complete(result)

static func from_library(record: Dictionary) -> Dictionary:
	var source: Dictionary = record["parameters"].duplicate(true)
	source["kind"] = record["kind"]
	var result := token(source)
	result["id"] = Data.new_id()
	result["title"] = record["title"]
	result["kind"] = record["kind"]
	result["tags"] = record["tags"].duplicate()
	return result

static func pack(trays: Dictionary) -> Dictionary:
	var raw := defaults()
	for key in trays: raw[key] = []
	var images := {}
	for key in trays:
		for data: Dictionary in trays[key]:
			raw[key].append(Instance.encode(token(data)))
			for id: String in Instance.images(data):
				if images.has(id): continue
				var loaded := Images.load_image(id)
				if not loaded["ok"]: return loaded
				images[id] = Marshalls.raw_to_base64(loaded["data"])
	return {"ok":true,"data":raw,"images":images}

static func decode(raw: Variant, images: Variant, occupied: Dictionary) -> Dictionary:
	var error := {"ok":false,"message":"冒险棋子托盘数据无效或棋子编号重复。"}
	if not raw is Dictionary or not images is Dictionary: return error
	for id in images:
		if not Images.valid_id(id) or not images[id] is String or images[id].length()>3333400: return error
		var bytes := Marshalls.base64_to_raw(images[id])
		if Images.content_id(bytes)!=id: return error
		var checked := Images._decode(bytes)
		if not checked["ok"]: return checked
	var result := defaults()
	if not raw.has("dm") or not raw.has("public"): return error
	if raw.size()>130: return error
	for key in raw:
		if not key is String or (key not in KEYS and (not key.begins_with("member:") or not Store._id_valid(key.trim_prefix("member:")))): return error
		result[key] = []
		if not raw.get(key) is Array or raw[key].size()>LIMIT: return error
		for item in raw[key]:
			if not item is Dictionary or not item.get("id") is String or not Store._id_valid(item["id"]) or occupied.has(item["id"]): return error
			var decoded := Instance.decode(item)
			if not decoded["ok"]: return decoded
			var params: Dictionary = decoded["parameters"]
			params["id"] = item["id"]
			for id: String in Instance.images(params):
				if not images.has(id): return {"ok":false,"message":"托盘棋子缺少图片依赖。"}
			occupied[item["id"]] = true
			result[key].append(params)
	for id in images:
		var installed := Images.save_image(Marshalls.base64_to_raw(images[id]))
		if not installed["ok"]: return installed
	return {"ok":true,"data":result}

static func signature(trays: Dictionary) -> String:
	var encoded := defaults()
	for key in trays:
		encoded[key] = []
		for data: Dictionary in trays[key]: encoded[key].append(Instance.encode(token(data)))
	return JSON.stringify(encoded).sha256_text()
