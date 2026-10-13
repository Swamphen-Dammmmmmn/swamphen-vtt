extends RefCounted
const Store = preload("res://scripts/token_library_store.gd")
const Footprint = preload("res://scripts/token_footprint.gd")
const Appearance = preload("res://scripts/token_appearance.gd")
const Components = preload("res://scripts/token_components.gd")
const Sticker = preload("res://scripts/token_sticker.gd")

static func raw(data: Dictionary) -> Dictionary:
	var result := data.duplicate(true)
	result.erase("node")
	for key in ["hp","max_hp","ac"]: result[key] = "" if int(data.get(key,-1))<0 else str(int(data[key]))
	return result

static func record(data: Dictionary) -> Dictionary:
	var params := data.duplicate(true)
	params.erase("node")
	return {"id":"scene", "kind":data.get("kind","basic"), "title":data["title"], "tags":data.get("tags",[]).duplicate(), "parameters":params}

static func encode(data: Dictionary) -> Dictionary:
	var result := data.duplicate(true)
	result.erase("node")
	result["color"] = data["color"].to_html(false)
	var cell: Vector2i = data.get("cell",Vector2i.ZERO)
	result["cell"] = [cell.x,cell.y]
	return result

static func decode(data: Dictionary) -> Dictionary:
	var source := data.duplicate(true)
	if not source.get("tags",[]) is Array: return {"ok":false,"message":"棋子标签无效。"}
	if not source.get("color") is String or not Color.html_is_valid(source["color"]): return {"ok":false,"message":"棋子颜色无效。"}
	for key in ["hp","max_hp","ac"]:
		if not Store._integer(source.get(key)) or int(source[key]) < -1 or int(source[key])>999999: return {"ok":false,"message":"棋子数值无效。"}
	if not Store._integer(source.get("size")): return {"ok":false,"message":"棋子占地无效。"}
	if source.get("tags",[]).size()>32: return {"ok":false,"message":"棋子标签过多。"}
	for tag in source.get("tags",[]):
		if not tag is String or tag.strip_edges().is_empty() or tag.length()>40: return {"ok":false,"message":"棋子标签无效。"}
	source["color"] = Color.from_string(source["color"],Color("2e7ae0"))
	var result := Store.validate(raw(source))
	if not result["ok"]: return result
	var params: Dictionary = result["parameters"]
	params["kind"] = source.get("kind","basic")
	params["tags"] = source.get("tags",[]).duplicate()
	return {"ok":true,"parameters":params}

static func build(data: Dictionary, ghost := false) -> Node3D:
	var components: Dictionary = data.get("components",{})
	return Appearance.build(int(data["size"]),data["color"],data["base"],ghost) if components.is_empty() else Components.build(Components.validate(components,Footprint.dimensions(data)),ghost)

static func images(data: Dictionary) -> Array:
	if data.get("components",{}).is_empty(): return []
	return Sticker.resource_ids(data["components"]["standee"].get("sticker",Sticker.defaults()))
