extends RefCounted
const Shapes = preload("res://scripts/shape_plan.gd")
const Measure = preload("res://scripts/measurement_plan.gd")

static func defaults() -> Dictionary:
	return {"current_map_id":"","maps":{},"distance_mode":0}

static func pruned(data: Dictionary) -> Dictionary:
	var result: Dictionary = data.get("runtime",defaults()).duplicate(true)
	var available := {}
	for item: Dictionary in data["maps"]:
		available[item["id"]] = true
		if not result["maps"].has(item["id"]): continue
		var platforms := {}
		var tokens := {}
		for platform: Dictionary in item["data"]["platforms"]:
			platforms[platform["id"]] = true
			for token: Dictionary in platform["data"].get("tokens",[]): tokens[token["id"]] = true
		var state: Dictionary = result["maps"][item["id"]]
		var previous: Dictionary = state.get("platform_origins",{})
		var origins := {}
		for platform: Dictionary in item["data"]["platforms"]:
			var grid: Vector2 = platform["data"]["grid_origin_feet"]
			var offset: Vector3 = platform["offset_feet"]
			origins[platform["id"]] = [roundi((grid.x+offset.x)/5)+15,roundi((grid.y+offset.z)/5)+15]
		for shape: Dictionary in state["shapes"]:
			var platform_id: String = shape["platform_id"]
			if origins.has(platform_id) and previous.has(platform_id):
				for axis in range(2):
					var delta: float = origins[platform_id][axis]-previous[platform_id][axis]
					shape["origin"][axis] += delta
					shape["cell"][axis] += int(delta)
		for measurement: Dictionary in state["measurements"]:
			for endpoint: Dictionary in measurement["endpoints"]:
				var platform_id: String = endpoint["platform_id"]
				if origins.has(platform_id) and previous.has(platform_id):
					for axis in range(2): endpoint["cell"][axis] += origins[platform_id][axis]-previous[platform_id][axis]
		state["platform_origins"] = origins
		state["shapes"] = state["shapes"].filter(func(shape: Dictionary): return platforms.has(shape.get("platform_id","")))
		state["measurements"] = state["measurements"].filter(func(measurement: Dictionary):
			for endpoint: Dictionary in measurement["endpoints"]:
				if not platforms.has(endpoint["platform_id"]) or (not endpoint["token_id"].is_empty() and not tokens.has(endpoint["token_id"])): return false
			return true
		)
	for id in result["maps"].keys():
		if not available.has(id): result["maps"].erase(id)
	if not available.has(result["current_map_id"]): result["current_map_id"] = ""
	return result

static func remap(raw: Dictionary, mapping: Dictionary) -> Dictionary:
	var result := defaults()
	result["current_map_id"] = mapping.get(raw["current_map_id"],"")
	result["distance_mode"] = raw.get("distance_mode",0)
	for id in raw["maps"]:
		var state: Dictionary = raw["maps"][id].duplicate(true)
		var origins := {}
		for platform_id in state.get("platform_origins",{}): origins[mapping.get(platform_id,platform_id)] = state["platform_origins"][platform_id]
		state["platform_origins"] = origins
		for shape: Dictionary in state["shapes"]: shape["platform_id"] = mapping.get(shape["platform_id"],shape["platform_id"])
		for measurement: Dictionary in state["measurements"]:
			for endpoint: Dictionary in measurement["endpoints"]:
				endpoint["platform_id"] = mapping.get(endpoint["platform_id"],endpoint["platform_id"])
				endpoint["token_id"] = mapping.get(endpoint["token_id"],endpoint["token_id"])
		result["maps"][mapping.get(id,id)] = state
	return result

static func capture(board: Node3D) -> Dictionary:
	var state := {"shapes":[],"measurements":[],"platform_origins":{}}
	for platform: Dictionary in board.session_map["platforms"]:
		var origin: Vector2i = board.surfaces.origin(platform)
		state["platform_origins"][platform["id"]] = [origin.x,origin.y]
	for shape: Dictionary in board.shape_plan.shapes:
		var data := shape.duplicate(true)
		var origin: Vector2 = Shapes.get_origin(shape)
		data["origin"] = [origin.x,origin.y]
		var cell: Vector2i = shape["cell"]
		data["cell"] = [cell.x,cell.y]
		state["shapes"].append(data)
	for plan in board.measurements:
		if not plan.completed: continue
		plan.resolve(board.tokens)
		var data := {"display_id":plan.display_id,"endpoints":[]}
		for endpoint: Dictionary in plan.endpoints:
			var copy := {"cell":[endpoint["cell"].x,endpoint["cell"].y],"platform_id":endpoint.get("platform_id",""),"token_id":""}
			for token: Dictionary in board.tokens:
				if token["id"]==endpoint["token_id"]: copy["token_id"] = token["persistent_id"]
			data["endpoints"].append(copy)
		state["measurements"].append(data)
	return state

