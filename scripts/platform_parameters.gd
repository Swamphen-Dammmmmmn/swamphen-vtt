extends RefCounted
## Values use feet. One scene unit represents five feet.
const MATERIALS := ["grass", "sand", "beach", "water"]
const TITLES := ["草地", "沙漠", "沙滩", "水面"]

static func defaults() -> Dictionary:
	return {"title":"地台", "width_feet":50.0, "length_feet":50.0, "thickness_feet":5.0,
		"top_feet":0.0, "grid_origin_feet":Vector2.ZERO, "bounds_origin_feet":Vector2.ZERO, "material":"grass", "landing_cells":[]}

static func validate(source: Dictionary) -> Dictionary:
	var data := source.duplicate(true)
	data["title"] = str(data.get("title", "")).strip_edges()
	if data["title"].is_empty(): return {"ok":false,"message":"请填写地台名称。"}
	for key in ["width_feet", "length_feet"]:
		var value := float(data.get(key,0))
		if not is_finite(value) or value < 5 or value > 1000 or not is_equal_approx(fmod(value,5.0),0.0):
			return {"ok":false,"message":"长宽须为 5～1000 英尺内的整 5 英尺尺寸。"}
		data[key] = value
	var thickness := float(data.get("thickness_feet",0))
	if not is_finite(thickness) or thickness < 1 or thickness > 50 or thickness != floorf(thickness):
		return {"ok":false,"message":"基础厚度须为 1～50 英尺内的整数。"}
	data["thickness_feet"] = thickness
	if str(data.get("material","")) not in MATERIALS: return {"ok":false,"message":"请选择基础材质。"}
	return {"ok":true,"data":data}

static func expanded(source: Dictionary, additions: Dictionary) -> Dictionary:
	for key in ["x_negative","x_positive","z_negative","z_positive","bottom"]:
		var amount := float(additions.get(key,0.0))
		var interval := 1.0 if key == "bottom" else 5.0
		if not is_finite(amount) or amount < 0.0 or not is_zero_approx(fmod(amount,interval)):
			return {"ok":false,"message":"水平扩展须为非负整5英尺，底部扩展须为非负整1英尺。"}
	return validate(expansion_preview(source,additions))

static func expansion_preview(source: Dictionary, additions: Dictionary) -> Dictionary:
	var data := source.duplicate(true)
	data["width_feet"] += additions.get("x_negative",0.0)+additions.get("x_positive",0.0)
	data["length_feet"] += additions.get("z_negative",0.0)+additions.get("z_positive",0.0)
	data["thickness_feet"] += additions.get("bottom",0.0)
	data["bounds_origin_feet"] = source.get("bounds_origin_feet",source["grid_origin_feet"])-Vector2(additions.get("x_negative",0.0),additions.get("z_negative",0.0))
	return data
