extends RefCounted
## Rectangles use cells relative to the platform's fixed five-foot grid origin.

static func bounds(data: Dictionary) -> Rect2i:
	var origin: Vector2 = data.get("bounds_origin_feet",data["grid_origin_feet"])
	var grid_origin: Vector2 = data["grid_origin_feet"]
	return Rect2i(Vector2i(roundi((origin.x-grid_origin.x)/5),roundi((origin.y-grid_origin.y)/5)),Vector2i(roundi(float(data["width_feet"])/5),roundi(float(data["length_feet"])/5)))

static func rectangle(region: Dictionary) -> Rect2i:
	return Rect2i(int(region.get("x",0)),int(region.get("z",0)),int(region.get("width",0)),int(region.get("length",0)))

static func validate(region: Dictionary, data: Dictionary) -> String:
	for key in ["x","z","width","length"]:
		var value := float(region.get(key,0))
		if not is_finite(value) or value!=floorf(value): return "起点须对齐整格，长宽须为整数格。"
	if int(region.get("width",0))<1 or int(region.get("length",0))<1: return "落下区长宽至少为1格。"
	if not bounds(data).encloses(rectangle(region)): return "落下区不能超出地台顶面。"
	return ""

static func cells(data: Dictionary) -> Dictionary:
	var result := {}
	for cell in data.get("landing_cells",[]): result[Vector2i(cell)] = true
	return result

static func normalize(data: Dictionary) -> void:
	# Convert the previous in-memory rectangle format; no platform files exist yet.
	var occupied := cells(data)
	for region: Dictionary in data.get("landing_areas",[]):
		var rect := rectangle(region)
		for z in range(rect.position.y,rect.end.y):
			for x in range(rect.position.x,rect.end.x): occupied[Vector2i(x,z)] = true
	_store(data,occupied)
	data.erase("landing_areas")
	data.erase("next_landing_id")

static func changed_count(data: Dictionary, region: Dictionary, adding: bool) -> int:
	var occupied := cells(data)
	var rect := rectangle(region)
	var count := 0
	for z in range(rect.position.y,rect.end.y):
		for x in range(rect.position.x,rect.end.x):
			if occupied.has(Vector2i(x,z))!=adding: count += 1
	return count

static func apply_rectangle(data: Dictionary, region: Dictionary, adding: bool) -> void:
	var occupied := cells(data)
	var rect := rectangle(region)
	for z in range(rect.position.y,rect.end.y):
		for x in range(rect.position.x,rect.end.x):
			var cell := Vector2i(x,z)
			if adding: occupied[cell] = true
			else: occupied.erase(cell)
	_store(data,occupied)

static func _store(data: Dictionary, occupied: Dictionary) -> void:
	var result: Array[Vector2i] = []
	var limits := bounds(data)
	for cell: Vector2i in occupied:
		if limits.has_point(cell): result.append(cell)
	result.sort_custom(func(a: Vector2i,b: Vector2i): return a.y<b.y or (a.y==b.y and a.x<b.x))
	data["landing_cells"] = result

static func contains_cell(data: Dictionary, cell: Vector2i) -> bool:
	return cell in data.get("landing_cells",[])
