extends "res://scripts/route_plan.gd"

const Footprint = preload("res://scripts/token_footprint.gd")
const Rules = preload("res://scripts/distance_rules.gd")
var endpoints: Array[Dictionary] = []
var original_endpoint: Dictionary = {}
var completed := false
var display_id := 0
var waypoint_endpoints: Array[Dictionary] = []

func reset() -> void:
	super.reset()
	waypoint_endpoints.clear()
	endpoints.clear()
	original_endpoint.clear()
	completed = false

func begin(origin: Vector2i) -> void:
	reset()
	points.append(origin)
	point_surfaces.append(surface_context)
	endpoints.append({"cell": origin, "token_id": -1})

func begin_endpoint(endpoint: Dictionary) -> void:
	begin(endpoint["cell"])
	endpoints[0] = endpoint.duplicate()
	point_surfaces[0] = endpoint.get("platform_id","")

func add_endpoint(endpoint: Dictionary) -> void:
	if not endpoints.is_empty() and endpoints[-1] == endpoint:
		return
	waypoint_endpoints.append(endpoints[-1].duplicate())
	# Once the old destination becomes a waypoint, keep its resolved grid cell.
	if endpoints.size() > 1:
		endpoints[-1] = {"cell": points[-1], "token_id": -1,"platform_id":endpoints[-1].get("platform_id","")}
	endpoints.append(endpoint.duplicate())
	points.append(endpoint["cell"])
	point_surfaces.append(endpoint.get("platform_id",""))

func replace_endpoint(index: int, endpoint: Dictionary) -> void:
	if index >= 0 and index < endpoints.size():
		endpoints[index] = endpoint.duplicate() if index in [0, endpoints.size() - 1] else {"cell": endpoint["cell"], "token_id": -1,"platform_id":endpoint.get("platform_id","")}
		points[index] = endpoints[index]["cell"]
		point_surfaces[index] = endpoint.get("platform_id","")

func start_edit(index: int) -> void:
	if index >= 0 and index < points.size():
		editing_index = index
		original_cell = points[index]
		original_surface = point_surfaces[index]
		original_endpoint = endpoints[index].duplicate()

func update_edit(cell: Vector2i) -> void:
	if editing_index >= 0:
		points[editing_index] = cell
		endpoints[editing_index] = {"cell": cell, "token_id": -1, "platform_id": surface_context}
		point_surfaces[editing_index] = surface_context

func cancel_edit() -> void:
	if editing_index >= 0:
		endpoints[editing_index] = original_endpoint.duplicate()
		points[editing_index] = original_cell
		point_surfaces[editing_index] = original_surface
		editing_index = -1
	original_endpoint.clear()

func finish_edit() -> void:
	super.finish_edit()
	original_endpoint.clear()

func delete_point(index: int) -> void:
	if editing_index < 0 and index >= 0 and index < points.size():
		waypoint_endpoints.clear()
		endpoints.remove_at(index)
		points.remove_at(index)
		point_surfaces.remove_at(index)

func undo_point() -> void:
	if editing_index < 0 and points.size() > 1:
		endpoints.remove_at(endpoints.size() - 1)
		super.undo_point()
		if not waypoint_endpoints.is_empty():
			endpoints[-1] = waypoint_endpoints.pop_back()

func resolve(tokens: Array[Dictionary]) -> bool:
	if endpoints.is_empty():
		return false
	var previous := points.duplicate()
	for index in range(endpoints.size()):
		points[index] = endpoints[index]["cell"]
	if points.size() == 1:
		points[0] = _space(endpoints[0], tokens).position
	elif points.size() == 2:
		var pair := Rules.closest_cells(_space(endpoints[0], tokens), _space(endpoints[1], tokens))
		points[0] = pair[0]
		points[1] = pair[1]
	else:
		var first := Rules.closest_cells(_space(endpoints[0], tokens), Rect2i(points[1], Vector2i.ONE))
		var last := Rules.closest_cells(Rect2i(points[-2], Vector2i.ONE), _space(endpoints[-1], tokens))
		points[0] = first[0]
		points[-1] = last[1]
	for index in range(endpoints.size()):
		endpoints[index]["cell"] = points[index]
		point_surfaces[index] = endpoints[index].get("platform_id",point_surfaces[index])
	return previous != points

func _space(endpoint: Dictionary, tokens: Array[Dictionary]) -> Rect2i:
	if int(endpoint["token_id"]) >= 0:
		for token in tokens:
			if token["id"] == endpoint["token_id"]:
				endpoint["platform_id"] = token.get("platform_id",endpoint.get("platform_id",""))
				return Footprint.space(token)
		# Keep the last resolved location if the referenced token is removed.
		endpoint["token_id"] = -1
	return Rect2i(endpoint["cell"], Vector2i.ONE)
