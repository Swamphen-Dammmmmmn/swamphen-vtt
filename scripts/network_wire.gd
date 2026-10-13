extends RefCounted
const Store = preload("res://scripts/adventure_library_store.gd")
const Images = preload("res://scripts/token_image_store.gd")
const Members = preload("res://scripts/adventure_members.gd")
const Instance = preload("res://scripts/token_instance.gd")

static func view(adventure: Dictionary, actor: String, accessible: Array) -> Dictionary:
	var result := adventure.duplicate(true)
	result["maps"] = result["maps"].filter(func(map: Dictionary): return map["id"] in accessible)
	for key in result["trays"].keys():
		if not Members.can_tray(result["party"],actor,key): result["trays"].erase(key)
	# Required legacy keys stay empty; no DM tray contents are disclosed.
	if not result["trays"].has("dm"): result["trays"]["dm"] = []
	for id in result["party"]["members"]:
		if id!="dm": result["party"]["members"][id]["identity_code"] = str(id).sha256_text().left(32)
	result["party"] = Members.normalized(result)
	result["runtime"] = preload("res://scripts/adventure_runtime.gd").pruned(result)
	result["network"] = preload("res://scripts/network_policy.gd").normalize(result)
	if not result["runtime"]["current_map_id"] in accessible: result["runtime"]["current_map_id"] = ""
	return result

static func pack(adventure: Dictionary, id: String) -> Dictionary:
	var packed := Store._pack(adventure,id,null)
	if not packed["ok"]: return packed
	var record: Dictionary = packed["record"]
	var resources := {}
	for map: Dictionary in record["maps"]:
		resources.merge(map["map"]["images"],true)
		map["map"].erase("images")
		if map["map"].has("preview_png"):
			var preview := Marshalls.base64_to_raw(map["map"]["preview_png"])
			var saved := Images.save_image(preview)
			if not saved["ok"]: return saved
			var preview_id := Images.content_id(preview)
			resources[preview_id] = map["map"]["preview_png"]
			map["thumbnail_resource"] = preview_id
		map["map"].erase("preview_png")
	resources.merge(record["tray_images"],true)
	record.erase("tray_images")
	var bytes := 0
	var manifest := {}
	for image_id: String in resources:
		var raw := Marshalls.base64_to_raw(resources[image_id])
		bytes += raw.size()
		manifest[image_id] = raw.size()
	if bytes>64*1024*1024: return {"ok":false,"message":"本次场景图片超过64 MiB传输预算。"}
	return {"ok":true,"record":record,"manifest":manifest}

static func unpack(record: Dictionary, manifest: Dictionary) -> Dictionary:
	var copy := record.duplicate(true)
	var embedded := {}
	for id in manifest:
		if not Images.valid_id(id): return {"ok":false,"message":"图片编号无效。"}
		var loaded := Images.load_image(id)
		if not loaded["ok"]: return loaded
		if loaded["data"].size()!=int(manifest[id]): return {"ok":false,"message":"图片大小不匹配。"}
		embedded[id] = Marshalls.raw_to_base64(loaded["data"])
	copy["tray_images"] = embedded
	for map: Dictionary in copy.get("maps",[]):
		map["map"]["images"] = embedded
		if map.get("thumbnail_resource") is String and embedded.has(map["thumbnail_resource"]): map["map"]["preview_png"] = embedded[map["thumbnail_resource"]]
	return Store._decode(copy,str(copy.get("id",""))+".json")

static func indexed(adventure: Dictionary) -> Dictionary:
	var result := {}
	for map: Dictionary in adventure["maps"]:
		for platform: Dictionary in map["data"]["platforms"]:
			for token: Dictionary in platform["data"].get("tokens",[]):
				result[token["id"]] = {"token":Instance.encode(token),"map":map["id"],"platform":platform["id"],"tray":""}
	for key in adventure["trays"]:
		for token: Dictionary in adventure["trays"][key]: result[token["id"]] = {"token":Instance.encode(token),"map":"","platform":"","tray":key}
	return result

static func changes(before: Dictionary, after: Dictionary, map_id: String) -> Dictionary:
	var old := indexed(before)
	var next := indexed(after)
	var changed: Array = []
	var removed: Array = []
	for id in next:
		if not old.has(id) or canonical(old[id])!=canonical(next[id]): changed.append(next[id])
	for id in old:
		if not next.has(id): removed.append(id)
	return {"changed":changed,"removed":removed,"map":map_id,"runtime":after["runtime"]["maps"].get(map_id,{"shapes":[],"measurements":[],"platform_origins":{}})}

static func canonical(value: Variant) -> String:
	return JSON.stringify(_numbers(value),"",true)

static func _numbers(value: Variant) -> Variant:
	if value is Dictionary:
		var result := {}
		for key in value: result[key] = _numbers(value[key])
		return result
	if value is Array:
		var result: Array = []
		for item in value: result.append(_numbers(item))
		return result
	if typeof(value) in [TYPE_INT,TYPE_FLOAT]: return float(value)
	return value

static func state_signature(adventure: Dictionary) -> String:
	return canonical({"tokens":indexed(adventure),"runtime":preload("res://scripts/adventure_runtime.gd").pruned(adventure)}).sha256_text()
