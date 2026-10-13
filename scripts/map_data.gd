extends RefCounted
const PlatformStore = preload("res://scripts/platform_library_store.gd")
const Weather = preload("res://scripts/map_weather.gd")

static func defaults() -> Dictionary:
	return {"title":"地图","environment":Weather.defaults(),"platforms":[]}

static func new_id() -> String:
	return Crypto.new().generate_random_bytes(16).hex_encode()

static func import_platform(record: Dictionary) -> Dictionary:
	var data: Dictionary = record["parameters"].duplicate(true)
	if data.get("paint_overlay") != null: data["paint_overlay"] = data["paint_overlay"].duplicate()
	for token: Dictionary in data.get("tokens",[]): token["id"] = new_id()
	return {"id":new_id(),"source_id":record["id"],"offset_feet":Vector3(0,-float(data["top_feet"]),0),"data":data}

static func bounds(item: Dictionary, offset: Variant = null) -> AABB:
	var data: Dictionary = item["data"]
	var at: Vector3 = item["offset_feet"] if offset==null else offset
	var origin: Vector2 = data.get("bounds_origin_feet",data["grid_origin_feet"])
	return AABB(Vector3(origin.x,float(data["top_feet"])-float(data["thickness_feet"]),origin.y)+at,Vector3(data["width_feet"],data["thickness_feet"],data["length_feet"]))

static func conflicts(item: Dictionary, offset: Vector3, items: Array) -> bool:
	var box := bounds(item,offset)
	for other: Dictionary in items:
		if other["id"]==item["id"]: continue
		var b := bounds(other)
		var overlap := box.end.min(b.end)-box.position.max(b.position)
		if overlap.x>0.001 and overlap.y>0.001 and overlap.z>0.001: return true
	return false

static func signature(data: Dictionary) -> String:
	var values: Array = [data["title"],data["environment"]]
	for item: Dictionary in data["platforms"]:
		var at: Vector3 = item["offset_feet"]
		values.append([item["id"],item["source_id"],[at.x,at.y,at.z],PlatformStore.signature(item["data"])])
	return JSON.stringify(values).sha256_text()