static func restore(board: Node3D, state: Dictionary) -> void:
	for raw: Dictionary in state.get("shapes",[]):
		var shape := raw.duplicate(true)
		shape["origin"] = Vector2(raw["origin"][0],raw["origin"][1])
		shape["cell"] = Vector2i(raw["cell"][0],raw["cell"][1])
		board.shape_plan.shapes.append(shape)
		board.shape_plan.next_display_id = maxi(board.shape_plan.next_display_id,int(shape["display_id"])+1)
	for raw: Dictionary in state.get("measurements",[]):
		var plan := Measure.new()
		plan.display_id = int(raw["display_id"])
		for endpoint: Dictionary in raw["endpoints"]:
			var data := {"cell":Vector2i(endpoint["cell"][0],endpoint["cell"][1]),"platform_id":endpoint["platform_id"],"token_id":-1}
			for token: Dictionary in board.tokens:
				if token["persistent_id"]==endpoint["token_id"]: data["token_id"] = token["id"]
			if plan.endpoints.is_empty(): plan.begin_endpoint(data)
			else: plan.add_endpoint(data)
		plan.resolve(board.tokens)
		plan.completed = true
		board.measurements.append(plan)
		board.next_measurement_id = maxi(board.next_measurement_id,plan.display_id+1)
	board._render_shapes()
	board._update_saved_measurements()

static func number(value: Variant, minimum: float, maximum: float) -> bool:
	return typeof(value) in [TYPE_INT,TYPE_FLOAT] and is_finite(float(value)) and float(value)>=minimum and float(value)<=maximum

static func vector(value: Variant, integer := false) -> bool:
	if not value is Array or value.size()!=2: return false
	for component in value:
		if not number(component,-1000015,1000015) or (integer and float(component)!=floorf(float(component))): return false
	return true

static func decode(raw: Variant, maps: Array) -> Dictionary:
	var error := {"ok":false,"message":"冒险游玩状态无效。"}
	if not raw is Dictionary or not raw.get("current_map_id") is String or not raw.get("maps") is Dictionary: return error
	var mode: Variant = raw.get("distance_mode",0)
	if not number(mode,0,2) or float(mode)!=floorf(float(mode)): return error
	var available := {}
	for item: Dictionary in maps: available[item["id"]] = item
	if not raw["current_map_id"].is_empty() and not available.has(raw["current_map_id"]): return error
	for id in raw["maps"]:
		if not available.has(id) or not raw["maps"][id] is Dictionary: return error
		var state: Dictionary = raw["maps"][id]
		var platforms := {}
		var tokens := {}
		for platform: Dictionary in available[id]["data"]["platforms"]:
			platforms[platform["id"]] = true
			for token: Dictionary in platform["data"].get("tokens",[]): tokens[token["id"]] = true
		if not state.get("platform_origins",{}) is Dictionary: return error
		for platform_id in state.get("platform_origins",{}):
			if not platforms.has(platform_id) or not vector(state["platform_origins"][platform_id],true): return error
		if not state.get("shapes") is Array or state["shapes"].size()>100 or not state.get("measurements") is Array or state["measurements"].size()>256: return error
		var shape_ids := {}
		for shape in state["shapes"]:
			if not shape is Dictionary or not vector(shape.get("cell"),true) or not vector(shape.get("origin")): return error
			if not shape.get("platform_id") is String or not platforms.has(shape["platform_id"]): return error
			if not number(shape.get("kind"),0,3) or float(shape["kind"])!=floorf(float(shape["kind"])): return error
			if not number(shape.get("display_id"),1,1000000) or float(shape["display_id"])!=floorf(float(shape["display_id"])) or shape_ids.has(shape["display_id"]): return error
			shape_ids[shape["display_id"]] = true
			for key in ["radius","width","length"]:
				if not number(shape.get(key),1,300): return error
			if not number(shape.get("angle"),1,180) or not number(shape.get("rotation"),0,360) or shape.get("anchor") not in [0,1]: return error
		var measure_ids := {}
		for measurement in state["measurements"]:
			if not measurement is Dictionary or not measurement.get("endpoints") is Array or measurement["endpoints"].size()<2 or measurement["endpoints"].size()>256: return error
			if not number(measurement.get("display_id"),1,1000000) or float(measurement["display_id"])!=floorf(float(measurement["display_id"])) or measure_ids.has(measurement["display_id"]): return error
			measure_ids[measurement["display_id"]] = true
			for endpoint in measurement["endpoints"]:
				if not endpoint is Dictionary or not vector(endpoint.get("cell"),true) or not endpoint.get("token_id") is String or not endpoint.get("platform_id") is String: return error
				if not endpoint["token_id"].is_empty() and not tokens.has(endpoint["token_id"]): return error
				if not platforms.has(endpoint["platform_id"]): return error
	var normalized: Dictionary = raw.duplicate(true)
	normalized["distance_mode"] = int(mode)
	return {"ok":true,"data":normalized}
