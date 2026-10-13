extends RefCounted
const Runtime = preload("res://scripts/adventure_runtime.gd")

static func defaults() -> Dictionary:
	return {"configured":false,"visible_maps":[],"locked_maps":[],"tool_owners":{}}

static func normalize(adventure: Dictionary) -> Dictionary:
	var policy: Dictionary = adventure.get("network",defaults()).duplicate(true)
	var maps := {}
	var tools := {}
	for map: Dictionary in adventure.get("maps",[]):
		maps[map["id"]] = true
		var state: Dictionary = adventure.get("runtime",{}).get("maps",{}).get(map["id"],{})
		for category in ["shapes","measurements"]:
			for item: Dictionary in state.get(category,[]): tools["%s:%s:%d" % [map["id"],category,int(item["display_id"])]] = true
	for key in ["visible_maps","locked_maps"]: policy[key] = policy[key].filter(func(id: String): return maps.has(id))
	for key in policy["tool_owners"].keys():
		if not tools.has(key): policy["tool_owners"].erase(key)
	return policy

static func decode(raw: Variant, adventure: Dictionary) -> Dictionary:
	var error := {"ok":false,"message":"冒险联机访问设置无效。"}
	if not raw is Dictionary or not raw.get("configured") is bool or not raw.get("tool_owners") is Dictionary: return error
	for key in ["visible_maps","locked_maps"]:
		if not raw.get(key) is Array or raw[key].size()>64: return error
		for id in raw[key]:
			if not id is String or not valid_id(id): return error
	for key in raw["tool_owners"]:
		if not key is String or key.length()>100 or not raw["tool_owners"][key] is String or not adventure["party"]["members"].has(raw["tool_owners"][key]): return error
	var source := adventure.duplicate()
	source["network"] = raw
	return {"ok":true,"data":normalize(source)}

static func valid_id(id: String) -> bool:
	return preload("res://scripts/platform_library_store.gd")._id_valid(id)
