extends RefCounted
const Store = preload("res://scripts/token_library_store.gd")
const Footprint = preload("res://scripts/token_footprint.gd")
const Appearance = preload("res://scripts/token_appearance.gd")
const Components = preload("res://scripts/token_components.gd")
const Sticker = preload("res://scripts/token_sticker.gd")
const SCENE_FIELDS := ["temp_hp", "notes", "quarter_turn", "model_yaw_deg"]
const MAX_NOTES := 8000

static func scene_values(data: Dictionary) -> Dictionary:
	return {"temp_hp":int(data.get("temp_hp",0)), "notes":str(data.get("notes","")), "quarter_turn":int(data.get("quarter_turn",0)), "model_yaw_deg":float(data.get("model_yaw_deg",0.0))}

static func apply_orientation(actor: Node3D, data: Dictionary) -> void:
	var quarter := deg_to_rad(float(data.get("quarter_turn",0))*90.0)
	var offset := deg_to_rad(float(data.get("model_yaw_deg",0.0)))
	var extent := Footprint.dimensions(data)
	if not actor.has_meta("appearance_bounds"):
		var measured := AABB()
		var found := false
		for child in actor.get_children():
			if child is MeshInstance3D and child.mesh!=null:
				var box: AABB = child.transform*child.mesh.get_aabb()
				measured = measured.merge(box) if found else box
				found = true
		if found: actor.set_meta("appearance_bounds",measured)
	var bounds: AABB = actor.get_meta("appearance_bounds",AABB(Vector3(-extent.x/2.0,0,-extent.y/2.0),Vector3(extent.x,float(data.get("size",1)),extent.y)))
	var center := bounds.get_center()
	var basis := Basis(Vector3.UP,offset)
	var transform := Transform3D(basis,center-basis*center)
	actor.rotation.y = quarter
	for child in actor.get_children():
		if not child is Node3D: continue
		if not child.has_meta("orientation_rest"): child.set_meta("orientation_rest",child.transform)
		var rest: Transform3D = child.get_meta("orientation_rest")
		child.transform = rest if child.has_meta("rule_proxy") else transform*rest
		if child.has_meta("rule_proxy"): child.rotation.y = -quarter
	actor.set_meta("oriented_bounds",transform*bounds)

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
	var temporary: Variant = source.get("temp_hp",0)
	var quarter: Variant = source.get("quarter_turn",0)
	var angle: Variant = source.get("model_yaw_deg",0.0)
	var notes: Variant = source.get("notes","")
	if not Store._integer(temporary) or int(temporary)<0 or int(temporary)>999999: return {"ok":false,"message":"临时生命值无效。"}
	if not Store._integer(quarter) or int(quarter)<0 or int(quarter)>3: return {"ok":false,"message":"棋子实际朝向无效。"}
	if typeof(angle) not in [TYPE_INT,TYPE_FLOAT] or not is_finite(float(angle)) or absf(float(angle))>360: return {"ok":false,"message":"棋子模型偏角无效。"}
	if not notes is String or notes.length()>MAX_NOTES: return {"ok":false,"message":"棋子备注过长或无效。"}
	params.merge(scene_values(source),true)
	return {"ok":true,"parameters":params}

static func build(data: Dictionary, ghost := false) -> Node3D:
	var components: Dictionary = data.get("components",{})
	var actor: Node3D = Appearance.build(int(data["size"]),data["color"],data["base"],ghost,data.get("materials",{})) if components.is_empty() else Components.build(Components.validate(components,Footprint.dimensions(data)),ghost)
	apply_orientation(actor,data)
	return actor

static func images(data: Dictionary) -> Array:
	if data.get("components",{}).is_empty(): return []
	return Sticker.resource_ids(data["components"]["standee"].get("sticker",Sticker.defaults()))
