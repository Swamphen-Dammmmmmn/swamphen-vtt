extends RefCounted

const Basic = preload("res://scripts/token_parameters.gd")
const Footprint = preload("res://scripts/token_footprint.gd")
const Components = preload("res://scripts/token_components.gd")

static func validate(raw: Dictionary) -> Dictionary:
	if not Footprint.valid(raw) or not raw.has("width") or not raw.has("length"):
		return {"ok": false, "field": "footprint", "message": "占地宽长须为 1～15 的整数格。"}
	var extent := Footprint.dimensions(raw)
	if not raw.get("components") is Dictionary:
		return {"ok": false, "field": "components", "message": "组件参数无效。"}
	var checked := Components.validate(raw["components"], extent)
	if not checked["ok"]: return checked
	var common := raw.duplicate(true)
	common.erase("materials")
	common["size"] = 1
	common["base"] = "circle"
	common["color"] = Color("2e7ae0")
	var result := Basic.validate(common)
	if not result["ok"]: return result
	var params: Dictionary = result["parameters"]
	params.erase("materials")
	params["width"] = extent.x
	params["length"] = extent.y
	params["size"] = mini(extent.x, extent.y)
	params["components"] = checked["components"]
	params["component_version"] = 2
	params["color"] = Color(params["components"]["standee"]["color"])
	var shape: String = params["components"]["base"]["shape"]
	params["base"] = "square" if shape == "rectangle" else ("hexagon" if shape == "polygon" else "circle")
	return result
