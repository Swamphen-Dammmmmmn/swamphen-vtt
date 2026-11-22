extends RefCounted
# In-memory target guard only. Does not add IDs/revisions to saved or network data.
const Plan = preload("res://scripts/measurement_plan.gd")

static func capture(plan: Plan, map_id: String, point: int) -> Dictionary:
	return {
		"plan": plan, "id": plan.display_id, "map_id": map_id, "point": point,
		"source_points": plan.points.duplicate(),
		"source_endpoints": plan.endpoints.duplicate(true),
	}

static func is_valid(target: Dictionary, map_id: String, plans: Array) -> bool:
	var plan: Variant = target.get("plan")
	if not plan is Plan or target.get("map_id") != map_id or not plans.has(plan): return false
	if target.get("id") != plan.display_id: return false
	var point := int(target.get("point", -2))
	return plan.completed and plan.editing_index < 0 and point >= -1 and point < plan.points.size() and plan.points == target.get("source_points") and plan.endpoints == target.get("source_endpoints")
