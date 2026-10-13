extends RefCounted
const Maps = preload("res://scripts/map_data.gd")
const MapStore = preload("res://scripts/map_library_store.gd")
const Runtime = preload("res://scripts/adventure_runtime.gd")
const Policy = preload("res://scripts/network_policy.gd")
const Members = preload("res://scripts/adventure_members.gd")
const Trays = preload("res://scripts/adventure_trays.gd")

static func defaults() -> Dictionary:
	return {"title":"冒险","maps":[],"runtime":Runtime.defaults(),"trays":Trays.defaults(),"party":Members.defaults(),"network":Policy.defaults()}

static func import_map(record: Dictionary) -> Dictionary:
	var data: Dictionary = record["parameters"].duplicate(true)
	for platform: Dictionary in data["platforms"]:
		platform["id"] = Maps.new_id()
		for token: Dictionary in platform["data"].get("tokens",[]): token["id"] = Maps.new_id()
	return {"id":Maps.new_id(),"source_id":record["id"],"data":data,"thumbnail":record.get("thumbnail")}

static func signature(data: Dictionary) -> String:
	var items: Array = [data["title"]]
	items.append(Members.normalized(data))
	items.append(Policy.normalize(data))
	items.append(Runtime.pruned(data))
	items.append(Trays.signature(data.get("trays",Trays.defaults())))
	for item: Dictionary in data["maps"]:
		items.append([item["id"],item["source_id"],MapStore.signature(item["data"])])
	return JSON.stringify(items).sha256_text()
