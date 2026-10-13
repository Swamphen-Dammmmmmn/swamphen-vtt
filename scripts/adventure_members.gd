extends RefCounted
const Identity = preload("res://scripts/local_identity.gd")
const Ids = preload("res://scripts/map_data.gd")
const Files = preload("res://scripts/platform_library_store.gd")
const LIMIT := 128

static func defaults() -> Dictionary:
	return {"members":{"dm":{"nickname":"DM","identity_code":"","role":"dm"}},"owners":{},"positions":{}}

static func tray_key(member: String) -> String:
	return "dm" if member == "dm" else "member:"+member

static func tokens(adventure: Dictionary) -> Dictionary:
	var result := {}
	for map: Dictionary in adventure.get("maps",[]):
		for platform: Dictionary in map["data"]["platforms"]:
			for token: Dictionary in platform["data"].get("tokens",[]): result[token["id"]] = true
	for entries: Array in adventure.get("trays",{}).values():
		for token: Dictionary in entries: result[token["id"]] = true
	return result

static func normalized(adventure: Dictionary) -> Dictionary:
	var result: Dictionary = adventure.get("party",defaults()).duplicate(true)
	var existing := tokens(adventure)
	for id in result["owners"].keys():
		if not existing.has(id): result["owners"].erase(id)
	for id in existing:
		if not result["owners"].has(id): result["owners"][id] = "dm"
	var maps := {}
	for map: Dictionary in adventure.get("maps",[]): maps[map["id"]] = true
	for member in result["positions"]:
		if not maps.has(result["positions"][member]): result["positions"][member] = ""
	return result

static func decode(raw: Variant, adventure: Dictionary) -> Dictionary:
	var error := {"ok":false,"message":"冒险成员或棋子归属数据无效。"}
	if not raw is Dictionary or not raw.get("members") is Dictionary or not raw.get("owners") is Dictionary or not raw.get("positions") is Dictionary: return error
	var members: Dictionary = raw["members"]
	if not members.has("dm") or members.size()>LIMIT+1: return error
	var codes := {}
	for id in members:
		if not id is String or (id != "dm" and not Files._id_valid(id)): return error
		var member: Variant = members[id]
		if not member is Dictionary or member.get("role") != ("dm" if id=="dm" else "pl"): return error
		if id=="dm":
			if member.get("identity_code") != "" or not member.get("nickname") is String or member["nickname"].is_empty() or member["nickname"].length()>40: return error
		else:
			var checked := Identity.validate({"nickname":member.get("nickname"),"code":member.get("identity_code")})
			if not checked.is_empty() or codes.has(member["identity_code"]): return error
			codes[member["identity_code"]] = true
	for id in raw["owners"]:
		if not id is String or not Files._id_valid(id) or not raw["owners"][id] is String or not members.has(raw["owners"][id]): return error
	for member in raw["positions"]:
		if not members.has(member) or not raw["positions"][member] is String: return error
	for key in adventure.get("trays",{}):
		if key in ["dm","public"]: continue
		if not key.begins_with("member:") or not members.has(key.trim_prefix("member:")): return error
		for token: Dictionary in adventure["trays"][key]:
			if raw["owners"].get(token["id"],"dm") != key.trim_prefix("member:"): return error
	var source := adventure.duplicate()
	source["party"] = raw
	return {"ok":true,"data":normalized(source)}

static func can_token(party: Dictionary, actor: String, id: String) -> bool:
	return party["members"].has(actor) and (actor=="dm" or party["owners"].get(id,"dm")==actor)

static func can_tray(party: Dictionary, actor: String, key: String) -> bool:
	return party["members"].has(actor) and (actor=="dm" or key in ["public",tray_key(actor)])

static func can_store(party: Dictionary, actor: String, token_id: String, key: String) -> bool:
	if not can_token(party,actor,token_id) or not can_tray(party,actor,key): return false
	return key in ["dm","public"] or key==tray_key(party["owners"].get(token_id,"dm"))

# Connections are intentionally separate from saved member records.
static func join(adventure: Dictionary, code: String, nickname: String, connection: String, online: Dictionary) -> Dictionary:
	var checked := Identity.validate({"nickname":nickname,"code":code})
	if not checked.is_empty() or connection.is_empty(): return {"ok":false,"message":checked if not checked.is_empty() else "连接编号无效。"}
	if online.values().has(connection): return {"ok":false,"message":"此连接已有成员身份。"}
	var party: Dictionary = adventure["party"]
	var member_id := ""
	for id in party["members"]:
		if id!="dm" and party["members"][id]["identity_code"]==code: member_id = id
	if not member_id.is_empty() and online.has(member_id): return {"ok":false,"message":"该身份已在线，请先退出原设备。"}
	if member_id.is_empty():
		if party["members"].size()>=LIMIT+1: return {"ok":false,"message":"冒险成员已达上限。"}
		member_id = Ids.new_id()
		party["members"][member_id] = {"nickname":nickname.strip_edges(),"identity_code":code,"role":"pl"}
	party["members"][member_id]["nickname"] = nickname.strip_edges()
	var key := tray_key(member_id)
	if not adventure["trays"].has(key): adventure["trays"][key] = []
	online[member_id] = connection
	return {"ok":true,"member_id":member_id}

static func release_connection(online: Dictionary, member: String, connection: String) -> void:
	if online.get(member)==connection: online.erase(member)

static func set_map(adventure: Dictionary, member: String, map_id: String) -> bool:
	if not adventure["party"]["members"].has(member): return false
	for map: Dictionary in adventure["maps"]:
		if map["id"]==map_id:
			adventure["party"]["positions"][member] = map_id
			return true
	return false

static func can_edit_scene(party: Dictionary, actor: String) -> bool:
	return actor=="dm" and party["members"].has(actor)

static func actor_for_connection(online: Dictionary, connection: String) -> String:
	for member: String in online:
		if online[member]==connection: return member
	return ""
