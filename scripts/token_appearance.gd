extends RefCounted

const Surface = preload("res://scripts/token_surface.gd")
const BASES := ["square", "circle", "hexagon"]

static func material(color: Color, preview := false) -> StandardMaterial3D:
	var surface := StandardMaterial3D.new()
	surface.albedo_color = color
	surface.roughness = 0.85
	if preview:
		surface.albedo_color.a = 0.65
		surface.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	return surface

static func build(size: int, color: Color, base := "square", preview := false, materials: Dictionary = {}) -> Node3D:
	var actor := Node3D.new()
	var base_mesh: Mesh
	if base in ["circle", "hexagon"]:
		var cylinder := CylinderMesh.new()
		cylinder.top_radius = size * 0.43
		cylinder.bottom_radius = size * 0.43
		cylinder.height = 0.15
		cylinder.radial_segments = 6 if base == "hexagon" else 32
		base_mesh = cylinder
	else:
		var square := BoxMesh.new()
		square.size = Vector3(size * 0.86, 0.15, size * 0.86)
		base_mesh = square
	var foot := MeshInstance3D.new()
	foot.name = "Base"
	foot.mesh = base_mesh
	foot.position.y = 0.09
	foot.material_override = material(color.darkened(0.25), preview)
	actor.add_child(foot)
	var plate := MeshInstance3D.new()
	plate.name = "Standee"
	var plate_mesh := BoxMesh.new()
	plate_mesh.size = Vector3(size * 0.7, size * 0.85, 0.14)
	plate.mesh = plate_mesh
	plate.position.y = size * 0.425 + 0.17
	plate.material_override = material(color, preview)
	actor.add_child(plate)
	Surface.apply_basic(actor, materials, preview)
	if preview:
		for child in actor.get_children():
			child.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	return actor
