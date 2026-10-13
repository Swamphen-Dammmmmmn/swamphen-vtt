extends RefCounted
const MapData = preload("res://scripts/map_data.gd")
const Landing = preload("res://scripts/platform_landing.gd")
var platforms: Array = []
var current := ""
var board: Node3D

func item(id: String) -> Dictionary:
	for platform: Dictionary in platforms:
		if platform["id"]==id: return platform
	return {}

func origin(platform: Dictionary) -> Vector2i:
	var at: Vector3 = platform["offset_feet"]
	var grid: Vector2 = platform["data"]["grid_origin_feet"]
	return Vector2i(roundi((grid.x+at.x)/5)+15,roundi((grid.y+at.z)/5)+15)

func height(id: String) -> float:
	var platform := item(id)
	return (float(platform["data"]["top_feet"])+float(platform["offset_feet"].y))/5 if not platform.is_empty() else 0.0

func contains(platform: Dictionary, cell: Vector2i, extent: Vector2i, permission: bool) -> bool:
	var local := cell-origin(platform)
	if not Landing.bounds(platform["data"]).encloses(Rect2i(local,extent)): return false
	if permission:
		var allowed := Landing.cells(platform["data"])
		for z in range(local.y,local.y+extent.y):
			for x in range(local.x,local.x+extent.x):
				if not allowed.has(Vector2i(x,z)): return false
	return true

func find(cell: Vector2i, extent := Vector2i.ONE, preferred := "", permission := false) -> String:
	var candidate := item(preferred)
	if not candidate.is_empty() and contains(candidate,cell,extent,permission): return preferred
	# Explicit surface references never silently jump to an overlapping floor.
	if not preferred.is_empty(): return ""
	var chosen := ""
	var top := -INF
	for platform: Dictionary in platforms:
		if contains(platform,cell,extent,permission) and height(platform["id"])>top:
			chosen = platform["id"]
			top = height(chosen)
	return chosen

func hit(mouse: Vector2) -> Dictionary:
	var start: Vector3 = board.camera.project_ray_origin(mouse)
	var end: Vector3 = start+board.camera.project_ray_normal(mouse)*1000000
	var closest := INF
	var result := {}
	for platform: Dictionary in platforms:
		var box := MapData.bounds(platform)
		box.position /= 5
		box.size /= 5
		var point: Variant = box.intersects_segment(start,end)
		if point==null: continue
		var distance: float = start.distance_squared_to(point)
		if distance<closest:
			closest = distance
			result = {"id":platform["id"],"point":point,"top":absf(point.y-box.end.y)<0.002}
	return result if result.get("top",false) else {}

func mouse_cell(mouse: Vector2) -> Vector2i:
	var result := hit(mouse)
	current = result.get("id","")
	if result.is_empty(): return Vector2i(-1000001,-1000001)
	var point: Vector3 = result["point"]
	return Vector2i(floori(point.x+15),floori(point.z+15))

func world(cell: Vector2i, extent: Vector2i, preferred := "") -> Vector3:
	var id := preferred
	if id.is_empty(): id = find(cell,extent,current)
	if id.is_empty(): id = find(cell,extent)
	return Vector3(cell.x-15+extent.x/2.0,height(id),cell.y-15+extent.y/2.0)

func visible_hit(point: Vector3, mouse: Vector2) -> bool:
	var start: Vector3 = board.camera.project_ray_origin(mouse)
	for platform: Dictionary in platforms:
		var box := MapData.bounds(platform)
		box.position /= 5
		box.size /= 5
		var hit: Variant = box.intersects_segment(start,point)
		if hit!=null and start.distance_squared_to(hit)+0.001<start.distance_squared_to(point): return false
	return true
