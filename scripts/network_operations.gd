extends RefCounted
const Wire = preload("res://scripts/network_wire.gd")
const Members = preload("res://scripts/adventure_members.gd")
const Instance = preload("res://scripts/token_instance.gd")
const Store = preload("res://scripts/platform_library_store.gd")
const Landing = preload("res://scripts/platform_landing.gd")
const Footprint = preload("res://scripts/token_footprint.gd")
const Images = preload("res://scripts/token_image_store.gd")
const Runtime = preload("res://scripts/adventure_runtime.gd")

static func error(message := "操作无效或没有权限。") -> Dictionary:
	return {"ok":false,"message":message}

static func apply(adventure: Dictionary, actor: String, accessible: Array, request: Dictionary, tool_owners: Dictionary) -> Dictionary:
	if not request.get("changed") is Array or request["changed"].size()>256 or not request.get("removed") is Array or request["removed"].size()>256 or not request.get("runtime") is Dictionary: return error()
	var map_id: Variant = request.get("map")
	if not map_id is String or map_id not in accessible or adventure["party"]["positions"].get(actor)!=map_id: return error()
	var previous := Wire.indexed(adventure)
	var candidate := adventure.duplicate(true)
	var tools := tool_owners.duplicate(true)
	var seen := {}
	for id in request["removed"]:
		if not id is String or seen.has(id) or not previous.has(id) or not Members.can_token(adventure["party"],actor,id): return error()
		if not previous[id]["map"].is_empty() and previous[id]["map"]!=map_id: return error()
		seen[id] = true
		_erase(candidate,id)
		candidate["party"]["owners"].erase(id)
	for item in request["changed"]:
		if not item is Dictionary or not item.get("token") is Dictionary: return error()
		var id: Variant = item["token"].get("id")
		if not id is String or not Store._id_valid(id) or seen.has(id): return error()
		seen[id] = true
		var decoded := Instance.decode(item["token"])
		if not decoded["ok"]: return decoded
		var token: Dictionary = decoded["parameters"]
		token["id"] = id
		if previous.has(id):
			if not Members.can_token(adventure["party"],actor,id): return error()
			if not previous[id]["map"].is_empty() and previous[id]["map"]!=map_id: return error()
			if Footprint.dimensions(token)!=Footprint.dimensions(_parameters(previous[id]["token"])) and previous[id]["tray"].is_empty(): return error("场内棋子不能修改占地。")
		else: candidate["party"]["owners"][id] = actor
		for resource: String in Instance.images(token):
			if not Images.load_image(resource)["ok"]: return error("棋子图片尚未接收完成。")
		_erase(candidate,id)
		var tray: Variant = item.get("tray")
		if not tray is String: return error()
		if not tray.is_empty():
			if not candidate["trays"].has(tray) or not Members.can_store(candidate["party"],actor,id,tray) or candidate["trays"][tray].size()>=4096: return error()
			candidate["trays"][tray].append(token)
		else:
			if item.get("map")!=map_id or not item.get("platform") is String or not Store._vector(item["token"].get("cell")): return error()
			var raw: Array = item["token"]["cell"]
			if float(raw[0])!=floorf(float(raw[0])) or float(raw[1])!=floorf(float(raw[1])): return error()
			token["cell"] = Vector2i(raw[0],raw[1])
			var target := _platform(candidate,map_id,item["platform"])
			if target.is_empty() or target["data"]["tokens"].size()>=4096: return error()
			var rectangle := Rect2i(token["cell"],Footprint.dimensions(token))
			if not Landing.bounds(target["data"]).encloses(rectangle): return error("棋子超出地台。")
			var allowed := Landing.cells(target["data"])
			var moved: bool = not previous.has(id) or previous[id]["map"]!=map_id or previous[id]["platform"]!=item["platform"] or Wire.canonical(previous[id]["token"]["cell"])!=Wire.canonical(item["token"]["cell"])
			if moved:
				for z in range(rectangle.position.y,rectangle.end.y):
					for x in range(rectangle.position.x,rectangle.end.x):
						if not allowed.has(Vector2i(x,z)): return error("该位置不允许摆放棋子。")
			target["data"]["tokens"].append(token)
	# Token deletion legitimately removes its bound measurements before comparison.
	candidate["runtime"] = Runtime.pruned(candidate)
	var old_state: Dictionary = candidate["runtime"]["maps"].get(map_id,{"shapes":[],"measurements":[],"platform_origins":{}})
	var new_state: Dictionary = request["runtime"].duplicate(true)
	new_state["platform_origins"] = old_state.get("platform_origins",{})
	for category in ["shapes","measurements"]:
		if not new_state.get(category) is Array: return error()
		var existing := {}
		for entry: Dictionary in old_state[category]: existing[int(entry["display_id"])] = entry
		var next := {}
		for entry in new_state[category]:
			if not entry is Dictionary or not Runtime.number(entry.get("display_id"),1,1000000): return error()
			var display := int(entry["display_id"])
			if next.has(display): return error()
			next[display] = entry
			var key := "%s:%s:%d" % [map_id,category,display]
			if existing.has(display):
				if Wire.canonical(existing[display])!=Wire.canonical(entry) and tools.get(key,"dm")!=actor: return error("不能修改其他成员的工具记录。")
			else: tools[key] = actor
		for display in existing:
			if not next.has(display):
				var key := "%s:%s:%d" % [map_id,category,display]
				if tools.get(key,"dm")!=actor: return error("不能删除其他成员的工具记录。")
				tools.erase(key)
	candidate["runtime"]["maps"][map_id] = new_state
	var validated := Runtime.decode(candidate["runtime"],candidate["maps"])
	if not validated["ok"]: return validated
	candidate["runtime"] = validated["data"]
	return {"ok":true,"data":candidate,"tool_owners":tools}

static func _parameters(raw: Dictionary) -> Dictionary:
	return Instance.decode(raw)["parameters"]

static func _platform(adventure: Dictionary, map: String, id: String) -> Dictionary:
	for item: Dictionary in adventure["maps"]:
		if item["id"]==map:
			for platform: Dictionary in item["data"]["platforms"]:
				if platform["id"]==id: return platform
	return {}

static func _erase(adventure: Dictionary, id: String) -> void:
	for item: Dictionary in adventure["maps"]:
		for platform: Dictionary in item["data"]["platforms"]:
			platform["data"]["tokens"] = platform["data"].get("tokens",[]).filter(func(token: Dictionary): return token["id"]!=id)
	for key in adventure["trays"]: adventure["trays"][key] = adventure["trays"][key].filter(func(token: Dictionary): return token["id"]!=id)
