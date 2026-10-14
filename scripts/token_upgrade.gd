extends RefCounted

const Appearance = preload("res://scripts/token_appearance.gd")
const Components = preload("res://scripts/token_components.gd")

# Derive the advanced components from the exact basic mesh, including its small ground gaps.
static func from_basic(record: Dictionary) -> Dictionary:
	var params: Dictionary = record["parameters"]
	var count := int(params["size"])
	var color: Color = params["color"]
	var model := Appearance.build(count, color, params["base"])
	var base: MeshInstance3D = model.get_node("Base")
	var standee: MeshInstance3D = model.get_node("Standee")
	var base_bounds := base.mesh.get_aabb()
	var standee_bounds := standee.mesh.get_aabb()
	var base_center := base.transform * base_bounds.get_center()
	var standee_center := standee.transform * standee_bounds.get_center()
	var components := Components.defaults()
	var foot: Dictionary = components["base"]
	foot["shape"] = {"square": "rectangle", "circle": "circle", "hexagon": "polygon"}[params["base"]]
	foot["sides"] = 6
	foot["width_ft"] = base_bounds.size.x * 5.0
	foot["length_ft"] = base_bounds.size.z * 5.0
	foot["thickness_ft"] = base_bounds.size.y * 5.0
	foot["offset_ft"] = [base_center.x * 5.0, (base_center.y - base_bounds.size.y / 2.0) * 5.0, base_center.z * 5.0]
	foot["color"] = (base.material_override as StandardMaterial3D).albedo_color.to_html(false)
	var plate: Dictionary = components["standee"]
	plate["width_ft"] = standee_bounds.size.x * 5.0
	plate["height_ft"] = standee_bounds.size.y * 5.0
	plate["thickness_ft"] = standee_bounds.size.z * 5.0
	plate["offset_ft"] = [standee_center.x * 5.0, (standee_center.y - base_bounds.size.y - standee_bounds.size.y / 2.0) * 5.0, standee_center.z * 5.0]
	plate["color"] = (standee.material_override as StandardMaterial3D).albedo_color.to_html(false)
	for part in ["base", "standee"]:
		if params.get("materials", {}).has(part):
			components[part]["material"] = params.materials[part].duplicate(true)
			components[part]["color"] = components[part].material.color
	model.free()
	var raw := {"title": record["title"], "kind": "advanced", "width": count, "length": count, "components": components}
	for key in ["hp", "max_hp", "ac"]:
		raw[key] = "" if int(params[key]) < 0 else str(int(params[key]))
	return raw
